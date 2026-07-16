import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/vault_provider.dart';
import '../theme/app_theme.dart';

class AlbumScreen extends StatefulWidget {
  final drive.File folder;

  const AlbumScreen({super.key, required this.folder});

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  final ImagePicker _picker = ImagePicker();
  final Map<String, MemoryImage> _imageCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<VaultProvider>(context, listen: false).fetchItems(widget.folder.id!);
    });
  }

  Future<MemoryImage?> _getImage(String fileId, VaultProvider vault) async {
    if (_imageCache.containsKey(fileId)) return _imageCache[fileId];
    final image = await vault.decryptPhoto(fileId);
    if (image != null) {
      _imageCache[fileId] = image;
    }
    return image;
  }

  Future<void> _pickAndUploadImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      final vault = Provider.of<VaultProvider>(context, listen: false);
      await vault.uploadPhoto(widget.folder.id!, image.name, bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundCream,
      appBar: AppBar(
        title: Text(widget.folder.name ?? 'Album'),
        backgroundColor: AppTheme.burntOrange,
        foregroundColor: Colors.white,
      ),
      body: Consumer<VaultProvider>(
        builder: (context, vault, child) {
          if (vault.isLoading && vault.items.isEmpty) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.burntOrange));
          }

          if (vault.items.isEmpty) {
            return Center(
              child: Text(
                'No photos yet.\nTap + to add some!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: vault.items.length,
            itemBuilder: (context, index) {
              final file = vault.items[index];
              return FutureBuilder<MemoryImage?>(
                future: _getImage(file.id!, vault),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Container(
                      color: AppTheme.earthyBrown.withOpacity(0.3),
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.earthyBrown,
                          ),
                        ),
                      ),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Container(
                      color: Colors.red.withOpacity(0.1),
                      child: const Icon(Icons.broken_image, color: Colors.red),
                    );
                  }
                  return GestureDetector(
                    onLongPress: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete Photo?'),
                          content: const Text('This will permanently delete the photo from Google Drive.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true), 
                              child: const Text('Delete', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await vault.deleteItem(file.id!);
                        // Also remove from local cache
                        _imageCache.remove(file.id!);
                      }
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image(
                        image: snapshot.data!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndUploadImage,
        backgroundColor: AppTheme.burntOrange,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_photo_alternate),
      ),
    );
  }
}
