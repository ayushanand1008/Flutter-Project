import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:test_proto/providers/handshake_provider.dart';
import 'package:test_proto/services/firestore_service.dart';
import 'package:test_proto/ui/theme/app_theme.dart';

/// Pairing screen shown to users who are logged in but have no couples document yet.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  bool _isLoading = false;
  String? _generatedCode;
  String? _errorText;
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _createCode() async {
    setState(() { _isLoading = true; _errorText = null; });

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);
      final code = await firestoreService.createPairingCode(user.uid, user.email ?? '');
      setState(() { _generatedCode = code.code; });
    } catch (e) {
      setState(() { _errorText = 'Failed to generate code. Try again.'; });
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  Future<void> _joinWithCode() async {
    final inputCode = _codeController.text.trim();
    if (inputCode.length != 6) {
      setState(() { _errorText = 'Please enter a valid 6-digit code.'; });
      return;
    }

    setState(() { _isLoading = true; _errorText = null; });

    try {
      final user = FirebaseAuth.instance.currentUser!;
      final firestoreService = Provider.of<FirestoreService>(context, listen: false);

      final pairingCode = await firestoreService.findPairingCode(inputCode);
      if (pairingCode == null) {
        setState(() { _errorText = 'Code not found or expired. Ask your partner to generate a new one.'; });
        return;
      }

      if (pairingCode.creatorUid == user.uid) {
        setState(() { _errorText = 'You cannot pair with yourself!'; });
        return;
      }

      // Generate a shared crypto salt
      final salt = _generateSalt();

      // Create the couples document — this triggers the HandshakeProvider listener on User A's device
      await firestoreService.createCouplesDocument(
        userAUid: pairingCode.creatorUid,
        userAEmail: pairingCode.creatorEmail,
        userBUid: user.uid,
        userBEmail: user.email ?? '',
        salt: salt,
      );

      // HandshakeProvider stream will auto-update both devices once Firestore writes.
      // The AuthGuard will rebuild and route to the dashboard once status = 'ready'.
    } catch (e) {
      setState(() { _errorText = 'Failed to pair. Please try again.'; });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  String _generateSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      appBar: AppBar(
        title: const Text('Connect with Partner'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.burntOrange))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Icon(Icons.favorite, size: 72, color: AppTheme.burntOrange),
                  const SizedBox(height: 16),
                  Text(
                    'Pair Your Vault',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'One partner creates a code, the other enters it. This links your encrypted scrapbook forever.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 48),

                  // ── CREATE SECTION ───────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.earthyBrown.withOpacity(0.15)),
                    ),
                    child: Column(
                      children: [
                        Text('Step 1: Create a Code', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        Text(
                          'Share this 6-digit code with your partner.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        if (_generatedCode != null) ...[
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: _generatedCode!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Code copied to clipboard!')),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                              decoration: BoxDecoration(
                                color: AppTheme.burntOrange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.burntOrange),
                              ),
                              child: Text(
                                _generatedCode!,
                                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                  letterSpacing: 8,
                                  color: AppTheme.burntOrange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('Tap to copy · Expires in 15 min', style: Theme.of(context).textTheme.bodySmall),
                        ] else
                          ElevatedButton.icon(
                            onPressed: _createCode,
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('Generate Pairing Code'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.burntOrange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Row(children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('OR'),
                    ),
                    Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 24),

                  // ── JOIN SECTION ─────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.earthyBrown.withOpacity(0.15)),
                    ),
                    child: Column(
                      children: [
                        Text('Step 2: Enter Partner\'s Code', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(letterSpacing: 6),
                          decoration: const InputDecoration(
                            hintText: '000000',
                            counterText: '',
                          ),
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _joinWithCode,
                          icon: const Icon(Icons.link),
                          label: const Text('Pair Now'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.earthyBrown,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_errorText != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorText!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
