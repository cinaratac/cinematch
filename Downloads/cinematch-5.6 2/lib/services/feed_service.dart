import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FeedService {
  FeedService._internal();

  // Bellekteki TEK ve yegane kopya
  static final FeedService instance = FeedService._internal();

  // Geriye dönük uyumluluk: Uygulamanın diğer yerlerinde hata vermemesi için
  // diğer erişim yöntemlerini de bu TEK kopyaya yönlendiriyoruz.
  factory FeedService() => instance;
  static FeedService get I => instance;

  final FirebaseFirestore _fs = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Query<Map<String, dynamic>> _baseQuery() {
    return _fs.collection('posts').orderBy('createdAt', descending: true);
  }

  DocumentReference<Map<String, dynamic>> _postRef(String postId) {
    return _fs.collection('posts').doc(postId);
  }

  Future<QuerySnapshot<Map<String, dynamic>>> fetchInitial({
    int limit = 20,
  }) async {
    final q = _baseQuery().limit(limit);
    try {
      return await q.get(const GetOptions(source: Source.server));
    } catch (_) {
      return q.get(const GetOptions(source: Source.cache));
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> fetchMore({
    required DocumentSnapshot<Map<String, dynamic>> lastDoc,
    int limit = 20,
  }) {
    final q = _baseQuery().startAfterDocument(lastDoc).limit(limit);
    return q.get();
  }

  Future<Set<String>> fetchUserLikedPostIds(String userId) async {
    try {
      final querySnapshot = await _fs
          .collectionGroup('likes')
          .where('by', isEqualTo: userId)
          .get(const GetOptions(source: Source.serverAndCache));

      final likedIds = <String>{};
      for (var doc in querySnapshot.docs) {
        final parent = doc.reference.parent.parent;
        if (parent != null) {
          likedIds.add(parent.id);
        }
      }
      return likedIds;
    } catch (e) {
      return {};
    }
  }

  Future<Set<String>> fetchUserFollowingIds(String userId) async {
    try {
      final querySnapshot = await _fs
          .collection('users')
          .doc(userId)
          .collection('following')
          .get(const GetOptions(source: Source.serverAndCache));

      return querySnapshot.docs.map((d) => d.id).toSet();
    } catch (e) {
      return {};
    }
  }

  // --- GÜNCELLENMİŞ FONKSİYON ---
  Future<void> createPost({
    required String text,
    Map<String, dynamic>? movie,
    String? handle,
    String? displayName,
    String? photoURL,
    List<String>? photoURLs, // YENİ: Çoklu foto desteği
    double? rating,
    bool isSpoiler = false,
    List<String>? tags,
    String? reviewTitle,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = _fs.collection('posts').doc();
    final now = FieldValue.serverTimestamp();
    final normalizedMovie = _normalizeMovie(movie);

    await doc.set({
      'id': doc.id,
      'authorId': user.uid,
      'displayName': displayName ?? '',
      'handle': (handle ?? '').trim(),
      'photoURL': photoURL ?? '', // Geriye dönük uyumluluk
      'photoURLs': photoURLs ?? [], // Yeni liste
      'movie': normalizedMovie,
      'movieTitle': normalizedMovie?['title'],
      'moviePoster':
          normalizedMovie?['poster'] ?? normalizedMovie?['posterUrl'],
      'tmdbId': normalizedMovie?['tmdbId'],
      'text': text.trim(),
      'rating': rating,
      'isSpoiler': isSpoiler,
      'tags': tags ?? [],
      'reviewTitle': reviewTitle?.trim(),
      'isReview':
          rating != null || (reviewTitle != null && reviewTitle.isNotEmpty),
      'likeCount': 0,
      'replyCount': 0,
      'repostCount': 0,
      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: false));
  }

  Map<String, dynamic>? _normalizeMovie(Map<String, dynamic>? movie) {
    if (movie == null) return null;

    final normalized = Map<String, dynamic>.from(movie);
    final title = (normalized['title'] ?? normalized['name'] ?? '').toString();
    var poster =
        (normalized['poster'] ??
                normalized['posterUrl'] ??
                normalized['image'] ??
                normalized['poster_path'] ??
                '')
            .toString();
    if (poster.startsWith('/')) {
      poster = 'https://image.tmdb.org/t/p/w500$poster';
    }
    final tmdbId = _coerceTmdbId(
      normalized['tmdbId'] ?? normalized['id'] ?? normalized['movieId'],
    );

    if (title.isNotEmpty) normalized['title'] = title;
    if (poster.isNotEmpty) {
      normalized['poster'] = poster;
      normalized['posterUrl'] = poster;
    }
    if (tmdbId != null) {
      normalized['tmdbId'] = tmdbId;
      normalized['id'] = tmdbId;
    }

    return normalized;
  }

  int? _coerceTmdbId(dynamic raw) {
    if (raw is int && raw > 0) return raw;
    if (raw is num && raw > 0) return raw.toInt();
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.startsWith('film:')) return null;
      final parsed = int.tryParse(trimmed);
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  Future<void> toggleLike({required String postId, required bool like}) async {
    final user = _auth.currentUser;
    final me = user?.uid;
    if (me == null) return;

    final postRef = _postRef(postId);
    final likeRef = postRef.collection('likes').doc(me);

    await _fs.runTransaction((tx) async {
      final likeSnap = await tx.get(likeRef);
      final now = FieldValue.serverTimestamp();

      if (like) {
        if (!likeSnap.exists) {
          tx.set(likeRef, {
            'by': me,
            'createdAt': now,
          }, SetOptions(merge: true));
          tx.update(postRef, {
            'likeCount': FieldValue.increment(1),
            'updatedAt': now,
          });
        }
      } else {
        if (likeSnap.exists) {
          tx.delete(likeRef);
          tx.update(postRef, {
            'likeCount': FieldValue.increment(-1),
            'updatedAt': now,
          });
        }
      }
    });

    // NOT: _writeNotification kısmı silindi. Çünkü index.js içindeki
    // createNotificationOnLike fonksiyonu Firestore trigger'ı olarak bu işi zaten yapıyor.
  }

  Future<void> followUser(String otherUid) async {
    final me = _auth.currentUser?.uid;
    if (me == null || me == otherUid) return;
    final ref = _fs
        .collection('users')
        .doc(me)
        .collection('following')
        .doc(otherUid);
    await ref.set({
      'by': me,
      'to': otherUid,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> reportPost(String postId) async {
    final me = _auth.currentUser?.uid;
    if (me == null) return;
    await _fs.collection('reports').add({
      'type': 'post',
      'postId': postId,
      'by': me,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> notifyComment({
    required String postId,
    required String postAuthorUid,
    String? preview,
  }) async {
    final user = _auth.currentUser;
    final me = user?.uid;
    if (me == null) return;
    if (postAuthorUid.isEmpty || postAuthorUid == me) return;

    try {
      await _writeNotification(
        toUid: postAuthorUid,
        type: 'comment',
        postId: postId,
        actorId: me,
        actorName: user?.displayName,
        actorPhotoURL: user?.photoURL,
        preview: preview,
        deterministicId: '${postId}_comments',
        isGrouped: true,
      );
    } catch (_) {}
  }

  Future<void> notifyCommentReply({
    required String postId,
    required String targetUid,
    required String parentReplyId,
    required String replyToReplyId,
    String? preview,
  }) async {
    final user = _auth.currentUser;
    final me = user?.uid;
    if (me == null) return;
    if (targetUid.isEmpty || targetUid == me) return;

    try {
      await _writeNotification(
        toUid: targetUid,
        type: 'comment_reply',
        postId: postId,
        actorId: me,
        actorName: user?.displayName,
        actorPhotoURL: user?.photoURL,
        preview: preview,
        metadata: {
          'parentReplyId': parentReplyId,
          'replyToReplyId': replyToReplyId,
        },
      );
    } catch (_) {}
  }

  Future<void> _writeNotification({
    required String toUid,
    required String type,
    required String postId,
    required String actorId,
    String? actorName,
    String? actorPhotoURL,
    String? preview,
    String? deterministicId,
    bool isGrouped = false, // YENİ PARAMETRE
    Map<String, dynamic>? metadata,
  }) async {
    final col = _fs.collection('users').doc(toUid).collection('notifications');

    // Eğer ID verilmemişse rastgele oluştur
    final ref = (deterministicId == null)
        ? col.doc()
        : col.doc(deterministicId);

    final Map<String, dynamic> data = {
      'type': type,
      'actorId': actorId, // Son işlem yapan kişi
      'actorName': actorName ?? '',
      'actorPhotoURL': actorPhotoURL ?? '',
      'postId': postId,
      'createdAt':
          FieldValue.serverTimestamp(), // Tarihi güncelle (üste çıksın)
      'read': false, // Tekrar okunmamış yap
    };

    if (preview != null && preview.isNotEmpty) {
      data['preview'] = preview;
    }
    if (metadata != null) data.addAll(metadata);

    // YENİ: Gruplama varsa sayacı artır, yoksa 1 yap
    if (isGrouped) {
      data['count'] = FieldValue.increment(1);
    } else {
      data['count'] = 1;
    }

    await ref.set(data, SetOptions(merge: true));
  }
}
