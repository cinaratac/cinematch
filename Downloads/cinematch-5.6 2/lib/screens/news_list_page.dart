import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/blog_post.dart';
import 'package:fluttergirdi/models/news_article.dart';
import 'package:fluttergirdi/screens/blog_detail_page.dart';
import 'package:fluttergirdi/screens/news_detail_page.dart';
import 'package:fluttergirdi/services/blog_service.dart';
import 'package:fluttergirdi/services/news_service.dart';

class NewsListPage extends StatefulWidget {
  const NewsListPage({super.key});

  @override
  State<NewsListPage> createState() => _NewsListPageState();
}

class DiscoverNewsAndBlogSections extends StatefulWidget {
  const DiscoverNewsAndBlogSections({super.key});

  @override
  State<DiscoverNewsAndBlogSections> createState() =>
      _DiscoverNewsAndBlogSectionsState();
}

class _DiscoverNewsAndBlogSectionsState
    extends State<DiscoverNewsAndBlogSections>
    with AutomaticKeepAliveClientMixin {
  static const _pageSize = 3;

  List<NewsArticle> _news = const [];
  List<BlogPost> _blogs = const [];
  DocumentSnapshot<Map<String, dynamic>>? _newsCursor;
  DocumentSnapshot<Map<String, dynamic>>? _blogCursor;
  bool _newsLoading = true;
  bool _blogLoading = true;
  bool _newsLoadingMore = false;
  bool _blogLoadingMore = false;
  bool _hasMoreNews = false;
  bool _hasMoreBlogs = false;
  Object? _newsError;
  Object? _blogError;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadNews();
    _loadBlogs();
  }

  Future<void> _loadNews({bool forceRefresh = false}) async {
    setState(() {
      _newsLoading = true;
      _newsError = null;
    });
    try {
      final page = await NewsService.instance.fetchFirstPage(
        pageSize: _pageSize,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _news = page.articles;
        _newsCursor = page.cursor;
        _hasMoreNews = page.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _newsError = error);
    } finally {
      if (mounted) setState(() => _newsLoading = false);
    }
  }

  Future<void> _loadBlogs({bool forceRefresh = false}) async {
    setState(() {
      _blogLoading = true;
      _blogError = null;
    });
    try {
      final page = await BlogService.instance.fetchFirstPage(
        pageSize: _pageSize,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _blogs = page.posts;
        _blogCursor = page.cursor;
        _hasMoreBlogs = page.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _blogError = error);
    } finally {
      if (mounted) setState(() => _blogLoading = false);
    }
  }

  Future<void> _loadMoreNews() async {
    final cursor = _newsCursor;
    if (cursor == null || !_hasMoreNews || _newsLoadingMore) return;
    setState(() => _newsLoadingMore = true);
    try {
      final page = await NewsService.instance.fetchNextPage(
        after: cursor,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      final knownIds = _news.map((article) => article.id).toSet();
      setState(() {
        _news = [
          ..._news,
          ...page.articles.where((article) => knownIds.add(article.id)),
        ];
        _newsCursor = page.cursor;
        _hasMoreNews = page.hasMore;
      });
    } catch (_) {
      if (mounted) _showLoadMoreError('Diğer haberler yüklenemedi.');
    } finally {
      if (mounted) setState(() => _newsLoadingMore = false);
    }
  }

  Future<void> _loadMoreBlogs() async {
    final cursor = _blogCursor;
    if (cursor == null || !_hasMoreBlogs || _blogLoadingMore) return;
    setState(() => _blogLoadingMore = true);
    try {
      final page = await BlogService.instance.fetchNextPage(
        after: cursor,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      final knownIds = _blogs.map((post) => post.id).toSet();
      setState(() {
        _blogs = [
          ..._blogs,
          ...page.posts.where((post) => knownIds.add(post.id)),
        ];
        _blogCursor = page.cursor;
        _hasMoreBlogs = page.hasMore;
      });
    } catch (_) {
      if (mounted) _showLoadMoreError('Diğer blog yazıları yüklenemedi.');
    } finally {
      if (mounted) setState(() => _blogLoadingMore = false);
    }
  }

  void _showLoadMoreError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openArticle(NewsArticle article) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            NewsDetailPage(articleId: article.id, initialArticle: article),
      ),
    );
  }

  void _openPost(BlogPost post) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BlogDetailPage(post: post)),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_buildNews(), const SizedBox(height: 42), _buildBlogs()],
      ),
    );
  }

  Widget _buildNews() {
    if (_newsLoading && _news.isEmpty) {
      return const _EmbeddedLoading(
        masthead: _Masthead(
          kicker: 'CINEMATCH',
          title: 'Sinema Gündemi',
          subtitle: 'Vizyondan, sektörden ve sinema dünyasından haberler',
        ),
      );
    }
    if (_newsError != null && _news.isEmpty) {
      return _ErrorState(
        message: 'Haberler şu anda yüklenemedi.',
        onRetry: () => _loadNews(forceRefresh: true),
      );
    }
    if (_news.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Masthead(
          kicker: 'CINEMATCH',
          title: 'Sinema Gündemi',
          subtitle: 'Vizyondan, sektörden ve sinema dünyasından haberler',
        ),
        const SizedBox(height: 16),
        _LeadNewsCard(
          article: _news.first,
          onTap: () => _openArticle(_news.first),
        ),
        if (_news.length > 1) ...[
          const SizedBox(height: 24),
          const _SectionRule(title: 'Son Haberler'),
          const SizedBox(height: 2),
          for (final article in _news.skip(1)) ...[
            _NewspaperRow(article: article, onTap: () => _openArticle(article)),
            const Divider(height: 1),
          ],
        ],
        if (_hasMoreNews)
          _EmbeddedLoadMoreButton(
            loading: _newsLoadingMore,
            onPressed: _loadMoreNews,
          ),
      ],
    );
  }

  Widget _buildBlogs() {
    if (_blogLoading && _blogs.isEmpty) {
      return const _EmbeddedLoading(
        masthead: _Masthead(
          kicker: 'YAZARLARDAN',
          title: 'CineMatch Blog',
          subtitle: 'İncelemeler, listeler ve sinema üzerine özgün yazılar',
        ),
      );
    }
    if (_blogError != null && _blogs.isEmpty) {
      return _ErrorState(
        message: 'Blog yazıları şu anda yüklenemedi.',
        onRetry: () => _loadBlogs(forceRefresh: true),
      );
    }
    if (_blogs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Masthead(
          kicker: 'YAZARLARDAN',
          title: 'CineMatch Blog',
          subtitle: 'İncelemeler, listeler ve sinema üzerine özgün yazılar',
        ),
        const SizedBox(height: 16),
        _LeadBlogCard(post: _blogs.first, onTap: () => _openPost(_blogs.first)),
        if (_blogs.length > 1) ...[
          const SizedBox(height: 26),
          const _SectionRule(title: 'Yeni Yazılar'),
          const SizedBox(height: 4),
          for (final post in _blogs.skip(1)) ...[
            _BlogRow(post: post, onTap: () => _openPost(post)),
            const Divider(height: 1),
          ],
        ],
        if (_hasMoreBlogs)
          _EmbeddedLoadMoreButton(
            loading: _blogLoadingMore,
            onPressed: _loadMoreBlogs,
          ),
      ],
    );
  }
}

class _EmbeddedLoading extends StatelessWidget {
  const _EmbeddedLoading({required this.masthead});

  final Widget masthead;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        masthead,
        const SizedBox(height: 16),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ColoredBox(color: colors.surfaceContainerHighest),
        ),
      ],
    );
  }
}

class _EmbeddedLoadMoreButton extends StatelessWidget {
  const _EmbeddedLoadMoreButton({
    required this.loading,
    required this.onPressed,
  });

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Center(
        child: IconButton(
          tooltip: 'Daha fazla göster',
          onPressed: loading ? null : onPressed,
          icon: loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
          style: IconButton.styleFrom(
            fixedSize: const Size(44, 44),
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewsListPageState extends State<NewsListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _blogActivated = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
  }

  void _handleTabChange() {
    if (!_blogActivated && _tabController.index == 1) {
      setState(() => _blogActivated = true);
    }
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'CineMatch Gündem',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            height: 40,
            margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(9),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 5,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              labelColor: colors.onSurface,
              unselectedLabelColor: colors.onSurfaceVariant,
              labelStyle: const TextStyle(fontWeight: FontWeight.w900),
              tabs: const [
                Tab(text: 'Haberler'),
                Tab(text: 'Bloglar'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const _NewsTab(),
          _BlogTab(active: _blogActivated),
        ],
      ),
    );
  }
}

class _NewsTab extends StatefulWidget {
  const _NewsTab();

  @override
  State<_NewsTab> createState() => _NewsTabState();
}

class _NewsTabState extends State<_NewsTab> {
  late Future<List<NewsArticle>> _future;

  @override
  void initState() {
    super.initState();
    _future = NewsService.instance.fetchPublishedNews();
  }

  Future<void> _refresh() async {
    final future = NewsService.instance.fetchPublishedNews(forceRefresh: true);
    setState(() => _future = future);
    await future;
  }

  void _openArticle(NewsArticle article) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            NewsDetailPage(articleId: article.id, initialArticle: article),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<NewsArticle>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _LoadingList();
        }
        if (snapshot.hasError) {
          return _ErrorState(
            message: 'Haberler şu anda yüklenemedi.',
            onRetry: _refresh,
          );
        }

        final articles = snapshot.data ?? const <NewsArticle>[];
        if (articles.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: const _EmptyList(
              icon: Icons.newspaper_outlined,
              message: 'Henüz yayınlanmış haber yok.',
            ),
          );
        }

        final bottomInset = MediaQuery.paddingOf(context).bottom;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, 16, 16, 58 + bottomInset),
            children: [
              const _Masthead(
                kicker: 'CINEMATCH',
                title: 'Sinema Gündemi',
                subtitle: 'Vizyondan, sektörden ve sinema dünyasından haberler',
              ),
              const SizedBox(height: 16),
              _LeadNewsCard(
                article: articles.first,
                onTap: () => _openArticle(articles.first),
              ),
              if (articles.length > 1) ...[
                const SizedBox(height: 24),
                const _SectionRule(title: 'Son Haberler'),
                const SizedBox(height: 2),
                for (final article in articles.skip(1)) ...[
                  _NewspaperRow(
                    article: article,
                    onTap: () => _openArticle(article),
                  ),
                  const Divider(height: 1),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _BlogTab extends StatefulWidget {
  final bool active;

  const _BlogTab({required this.active});

  @override
  State<_BlogTab> createState() => _BlogTabState();
}

class _BlogTabState extends State<_BlogTab> {
  final List<BlogPost> _posts = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _started = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    if (widget.active) _loadFirstPage();
  }

  @override
  void didUpdateWidget(covariant _BlogTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !_started) _loadFirstPage();
  }

  Future<void> _loadFirstPage({bool forceRefresh = false}) async {
    if (_loading) return;
    setState(() {
      _started = true;
      _loading = true;
      _error = null;
    });
    try {
      final page = await BlogService.instance.fetchFirstPage(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(page.posts);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final cursor = _cursor;
    if (_loadingMore || !_hasMore || cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await BlogService.instance.fetchNextPage(after: cursor);
      if (!mounted) return;
      final knownIds = _posts.map((post) => post.id).toSet();
      setState(() {
        _posts.addAll(page.posts.where((post) => knownIds.add(post.id)));
        _cursor = page.cursor;
        _hasMore = page.hasMore;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diğer yazılar yüklenemedi.')),
      );
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _openPost(BlogPost post) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BlogDetailPage(post: post)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active && !_started) return const SizedBox.shrink();
    if (_loading && _posts.isEmpty) return const _LoadingList();
    if (_error != null && _posts.isEmpty) {
      return _ErrorState(
        message: 'Blog yazıları şu anda yüklenemedi.',
        onRetry: () => _loadFirstPage(forceRefresh: true),
      );
    }
    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadFirstPage(forceRefresh: true),
        child: const _EmptyList(
          icon: Icons.auto_stories_outlined,
          message: 'Henüz yayınlanmış blog yazısı yok.',
        ),
      );
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return RefreshIndicator(
      onRefresh: () => _loadFirstPage(forceRefresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 16, 16, 58 + bottomInset),
        children: [
          const _Masthead(
            kicker: 'YAZARLARDAN',
            title: 'CineMatch Blog',
            subtitle: 'İncelemeler, listeler ve sinema üzerine özgün yazılar',
          ),
          const SizedBox(height: 16),
          _LeadBlogCard(
            post: _posts.first,
            onTap: () => _openPost(_posts.first),
          ),
          if (_posts.length > 1) ...[
            const SizedBox(height: 26),
            const _SectionRule(title: 'Yeni Yazılar'),
            const SizedBox(height: 4),
            for (final post in _posts.skip(1)) ...[
              _BlogRow(post: post, onTap: () => _openPost(post)),
              const Divider(height: 1),
            ],
          ],
          if (_hasMore) ...[
            const SizedBox(height: 22),
            Center(
              child: OutlinedButton(
                onPressed: _loadingMore ? null : _loadMore,
                child: _loadingMore
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Daha fazla yazı göster'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Masthead extends StatelessWidget {
  final String kicker;
  final String title;
  final String subtitle;

  const _Masthead({
    required this.kicker,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: colors.onSurface, thickness: 1.2)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                kicker,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ),
            Expanded(child: Divider(color: colors.onSurface, thickness: 1.2)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Divider(color: colors.onSurface, height: 1, thickness: 2),
        const SizedBox(height: 3),
        Divider(color: colors.onSurface, height: 1, thickness: 0.5),
      ],
    );
  }
}

class _LeadNewsCard extends StatelessWidget {
  final NewsArticle article;
  final VoidCallback onTap;

  const _LeadNewsCard({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (article.imageUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: article.imageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 900,
                    placeholder: (_, _) =>
                        ColoredBox(color: colors.surfaceContainerHighest),
                    errorWidget: (_, _, _) =>
                        ColoredBox(color: colors.surfaceContainerHighest),
                  ),
                ),
              ),
              const SizedBox(height: 13),
            ],
            _CategoryDate(
              category: article.category,
              date: article.publishedAt,
            ),
            const SizedBox(height: 7),
            Text(
              article.title,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 29,
                height: 1.08,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.7,
              ),
            ),
            if (article.summary.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                article.summary,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.44,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NewspaperRow extends StatelessWidget {
  final NewsArticle article;
  final VoidCallback onTap;

  const _NewspaperRow({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CategoryDate(
                      category: article.category,
                      date: article.publishedAt,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      article.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        height: 1.13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (article.summary.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        article.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (article.imageUrl.isNotEmpty) ...[
                const SizedBox(width: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: CachedNetworkImage(
                    imageUrl: article.imageUrl,
                    width: 112,
                    height: 104,
                    fit: BoxFit.cover,
                    memCacheWidth: 300,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadBlogCard extends StatelessWidget {
  final BlogPost post;
  final VoidCallback onTap;

  const _LeadBlogCard({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.coverImageUrl.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Hero(
                    tag: 'blog-cover-${post.id}',
                    child: CachedNetworkImage(
                      imageUrl: post.coverImageUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 900,
                      placeholder: (_, _) =>
                          ColoredBox(color: colors.surfaceContainerHighest),
                      errorWidget: (_, _, _) =>
                          ColoredBox(color: colors.surfaceContainerHighest),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 13),
            ],
            _CategoryDate(category: post.category, date: post.publishedAt),
            const SizedBox(height: 7),
            Text(
              post.title,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 29,
                height: 1.08,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.7,
              ),
            ),
            if (post.excerpt.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                post.excerpt,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.44,
                ),
              ),
            ],
            const SizedBox(height: 14),
            _BlogAuthor(post: post),
          ],
        ),
      ),
    );
  }
}

class _BlogRow extends StatelessWidget {
  final BlogPost post;
  final VoidCallback onTap;

  const _BlogRow({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CategoryDate(
                      category: post.category,
                      date: post.publishedAt,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      post.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        height: 1.13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (post.excerpt.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        post.excerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 9),
                    _BlogAuthor(post: post),
                  ],
                ),
              ),
              if (post.coverImageUrl.isNotEmpty) ...[
                const SizedBox(width: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: post.coverImageUrl,
                    width: 112,
                    height: 126,
                    fit: BoxFit.cover,
                    memCacheWidth: 300,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BlogAuthor extends StatelessWidget {
  final BlogPost post;

  const _BlogAuthor({required this.post});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        CircleAvatar(
          radius: 13,
          backgroundColor: colors.surfaceContainerHighest,
          backgroundImage: post.authorPhotoUrl.isEmpty
              ? null
              : CachedNetworkImageProvider(post.authorPhotoUrl),
          child: post.authorPhotoUrl.isEmpty
              ? Icon(
                  Icons.person_rounded,
                  size: 15,
                  color: colors.onSurfaceVariant,
                )
              : null,
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            post.authorName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (post.readingMinutes > 0) ...[
          Text(' · ', style: TextStyle(color: colors.onSurfaceVariant)),
          Text(
            '${post.readingMinutes} dk',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _CategoryDate extends StatelessWidget {
  final String category;
  final DateTime? date;

  const _CategoryDate({required this.category, required this.date});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dateText = _shortDate(date);
    return Row(
      children: [
        Flexible(
          child: Text(
            category.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ),
        if (dateText.isNotEmpty) ...[
          Text('  •  ', style: TextStyle(color: colors.outline)),
          Text(
            dateText,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionRule extends StatelessWidget {
  final String title;

  const _SectionRule({required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.onSurface, width: 2),
          bottom: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 60),
          color: colors.surfaceContainerHighest,
        ),
        const SizedBox(height: 16),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ColoredBox(color: colors.surfaceContainerHighest),
        ),
        const SizedBox(height: 16),
        for (final width in [double.infinity, 260.0, 310.0]) ...[
          Container(
            width: width,
            height: 18,
            color: colors.surfaceContainerHighest,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Tekrar dene'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyList({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.24),
        Icon(icon, size: 48, color: colors.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
      ],
    );
  }
}

String _shortDate(DateTime? date) {
  if (date == null) return '';
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}
