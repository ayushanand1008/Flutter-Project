import 'dart:typed_data';
import 'package:googleapis/drive/v3.dart' as drive;

class DriveService {
  final drive.DriveApi _api;

  DriveService(this._api);

  Future<String> createFolder(String name, {String? parentId}) async {
    final folder = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder';

    if (parentId != null) {
      folder.parents = [parentId];
    }

    final created = await _api.files.create(folder);
    return created.id!;
  }

  Future<void> grantWriterPermission(String folderId, String emailAddress) async {
    final permission = drive.Permission()
      ..type = 'user'
      ..role = 'writer'
      ..emailAddress = emailAddress;

    await _api.permissions.create(
      permission,
      folderId,
      sendNotificationEmail: false,
    );
  }

  Future<List<drive.File>> listChildren(String folderId) async {
    final fileList = await _api.files.list(
      q: "'$folderId' in parents and trashed = false",
      $fields: 'files(id, name, mimeType, modifiedTime)',
      orderBy: 'modifiedTime desc',
      // Ensure we search across shared items
      supportsAllDrives: true,
      includeItemsFromAllDrives: true,
      corpora: 'allDrives',
    );
    return fileList.files ?? [];
  }

  Future<drive.File> getFile(String fileId) async {
    return await _api.files.get(
      fileId,
      $fields: 'id, name, mimeType, parents',
    ) as drive.File;
  }

  Future<String> uploadFile(String folderId, String name, Uint8List bytes, {String mimeType = 'application/octet-stream'}) async {
    final file = drive.File()
      ..name = name
      ..parents = [folderId];

    final media = drive.Media(
      Stream.value(bytes.toList()),
      bytes.length,
      contentType: mimeType,
    );

    final created = await _api.files.create(file, uploadMedia: media);
    return created.id!;
  }

  Future<Uint8List> downloadFile(String fileId) async {
    final media = await _api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final bytes = <int>[];
    await for (var chunk in media.stream) {
      bytes.addAll(chunk);
    }
    return Uint8List.fromList(bytes);
  }

  Future<void> deleteFile(String fileId) async {
    await _api.files.delete(fileId);
  }
}
