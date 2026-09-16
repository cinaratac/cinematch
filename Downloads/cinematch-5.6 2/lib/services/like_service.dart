import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Stable, order-independent pair id using two UIDs (sorted lexicographically)
String pairIdOf(String u1, String u2) =>
    (u1.compareTo(u2) < 0) ? '${u1}_$u2' : '${u2}_$u1';

class LikeService {
  LikeService._();
  static final instance = LikeService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _likesCol =>
      _db.collection('likes');
  CollectionReference<Map<String, dynamic>> get _matchesCol =>
      _db.collection('matches');
  CollectionReference<Map<String, dynamic>> get _chatsCol =>
      _db.collection('chats');

  bool _isTrue(dynamic v) => v == true;

  /// Current user's UID or throws if not signed in
  String get _uid =>
      _auth.currentUser?.uid ?? (throw StateError('No Firebase user'));

  /// Register a like from the current user to [otherUid].
  /// If both sides liked each other, creates/updates `matches/{pairId}` and a chat stub.
  Future<void> likeUser(
    String otherUid, {
    int commonFavoritesCount = 0,
    int commonFiveStarsCount = 0,
  }) async {
    final me = _uid;
    if (me == otherUid) return; // ignore self

    final pairId = pairIdOf(me, otherUid);
    final docRef = _likesCol.doc(pairId);

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        late String a;
        late String b;
        if (!snap.exists) {
          // First interaction for this pair
          a = (me.compareTo(otherUid) < 0) ? me : otherUid;
          b = (a == me) ? otherUid : me;

          final init = {
            'a': a,
            'b': b,
            'uids': [a, b],
            'aLiked': a == me,
            'bLiked': b == me,
            'aPass': false,
            'bPass': false,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          };

          // Yalnızca karşı tarafın "seen" bayrağını sıfırla (yeni bildirim)
          if (a == me) {
            init['bSeen'] = false;
          } else {
            init['aSeen'] = false;
          }

          tx.set(docRef, init);
          return;
        }

        final data = Map<String, dynamic>.from(snap.data()!);
        a = data['a'] as String;
        b = data['b'] as String;
        final meIsA = me == a;
        final likeField = meIsA ? 'aLiked' : 'bLiked';
        final passField = meIsA ? 'aPass' : 'bPass';

        final newALiked = meIsA ? true : (data['aLiked'] == true);
        final newBLiked = meIsA ? (data['bLiked'] == true) : true;
        final willBothLike = newALiked && newBLiked;

        // opposite user's seen flag name (the receiver side)
        final seenToReset = meIsA ? 'bSeen' : 'aSeen';

        // Only when my like transitions to true (or pass→like) do we reset receiver's seen to false.
        final shouldResetAndLike =
            (data[likeField] != true) || (data[passField] == true);

        if (shouldResetAndLike) {
          final Map<String, dynamic> upd = {
            likeField: true,
            passField: false, // like overrides pass
            'uids': FieldValue.arrayUnion([a, b]),
            'updatedAt': FieldValue.serverTimestamp(),
            // notify receiver: a fresh like
            seenToReset: false,
          };
          tx.update(docRef, upd);
        }

        if (willBothLike) {
          final matchId = pairId; // use the same id for simplicity
          final matchRef = _matchesCol.doc(matchId);
          final now = FieldValue.serverTimestamp();
          tx.set(matchRef, {
            'uids': [a, b],
            'commonFavoritesCount': commonFavoritesCount,
            'commonFiveStarsCount': commonFiveStarsCount,
            'createdAt': now,
            'updatedAt': now,
          }, SetOptions(merge: true));
        }
      });
    } catch (e) {
      final meIsA = (me.compareTo(otherUid) < 0);
      await docRef.set({
        'a': meIsA ? me : otherUid,
        'b': meIsA ? otherUid : me,
        'uids': [me, otherUid],
        // mark my side like, clear my pass
        meIsA ? 'aLiked' : 'bLiked': true,
        meIsA ? 'aPass' : 'bPass': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    // Mirror log to a separate collection
    try {
      await _db.collection('likeLogs').add({
        'from': me,
        'to': otherUid,
        'action': 'like',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // non-fatal
    }
  }

  /// Register a pass (skip). This does not delete likes; it just marks pass.
  Future<void> passUser(String otherUid) async {
    final me = _uid;
    if (me == otherUid) return;

    final pairId = pairIdOf(me, otherUid);
    final docRef = _likesCol.doc(pairId);

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        late String a;
        late String b;
        if (!snap.exists) {
          a = (me.compareTo(otherUid) < 0) ? me : otherUid;
          b = (a == me) ? otherUid : me;
          tx.set(docRef, {
            'a': a,
            'b': b,
            'uids': [a, b],
            'aLiked': false,
            'bLiked': false,
            'aPass': a == me,
            'bPass': b == me,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return;
        }

        final data = Map<String, dynamic>.from(snap.data()!);
        a = data['a'] as String;
        b = data['b'] as String;
        final meIsA = me == a;
        final passField = meIsA ? 'aPass' : 'bPass';
        if (data[passField] != true) {
          tx.update(docRef, {
            passField: true,
            'uids': FieldValue.arrayUnion([a, b]),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (e) {
      // Fallback merge write so pass is not lost if transaction fails
      await docRef.set({
        'a': (me.compareTo(otherUid) < 0) ? me : otherUid,
        'b': (me.compareTo(otherUid) < 0) ? otherUid : me,
        'uids': [me, otherUid],
        (me.compareTo(otherUid) < 0) ? 'aPass' : 'bPass': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    // Mirror log to a separate collection
    try {
      await _db.collection('likeLogs').add({
        'from': me,
        'to': otherUid,
        'action': 'pass',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // non-fatal
    }
  }

  /// Remove a match for this pair. Keeps the like history unless [alsoClearLikes] is true.
  Future<void> unmatch(String otherUid, {bool alsoClearLikes = false}) async {
    final me = _uid;
    final matchId = pairIdOf(me, otherUid);

    final batch = _db.batch();
    batch.delete(_matchesCol.doc(matchId));
    // Optionally clear like doc too
    if (alsoClearLikes) {
      batch.delete(_likesCol.doc(matchId));
    }
    // Optionally clear chat stub (messages subcollection left intact unless you also delete recursively via Cloud Functions)
    batch.delete(_chatsCol.doc(matchId));
    await batch.commit();
  }

  /// True if a match doc exists for current user and [otherUid]
  Future<bool> isMatchedWith(String otherUid) async {
    final me = _uid;
    final matchId = pairIdOf(me, otherUid);
    final doc = await _matchesCol.doc(matchId).get();
    return doc.exists;
  }

  /// Stream the current user's matches ordered by updatedAt desc
  Stream<QuerySnapshot<Map<String, dynamic>>> myMatchesStream() {
    final me = _uid;
    return _matchesCol
        .where('uids', arrayContains: me)
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  /// Toplam "görülmemiş" gelen beğeni sayısı (badge için).
  /// A tarafıysam: bLiked==true && aSeen==false
  /// B tarafıysam: aLiked==true && bSeen==false
  Stream<int> incomingLikesUnreadCount([String? uidOverride]) {
    final myUid = uidOverride ?? _uid;
    final col = _likesCol;

    // Do NOT filter by aSeen/bSeen here; some old docs may not have the field at all.
    final asAAll = col
        .where('a', isEqualTo: myUid)
        .where('bLiked', isEqualTo: true)
        .snapshots();

    final asBAll = col
        .where('b', isEqualTo: myUid)
        .where('aLiked', isEqualTo: true)
        .snapshots();

    return Stream<int>.multi((emitter) {
      int aCount = 0;
      int bCount = 0;

      int _countUnseenA(
        Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
        int c = 0;
        for (final d in docs) {
          final m = d.data();
          // For my A side, "unseen" means aSeen != true (i.e., false or missing)
          if (!_isTrue(m['aSeen'])) c++;
        }
        return c;
      }

      int _countUnseenB(
        Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
        int c = 0;
        for (final d in docs) {
          final m = d.data();
          // For my B side, "unseen" means bSeen != true (i.e., false or missing)
          if (!_isTrue(m['bSeen'])) c++;
        }
        return c;
      }

      final subA = asAAll.listen((qa) {
        aCount = _countUnseenA(qa.docs);
        emitter.add(aCount + bCount);
      });

      final subB = asBAll.listen((qb) {
        bCount = _countUnseenB(qb.docs);
        emitter.add(aCount + bCount);
      });

      emitter.onCancel = () {
        subA.cancel();
        subB.cancel();
      };
    });
  }

  /// Beğeniler ekranına girince kendi tarafımdaki seen bayraklarını true yapar.
  /// Ayrıca aSeenAt / bSeenAt timestamp'lerini ve updatedAt'i günceller.
  Future<void> markIncomingLikesSeen([String? uidOverride]) async {
    final myUid = uidOverride ?? _uid;
    final batch = _db.batch();
    int writes = 0;

    // As A: B liked me
    final q1 = await _likesCol
        .where('a', isEqualTo: myUid)
        .where('bLiked', isEqualTo: true)
        .get();
    for (final d in q1.docs) {
      final m = d.data();
      if (_isTrue(m['aSeen'])) continue; // already seen
      batch.set(d.reference, {
        'aSeen': true,
        'aSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      writes++;
    }

    // As B: A liked me
    final q2 = await _likesCol
        .where('b', isEqualTo: myUid)
        .where('aLiked', isEqualTo: true)
        .get();
    for (final d in q2.docs) {
      final m = d.data();
      if (_isTrue(m['bSeen'])) continue; // already seen
      batch.set(d.reference, {
        'bSeen': true,
        'bSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      writes++;
    }

    if (writes > 0) {
      await batch.commit();
    }
  }
}
