import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/widgets/post_tile.dart';
import 'package:fluttergirdi/widgets/compose_post_sheet.dart';
import 'package:fluttergirdi/services/feed_service.dart';
import 'package:fluttergirdi/controllers/feed_controller.dart';
import 'package:fluttergirdi/services/tab_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

// ---------------------------------------------------------------------------
// Film başına post listesini bellekte tutar.
// Aynı film detay sayfası tekrar açılınca Firestore'a gitmez.
// ---------------------------------------------------------------------------
class _ReviewCache {
  static final _ReviewCache instance = _ReviewCache._();
  _ReviewCache._();

  // tmdbId → (timestamp, posts)
  final Map<
    int,
    ({
      DateTime fetchedAt,
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    })
  >
  _data = {};

  static const _ttl = Duration(minutes: 5);

  List<QueryDocumentSnapshot<Map<String, dynamic>>>? get(int tmdbId) {
    final entry = _data[tmdbId];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.fetchedAt) > _ttl) {
      _data.remove(tmdbId);
      return null;
    }
    return List.unmodifiable(entry.docs);
  }

  void set(int tmdbId, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    _data[tmdbId] = (fetchedAt: DateTime.now(), docs: List.unmodifiable(docs));
  }

  void invalidate(int tmdbId) => _data.remove(tmdbId);
}

class MovieReviewSection extends StatefulWidget {
  final int tmdbId;
  final Map<String, dynamic> movieData;
  final String? posterUrl;

  const MovieReviewSection({
    super.key,
    required this.tmdbId,
    required this.movieData,
    this.posterUrl,
  });

  @override
  State<MovieReviewSection> createState() => _MovieReviewSectionState();
}

class _MovieReviewSectionState extends State<MovieReviewSection> {
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _docs;
  bool _loading = false;

  @override
  void initState() {
    super.initState();

    _docs = _ReviewCache.instance.get(widget.tmdbId);
    if (_docs == null) {
      _loading = true;
      _loadPosts();
    }
  }

  Future<void> _loadPosts() async {
    final tmdbId = widget.tmdbId;
    final tmdbIdText = tmdbId.toString();
    try {
      final snap = await FirebaseFirestore.instance
          .collection('posts')
          .where(
            Filter.or(
              Filter('tmdbId', isEqualTo: tmdbId),
              Filter('tmdbId', isEqualTo: tmdbIdText),
              Filter('movieId', isEqualTo: tmdbId),
              Filter('movieId', isEqualTo: tmdbIdText),
              Filter('movie.tmdbId', isEqualTo: tmdbId),
              Filter('movie.tmdbId', isEqualTo: tmdbIdText),
              Filter('movie.id', isEqualTo: tmdbId),
              Filter('movie.id', isEqualTo: tmdbIdText),
              Filter('movie.movieId', isEqualTo: tmdbId),
              Filter('movie.movieId', isEqualTo: tmdbIdText),
            ),
          )
          .limit(12)
          .get(const GetOptions(source: Source.serverAndCache));
      if (!mounted) return;
      _applyLoadedPosts(snap.docs);
    } catch (_) {
      try {
        final fallbackDocs = await _loadLegacyFallback(tmdbId, tmdbIdText);
        if (mounted) _applyLoadedPosts(fallbackDocs);
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _loadLegacyFallback(
    int tmdbId,
    String tmdbIdText,
  ) async {
    final posts = FirebaseFirestore.instance.collection('posts');
    final snapshots = await Future.wait([
      posts.where('tmdbId', whereIn: [tmdbId, tmdbIdText]).limit(12).get(),
      posts.where('movieId', whereIn: [tmdbId, tmdbIdText]).limit(12).get(),
      posts
          .where('movie.tmdbId', whereIn: [tmdbId, tmdbIdText])
          .limit(12)
          .get(),
      posts.where('movie.id', whereIn: [tmdbId, tmdbIdText]).limit(12).get(),
      posts
          .where('movie.movieId', whereIn: [tmdbId, tmdbIdText])
          .limit(12)
          .get(),
    ]);
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        byId[doc.id] = doc;
      }
    }
    return byId.values.toList(growable: false);
  }

  void _applyLoadedPosts(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> loadedDocs,
  ) {
    final docs = loadedDocs.toList();
    docs.sort((a, b) {
      final tA = a.data()['createdAt'] as Timestamp?;
      final tB = b.data()['createdAt'] as Timestamp?;
      if (tA == null) return 1;
      if (tB == null) return -1;
      return tB.compareTo(tA);
    });
    _ReviewCache.instance.set(widget.tmdbId, docs);
    setState(() {
      _docs = docs;
      _loading = false;
    });
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}g';
    return '${diff.inDays ~/ 7}h';
  }

  void _navigateToCompose(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposePostPage(
          maxChars: 1000,
          initialMovie: {
            'id': widget.tmdbId,
            'tmdbId': widget.tmdbId,
            'title': widget.movieData['title'],
            'poster': widget.posterUrl,
          },
          onSend:
              ({
                required text,
                movie,
                images,
                rating,
                required isSpoiler,
                tags,
                reviewTitle,
              }) async {
                final user = FirebaseAuth.instance.currentUser;
                if (user == null) return;

                List<String> postImageUrls = [];
                if (images != null && images.isNotEmpty) {
                  for (var i = 0; i < images.length; i++) {
                    final ref = FirebaseStorage.instance
                        .ref()
                        .child('post_images')
                        .child(
                          '${user.uid}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
                        );
                    await ref.putFile(images[i]);
                    postImageUrls.add(await ref.getDownloadURL());
                  }
                }

                await FeedService.instance.createPost(
                  text: text,
                  movie: movie,
                  photoURL: postImageUrls.isNotEmpty
                      ? postImageUrls.first
                      : null,
                  photoURLs: postImageUrls,
                  displayName: user.displayName,
                  handle: user.email?.split('@')[0],
                  rating: rating,
                  isSpoiler: isSpoiler,
                  tags: tags,
                  reviewTitle: reviewTitle,
                );

                _ReviewCache.instance.invalidate(widget.tmdbId);

                if (context.mounted) {
                  FeedController.instance.refresh();
                  TabService.instance.changeTab(0);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Gönderiniz Paylaşıldı!'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final textColor = isDark ? Colors.white : Colors.black;

    final docs = _docs ?? [];
    final hasPosts = docs.isNotEmpty;
    final showSkeleton = _loading && _docs == null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30),
      decoration: BoxDecoration(color: hasPosts ? bgColor : Colors.transparent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Bu Film Hakkında Söylenenler',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (showSkeleton)
            _buildSkeleton(isDark)
          else if (!hasPosts)
            _buildEmpty(context, isDark, textColor)
          else
            _buildList(docs, textColor),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Skeleton — cache boşken gösterilir, genellikle sadece ilk açılışta
  // ---------------------------------------------------------------------------
  Widget _buildSkeleton(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(children: List.generate(2, (_) => _skeletonCard(isDark))),
    );
  }

  Widget _skeletonCard(bool isDark) {
    final base = isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _bone(36, 36, base, shape: BoxShape.circle),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bone(100, 12, base),
                  const SizedBox(height: 6),
                  _bone(60, 10, base),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _bone(double.infinity, 12, base),
          const SizedBox(height: 6),
          _bone(200, 12, base),
        ],
      ),
    );
  }

  Widget _bone(
    double w,
    double h,
    Color color, {
    BoxShape shape = BoxShape.rectangle,
  }) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: color,
        shape: shape,
        borderRadius: shape == BoxShape.rectangle
            ? BorderRadius.circular(6)
            : null,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Boş durum
  // ---------------------------------------------------------------------------
  Widget _buildEmpty(BuildContext context, bool isDark, Color textColor) {
    return GestureDetector(
      onTap: () => _navigateToCompose(context),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
        ),
        child: Column(
          children: [
            Icon(
              Icons.add_comment_rounded,
              color: textColor.withValues(alpha: 0.4),
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              'Henüz kimse bir şey söylememiş.\nİlk yorumu sen yaparak tartışmayı başlat!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor.withValues(alpha: 0.7),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Post listesi
  // ---------------------------------------------------------------------------
  Widget _buildList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Color textColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (var i = 0; i < docs.length; i++) ...[
            RepaintBoundary(child: _buildPostTile(docs[i])),
            if (i != docs.length - 1) const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildPostTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data();
    final ts = m['createdAt'];
    final movieMap = m['movie'] is Map ? m['movie'] as Map : null;

    return PostTile(
      postId: doc.id,
      authorId: (m['authorId'] ?? '').toString(),
      displayName: (m['displayName'] ?? '').toString(),
      handle: (m['handle'] ?? '').toString(),
      photoURL: (m['photoURL'] ?? '').toString(),
      timeLabel: ts == null ? '' : _timeAgo((ts as Timestamp).toDate()),
      text: (m['text'] ?? '').toString(),
      movieTitle: m['movieTitle'] ?? movieMap?['title'],
      moviePoster:
          m['moviePoster'] ?? movieMap?['poster'] ?? movieMap?['posterUrl'],
      movieTmdbId: widget.tmdbId,
      postImage: m['postImage'],
      postImages: List<String>.from(m['photoURLs'] ?? []),
      rating: (m['rating'] as num?)?.toDouble(),
      isSpoiler: m['isSpoiler'] == true,
      tags: List<String>.from(m['tags'] ?? []),
      reviewTitle: m['reviewTitle'] as String?,
      likeCount: ((m['likeCount'] ?? 0) as num).toInt(),
      replyCount: ((m['replyCount'] ?? 0) as num).toInt(),
      initialIsLiked: false,
      initialIsFollowing: false,
      onToggleLike: (pid, val) =>
          FeedService.instance.toggleLike(postId: pid, like: val),
      onStartChat: (_) {},
      onFollow: (uid) => FeedService.instance.followUser(uid),
      onReport: (pid) => FeedService.instance.reportPost(pid),
    );
  }
}
