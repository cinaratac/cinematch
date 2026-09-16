import 'package:cloud_firestore/cloud_firestore.dart';

class BlockingService {
  BlockingService._();
  static final BlockingService instance = BlockingService._();

  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  /// Kullanıcıyı Engelle (Çift taraflı kayıt atar)
  Future<void> blockUser({
    required String currentUserId,
    required String targetUserId,
  }) async {
    final batch = _fs.batch();

    // 1. Benim engellediklerim listeme ekle
    final myBlockRef = _fs
        .collection('users')
        .doc(currentUserId)
        .collection('blocked')
        .doc(targetUserId);
    batch.set(myBlockRef, {'createdAt': FieldValue.serverTimestamp()});

    // 2. Karşı tarafın "beni engelleyenler" listesine ekle
    final hisBlockedByRef = _fs
        .collection('users')
        .doc(targetUserId)
        .collection('blockedBy')
        .doc(currentUserId);
    batch.set(hisBlockedByRef, {'createdAt': FieldValue.serverTimestamp()});

    await batch.commit();
  }

  /// Engeli Kaldır
  Future<void> unblockUser({
    required String currentUserId,
    required String targetUserId,
  }) async {
    final batch = _fs.batch();

    final myBlockRef = _fs
        .collection('users')
        .doc(currentUserId)
        .collection('blocked')
        .doc(targetUserId);
    batch.delete(myBlockRef);

    final hisBlockedByRef = _fs
        .collection('users')
        .doc(targetUserId)
        .collection('blockedBy')
        .doc(currentUserId);
    batch.delete(hisBlockedByRef);

    await batch.commit();
  }

  /// Feed ve Öneriler için FİLTRELEME Listesi
  /// Hem senin engellediğin hem de seni engelleyen kullanıcıların ID'lerini Set olarak döner.
  Future<Set<String>> getBlockedAndBlockerIds(String userId) async {
    final blockedIds = <String>{};

    try {
      final blockedSnap = await _fs
          .collection('users')
          .doc(userId)
          .collection('blocked')
          .get();
      final blockedBySnap = await _fs
          .collection('users')
          .doc(userId)
          .collection('blockedBy')
          .get();

      for (var doc in blockedSnap.docs) {
        blockedIds.add(doc.id);
      }
      for (var doc in blockedBySnap.docs) {
        blockedIds.add(doc.id);
      }
    } catch (e) {
      // Hata durumu
    }

    return blockedIds;
  }

  /// İki kullanıcı arasında herhangi bir engelleme (sen onu veya o seni) var mı?
  /// İki kullanıcı arasındaki engelleme durumunu detaylı döner
  Future<Map<String, bool>> checkBlockStatus({
    required String currentUserId,
    required String targetUserId,
  }) async {
    bool iBlockedThem = false;
    bool theyBlockedMe = false;

    try {
      // 1. Ben onu engelledim mi?
      final meBlocked = await _fs
          .collection('users')
          .doc(currentUserId)
          .collection('blocked')
          .doc(targetUserId)
          .get();
      iBlockedThem = meBlocked.exists;

      // 2. O beni engellemiş mi? (Benim 'blockedBy' listemde o var mı?)
      final heBlocked = await _fs
          .collection('users')
          .doc(currentUserId)
          .collection('blockedBy')
          .doc(targetUserId)
          .get();
      theyBlockedMe = heBlocked.exists;
    } catch (e) {
      // Hata durumu
    }

    return {
      'iBlockedThem': iBlockedThem,
      'theyBlockedMe': theyBlockedMe,
    };
  }
}