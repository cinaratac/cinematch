import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/services/app_popular_movies_service.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';

class AppPopularMovies extends StatefulWidget {
  const AppPopularMovies({super.key});

  @override
  State<AppPopularMovies> createState() => _AppPopularMoviesState();
}

class _AppPopularMoviesState extends State<AppPopularMovies>
    with AutomaticKeepAliveClientMixin {
  List<AppPopularMovie>? _movies;
  bool _loading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final service = AppPopularMoviesService.instance;
    final cached = service.cachedMovies;
    if (cached != null) {
      _movies = cached;
      return;
    }

    _loading = true;
    service
        .loadWeeklyPopularMovies()
        .then((movies) {
          if (!mounted) return;
          setState(() {
            _movies = movies;
            _loading = false;
          });
        })
        .catchError((_) {
          if (!mounted) return;
          setState(() {
            _movies = const [];
            _loading = false;
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final movies = _movies ?? const <AppPopularMovie>[];
    if (!_loading && movies.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final itemCount = movies.isEmpty ? 5 : movies.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 0, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  size: 19,
                  color: Color.fromARGB(255, 36, 190, 19),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Uygulamada Popüler',
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
            height: 196,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: itemCount,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                if (movies.isEmpty) {
                  return _AppPopularMoviePlaceholder(textColor: textColor);
                }
                return _AppPopularMovieCard(
                  movie: movies[index],
                  rank: index + 1,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AppPopularMovieCard extends StatelessWidget {
  final AppPopularMovie movie;
  final int rank;

  const _AppPopularMovieCard({required this.movie, required this.rank});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return GestureDetector(
      onTap: movie.tmdbId == null
          ? null
          : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MovieDetailScreen(
                    tmdbId: movie.tmdbId!,
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
                  Positioned(left: 3, top: 3, child: _RankBadge(rank: rank)),
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
              _subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: textColor.withValues(alpha: 0.62),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _subtitle {
    final countText = movie.additions <= 1
        ? '1 kişi izledi'
        : '${movie.additions} kişi izledi';
    return movie.year == null ? countText : '${movie.year} · $countText';
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;

  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    return Text(
      rank.toString(),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 24,
        fontWeight: FontWeight.w900,
        height: 1,
        shadows: [
          Shadow(color: Color.fromARGB(255, 47, 193, 54), blurRadius: 2),
          Shadow(color: Colors.black, offset: Offset(0, 1), blurRadius: 2),
        ],
      ),
    );
  }
}

class _AppPopularMoviePlaceholder extends StatelessWidget {
  final Color textColor;

  const _AppPopularMoviePlaceholder({required this.textColor});

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
