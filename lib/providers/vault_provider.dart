import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../services/auth_service.dart';
import '../services/drive_service.dart';
import 'session_provider.dart';
import 'handshake_provider.dart';
import '../utils/crypto_utils.dart';

class VaultProvider extends ChangeNotifier {
  final AuthService? _authService;
  final SessionProvider? _sessionProvider;
  final HandshakeProvider? _handshakeProvider;

  VaultProvider(this._authService, this._sessionProvider, this._handshakeProvider);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<drive.File> _items = [];
  String? _errorMessage;

  List<drive.File> get items => _items;
  String? get errorMessage => _errorMessage;

  Future<DriveService?> _getDriveService() async {
    if (_authService == null) return null;
    final client = await _authService.getAuthenticatedHttpClient();
    if (client == null) return null;
    return DriveService(drive.DriveApi(client));
  }

  /// Creates a subfolder with regex sanitized location and explicitly grants partner writer permission.
  Future<String?> createSubfolder(String location) async {
    final driveService = await _getDriveService();
    if (driveService == null || _handshakeProvider == null || _authService == null) return null;

    final doc = _handshakeProvider.couplesDocument;
    if (doc == null || doc.masterDriveFolderId == null) return null;

    final currentEmail = _authService.currentUser?.email ?? '';

    _isLoading = true;
    notifyListeners();

    try {
      // Apply exact regex sanitization rule
      final sanitizedLocation = location
          .replaceAll(RegExp(r'[^a-zA-Z0-9\s\-_]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');

      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final folderName = '${dateStr}_$sanitizedLocation';

      // Create the subfolder inside the master folder
      final subfolderId = await driveService.createFolder(folderName, parentId: doc.masterDriveFolderId);

      // Grant partner access — skip granting if email matches current user (can't grant yourself permission)
      if (doc.userAEmail.isNotEmpty && doc.userAEmail != currentEmail) {
        await driveService.grantWriterPermission(subfolderId, doc.userAEmail);
      }
      if (doc.userBEmail.isNotEmpty && doc.userBEmail != currentEmail && doc.userBEmail != doc.userAEmail) {
        await driveService.grantWriterPermission(subfolderId, doc.userBEmail);
      }

      return subfolderId;
    } catch (e) {
      print("Error creating subfolder: $e");
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetches items (folders or files) for the given folder ID
  Future<void> fetchItems(String folderId) async {
    final driveService = await _getDriveService();
    if (driveService == null) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      print('[VaultProvider] Fetching items for folder ID: $folderId');
      final allItems = await driveService.listChildren(folderId);
      print('[VaultProvider] Raw items returned: ${allItems.length}');
      for (var file in allItems) {
        print('[VaultProvider] Found: ${file.name} (mimeType: ${file.mimeType})');
      }

      // Filter out Google Docs/Sheets files that cause 403 errors when trying to download as binary
      _items = allItems.where((file) {
        final mimeType = file.mimeType ?? '';
        if (mimeType == 'application/vnd.google-apps.folder') return true;
        if (mimeType.startsWith('application/vnd.google-apps.')) return false;
        return true;
      }).toList();
      print('[VaultProvider] Filtered items: ${_items.length}');
    } catch (e) {
      print('[VaultProvider] Error fetching items: $e');
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Uploads an encrypted photo
  Future<void> uploadPhoto(String folderId, String fileName, Uint8List rawBytes) async {
    final driveService = await _getDriveService();
    if (driveService == null || _sessionProvider == null) return;

    final key = _sessionProvider.masterKey;
    if (key == null) throw Exception("Session locked. Master key is not in memory.");

    _isLoading = true;
    notifyListeners();

    try {
      // Encrypt the photo
      final encryptedBytes = CryptoUtils.encryptFile(rawBytes, key);
      
      // Upload the encrypted blob
      await driveService.uploadFile(folderId, fileName, encryptedBytes);
      
      // Refresh the list after upload
      await fetchItems(folderId);
    } catch (e) {
      print("Error uploading photo: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Lazy loads and decrypts an image yielding a MemoryImage.
  /// Scopes variables carefully to allow GC to reclaim intermediate buffers immediately.
  Future<MemoryImage?> decryptPhoto(String fileId) async {
    final driveService = await _getDriveService();
    if (driveService == null || _sessionProvider == null) return null;

    final key = _sessionProvider.masterKey;
    if (key == null) return null;

    try {
      // Download encrypted blob
      Uint8List? encryptedBytes = await driveService.downloadFile(fileId);
      
      // Decrypt
      Uint8List? decryptedBytes = CryptoUtils.decryptFile(encryptedBytes, key);
      
      // Create memory image
      final image = MemoryImage(decryptedBytes);
      
      // Explicitly nullify references to large intermediate buffers
      encryptedBytes = null;
      decryptedBytes = null;
      
      return image;
    } catch (e) {
      print("Error decrypting photo: $e");
      return null;
    }
  }

  /// Downloads an encrypted blob directly from Drive (for Isolate decryption).
  Future<Uint8List?> downloadEncryptedBlob(String fileId) async {
    final driveService = await _getDriveService();
    if (driveService == null) return null;

    try {
      return await driveService.downloadFile(fileId);
    } catch (e) {
      print("Error downloading blob: $e");
      return null;
    }
  }

  /// Deletes an item from Google Drive
  Future<void> deleteItem(String fileId) async {
    final driveService = await _getDriveService();
    if (driveService == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      await driveService.deleteFile(fileId);
      // Remove from local list to avoid extra network fetch
      _items.removeWhere((file) => file.id == fileId);
    } catch (e) {
      print("Error deleting item: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetches the first image in a folder to use as a thumbnail preview
  Future<MemoryImage?> fetchFolderThumbnail(String folderId) async {
    final driveService = await _getDriveService();
    if (driveService == null) return null;

    try {
      final children = await driveService.listChildren(folderId);
      final firstImage = children.firstWhere(
        (f) => f.mimeType != 'application/vnd.google-apps.folder',
        orElse: () => drive.File()..id = null, // Return empty File instead of null to bypass type errors
      );

      if (firstImage.id == null) return null; // Folder has no images

      return await decryptPhoto(firstImage.id!);
    } catch (e) {
      print("Error fetching folder thumbnail: $e");
      return null;
    }
  }
}
