import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'providers/session_provider.dart';
import 'providers/handshake_provider.dart';
import 'providers/vault_provider.dart';
import 'providers/settings_provider.dart';

import 'ui/theme/app_theme.dart';
import 'ui/screens/set_password_screen.dart';
import 'ui/screens/calculator_screen.dart';
import 'ui/screens/dashboard_screen.dart';
import 'ui/widgets/exit_overlay.dart';
import 'ui/screens/pairing_screen.dart';

late final GoRouter appRouter;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  final prefs = await SharedPreferences.getInstance();
  final hasSetPassword = prefs.getBool('has_set_password') ?? false;

  appRouter = GoRouter(
    initialLocation: hasSetPassword ? '/calculator' : '/setup',
    routes: [
      GoRoute(
        path: '/setup',
        builder: (context, state) => const SetPasswordScreen(),
      ),
      GoRoute(
        path: '/calculator',
        builder: (context, state) => const CalculatorScreen(),
      ),
      GoRoute(
        path: '/exit',
        builder: (context, state) => const ExitOverlay(),
      ),
      GoRoute(
        path: '/vault',
        builder: (context, state) => const AuthGuard(child: DashboardScreen()),
      ),
    ],
  );

  runApp(MyApp(hasSetPassword: hasSetPassword));
}

class MyApp extends StatelessWidget {
  final bool hasSetPassword;

  const MyApp({super.key, required this.hasSetPassword});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>(
          create: (_) => SettingsProvider(),
        ),
        Provider<AuthService>(
          create: (_) => AuthService(),
        ),
        Provider<FirestoreService>(
          create: (_) => FirestoreService(),
        ),
        ChangeNotifierProvider<SessionProvider>(
          create: (_) => SessionProvider(),
        ),
        ChangeNotifierProxyProvider3<FirestoreService, AuthService, SessionProvider, HandshakeProvider>(
          create: (context) => HandshakeProvider(
            context.read<FirestoreService>(),
            context.read<AuthService>(),
            context.read<SessionProvider>(),
          ),
          update: (context, firestore, auth, session, previous) =>
              previous ?? HandshakeProvider(firestore, auth, session),
        ),
        ChangeNotifierProxyProvider3<AuthService, SessionProvider, HandshakeProvider, VaultProvider>(
          create: (context) => VaultProvider(
            context.read<AuthService>(),
            context.read<SessionProvider>(),
            context.read<HandshakeProvider>(),
          ),
          update: (context, auth, session, handshake, previous) =>
              previous ?? VaultProvider(auth, session, handshake),
        ),
      ],
      child: MaterialApp.router(
        title: 'Calculator', // Decoy title
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        routerConfig: appRouter,
      ),
    );
  }
}

/// AuthGuard ensures the user is signed into Google and has completed the handshake
/// before they can view the vault Dashboard.
class AuthGuard extends StatelessWidget {
  final Widget child;

  const AuthGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return StreamBuilder(
      stream: authService.userChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          // Show sign in screen if not authenticated
          return Scaffold(
            appBar: AppBar(
              title: const Text('Connect Account'),
            ),
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  // Force a disconnect first to clear any stuck rejected scopes
                  try {
                    await GoogleSignIn().disconnect();
                  } catch (_) {}

                  final cred = await authService.signIn();
                  if (cred != null && context.mounted) {
                    final uid = cred.user?.uid;
                    if (uid != null) {
                      Provider.of<HandshakeProvider>(context, listen: false).initialize(uid);
                    }
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Sign-in failed. Please accept the required Drive permissions.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: const Text('Sign in with Google'),
              ),
            ),
          );
        }

        // Initialize handshake provider once logged in
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Provider.of<HandshakeProvider>(context, listen: false).initialize(user.uid);
        });

        return Consumer<HandshakeProvider>(
          builder: (context, handshake, _) {
            final status = handshake.handshakeStatus;

            if (status == 'ready') {
              return child;
            }

            // No couples document yet — show the pairing UI
            if (status == 'idle') {
              return const PairingScreen();
            }

            // Folder creation in progress — show a warm loading screen
            return Scaffold(
              backgroundColor: const Color(0xFFFDE3C6),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFFE64A19)),
                    const SizedBox(height: 24),
                    Text(
                      status == 'creating_folder'
                          ? 'Creating your shared vault...\nThis takes just a moment!'
                          : 'Syncing... ($status)',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Sniglet',
                        fontSize: 18,
                        color: Color(0xFF5D4037),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
