import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../providers/vault_provider.dart';
import '../../providers/session_provider.dart';
import '../../utils/crypto_utils.dart';
import '../theme/app_theme.dart';

class E2EEImageWidget extends StatefulWidget {
  final String fileId;
  final double? width;
  final double? height;
  final BoxFit fit;

  const E2EEImageWidget({
    super.key,
    required this.fileId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  State<E2EEImageWidget> createState() => _E2EEImageWidgetState();
}

class _E2EEImageWidgetState extends State<E2EEImageWidget> with SingleTickerProviderStateMixin {
  Uint8List? _decryptedBytes;
  bool _hasError = false;
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _loadAndDecryptImage();
  }

  Future<void> _loadAndDecryptImage() async {
    try {
      final vaultProvider = Provider.of<VaultProvider>(context, listen: false);
      final sessionProvider = Provider.of<SessionProvider>(context, listen: false);

      final key = sessionProvider.masterKey;
      if (key == null) {
        throw Exception("Session locked. Cannot decrypt.");
      }

      // Download the encrypted blob
      Uint8List? encryptedBlob = await vaultProvider.downloadEncryptedBlob(widget.fileId);
      if (encryptedBlob == null) {
        throw Exception("Failed to download blob.");
      }

      // Spawn an isolate to decrypt the payload
      final payload = {
        'data': encryptedBlob,
        'key': key,
      };

      final decrypted = await compute(_decryptInIsolate, payload);

      if (mounted) {
        setState(() {
          _decryptedBytes = decrypted;
        });
      }

      // Strict Memory Management: Explicitly nullify large byte buffers in scope
      encryptedBlob = null;
      payload.clear();
      
    } catch (e) {
      print("E2EEImageWidget Error: $e");
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  /// The top-level function executed in the Isolate.
  static Uint8List _decryptInIsolate(Map<String, dynamic> payload) {
    final Uint8List data = payload['data'] as Uint8List;
    final Uint8List key = payload['key'] as Uint8List;
    return CryptoUtils.decryptFile(data, key);
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    // CRITICAL: Explicitly nullify the decrypted bytes buffer for rapid Garbage Collection
    _decryptedBytes = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: AppTheme.backgroundCream.withOpacity(0.5),
        child: const Center(
          child: Icon(
            Icons.broken_image,
            color: AppTheme.earthyBrown,
            size: 48,
          ),
        ),
      );
    }

    if (_decryptedBytes == null) {
      return AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, child) {
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.backgroundCream,
                  AppTheme.backgroundCream.withOpacity(0.7),
                  AppTheme.backgroundCream,
                ],
                stops: const [0.0, 0.5, 1.0],
                begin: Alignment(-1.0 + (_shimmerController.value * 2), -0.3),
                end: Alignment(1.0 + (_shimmerController.value * 2), 0.3),
              ),
            ),
          );
        },
      );
    }

    return Image.memory(
      _decryptedBytes!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
    );
  }
}
