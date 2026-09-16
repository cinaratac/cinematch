import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:infinite_carousel/infinite_carousel.dart';
import 'package:shimmer/shimmer.dart';
import '../services/recommendation_engine.dart';
import '../widgets/poster_image.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';

const double _posterSnapExtent = 132;
const double _posterWidth = 132;
const double _posterCollapsedHeight = 176;
const double _posterExpandedHeight = 190;

class _RecommendationPosterTile extends StatelessWidget {
  final MovieRecommendation recommendation;
  final double focus;
  final VoidCallback onTap;

  const _RecommendationPosterTile({
    required this.recommendation,
    required this.focus,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final easedFocus = Curves.easeOutCubic.transform(focus);
    const width = _posterWidth;
    final height =
        _posterCollapsedHeight +
        ((_posterExpandedHeight - _posterCollapsedHeight) * easedFocus);
    final opacity = 0.52 + (0.48 * easedFocus);
    final selected = focus > 0.62;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: opacity,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedContainer(
            width: width,
            height: height,
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              border: selected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(
                        alpha: 0.35 + focus * 0.4,
                      ),
                      width: 2,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: 0.2 + (0.22 * easedFocus),
                  ),
                  blurRadius: 10 + (10 * easedFocus),
                  offset: Offset(0, 5 + (5 * easedFocus)),
                ),
              ],
            ),
            child: Hero(
              tag: 'poster_${recommendation.tmdbId}',
              child: RepaintBoundary(
                child: ClipRRect(
                  borderRadius: BorderRadius.zero,
                  child: PosterImage(
                    key: ValueKey(
                      'ai-poster-${recommendation.tmdbId}-${recommendation.posterUrl}',
                    ),
                    posterUrl: recommendation.posterUrl,
                    title: recommendation.title,
                    tmdbId: recommendation.tmdbId,
                    fit: BoxFit.cover,
                    cacheWidth: 396,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecommendationDetailsPanel extends StatelessWidget {
  final MovieRecommendation recommendation;

  const _RecommendationDetailsPanel({super.key, required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final genres = recommendation.genres.take(3).join(' / ');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    recommendation.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _RecommendationScorePill(
                  icon: Icons.star_rounded,
                  label: recommendation.voteAverage.toStringAsFixed(1),
                  color: Colors.amber,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (genres.isNotEmpty)
                  _RecommendationMetaPill(
                    icon: Icons.movie_filter_rounded,
                    label: genres,
                  ),
                _RecommendationMetaPill(
                  icon: Icons.favorite_rounded,
                  label: '%${recommendation.matchScore.toInt()} uyum',
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (recommendation.matchReason.trim().isNotEmpty) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 15,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Neden \u00f6nerildi?',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              recommendation.matchReason,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecommendationMetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _RecommendationMetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendationScorePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _RecommendationScorePill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RecommendationCard extends StatefulWidget {
  const RecommendationCard({super.key});

  @override
  State<RecommendationCard> createState() => _RecommendationCardState();
}

class _RecommendationCardState extends State<RecommendationCard>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;
  List<MovieRecommendation>? _recommendations;
  bool _loading = true;
  int _focusedIndex = 0;
  int _detailsIndex = 0;
  final InfiniteScrollController _posterController = InfiniteScrollController();
  late final AnimationController _detailsController;
  late final Animation<double> _detailsOpacity;
  late final Animation<Offset> _detailsOffset;

  @override
  void initState() {
    super.initState();
    _detailsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    final detailsCurve = CurvedAnimation(
      parent: _detailsController,
      curve: Curves.easeOutCubic,
    );
    _detailsOpacity = Tween<double>(begin: 0, end: 1).animate(detailsCurve);
    _detailsOffset = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(detailsCurve);

    _loadRecommendations();
  }

  @override
  void dispose() {
    _posterController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  void _selectRecommendation(
    int index, {
    bool animateScroll = true,
    bool animateDetails = true,
  }) {
    final recommendations = _recommendations;
    if (recommendations == null || recommendations.isEmpty) return;

    final clampedIndex = index.clamp(0, recommendations.length - 1);
    final detailsChanged = clampedIndex != _detailsIndex;

    setState(() {
      _focusedIndex = clampedIndex;
      _detailsIndex = clampedIndex;
    });
    if (detailsChanged && animateDetails) {
      _detailsController.forward(from: 0);
    }

    if (!animateScroll || !_posterController.hasClients) return;

    _posterController.animateToItem(
      clampedIndex,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _openMovieDetail(MovieRecommendation recommendation) {
    if (recommendation.tmdbId == 0) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MovieDetailScreen(
          tmdbId: recommendation.tmdbId,
          title: recommendation.title,
          posterUrl: recommendation.posterUrl,
        ),
      ),
    );
  }

  void _handleCarouselIndexChanged(int index) {
    if (index == _detailsIndex && index == _focusedIndex) return;

    setState(() {
      _focusedIndex = index;
      _detailsIndex = index;
    });
    _detailsController.forward(from: 0);
  }

  Future<void> _loadRecommendations() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final recs = await RecommendationEngine.instance.generateRecommendations(
        uid,
      );

      if (mounted) {
        setState(() {
          _recommendations = recs;
          _loading = false;
          _focusedIndex = 0;
          _detailsIndex = 0;
        });
        _detailsController.forward(from: 0);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Öneriler yenilenemedi. Lütfen tekrar dene.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showInfoDialog() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.surfaceContainerHighest, cs.surface],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withValues(alpha: 0.2),
                      blurRadius: 20,
                      spreadRadius: -5,
                    ),
                  ],
                ),
                child: Icon(Icons.auto_awesome, color: cs.primary, size: 32),
              ),

              const SizedBox(height: 20),

              Text(
                'Sistem Nas\u0131l \u00c7al\u0131\u015f\u0131yor?',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

              _buildFancyInfoItem(
                context,
                icon: Icons.person_search_rounded,
                title: 'Sana \u00d6zel Analiz',
                desc:
                    'Ge\u00e7mi\u015fin, y\u00f6netmenlerin ve sevdi\u011fin oyuncular taran\u0131yor.',
              ),
              const SizedBox(height: 16),
              _buildFancyInfoItem(
                context,
                icon: Icons.calendar_month_rounded,
                title: 'Haftal\u0131k Yenilenme',
                desc:
                    'Her hafta listen s\u0131f\u0131rlan\u0131r ve ke\u015ffetmen i\u00e7in yepyeni, taze \u00f6neriler getirilir.',
              ),

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'S\u00fcper, Anla\u015f\u0131ld\u0131',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFancyInfoItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String desc,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState(ThemeData theme, ColorScheme cs) {
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = isDark
        ? cs.surfaceContainerHighest
        : const Color(0xFFE1E4E2);
    final highlightColor = isDark
        ? cs.surfaceContainerHigh
        : const Color(0xFFF4F6F4);

    Widget block(double width, double height, {double radius = 6}) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Shimmer.fromColors(
        baseColor: baseColor,
        highlightColor: highlightColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  block(20, 20, radius: 10),
                  const SizedBox(width: 8),
                  block(164, 18),
                  const Spacer(),
                  block(20, 20, radius: 10),
                ],
              ),
            ),
            SizedBox(
              height: _posterExpandedHeight,
              child: ClipRect(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 16),
                    block(_posterWidth, _posterExpandedHeight, radius: 4),
                    block(_posterWidth, _posterCollapsedHeight, radius: 4),
                    block(_posterWidth, _posterCollapsedHeight, radius: 4),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: block(190, 18)),
                        const SizedBox(width: 18),
                        block(48, 24, radius: 12),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        block(112, 24, radius: 12),
                        const SizedBox(width: 8),
                        block(82, 24, radius: 12),
                      ],
                    ),
                    const SizedBox(height: 12),
                    block(double.infinity, 54, radius: 10),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return _buildLoadingState(theme, cs);
    }

    if (_recommendations == null || _recommendations!.isEmpty) {
      return const SizedBox.shrink();
    }

    final recommendations = _recommendations!;
    final detailsIndex = _detailsIndex.clamp(0, recommendations.length - 1);
    final recommendation = recommendations[detailsIndex];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Haftal\u0131k Ke\u015fif Listen',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 32,
                  width: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    icon: Icon(
                      Icons.info_outline,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.72),
                    ),
                    tooltip: 'Bu liste nas\u0131l olu\u015fuyor?',
                    onPressed: _showInfoDialog,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 190,
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: InfiniteCarousel.builder(
                controller: _posterController,
                itemCount: recommendations.length,
                itemExtent: _posterSnapExtent,
                center: false,
                anchor: 0,
                loop: false,
                velocityFactor: 0.12,
                onIndexChanged: _handleCarouselIndexChanged,
                itemBuilder: (context, itemIndex, realIndex) {
                  final rec = recommendations[itemIndex];
                  final focus = itemIndex == _focusedIndex ? 1.0 : 0.0;
                  return _RecommendationPosterTile(
                    recommendation: rec,
                    focus: focus,
                    onTap: () {
                      if (itemIndex == _detailsIndex) {
                        _openMovieDetail(rec);
                        return;
                      }
                      _selectRecommendation(itemIndex);
                    },
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: FadeTransition(
              opacity: _detailsOpacity,
              child: SlideTransition(
                position: _detailsOffset,
                child: _RecommendationDetailsPanel(
                  key: ValueKey(recommendation.tmdbId),
                  recommendation: recommendation,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
