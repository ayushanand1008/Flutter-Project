import 'dart:async';
import 'package:flutter/material.dart';
import '../models/couples_document.dart';
import '../services/firestore_service.dart';
import '../services/drive_service.dart';
import '../services/auth_service.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // To access appRouter
import '../providers/session_provider.dart';

class HandshakeProvider extends ChangeNotifier {
  final FirestoreService _firestoreService;
  final AuthService _authService;
  final SessionProvider _sessionProvider;
  
  CouplesDocument? _couplesDocument;
  StreamSubscription<CouplesDocument?>? _couplesSubscription;
  bool isExiting = false; // Set true during self-initiated export to prevent premature sign-out

  HandshakeProvider(this._firestoreService, this._authService, this._sessionProvider);

  CouplesDocument? get couplesDocument => _couplesDocument;
  String get handshakeStatus => _couplesDocument?.handshakeStatus ?? 'idle';

  void initialize(String uid) {
    _couplesSubscription?.cancel();
    _couplesSubscription = _firestoreService.watchCouplesDocument(uid).listen((doc) async {
      _couplesDocument = doc;
      notifyListeners();

      if (doc != null && doc.handshakeStatus == 'terminating') {
        // Only react to partner's termination, not our own export
        if (!isExiting) {
          await _clearLocalState();
        }
        return;
      }

      // Either partner can create the folder if they are the first to hit this state
      if (doc != null && doc.handshakeStatus == 'creating_folder') {
        await _processFolderCreation(doc);
      }
    });
  }

  Future<void> _clearLocalState() async {
    // 1. Wipe local session key
    _sessionProvider.lock();
    
    // 2. Clear user state
    await _authService.signOut();
    
    // 3. Clear preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('has_set_password');
    await prefs.remove('decoy_password');

    // 4. Force route wipe
    appRouter.go('/setup');
  }

  Future<void> _processFolderCreation(CouplesDocument doc) async {
    try {
      print('[FOLDER] Starting folder creation process');
      final client = await _authService.getAuthenticatedHttpClient();
      if (client == null) {
        print('[FOLDER] HTTP Client is NULL. Aborting.');
        return;
      }
      print('[FOLDER] Got HTTP Client');

      final driveService = DriveService(drive.DriveApi(client));
      final uid = _authService.currentUser?.uid;
      print('[FOLDER] Current UID: $uid');
      print('[FOLDER] User A: ${doc.userA}, User B: ${doc.userB}');

      // Create master folder
      print('[FOLDER] Creating Our_Scrapbook folder on Drive...');
      final folderId = await driveService.createFolder('Our_Scrapbook');
      print('[FOLDER] Folder created with ID: $folderId');

      // Grant the OTHER partner writer permission (skip if simulating with same account)
      final otherEmail = (doc.userA == uid) ? doc.userBEmail : doc.userAEmail;
      print('[FOLDER] Granting permission to other email: $otherEmail');
      
      if (otherEmail != _authService.currentUser?.email) {
        await driveService.grantWriterPermission(folderId, otherEmail);
        print('[FOLDER] Permission granted!');
      } else {
        print('[FOLDER] Skipping permission grant because simulating with same account.');
      }

      // Update Firestore to 'ready'
      print('[FOLDER] Updating Firestore to ready status...');
      await _firestoreService.updateMasterFolderId(doc.id, folderId);
      await _firestoreService.updateHandshakeStatus(doc.id, 'ready');
      print('[FOLDER] Done!');
    } catch (e, st) {
      print('[FOLDER] Error during folder creation: $e');
      print(st);
      // Change status to error so the UI can reflect it
      await _firestoreService.updateHandshakeStatus(doc.id, 'error');
    }
  }

  @override
  void dispose() {
    _couplesSubscription?.cancel();
    super.dispose();
  }
}
