import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../main.dart'; // To access appRouter

class SessionProvider extends ChangeNotifier with WidgetsBindingObserver {
  Uint8List? _volatileMasterKey;
  bool _isUnlocked = false;
  DateTime? _backgroundedAt;
  Timer? _lockTimer;
  
  SessionProvider() {
    WidgetsBinding.instance.addObserver(this);
  }

  bool get isUnlocked => _isUnlocked;

  void unlock(Uint8List key) {
    _volatileMasterKey = key;
    _isUnlocked = true;
    notifyListeners();
  }

  void lock() {
    _volatileMasterKey = null;
    _isUnlocked = false;
    notifyListeners();
  }

  Uint8List? get masterKey => _volatileMasterKey;

  void _executeLock() {
    lock();
    // Wipe navigation stack back to decoy calculator
    appRouter.go('/calculator');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_backgroundedAt == null && _isUnlocked) {
        _backgroundedAt = DateTime.now();
        // Start 3-minute strict timer
        _lockTimer = Timer(const Duration(minutes: 3), () {
          _executeLock();
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      // Cancel timer since app resumed
      _lockTimer?.cancel();
      _lockTimer = null;

      if (_backgroundedAt != null) {
        final diff = DateTime.now().difference(_backgroundedAt!);
        if (diff.inMinutes >= 3) {
          // Double check in case timer was suspended by OS
          _executeLock();
        }
      }
      _backgroundedAt = null;
    }
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
