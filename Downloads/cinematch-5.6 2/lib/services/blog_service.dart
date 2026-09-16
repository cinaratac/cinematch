import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/models/blog_post.dart';

class BlogPage {
  final List<BlogPost> posts;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;

  const BlogPage({
    required this.posts,
    required this.cursor,
    required this.hasMore,
  });
}

/// Yayınlanan blogları canlı dinleyici açmadan, sayfalı ve oturum içi önbellekli
/// olarak getirir. Liste belgesindeki yazar ve film özetleri kullanıldığı için
/// kartlar için ek kullanıcı veya film okuması yapılmaz.
class BlogService {
  BlogService._();

  static final BlogService instance = BlogService._();

  static const int defaultPageSize = 10;
  static const Duration _cacheTtl = Duration(minutes: 10);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Map<String, BlogPost> _postCache = {};
  BlogPage? _firstPageCache;
  int? _firstPageCacheSize;
  DateTime? _firstPageFetchedAt;
  Future<BlogPage>? _firstPageInFlight;
  int? _firstPageInFlightSize;
  List<BlogPost>? _teaserCache;
  DateTime? _teaserCachedAt;
  Future<List<BlogPost>>? _teaserInFlight;

  BlogPost? cachedPost(String id) => _postCache[id];

  Future<BlogPage> fetchFirstPage({
    int pageSize = defaultPageSize,
    bool forceRefresh = false,
  }) {
    final cachedAt = _firstPageFetchedAt;
    final isFresh =
        cachedAt != null && DateTime.now().difference(cachedAt) <= _cacheTtl;
    if (!forceRefresh &&
        isFresh &&
        _firstPageCache != null &&
        _firstPageCacheSize == pageSize) {
      return Future.value(_firstPageCache);
    }

    if (!forceRefresh &&
        _firstPageInFlight != null &&
        _firstPageInFlightSize == pageSize) {
      return _firstPageInFlight!;
    }

    final future = _fetchPage(pageSize: pageSize);
    _firstPageInFlight = future;
    _firstPageInFlightSize = pageSize;
    return future
        .then((page) {
          _firstPageCache = page;
          _firstPageCacheSize = pageSize;
          _firstPageFetchedAt = DateTime.now();
          return page;
        })
        .whenComplete(() {
          if (identical(_firstPageInFlight, future)) {
            _firstPageInFlight = null;
            _firstPageInFlightSize = null;
          }
        });
  }

  Future<BlogPage> fetchNextPage({
    required DocumentSnapshot<Map<String, dynamic>> after,
    int pageSize = defaultPageSize,
  }) => _fetchPage(pageSize: pageSize, after: after);

  Future<BlogPost?> fetchPost(String id) async {
    final cached = _postCache[id];
    if (cached != null) return cached;

    final doc = await _db
        .collection('public_blog_posts')
        .doc(id)
        .get(const GetOptions(source: Source.serverAndCache));
    if (!doc.exists) return null;
    final post = BlogPost.fromFirestore(doc);
    _postCache[id] = post;
    return post;
  }

  Future<List<BlogPost>> fetchTeaserCandidates({int limit = 5}) {
    final cachedAt = _teaserCachedAt;
    final isFresh =
        cachedAt != null && DateTime.now().difference(cachedAt) <= _cacheTtl;
    if (isFresh && _teaserCache != null) return Future.value(_teaserCache);
    if (_teaserInFlight != null) return _teaserInFlight!;

    final future = _db
        .collection('public_blog_posts')
        .orderBy('publishedAt', descending: true)
        .limit(limit)
        .get(const GetOptions(source: Source.serverAndCache))
        .then((snapshot) {
          final posts = snapshot.docs
              .map(BlogPost.fromFirestore)
              .where((post) => post.title.isNotEmpty)
              .toList(growable: false);
          _teaserCache = posts;
          _teaserCachedAt = DateTime.now();
          for (final post in posts) {
            _postCache[post.id] = post;
          }
          return posts;
        });
    _teaserInFlight = future;
    return future.whenComplete(() => _teaserInFlight = null);
  }

  Future<BlogPage> _fetchPage({
    required int pageSize,
    DocumentSnapshot<Map<String, dynamic>>? after,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection('public_blog_posts')
        .orderBy('publishedAt', descending: true)
        .limit(pageSize + 1);
    if (after != null) query = query.startAfterDocument(after);

    final snapshot = await query.get(
      const GetOptions(source: Source.serverAndCache),
    );
    final pageDocs = snapshot.docs.take(pageSize).toList(growable: false);
    final posts = pageDocs
        .map(BlogPost.fromFirestore)
        .where((post) => post.title.isNotEmpty)
        .toList(growable: false);
    for (final post in posts) {
      _postCache[post.id] = post;
    }

    return BlogPage(
      posts: posts,
      cursor: pageDocs.isEmpty ? after : pageDocs.last,
      hasMore: snapshot.docs.length > pageSize,
    );
  }
}
