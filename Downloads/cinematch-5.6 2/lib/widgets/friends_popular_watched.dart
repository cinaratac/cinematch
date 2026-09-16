import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/services/friends_popular_watched_service.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';

class FriendsPopularWatched extends StatefulWidget {
  final Iterable<String> followingUserIds;
  final int reloadToken;

  const FriendsPopularWatched({
    super.key,
    required this.followingUserIds,
    this.reloadToken = 0,
  });

  @override
  State<FriendsPopularWatched> createState() => _FriendsPopularWatchedState();
}

class _FriendsPopularWatchedState extends State<FriendsPopularWatched> {
  static final Map<String, List<FriendPopularMovie>> _cache = {};
  static final Map<String, Future<List<FriendPopularMovie>>> _pending = {};

  late String _loadKey;
  List<FriendPopularMovie>? _movies;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadKey = _makeKey();
    _load();
  }

  @override
  void didUpdateWidget(covariant FriendsPopularWatched oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = _makeKey();
    if (nextKey != _loadKey || oldWidget.reloadToken != widget.reloadToken) {
      _loadKey = nextKey;
      _movies = null;
      _load(force: oldWidget.reloadToken != widget.reloadToken);
    }
  }

  String _makeKey() {
    final ids =
        widget.followingUserIds
            .map((uid) => uid.trim())
            .where((uid) => uid.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ids.join(',');
  }

  void _load({bool force = false}) {
    if (_loadKey.isEmpty) {
      _movies = const [];
      _loading = false;
      return;
    }

    final requestKey = _loadKey;
    if (force) {
      _cache.remove(requestKey);
      _pending.remove(requestKey);
    }

    if (!force && _cache[_loadKey] != null) {
      _movies = _cache[_loadKey];
      _loading = false;
      if (mounted) setState(() {});
      return;
    }

    setState(() => _loading = true);
    final future = _pending.putIfAbsent(
      requestKey,
      () => FriendsPopularWatchedService.instance.loadPopularWatched(
        followingUids: widget.followingUserIds,
      ),
    );

    future
        .then((movies) {
          _pending.remove(requestKey);
          _cache[requestKey] = movies;
          if (_cache.length > 20) _cache.remove(_cache.keys.first);
          if (!mounted || requestKey != _loadKey) return;
          setState(() {
            _movies = movies;
            _loading = false;
          });
        })
        .catchError((_) {
          _pending.remove(requestKey);
          if (!mounted || requestKey != _loadKey) return;
          setState(() {
            _movies = const [];
            _loading = false;
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    final movies = _movies ?? const <FriendPopularMovie>[];
    if (!_loading && movies.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final itemCount = movies.isNotEmpty ? movies.length : 4;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Icon(
                  Icons.local_fire_department_rounded,
                  size: 19,
                  color: const Color.fromARGB(255, 36, 190, 19),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Arkadaşların Arasında Popüler',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 188,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: itemCount,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                if (movies.isEmpty) {
                  return _PopularMoviePlaceholder(textColor: textColor);
                }
                return _PopularMovieCard(movie: movies[index]);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PopularMovieCard extends StatelessWidget {
  final FriendPopularMovie movie;

  const _PopularMovieCard({required this.movie});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MovieDetailScreen(
              tmdbId: movie.tmdbId,
              title: movie.title,
              posterUrl: movie.posterUrl,
            ),
          ),
        );
      },
      child: SizedBox(
        width: 104,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.zero,
                      child: PosterImage(
                        posterUrl: movie.posterUrl,
                        title: movie.title,
                        tmdbId: movie.tmdbId,
                        fit: BoxFit.cover,
                        cacheWidth: 312,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 7,
                    right: 7,
                    child: _WatcherAvatarStack(watchers: movie.watchers),
                  ),
                  Positioned(
                    left: 7,
                    bottom: 7,
                    child: _WatcherCountBadge(count: movie.watchers.length),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _watcherText(movie.watchers.length),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: textColor.withValues(alpha: 0.62),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _watcherText(int count) {
    if (count <= 1) return '1 arkadaş izledi';
    return '$count arkadaş izledi';
  }
}

class _WatcherAvatarStack extends StatelessWidget {
  final List<FriendMovieWatcher> watchers;

  const _WatcherAvatarStack({required this.watchers});

  @override
  Widget build(BuildContext context) {
    final visible = watchers.take(3).toList();
    final overflow = watchers.length - visible.length;
    final avatarCount = visible.length + (overflow > 0 ? 1 : 0);
    final width = math.max(28.0, 28.0 + ((avatarCount - 1) * 16.0));

    return SizedBox(
      width: width,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              right: i * 16,
              child: _WatcherAvatar(watcher: visible[i]),
            ),
          if (overflow > 0)
            Positioned(
              right: visible.length * 16,
              child: _OverflowAvatar(count: overflow),
            ),
        ],
      ),
    );
  }
}

class _WatcherAvatar extends StatelessWidget {
  final FriendMovieWatcher watcher;

  const _WatcherAvatar({required this.watcher});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: watcher.displayName,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.4),
          color: Colors.grey.shade800,
        ),
        clipBehavior: Clip.antiAlias,
        child: watcher.photoURL.isNotEmpty
            ? Transform.scale(
                scale:
                    1.15, // İçteki resmi %15 büyütür, beyazlıklar çemberin dışına itilip kesilir.
                child: CachedNetworkImage(
                  imageUrl: watcher.photoURL,
                  memCacheWidth: 84,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const Icon(
                    Icons.person_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              )
            : const Icon(Icons.person_rounded, size: 16, color: Colors.white),
      ),
    );
  }
}

class _OverflowAvatar extends StatelessWidget {
  final int count;

  const _OverflowAvatar({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.4),
      ),
      child: Text(
        '+$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _WatcherCountBadge extends StatelessWidget {
  final int count;

  const _WatcherCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.visibility_rounded, color: Colors.white, size: 12),
          const SizedBox(width: 3),
          Text(
            count.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PopularMoviePlaceholder extends StatelessWidget {
  final Color textColor;

  const _PopularMoviePlaceholder({required this.textColor});

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);

    return SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.zero,
              child: ColoredBox(color: fill, child: const SizedBox.expand()),
            ),
          ),
          const SizedBox(height: 7),
          Container(
            height: 10,
            width: 82,
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 5),
          Container(
            height: 8,
            width: 64,
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}
