import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/widgets/post_tile.dart';
import 'package:fluttergirdi/services/feed_service.dart';

class PostDetailScreen extends StatelessWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  // Film ID'sini güvenli şekilde çekmek için yardımcı fonksiyon
  int? _parseTmdbId(Map<String, dynamic> m) {
    dynamic rawId = (m['movie'] is Map)
        ? (m['movie']['tmdbId'] ?? m['movie']['id'] ?? m['movie']['movieId'])
        : null;
    rawId ??= m['tmdbId'] ?? m['movieId'] ?? m['id'];
    if (rawId is int) return rawId;
    if (rawId is String) return int.tryParse(rawId);
    if (rawId is double) return rawId.toInt();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gönderi')),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        // 1. Adım: Gönderi verisini çek
        future: FirebaseFirestore.instance
            .collection('posts')
            .doc(postId)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text('Bu gönderi silinmiş veya bulunamadı.'),
            );
          }

          final d = snapshot.data!;
          final m = d.data()!;
          final authorId = (m['authorId'] ?? '').toString();

          final me = FirebaseAuth.instance.currentUser?.uid;

          // 2. Adım: Yazar profili, Beğeni durumu ve Takip durumunu PARALEL çek
          return FutureBuilder<List<dynamic>>(
            future: Future.wait([
              // [0] Yazarın güncel profili
              FirebaseFirestore.instance
                  .collection('users')
                  .doc(authorId)
                  .get(),

              // [1] Beğeni kontrolü (Ben bu postu beğendim mi?)
              (me != null)
                  ? FirebaseFirestore.instance
                        .collection('posts')
                        .doc(postId)
                        .collection('likes')
                        .doc(me)
                        .get()
                  : Future.value(null),

              // [2] Takip kontrolü (Ben bu yazarı takip ediyor muyum?)
              (me != null && me != authorId)
                  ? FirebaseFirestore.instance
                        .collection('users')
                        .doc(me)
                        .collection('following')
                        .doc(authorId)
                        .get()
                  : Future.value(null),
            ]),
            builder: (context, combinedSnap) {
              if (combinedSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final results = combinedSnap.data ?? [];

              // Yazar Verilerini İşle
              final userSnap = results.isNotEmpty
                  ? (results[0] as DocumentSnapshot<Map<String, dynamic>>?)
                  : null;

              // Cache/Post üzerindeki varsayılan veriler
              String displayName = (m['displayName'] ?? '').toString();
              String handle = (m['handle'] ?? '').toString();
              String photoURL = (m['photoURL'] ?? '').toString();

              // Güncel kullanıcı verisi varsa güncelle
              if (userSnap != null && userSnap.exists) {
                final userData = userSnap.data();
                if (userData != null) {
                  final uName = userData['displayName'] as String?;
                  if (uName != null && uName.isNotEmpty) displayName = uName;

                  final uUser = userData['username'] as String?;
                  final uLb = userData['letterboxdUsername'] as String?;
                  if (uUser != null && uUser.isNotEmpty) {
                    handle = '@$uUser';
                  } else if (uLb != null && uLb.isNotEmpty) {
                    handle = '@$uLb';
                  }

                  final uPhoto = userData['photoURL'] as String?;
                  if (uPhoto != null && uPhoto.isNotEmpty) photoURL = uPhoto;
                }
              }

              // Beğeni Durumu
              bool isLiked = false;
              if (results.length > 1 && results[1] != null) {
                final likeDoc = results[1] as DocumentSnapshot;
                isLiked = likeDoc.exists;
              }

              // Takip Durumu
              bool isFollowing = false;
              if (results.length > 2 && results[2] != null) {
                final followDoc = results[2] as DocumentSnapshot;
                isFollowing = followDoc.exists;
              }

              final createdAt = (m['createdAt'] as Timestamp?);
              final timeLabel = createdAt == null
                  ? ''
                  : _timeAgo(createdAt.toDate());

              // --- YENİ ALANLARIN PARSE EDİLMESİ ---
              final double? rating = (m['rating'] as num?)?.toDouble();
              final bool isSpoiler = m['isSpoiler'] == true;
              final List<String> tags = List<String>.from(m['tags'] ?? []);
              final String? reviewTitle = m['reviewTitle'] as String?;
              final List<String> postImages = List<String>.from(
                m['photoURLs'] ?? [],
              );
              final int? movieTmdbId = _parseTmdbId(m);

              return SingleChildScrollView(
                child: PostTile(
                  key: ValueKey(d.id),
                  postId: d.id,
                  authorId: authorId,
                  displayName: displayName,
                  handle: handle,
                  photoURL: photoURL,
                  timeLabel: timeLabel,

                  // İçerik
                  text: (m['text'] ?? '').toString(),
                  reviewTitle: reviewTitle,
                  rating: rating,
                  isSpoiler: isSpoiler,
                  tags: tags,

                  // Film Bilgileri
                  movieTitle:
                      m['movieTitle'] ??
                      (m['movie'] is Map ? m['movie']['title'] : null),
                  moviePoster:
                      m['moviePoster'] ??
                      (m['movie'] is Map
                          ? (m['movie']['poster'] ?? m['movie']['posterUrl'])
                          : null),
                  movieTmdbId: movieTmdbId,

                  // Görseller (Hem eski hem yeni yapı desteği)
                  postImage: m['postImage'],
                  postImages: postImages,

                  likeCount: ((m['likeCount'] ?? 0) as num).toInt(),
                  replyCount: ((m['replyCount'] ?? 0) as num).toInt(),

                  initialIsLiked: isLiked,
                  initialIsFollowing: isFollowing,
                  isDetail:
                      true, // Detay sayfasında olduğumuzu belirtiyoruz (Navigasyon döngüsünü önler)

                  onToggleLike: (pid, val) =>
                      FeedService.instance.toggleLike(postId: pid, like: val),
                  onStartChat: (uid) async {
                    // Chat entegrasyonu buraya
                  },
                  onFollow: (uid) async {
                    await FeedService.instance.followUser(uid);
                  },
                  onReport: (pid) => FeedService.instance.reportPost(pid),
                  onDelete: () => Navigator.pop(context),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);

    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}g';
    } else if (diff.inDays < 30) {
      // 7 ile 30 gün arasını hafta olarak göstermek istersen ('h' harfi hour ile karışmaması için 'hf' yapabilirsin veya gün olarak bırakabilirsin)
      final weeks = diff.inDays ~/ 7;
      return '${weeks}hf';
    } else if (diff.inDays < 365) {
      // 30 ile 365 gün arasını ay olarak gösterir
      final months = diff.inDays ~/ 30;
      return '${months}ay';
    } else {
      // 365 günden fazlasını yıl olarak gösterir
      final years = diff.inDays ~/ 365;
      return '${years}y';
    }
  }
}
