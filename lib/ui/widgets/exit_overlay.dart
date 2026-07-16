import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../providers/session_provider.dart';
import '../../providers/handshake_provider.dart';
import '../../services/exit_strategy_service.dart';
import '../theme/app_theme.dart';

class ExitOverlay extends StatefulWidget {
  const ExitOverlay({super.key});

  @override
  State<ExitOverlay> createState() => _ExitOverlayState();
}

class _ExitOverlayState extends State<ExitOverlay> {
  String _progress = "Initializing...";
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startExitPipeline();
    });
  }

  Future<void> _startExitPipeline() async {
    setState(() {
      _isExiting = true;
    });

    final exitService = ExitStrategyService(
      authService: Provider.of<AuthService>(context, listen: false),
      firestoreService: Provider.of<FirestoreService>(context, listen: false),
      sessionProvider: Provider.of<SessionProvider>(context, listen: false),
      handshakeProvider: Provider.of<HandshakeProvider>(context, listen: false),
    );

    try {
      await exitService.triggerSafeExit((status) {
        if (mounted) {
          setState(() {
            _progress = status;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = "Failed to export. Please restart.";
          _isExiting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Undismissible
      child: Scaffold(
        backgroundColor: AppTheme.backgroundCream,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isExiting)
                const CircularProgressIndicator(color: AppTheme.burntOrange)
              else
                const Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 24),
              Text(
                "Export & Disconnect",
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Text(
                  _progress,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppTheme.earthyBrown.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
