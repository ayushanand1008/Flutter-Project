import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../services/auth_service.dart';
import '../services/drive_service.dart';
import '../services/firestore_service.dart';
import '../providers/session_provider.dart';
import '../providers/handshake_provider.dart';
import '../utils/crypto_utils.dart';
import '../main.dart'; // For appRouter

class ExitStrategyService {
  final AuthService authService;
  final FirestoreService firestoreService;
  final SessionProvider sessionProvider;
  final HandshakeProvider handshakeProvider;

  ExitStrategyService({
    required this.authService,
    required this.firestoreService,
    required this.sessionProvider,
    required this.handshakeProvider,
  });

  /// Executes the bulk decryption export and terminates the vault safely.
  Future<void> triggerSafeExit(void Function(String) onProgress) async {
    final client = await authService.getAuthenticatedHttpClient();
    if (client == null) throw Exception("Not authenticated");
    final driveService = DriveService(drive.DriveApi(client));

    final doc = handshakeProvider.couplesDocument;
    if (doc == null) throw Exception("No active vault found.");

    final masterKey = sessionProvider.masterKey;
    if (masterKey == null) throw Exception("Session is locked.");

    // Signal HandshakeProvider not to auto-sign-out when it sees 'terminating'
    handshakeProvider.isExiting = true;

    try {
      // 1. Create Decrypted Export Directory
      onProgress("Creating Export Directory...");
      print('[EXIT] Creating export folder...');
      final exportFolderId = await driveService.createFolder('Our_Scrapbook_Decrypted_Export');
      print('[EXIT] Export folder created: $exportFolderId');
      
      // Grant partner access to the export folder (skip self)
      final currentEmail = authService.currentUser?.email ?? '';
      final partnerEmail = (doc.userA == authService.currentUser?.uid) ? doc.userBEmail : doc.userAEmail;
      if (partnerEmail.isNotEmpty && partnerEmail != currentEmail) {
        await driveService.grantWriterPermission(exportFolderId, partnerEmail);
      }

      // 2. Worker Queue to bulk-decrypt subfolders and files
      if (doc.masterDriveFolderId != null) {
        onProgress("Fetching folders to decrypt...");
        print('[EXIT] masterDriveFolderId = ${doc.masterDriveFolderId}');
        final subfolders = await driveService.listChildren(doc.masterDriveFolderId!);

        print('[EXIT] Found ${subfolders.length} subfolders to export');
        for (var folder in subfolders) {
          if (folder.id == null || folder.name == null) continue;
          // Only process actual folders, skip Google Docs types
          if (folder.mimeType != 'application/vnd.google-apps.folder') continue;

          // Create matching subfolder in export dir
          onProgress("Exporting ${folder.name}...");
          print('[EXIT] Creating export subfolder for: ${folder.name}');
          final exportSubfolderId = await driveService.createFolder(
            folder.name!,
            parentId: exportFolderId,
          );

          // Get files in subfolder
          final files = await driveService.listChildren(folder.id!);
          print('[EXIT] Found ${files.length} files in ${folder.name}');

          for (var file in files) {
            // Skip non-binary Google Workspace files
            final mimeType = file.mimeType ?? '';
            if (mimeType.startsWith('application/vnd.google-apps.') && mimeType != 'application/vnd.google-apps.folder') {
              print('[EXIT] Skipping Google Workspace file: ${file.name}');
              continue;
            }

            try {
              // Step 3a: Download encrypted blob
              print('[EXIT] Downloading: ${file.name}');
              Uint8List? encryptedBlob = await driveService.downloadFile(file.id!);
              if (encryptedBlob == null) continue;

              // Step 3b: Decrypt in memory (Isolate)
              final payload = {
                'data': encryptedBlob,
                'key': masterKey,
              };
              Uint8List? decryptedData = await compute(_decryptInIsolate, payload);

              if (decryptedData == null) continue;

              // Step 3c: Upload decrypted file to export folder
              final originalName = file.name ?? 'export';
              final decryptedName = originalName.endsWith('.jpg') || originalName.endsWith('.png')
                  ? originalName
                  : '$originalName.jpg';

              print('[EXIT] Uploading decrypted: $decryptedName');
              await driveService.uploadFile(exportSubfolderId, decryptedName, decryptedData, mimeType: 'image/jpeg');
              print('[EXIT] Done: $decryptedName');
            } catch (fileErr) {
              print('[EXIT] Failed to export file ${file.name}: $fileErr');
              // Continue with remaining files
            }
          }
        }

        // 3. Cascade Cleanup: Delete original encrypted vault folder
        onProgress("Cleaning up encrypted vault...");
        print('[EXIT] Deleting original encrypted vault folder...');
        await driveService.deleteFile(doc.masterDriveFolderId!);
      }

      // 4. Notify partner (AFTER export is done, so sign-out doesn't interrupt Drive)
      onProgress("Notifying partner...");
      print('[EXIT] Setting terminating status in Firestore...');
      await firestoreService.updateHandshakeStatus(doc.id, 'terminating');

      // 5. Delete Firestore Document
      onProgress("Deleting cloud references...");
      await firestoreService.deleteCouplesDocument(doc.id);

      // 6. Safe local exit
      onProgress("Finalizing exit...");
      print('[EXIT] Clearing local state and signing out...');
      
      sessionProvider.lock();
      await authService.signOut();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('has_set_password');
      await prefs.remove('decoy_password');

      appRouter.go('/setup');

    } catch (e, st) {
      print('[EXIT] FATAL ERROR during export: $e');
      print(st);
      onProgress("Error: $e");
      rethrow;
    }
  }

  /// Top-level compute isolate function
  static Uint8List _decryptInIsolate(Map<String, dynamic> payload) {
    final Uint8List data = payload['data'] as Uint8List;
    final Uint8List key = payload['key'] as Uint8List;
    return CryptoUtils.decryptFile(data, key);
  }
}
