import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class CryptoUtils {
  static const int _ivLength = 12;
  static const int _macLength = 16;

  /// Derives a 256-bit (32-byte) key using PBKDF2 (HMAC-SHA256)
  static Uint8List deriveKey(String password, String saltHex) {
    final salt = _hexToBytes(saltHex);
    final passwordBytes = Uint8List.fromList(utf8.encode(password));

    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, 100000, 32)); // 100k iterations, 32 bytes

    return derivator.process(passwordBytes);
  }

  /// Encrypts bytes using AES-256-GCM.
  /// Returns a packed blob: [12 bytes IV] + [16 bytes Auth Tag] + [Ciphertext]
  static Uint8List encryptFile(Uint8List data, Uint8List key) {
    final random = Random.secure();
    final iv = Uint8List(_ivLength);
    for (int i = 0; i < _ivLength; i++) {
      iv[i] = random.nextInt(256);
    }

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true, // encrypt
        AEADParameters(
          KeyParameter(key),
          _macLength * 8, // length in bits
          iv,
          Uint8List(0),
        ),
      );

    final ciphertextWithMac = cipher.process(data);

    // Pointycastle appends MAC to ciphertext. We need to unpack and repack.
    final actualCiphertextLength = ciphertextWithMac.length - _macLength;
    final actualCiphertext = ciphertextWithMac.sublist(0, actualCiphertextLength);
    final mac = ciphertextWithMac.sublist(actualCiphertextLength);

    final blob = BytesBuilder(copy: false);
    blob.add(iv);
    blob.add(mac);
    blob.add(actualCiphertext);
    return blob.toBytes();
  }

  /// Decrypts a packed blob: [12 bytes IV] + [16 bytes Auth Tag] + [Ciphertext]
  static Uint8List decryptFile(Uint8List packedData, Uint8List key) {
    if (packedData.length < _ivLength + _macLength) {
      throw Exception('Invalid data size. Must contain at least IV and Auth Tag.');
    }

    final iv = packedData.sublist(0, _ivLength);
    final mac = packedData.sublist(_ivLength, _ivLength + _macLength);
    final ciphertext = packedData.sublist(_ivLength + _macLength);

    // Reconstruct pointycastle expected format: ciphertext + mac
    final pointycastleFormat = BytesBuilder(copy: false);
    pointycastleFormat.add(ciphertext);
    pointycastleFormat.add(mac);
    final pcBytes = pointycastleFormat.toBytes();

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false, // decrypt
        AEADParameters(
          KeyParameter(key),
          _macLength * 8,
          iv,
          Uint8List(0),
        ),
      );

    return cipher.process(pcBytes);
  }

  static Uint8List _hexToBytes(String hexString) {
    final bytes = Uint8List(hexString.length ~/ 2);
    for (int i = 0; i < hexString.length; i += 2) {
      bytes[i ~/ 2] = int.parse(hexString.substring(i, i + 2), radix: 16);
    }
    return bytes;
  }
}
