import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/auth_service.dart';
import '../theme/app_theme.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              color: AppTheme.burntOrange,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Scrapbook Vault',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                      ),
                ),
                const SizedBox(height: 8),
                Consumer<AuthService>(
                  builder: (context, auth, _) {
                    return Text(
                      auth.currentUser?.email ?? 'Not Signed In',
                      style: const TextStyle(color: Colors.white70),
                    );
                  },
                ),
              ],
            ),
          ),

          ListTile(
            leading: const Icon(Icons.exit_to_app),
            title: const Text('Export & Disconnect'),
            onTap: () async {
              // Capture root context BEFORE closing drawer (drawer pop invalidates local context)
              final rootContext = Navigator.of(context, rootNavigator: true).context;
              Navigator.pop(context); // Close drawer
              
              // Small delay to let the drawer fully close before showing dialog
              await Future.delayed(const Duration(milliseconds: 300));
              if (!rootContext.mounted) return;

              // Prompt for numeric password
              final TextEditingController passController = TextEditingController();
              final confirmed = await showDialog<bool>(
                context: rootContext,
                builder: (dialogContext) {
                  return AlertDialog(
                    title: const Text('Confirm Exit Strategy'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'This will bulk-decrypt all photos to a new Drive folder and permanently destroy this Vault.',
                          style: TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: passController,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Enter Numeric Password',
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          final decoy = prefs.getString('decoy_password');
                          if (!dialogContext.mounted) return;
                          if (passController.text == decoy) {
                            Navigator.pop(dialogContext, true);
                          } else {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Incorrect password.')),
                            );
                          }
                        },
                        child: const Text('EXECUTE'),
                      ),
                    ],
                  );
                },
              );

              if (confirmed == true && rootContext.mounted) {
                // Wipe routing stack and show un-dismissible exit overlay
                rootContext.go('/exit');
              }
            },
          ),
          const Divider(),
          Consumer<SettingsProvider>(
            builder: (context, settings, _) {
              return ExpansionTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cloud Opacity: ${(settings.cloudOpacity * 100).round()}%'),
                        Slider(
                          value: settings.cloudOpacity,
                          min: 0.2,
                          max: 0.45,
                          divisions: 25,
                          activeColor: AppTheme.burntOrange,
                          onChanged: (value) {
                            settings.setCloudOpacity(value);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock, color: AppTheme.burntOrange),
            title: const Text('Lock Vault', style: TextStyle(color: AppTheme.burntOrange, fontWeight: FontWeight.bold)),
            onTap: () {
              Navigator.pop(context); // Close drawer
              
              // Wipe the volatile master key from memory
              Provider.of<SessionProvider>(context, listen: false).lock();
              
              // Wipe the navigation stack and return to the Decoy Calculator
              context.go('/calculator');
            },
          ),
        ],
      ),
    );
  }
}
