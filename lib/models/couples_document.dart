import 'package:cloud_firestore/cloud_firestore.dart';

class CouplesDocument {
  final String id;
  final String userA;
  final String userAEmail;
  final String userB;
  final String userBEmail;
  final String cryptoSalt;
  final String handshakeStatus;
  final String? masterDriveFolderId;
  final DateTime createdAt;

  CouplesDocument({
    required this.id,
    required this.userA,
    required this.userAEmail,
    required this.userB,
    required this.userBEmail,
    required this.cryptoSalt,
    required this.handshakeStatus,
    this.masterDriveFolderId,
    required this.createdAt,
  });

  factory CouplesDocument.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CouplesDocument(
      id: doc.id,
      userA: data['user_a'] ?? '',
      userAEmail: data['user_a_email'] ?? '',
      userB: data['user_b'] ?? '',
      userBEmail: data['user_b_email'] ?? '',
      cryptoSalt: data['crypto_salt'] ?? '',
      handshakeStatus: data['handshake_status'] ?? '',
      masterDriveFolderId: data['master_drive_folder_id'],
      createdAt: (data['created_at'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'user_a': userA,
      'user_a_email': userAEmail,
      'user_b': userB,
      'user_b_email': userBEmail,
      'crypto_salt': cryptoSalt,
      'handshake_status': handshakeStatus,
      'master_drive_folder_id': masterDriveFolderId,
      'created_at': Timestamp.fromDate(createdAt),
    };
  }
}
