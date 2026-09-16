import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WatchedMoviesService {
  WatchedMoviesService._();
  static final WatchedMoviesService instance = WatchedMoviesService._();

  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final Set<String> _watchedMovieIds = {};

  Set<String> get watchedMovieIds => _watchedMovieIds;

  Future<void> initWatchedHistory() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      _watchedMovieIds.clear();
      final Set<String> docIdsToResolve = {};

      // 1. GEÇMİŞİ KURTAR (Kullanıcının eski Firebase Doc ID'leri)
      final userDoc = await _fs.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final data = userDoc.data() ?? {};
        final fiveStar = List<dynamic>.from(data['fiveStarKeys'] ?? []);
        final disliked = List<dynamic>.from(data['dislikedKeys'] ?? []);
        final favorites = List<dynamic>.from(data['favoritesKeys'] ?? []);

        for (var id in [...fiveStar, ...disliked, ...favorites]) {
          if (id != null) {
            final strId = id.toString().trim().toLowerCase();
            _watchedMovieIds.add(strId);
            docIdsToResolve.add(
              strId,
            ); // TMDB karşılığını bulmak için listeye al
          }
        }
      }

      // 2. YENİ SİSTEM
      final historyDoc = await _fs
          .collection('users')
          .doc(uid)
          .collection('watched')
          .doc('history')
          .get();

      if (historyDoc.exists) {
        final data = historyDoc.data()?['ids'] as Map<String, dynamic>? ?? {};
        for (var key in data.keys) {
          final strId = key.trim().toLowerCase();
          _watchedMovieIds.add(strId);
          docIdsToResolve.add(strId);
        }
      }

      // 3. KRİTİK ÇÖZÜM: Firebase Doc ID'lerinin TMDB karşılıklarını bul
      // Firestore 10'arlı gruplar (chunks) halinde 'in' sorgusuna izin verir.
      if (docIdsToResolve.isNotEmpty) {
        final chunkedList = docIdsToResolve.toList();
        for (var i = 0; i < chunkedList.length; i += 10) {
          final chunk = chunkedList.sublist(
            i,
            i + 10 > chunkedList.length ? chunkedList.length : i + 10,
          );

          try {
            final qs = await _fs
                .collection('catalog_films')
                .where(FieldPath.documentId, whereIn: chunk)
                .get();

            for (var doc in qs.docs) {
              final tmdbId = doc.data()['tmdbId'];
              if (tmdbId != null) {
                // Her filmin TMDB ID'sini de izlenenler kümesine EKLİYORUZ!
                _watchedMovieIds.add(tmdbId.toString().trim().toLowerCase());
              }
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      // Sessizce geç
    }
  }

  Future<void> logMovieAsWatched(String movieId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || movieId.isEmpty) return;

    final key = movieId.trim().toLowerCase();
    _watchedMovieIds.add(key);

    await logMoviesAsWatchedForUser(uid: uid, movieIds: [key]);
  }

  Future<void> logMoviesAsWatchedForUser({
    required String uid,
    required Iterable<String> movieIds,
  }) async {
    final keys = _cleanKeys(movieIds);
    if (uid.isEmpty || keys.isEmpty) return;

    final docRef = _fs
        .collection('users')
        .doc(uid)
        .collection('watched')
        .doc('history');

    List<String> recentIds = [];
    try {
      final doc = await docRef.get(
        const GetOptions(source: Source.serverAndCache),
      );
      final raw = doc.data()?['recentIds'];
      if (raw is List) {
        recentIds = raw.map((id) => id.toString()).toList();
      }
    } catch (_) {}

    for (final key in keys.reversed) {
      recentIds.removeWhere((id) => id.trim().toLowerCase() == key);
      recentIds.insert(0, key);
      _watchedMovieIds.add(key);
    }

    if (recentIds.length > 20) {
      recentIds = recentIds.take(20).toList();
    }

    final idsMap = {for (final key in keys) key: true};

    final userRef = _fs.collection('users').doc(uid);
    final batch = _fs.batch();
    batch.set(docRef, {
      'ids': idsMap,
      'recentIds': recentIds,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(userRef, {
      'recentWatchedIds': recentIds,
      'recentWatchedUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> removeMovieFromWatched(String movieId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final key = movieId.trim().toLowerCase();
    _watchedMovieIds.remove(key);

    final docRef = _fs
        .collection('users')
        .doc(uid)
        .collection('watched')
        .doc('history');
    await docRef
        .update({
          'ids.$key': FieldValue.delete(),
          'recentIds': FieldValue.arrayRemove([key]),
        })
        .catchError((_) {});

    await _fs
        .collection('users')
        .doc(uid)
        .update({
          'recentWatchedIds': FieldValue.arrayRemove([key]),
          'recentWatchedUpdatedAt': FieldValue.serverTimestamp(),
        })
        .catchError((_) {});
  }

  List<String> _cleanKeys(Iterable<String> movieIds) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in movieIds) {
      final key = raw.trim().toLowerCase();
      if (key.isEmpty) continue;
      if (seen.add(key)) out.add(key);
    }
    return out;
  }
}
