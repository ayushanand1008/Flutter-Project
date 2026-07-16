import 'package:cloud_firestore/cloud_firestore.dart';

class PairingCode {
  final String id;
  final String code;
  final String creatorUid;
  final String creatorEmail;
  final DateTime expiresAt;

  PairingCode({
    required this.id,
    required this.code,
    required this.creatorUid,
    required this.creatorEmail,
    required this.expiresAt,
  });

  factory PairingCode.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PairingCode(
      id: doc.id,
      code: data['code'] ?? '',
      creatorUid: data['creator_uid'] ?? '',
      creatorEmail: data['creator_email'] ?? '',
      expiresAt: (data['expires_at'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'code': code,
      'creator_uid': creatorUid,
      'creator_email': creatorEmail,
      'expires_at': Timestamp.fromDate(expiresAt),
    };
  }
}
