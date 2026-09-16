import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/diary_entry.dart';
import 'package:fluttergirdi/screens/diary_screen.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/widgets/ui_polish.dart';

/// A read-free preview of the denormalized diary summary already present on
/// the user's profile document.
class RecentWatchedMovies extends StatelessWidget {
  final String uid;
  final String displayName;
  final List<dynamic> entries;

  const RecentWatchedMovies({
    super.key,
    required this.uid,
    required this.displayName,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final movies = _parseEntries(entries);

    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HairlineDivider(),
          Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: 18,
                color: textColor.withValues(alpha: 0.82),
              ),
              const SizedBox(width: 7),
              Text(
                'Son İzlenenler',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: uid.trim().isEmpty
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                DiaryScreen(uid: uid, displayName: displayName),
                          ),
                        );
                      },
                style: TextButton.styleFrom(
                  foregroundColor: textColor.withValues(alpha: 0.68),
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Tümü',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (movies.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Henüz günlük kaydı yok.',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.52),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 8.0;
                final itemWidth = ((constraints.maxWidth - (spacing * 3)) / 4)
                    .clamp(64.0, 92.0);
                return SizedBox(
                  height: (itemWidth * 1.5) + 22,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: movies.length,
                    separatorBuilder: (_, _) => const SizedBox(width: spacing),
                    itemBuilder: (context, index) => _RecentWatchedPoster(
                      movie: movies[index],
                      width: itemWidth,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  List<DiaryEntry> _parseEntries(List<dynamic> rawEntries) {
    final parsed = <DiaryEntry>[];
    for (final raw in rawEntries) {
      if (raw is DiaryEntry) {
        parsed.add(raw);
      } else if (raw is Map) {
        parsed.add(DiaryEntry.fromMap(Map<String, dynamic>.from(raw)));
      }
      if (parsed.length == 5) break;
    }
    return parsed;
  }
}

class _RecentWatchedPoster extends StatelessWidget {
  final DiaryEntry movie;
  final double width;

  const _RecentWatchedPoster({required this.movie, required this.width});

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final tmdbId = movie.tmdbId;

    return GestureDetector(
      onTap: tmdbId == null || tmdbId <= 0
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MovieDetailScreen(
                    tmdbId: tmdbId,
                    title: movie.title,
                    posterUrl: movie.posterUrl,
                  ),
                ),
              );
            },
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.zero,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: PosterImage(
                    posterUrl: movie.posterUrl,
                    title: movie.title,
                    tmdbId: tmdbId,
                    fit: BoxFit.cover,
                    enableFallback: false,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: textColor.withValues(alpha: 0.72),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
