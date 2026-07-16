import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/couples_document.dart';
import '../models/pairing_code.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _generateSixDigitCode() {
    final rng = Random();
    return (rng.nextInt(900000) + 100000).toString();
  }

  Future<PairingCode> createPairingCode(String creatorUid, String creatorEmail) async {
    final code = _generateSixDigitCode();
    final expiresAt = DateTime.now().add(const Duration(minutes: 15));

    final pairingCode = PairingCode(
      id: '', // Will be set after creation
      code: code,
      creatorUid: creatorUid,
      creatorEmail: creatorEmail,
      expiresAt: expiresAt,
    );

    final docRef = await _db.collection('pairing_codes').add(pairingCode.toFirestore());
    return PairingCode(
      id: docRef.id,
      code: code,
      creatorUid: creatorUid,
      creatorEmail: creatorEmail,
      expiresAt: expiresAt,
    );
  }

  Future<PairingCode?> findPairingCode(String code) async {
    final snapshot = await _db
        .collection('pairing_codes')
        .where('code', isEqualTo: code)
        .where('expires_at', isGreaterThan: Timestamp.now())
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    return PairingCode.fromFirestore(snapshot.docs.first);
  }

  Future<String> createCouplesDocument({
    required String userAUid,
    required String userAEmail,
    required String userBUid,
    required String userBEmail,
    required String salt,
  }) async {
    final docRef = _db.collection('couples').doc(); // Auto ID
    final coupleDoc = CouplesDocument(
      id: docRef.id,
      userA: userAUid,
      userAEmail: userAEmail,
      userB: userBUid,
      userBEmail: userBEmail,
      cryptoSalt: salt,
      handshakeStatus: 'creating_folder',
      createdAt: DateTime.now(),
    );

    await docRef.set(coupleDoc.toFirestore());
    return docRef.id;
  }

  Stream<CouplesDocument?> watchCouplesDocument(String uid) {
    // Try to find where user is A or B. Firestore 'or' queries are supported in v4.x
    // Alternatively, stream user A and user B separately, but modern Firestore has 'or'.
    return _db.collection('couples')
        .where(Filter.or(
          Filter('user_a', isEqualTo: uid),
          Filter('user_b', isEqualTo: uid),
        ))
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      return CouplesDocument.fromFirestore(snapshot.docs.first);
    });
  }

  Future<void> updateMasterFolderId(String id, String folderId) async {
    await _db.collection('couples').doc(id).update({'master_drive_folder_id': folderId});
  }

  Future<void> deleteCouplesDocument(String id) async {
    await _db.collection('couples').doc(id).delete();
  }

  Future<void> updateHandshakeStatus(String docId, String status) async {
    await _db.collection('couples').doc(docId).update({
      'handshake_status': status,
    });
  }
}
