import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FollowEvent {
  final String actorUid;
  final String targetUid;
  final bool followed;

  const FollowEvent({
    required this.actorUid,
    required this.targetUid,
    required this.followed,
  });
}

class FollowUserSummary {
  final String uid;
  final String displayName;
  final String photoURL;

  const FollowUserSummary({
    required this.uid,
    required this.displayName,
    required this.photoURL,
  });
}

class _FollowUsersCacheEntry {
  final List<FollowUserSummary> users;
  final DateTime savedAt;

  const _FollowUsersCacheEntry(this.users, this.savedAt);

  bool get isFresh {
    return DateTime.now().difference(savedAt) < const Duration(minutes: 3);
  }
}

class FollowSystemService {
  FollowSystemService._();
  static final FollowSystemService I = FollowSystemService._();

  static final StreamController<FollowEvent> _bus =
      StreamController<FollowEvent>.broadcast();
  static final Map<String, _FollowUsersCacheEntry> _followUsersCache = {};
  Stream<FollowEvent> get events => _bus.stream;

  FirebaseFirestore get _fs => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  Future<void> followUser(String targetUid) async {
    final me = _auth.currentUser?.uid;
    if (me == null || me == targetUid) return;

    final followingDoc = _fs
        .collection('users')
        .doc(me)
        .collection('following')
        .doc(targetUid);
    final followerDoc = _fs
        .collection('users')
        .doc(targetUid)
        .collection('followers')
        .doc(me);

    final already = (await followingDoc.get(
      const GetOptions(source: Source.server),
    )).exists;
    if (already) return;

    final batch = _fs.batch();
    batch.set(followingDoc, {
      'by': me,
      'to': targetUid,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(followerDoc, {
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
    _clearFollowUsersCache(uid: me, collection: 'following');
    _clearFollowUsersCache(uid: targetUid, collection: 'followers');
    _bus.add(FollowEvent(actorUid: me, targetUid: targetUid, followed: true));
  }

  Future<void> unfollowUser(String targetUid) async {
    final me = _auth.currentUser?.uid;
    if (me == null || me == targetUid) return;

    final followingDoc = _fs
        .collection('users')
        .doc(me)
        .collection('following')
        .doc(targetUid);
    final followerDoc = _fs
        .collection('users')
        .doc(targetUid)
        .collection('followers')
        .doc(me);

    final exists = (await followingDoc.get(
      const GetOptions(source: Source.server),
    )).exists;
    if (!exists) return;

    final batch = _fs.batch();
    batch.delete(followingDoc);
    batch.delete(followerDoc);

    await batch.commit();
    _clearFollowUsersCache(uid: me, collection: 'following');
    _clearFollowUsersCache(uid: targetUid, collection: 'followers');
    _bus.add(FollowEvent(actorUid: me, targetUid: targetUid, followed: false));
  }

  String _cacheKey(String uid, String collection) => '$uid::$collection';

  List<FollowUserSummary>? getCachedFollowUsers({
    required String uid,
    required String collection,
  }) {
    final entry = _followUsersCache[_cacheKey(uid, collection)];
    if (entry == null) return null;
    if (!entry.isFresh) {
      _followUsersCache.remove(_cacheKey(uid, collection));
      return null;
    }
    return List<FollowUserSummary>.unmodifiable(entry.users);
  }

  void _cacheFollowUsers({
    required String uid,
    required String collection,
    required List<FollowUserSummary> users,
  }) {
    _followUsersCache[_cacheKey(uid, collection)] = _FollowUsersCacheEntry(
      List<FollowUserSummary>.unmodifiable(users),
      DateTime.now(),
    );
  }

  void _clearFollowUsersCache({
    required String uid,
    required String collection,
  }) {
    _followUsersCache.remove(_cacheKey(uid, collection));
  }

  bool _isDeletedUser(Map<String, dynamic> data) {
    return data['isDeleted'] == true ||
        data['deleted'] == true ||
        data['accountDeleted'] == true ||
        data['deletedAt'] != null;
  }

  Future<List<FollowUserSummary>> fetchExistingFollowUsers({
    required String uid,
    required String collection,
    Iterable<String>? relationIds,
  }) async {
    final ids = relationIds != null
        ? relationIds.toList()
        : (await _fs.collection('users').doc(uid).collection(collection).get())
              .docs
              .map((doc) => doc.id)
              .toList();

    final cleanIds = <String>[];
    final seen = <String>{};
    for (final rawId in ids) {
      final id = rawId.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      cleanIds.add(id);
    }
    if (cleanIds.isEmpty) {
      _cacheFollowUsers(uid: uid, collection: collection, users: const []);
      return const [];
    }

    final usersById = <String, FollowUserSummary>{};
    for (var i = 0; i < cleanIds.length; i += 10) {
      final chunk = cleanIds.sublist(
        i,
        i + 10 > cleanIds.length ? cleanIds.length : i + 10,
      );
      final qs = await _fs
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();

      for (final doc in qs.docs) {
        final data = doc.data();
        if (_isDeletedUser(data)) continue;

        final displayName = (data['displayName'] ?? data['username'] ?? 'User')
            .toString()
            .trim();
        final photoURL = (data['photoURL'] ?? '').toString();
        usersById[doc.id] = FollowUserSummary(
          uid: doc.id,
          displayName: displayName.isEmpty ? 'User' : displayName,
          photoURL: photoURL,
        );
      }
    }

    final users = [
      for (final id in cleanIds)
        if (usersById[id] != null) usersById[id]!,
    ];
    _cacheFollowUsers(uid: uid, collection: collection, users: users);
    return users;
  }

  Future<int> fetchFollowerCountOnce(String uid) async {
    final users = await fetchExistingFollowUsers(
      uid: uid,
      collection: 'followers',
    );
    return users.length;
  }

  Future<int> fetchFollowingCountOnce(String uid) async {
    final users = await fetchExistingFollowUsers(
      uid: uid,
      collection: 'following',
    );
    return users.length;
  }
}
