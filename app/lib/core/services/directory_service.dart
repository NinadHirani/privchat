import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

class DirectoryUser {
  final String userId;
  final String displayName;
  final String edPublicKey;
  final String? photoUrl;

  const DirectoryUser({
    required this.userId,
    required this.displayName,
    required this.edPublicKey,
    this.photoUrl,
  });

  factory DirectoryUser.fromMap(Map<String, dynamic> map) {
    return DirectoryUser(
      userId: map['userId'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      edPublicKey: map['edPublicKey'] as String? ?? '',
      photoUrl: map['photoUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'displayName': displayName,
      'edPublicKey': edPublicKey,
      if (photoUrl != null && photoUrl!.isNotEmpty) 'photoUrl': photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class DirectoryService {
  DirectoryService._();
  static final DirectoryService I = DirectoryService._();

  static String normalizePhone(String raw) {
    var p = raw.replaceAll(RegExp(r'[^\d+]'), '');
    return p;
  }

  static String normalizeEmail(String raw) {
    return raw.trim().toLowerCase();
  }

  static String hashIdentifier(String normalized) {
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  /// Registers user's identifiers (phone and/or email) into Firestore as SHA-256 hashes.
  /// Neither phone numbers nor emails are stored in plaintext.
  Future<void> publishIdentity({
    required String userId,
    required String edPublicKey,
    required String displayName,
    String? phone,
    String? email,
    String? photoUrl,
  }) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();

      final record = DirectoryUser(
        userId: userId,
        displayName: displayName,
        edPublicKey: edPublicKey,
        photoUrl: photoUrl,
      ).toMap();

      bool hasEntry = false;

      if (phone != null && phone.trim().isNotEmpty) {
        final norm = normalizePhone(phone);
        if (norm.length >= 7) {
          final h = hashIdentifier(norm);
          final ref = firestore.collection('directory_hashes').doc(h);
          batch.set(ref, record, SetOptions(merge: true));
          hasEntry = true;
        }
      }

      if (email != null && email.trim().isNotEmpty) {
        final norm = normalizeEmail(email);
        if (norm.contains('@') && norm.contains('.')) {
          final h = hashIdentifier(norm);
          final ref = firestore.collection('directory_hashes').doc(h);
          batch.set(ref, record, SetOptions(merge: true));
          hasEntry = true;
        }
      }

      if (hasEntry) {
        await batch.commit();
      }
    } catch (e) {
      // Non-blocking in case of offline/mesh mode or firestore errors
    }
  }

  /// Given a collection of phone numbers and emails, queries Firestore using SHA-256 hashes
  /// in batches of up to 30 documents. Returns a map from hash -> DirectoryUser.
  Future<Map<String, DirectoryUser>> batchLookupHashes(Set<String> hashes) async {
    final result = <String, DirectoryUser>{};
    if (hashes.isEmpty) return result;

    try {
      final firestore = FirebaseFirestore.instance;
      final hashList = hashes.toList();
      const chunkSize = 30; // Firestore whereIn limit

      for (var i = 0; i < hashList.length; i += chunkSize) {
        final chunk = hashList.sublist(
          i,
          (i + chunkSize > hashList.length) ? hashList.length : i + chunkSize,
        );

        final querySnap = await firestore
            .collection('directory_hashes')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();

        for (final doc in querySnap.docs) {
          final data = doc.data();
          result[doc.id] = DirectoryUser.fromMap(data);
        }
      }
    } catch (_) {
      // Fallback gracefully if network is unavailable
    }

    return result;
  }
}
