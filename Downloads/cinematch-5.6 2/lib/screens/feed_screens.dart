import 'package:flutter/material.dart';
import 'package:fluttergirdi/utils/date_helper.dart';
import 'package:fluttergirdi/utils/layout_metrics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../controllers/feed_controller.dart';
import '../services/user_cache_service.dart';
import '../widgets/post_skeleton.dart';
import '../services/feed_service.dart';
import 'package:fluttergirdi/widgets/post_tile.dart';
import 'package:fluttergirdi/widgets/app_popular_movies.dart';
import 'package:fluttergirdi/widgets/recommended_users.dart';
import 'package:fluttergirdi/widgets/notifications.dart';
import '../widgets/compose_post_sheet.dart';
import 'package:fluttergirdi/widgets/offline_banner.dart';
import 'package:fluttergirdi/widgets/custom_drawer.dart';
import 'package:fluttergirdi/widgets/friends_popular_watched.dart';
import 'package:fluttergirdi/widgets/green_characters.dart';
import 'package:fluttergirdi/services/tab_service.dart';
import 'package:fluttergirdi/widgets/feed_publication_teaser.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage>
    with SingleTickerProviderStateMixin {
  final FeedController _controller = FeedController.instance;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (!_controller.isInitialized) {
      _controller.init();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _onScrollNotification(ScrollUpdateNotification scrollInfo) {
    // Yatay film/listeler ve sekme kaydırmaları feed durumunu değiştirmesin.
    if (scrollInfo.metrics.axis != Axis.vertical) return false;

    // Sadece görünür olan Popüler sekmesi için sayfalama yap.
    if (_tabController.index == 0 &&
        scrollInfo.metrics.maxScrollExtent - scrollInfo.metrics.pixels <=
            1500) {
      _controller.loadMore();
    }

    return false;
  }

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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    const topPadding = 0.0;

    return Scaffold(
      drawer: const CustomDrawer(),
      body: NestedScrollView(
        floatHeaderSlivers: true,
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            floating: true,
            snap: true,
            pinned: false,
            backgroundColor: cs.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            toolbarHeight: 60,
            titleSpacing: 0,
            title: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 166,
                  height: 46,
                  child: ClipRect(
                    child: Transform.scale(
                      scale: 2.6,
                      child: Image.asset(
                        'assets/images/cinematch_name.png',
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            actions: [const NotificationsButton(), const SizedBox(width: 8)],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(50),
              child: Container(
                height: 36,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: false,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  labelColor: cs.onSurface,
                  unselectedLabelColor: cs.onSurfaceVariant,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: -0.2,
                  ),
                  labelPadding: EdgeInsets.zero,
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  tabs: const [
                    Tab(text: 'Popüler'),
                    Tab(text: 'Takip Edilenler'),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: NotificationListener<ScrollUpdateNotification>(
          onNotification: _onScrollNotification,
          child: TabBarView(
            controller: _tabController,
            children: [
              RefreshIndicator(
                edgeOffset: topPadding,
                onRefresh: _controller.refresh,
                child: ValueListenableBuilder<int>(
                  valueListenable: _controller.popularRevision,
                  builder: (context, revision, child) =>
                      _buildPopularFeed(topPadding),
                ),
              ),
              _FollowingFeed(topPadding: topPadding),
            ],
          ),
        ),
      ),

      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 70.0),
        child: FloatingActionButton(
          heroTag: 'feed_compose_fab',
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => ComposePostPage(
                maxChars: 1000,
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

                      try {
                        List<String> imageUrls = [];
                        if (images != null && images.isNotEmpty) {
                          for (var i = 0; i < images.length; i++) {
                            final image = images[i];
                            final String fileName =
                                '${user.uid}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
                            final ref = FirebaseStorage.instance
                                .ref()
                                .child('post_images')
                                .child(fileName);
                            await ref.putFile(image);
                            final url = await ref.getDownloadURL();
                            imageUrls.add(url);
                          }
                        }

                        await FeedService.instance.createPost(
                          text: text,
                          movie: movie,
                          photoURL: imageUrls.isNotEmpty
                              ? imageUrls.first
                              : null,
                          photoURLs: imageUrls,
                          displayName: user.displayName,
                          handle: user.email?.split('@')[0] ?? 'user',
                          rating: rating,
                          isSpoiler: isSpoiler,
                          tags: tags,
                          reviewTitle: reviewTitle,
                        );

                        if (mounted) {
                          Navigator.of(context).pop();
                          TabService.instance.changeTab(0);
                          _controller.refresh();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Gönderildi!')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Hata oluştu.')),
                          );
                        }
                      }
                    },
              ),
            );
          },
          child: const Icon(Icons.edit_note_rounded),
        ),
      ),
    );
  }

  Widget _buildPopularFeed(double topPadding) {
    final bottomPadding =
        AppLayoutMetrics.bottomNavigationClearance(context) + 8;
    if (_controller.isLoading) {
      return ListView.builder(
        padding: EdgeInsets.only(top: topPadding + 8, bottom: bottomPadding),
        itemCount: 5,
        itemBuilder: (ctx, index) => const PostSkeleton(),
      );
    }

    final showPublicationTeaser = _controller.posts.length >= 10;
    return ListView.separated(
      padding: EdgeInsets.only(top: topPadding + 8, bottom: bottomPadding),
      itemCount:
          _controller.posts.length +
          1 +
          (showPublicationTeaser ? 1 : 0) +
          (_controller.isLoadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        if (i == 0) {
          return const _PopularFeedHeader();
        }

        if (showPublicationTeaser && i == 11) {
          return const FeedPublicationTeaser();
        }

        final postIndex = i - 1 - (showPublicationTeaser && i > 11 ? 1 : 0);

        if (postIndex >= _controller.posts.length) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final doc = _controller.posts[postIndex];
        final m = doc.data() ?? {};
        final pid = doc.id;
        final authorId = (m['authorId'] ?? '') as String;

        final cachedUser = UserCacheService.instance.getFromCache(authorId);
        final displayName =
            cachedUser?.displayName ?? (m['displayName'] ?? 'Kullanıcı');
        final handle = cachedUser?.handle ?? (m['handle'] ?? '');
        final photoURL = cachedUser?.photoURL ?? (m['photoURL'] ?? '');

        final createdAt = (m['createdAt'] as Timestamp?);
        final timeLabel = DateHelper.timeAgo(createdAt);

        final movieMap = m['movie'] is Map ? m['movie'] as Map : null;
        final movieTitle = ((m['movieTitle'] ?? movieMap?['title']) ?? '')
            .toString();
        final moviePoster =
            ((m['moviePoster'] ??
                        movieMap?['poster'] ??
                        movieMap?['posterUrl']) ??
                    '')
                .toString();

        final postWidget = PostTile(
          key: ValueKey(pid),
          postId: pid,
          authorId: authorId,
          displayName: displayName,
          handle: handle,
          photoURL: photoURL,
          timeLabel: timeLabel,
          movieTitle: movieTitle.isEmpty ? null : movieTitle,
          moviePoster: moviePoster.isEmpty ? null : moviePoster,
          movieTmdbId: _parseTmdbId(m),
          postImage: (m['postImage'] ?? '') as String,
          postImages: List<String>.from(m['photoURLs'] ?? []),
          text: m['text'] ?? '',
          likeCount: ((m['likeCount'] ?? 0) as num).toInt(),
          replyCount: ((m['replyCount'] ?? 0) as num).toInt(),
          rating: (m['rating'] as num?)?.toDouble(),
          isSpoiler: m['isSpoiler'] == true,
          tags: List<String>.from(m['tags'] ?? []),
          reviewTitle: m['reviewTitle'] as String?,

          initialIsLiked: _controller.myLikedPostIds.contains(pid),
          initialIsFollowing: _controller.myFollowingUserIds.contains(authorId),

          onToggleLike: (id, liked) => _controller.toggleLike(id, liked),
          onFollow: (uid) => _controller.followUser(uid),
          onStartChat: (_) {},
          onReport: (id) => FeedService.instance.reportPost(id),
          onDelete: () => _controller.removePost(pid),
        );

        if (postIndex == 3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              postWidget,
              const SizedBox(height: 12),
              const RecommendedUsers(title: 'Önerilen kullanıcılar', limit: 10),
            ],
          );
        }

        return postWidget;
      },
    );
  }
}

class _PopularFeedHeader extends StatefulWidget {
  const _PopularFeedHeader();

  @override
  State<_PopularFeedHeader> createState() => _PopularFeedHeaderState();
}

class _PopularFeedHeaderState extends State<_PopularFeedHeader>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const Column(children: [OfflineBanner(), AppPopularMovies()]);
  }
}

class _FollowingFeed extends StatefulWidget {
  final double topPadding;
  const _FollowingFeed({Key? key, required this.topPadding}) : super(key: key);

  @override
  State<_FollowingFeed> createState() => _FollowingFeedState();
}

class _FollowingFeedState extends State<_FollowingFeed>
    with AutomaticKeepAliveClientMixin {
  final FeedController _controller = FeedController.instance;
  int _friendsPopularReloadToken = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (!_controller.isFollowingInitialized) {
      _controller.initFollowing();
    }
  }

  int? _parseTmdbId(Map<String, dynamic> m) {
    dynamic rawId;
    if (m['movie'] is Map) {
      final movieMap = m['movie'] as Map;
      rawId = movieMap['tmdbId'] ?? movieMap['id'] ?? movieMap['movieId'];
    }
    rawId ??= m['tmdbId'] ?? m['movieId'] ?? m['id'];
    if (rawId is int) return rawId;
    if (rawId is String) return int.tryParse(rawId);
    if (rawId is double) return rawId.toInt();
    return null;
  }

  Future<void> _refreshFollowing() async {
    await _controller.refreshFollowing();
    if (!mounted) return;
    setState(() => _friendsPopularReloadToken++);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ValueListenableBuilder<int>(
      valueListenable: _controller.followingRevision,
      builder: (context, revision, child) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final bottomPadding =
        AppLayoutMetrics.bottomNavigationClearance(context) + 8;
    if (_controller.isFollowingLoading) {
      return ListView.builder(
        itemCount: 5,
        padding: EdgeInsets.only(
          top: widget.topPadding + 8,
          bottom: bottomPadding,
        ),
        itemBuilder: (_, __) => const PostSkeleton(),
      );
    }

    if (_controller.followingPosts.isEmpty) {
      final hasFollowing = _controller.myFollowingUserIds.isNotEmpty;
      return RefreshIndicator(
        edgeOffset: widget.topPadding,
        onRefresh: _refreshFollowing,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.only(top: widget.topPadding + 8),
              sliver: SliverToBoxAdapter(
                child: FriendsPopularWatched(
                  followingUserIds: _controller.myFollowingUserIds,
                  reloadToken: _friendsPopularReloadToken,
                ),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const GreenEyesCharacter(size: 150),
                    const SizedBox(height: 16),
                    Text(
                      hasFollowing
                          ? 'Takip ettiklerinin henüz gönderisi yok'
                          : 'Birilerini takip etmelisin',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
          ],
        ),
      );
    }

    final showPublicationTeaser = _controller.followingPosts.length >= 10;
    return RefreshIndicator(
      edgeOffset: widget.topPadding,
      onRefresh: _refreshFollowing,
      child: ListView.separated(
        padding: EdgeInsets.only(
          top: widget.topPadding + 8,
          bottom: bottomPadding,
        ),
        itemCount:
            _controller.followingPosts.length +
            1 +
            (showPublicationTeaser ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Column(
              children: [
                const OfflineBanner(),
                FriendsPopularWatched(
                  followingUserIds: _controller.myFollowingUserIds,
                  reloadToken: _friendsPopularReloadToken,
                ),
              ],
            );
          }

          if (showPublicationTeaser && i == 11) {
            return const FeedPublicationTeaser();
          }

          final postIndex = i - 1 - (showPublicationTeaser && i > 11 ? 1 : 0);
          final d = _controller.followingPosts[postIndex];
          final m = d.data() ?? {};
          final authorId = (m['authorId'] ?? '') as String;

          final cachedUser = UserCacheService.instance.getFromCache(authorId);
          final displayName =
              cachedUser?.displayName ?? (m['displayName'] ?? '') as String;
          final handle = cachedUser?.handle ?? (m['handle'] ?? '') as String;
          final photoURL =
              cachedUser?.photoURL ?? (m['photoURL'] ?? '') as String;

          final createdAt = (m['createdAt'] as Timestamp?);
          final timeLabel = createdAt == null
              ? ''
              : DateHelper.timeAgo(createdAt.toDate());
          final movieMap = m['movie'] is Map ? m['movie'] as Map : null;
          final movieTitle = ((m['movieTitle'] ?? movieMap?['title']) ?? '')
              .toString();
          final moviePoster =
              ((m['moviePoster'] ??
                          movieMap?['poster'] ??
                          movieMap?['posterUrl']) ??
                      '')
                  .toString();

          int? movieTmdbId = _parseTmdbId(m);
          final postImage = (m['postImage'] ?? '') as String;

          return PostTile(
            key: ValueKey(d.id),
            postId: d.id,
            authorId: authorId,
            displayName: displayName,
            handle: handle,
            photoURL: photoURL,
            timeLabel: timeLabel,
            movieTitle: movieTitle.isEmpty ? null : movieTitle,
            moviePoster: moviePoster.isEmpty ? null : moviePoster,
            movieTmdbId: movieTmdbId,
            postImage: postImage.isEmpty ? null : postImage,
            postImages: List<String>.from(m['photoURLs'] ?? []),
            text: (m['text'] ?? '') as String,
            likeCount: ((m['likeCount'] ?? 0) as num).toInt(),
            replyCount: ((m['replyCount'] ?? 0) as num).toInt(),
            rating: (m['rating'] as num?)?.toDouble(),
            isSpoiler: (m['isSpoiler'] == true),
            reviewTitle: m['reviewTitle'] as String?,
            tags: List<String>.from(m['tags'] ?? []),

            initialIsLiked: _controller.myLikedPostIds.contains(d.id),
            initialIsFollowing: _controller.myFollowingUserIds.contains(
              authorId,
            ),

            onToggleLike: (pid, like) => _controller.toggleLike(pid, like),
            onStartChat: (String _) async {},
            onFollow: (uid) => _controller.followUser(uid),
            onReport: (pid) => FeedService.instance.reportPost(pid),
            onDelete: () => _controller.removeFollowingPost(d.id),
          );
        },
      ),
    );
  }
}
