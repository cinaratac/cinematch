import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/models/news_article.dart';

class NewsPage {
  const NewsPage({
    required this.articles,
    required this.cursor,
    required this.hasMore,
  });

  final List<NewsArticle> articles;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

class NewsService {
  NewsService._();

  static final NewsService instance = NewsService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const Duration _cacheTtl = Duration(minutes: 10);
  List<NewsArticle>? _cachedArticles;
  DateTime? _cachedAt;
  Future<List<NewsArticle>>? _inFlight;
  final Map<String, NewsArticle> _articleCache = {};
  List<NewsArticle>? _teaserCache;
  DateTime? _teaserCachedAt;
  Future<List<NewsArticle>>? _teaserInFlight;
  NewsPage? _firstPageCache;
  int? _firstPageCacheSize;
  DateTime? _firstPageCachedAt;
  Future<NewsPage>? _firstPageInFlight;
  int? _firstPageInFlightSize;

  Future<NewsPage> fetchFirstPage({
    int pageSize = 3,
    bool forceRefresh = false,
  }) {
    final cachedAt = _firstPageCachedAt;
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
          _firstPageCachedAt = DateTime.now();
          return page;
        })
        .whenComplete(() {
          if (identical(_firstPageInFlight, future)) {
            _firstPageInFlight = null;
            _firstPageInFlightSize = null;
          }
        });
  }

  Future<NewsPage> fetchNextPage({
    required DocumentSnapshot<Map<String, dynamic>> after,
    int pageSize = 3,
  }) => _fetchPage(pageSize: pageSize, after: after);

  Future<List<NewsArticle>> fetchPublishedNews({
    int limit = 30,
    bool forceRefresh = false,
  }) {
    final cachedAt = _cachedAt;
    final isFresh =
        cachedAt != null && DateTime.now().difference(cachedAt) <= _cacheTtl;
    if (!forceRefresh && isFresh && _cachedArticles != null) {
      return Future.value(_cachedArticles);
    }
    if (!forceRefresh && _inFlight != null) return _inFlight!;

    final future = _db
        .collection('public_news')
        .orderBy('publishedAt', descending: true)
        .limit(limit)
        .get(const GetOptions(source: Source.serverAndCache))
        .then((snapshot) {
          final articles = snapshot.docs
              .map(NewsArticle.fromFirestore)
              .where((article) => article.title.isNotEmpty)
              .toList(growable: false);
          _cachedArticles = articles;
          _cachedAt = DateTime.now();
          for (final article in articles) {
            _articleCache[article.id] = article;
          }
          return articles;
        });
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<NewsArticle?> fetchArticle(String id) async {
    final cached = _articleCache[id];
    if (cached != null) return cached;
    final doc = await _db
        .collection('public_news')
        .doc(id)
        .get(const GetOptions(source: Source.serverAndCache));
    if (!doc.exists) return null;
    final article = NewsArticle.fromFirestore(doc);
    _articleCache[id] = article;
    return article;
  }

  Future<List<NewsArticle>> fetchTeaserCandidates({int limit = 5}) {
    final cachedAt = _teaserCachedAt;
    final isFresh =
        cachedAt != null && DateTime.now().difference(cachedAt) <= _cacheTtl;
    if (isFresh && _teaserCache != null) return Future.value(_teaserCache);
    if (_teaserInFlight != null) return _teaserInFlight!;

    final future = _db
        .collection('public_news')
        .orderBy('publishedAt', descending: true)
        .limit(limit)
        .get(const GetOptions(source: Source.serverAndCache))
        .then((snapshot) {
          final articles = snapshot.docs
              .map(NewsArticle.fromFirestore)
              .where((article) => article.title.isNotEmpty)
              .toList(growable: false);
          _teaserCache = articles;
          _teaserCachedAt = DateTime.now();
          for (final article in articles) {
            _articleCache[article.id] = article;
          }
          return articles;
        });
    _teaserInFlight = future;
    return future.whenComplete(() => _teaserInFlight = null);
  }

  Future<NewsPage> _fetchPage({
    required int pageSize,
    DocumentSnapshot<Map<String, dynamic>>? after,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection('public_news')
        .orderBy('publishedAt', descending: true)
        .limit(pageSize + 1);
    if (after != null) query = query.startAfterDocument(after);

    final snapshot = await query.get(
      const GetOptions(source: Source.serverAndCache),
    );
    final pageDocs = snapshot.docs.take(pageSize).toList(growable: false);
    final articles = pageDocs
        .map(NewsArticle.fromFirestore)
        .where((article) => article.title.isNotEmpty)
        .toList(growable: false);
    for (final article in articles) {
      _articleCache[article.id] = article;
    }
    return NewsPage(
      articles: articles,
      cursor: pageDocs.isEmpty ? after : pageDocs.last,
      hasMore: snapshot.docs.length > pageSize,
    );
  }
}
