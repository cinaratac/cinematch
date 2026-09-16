import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/widgets/ui_polish.dart';
import 'package:fluttergirdi/screens/actors_screen.dart';
import 'package:fluttergirdi/screens/director_screen.dart';
import 'package:fluttergirdi/services/catalog_service.dart';
import 'package:fluttergirdi/services/movie_availability_service.dart';
import 'package:fluttergirdi/services/shelf_state_cache.dart';
import 'package:fluttergirdi/widgets/movie_action_sheet.dart';
import 'package:fluttergirdi/widgets/movie_review_section.dart';
import 'package:url_launcher/url_launcher.dart';

class _MovieDetailsCacheEntry {
  final DateTime fetchedAt;
  final Map<String, dynamic> data;

  const _MovieDetailsCacheEntry({required this.fetchedAt, required this.data});
}

class _MovieDetailsCache {
  static const _ttl = Duration(minutes: 30);
  static final Map<int, _MovieDetailsCacheEntry> _entries = {};
  static final Map<int, Future<Map<String, dynamic>>> _inFlight = {};

  static Map<String, dynamic>? get(int tmdbId) {
    final entry = _entries[tmdbId];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.fetchedAt) > _ttl) {
      _entries.remove(tmdbId);
      return null;
    }
    return entry.data;
  }

  static Future<Map<String, dynamic>> getOrLoad(
    int tmdbId,
    Future<Map<String, dynamic>> Function() loader,
  ) async {
    final cached = get(tmdbId);
    if (cached != null) return cached;

    final pending = _inFlight[tmdbId];
    if (pending != null) return pending;

    final future = loader();
    _inFlight[tmdbId] = future;
    try {
      final data = await future;
      _entries[tmdbId] = _MovieDetailsCacheEntry(
        fetchedAt: DateTime.now(),
        data: data,
      );
      return data;
    } finally {
      _inFlight.remove(tmdbId);
    }
  }
}

class MovieDetailScreen extends StatefulWidget {
  final int tmdbId;
  final String? title;
  final String? posterUrl;

  const MovieDetailScreen({
    super.key,
    required this.tmdbId,
    this.title,
    this.posterUrl,
  });

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  Map<String, dynamic>? _movieData;
  List<dynamic> _cast = [];
  List<dynamic> _crew = [];
  bool _loading = true;
  bool _hasError = false;
  String? _catalogDocId;
  bool _isWatched = false;
  String? _watchedUid;
  Map<String, dynamic>? _directorInfo;
  MovieAvailability? _availability;
  bool _availabilityLoading = true;

  @override
  void initState() {
    super.initState();
    _initWatchedState();
    unawaited(_loadAvailability());
    final cachedDetails = _MovieDetailsCache.get(widget.tmdbId);
    if (cachedDetails != null) {
      _applyDetails(cachedDetails);
      _loading = false;
      _ensureCatalogRecord(cachedDetails);
    } else {
      unawaited(_fetchDetails());
    }
  }

  @override
  void dispose() {
    ShelfStateCache.instance.removeListener(_handleShelfStateChanged);
    super.dispose();
  }

  void _initWatchedState() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _watchedUid = uid;
    final cache = ShelfStateCache.instance;
    cache.addListener(_handleShelfStateChanged);
    _isWatched = _checkWatched(cache, uid);
    if (!cache.hasData(uid)) unawaited(_loadShelfState(uid));
  }

  Future<void> _loadShelfState(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      ShelfStateCache.instance.applyDoc(uid, doc);
    } catch (_) {}
  }

  void _handleShelfStateChanged() {
    final uid = _watchedUid;
    if (!mounted || uid == null) return;
    final next = _checkWatched(ShelfStateCache.instance, uid);
    if (next != _isWatched) setState(() => _isWatched = next);
  }

  bool _checkWatched(ShelfStateCache cache, String uid) {
    final tmdbKey = widget.tmdbId.toString();
    final catalogKey = _catalogDocId?.trim().toLowerCase();
    for (final field in const [
      'watchedKeys',
      'favoritesKeys',
      'fiveStarKeys',
      'dislikedKeys',
    ]) {
      final values = cache.get(uid, field);
      if (values.contains(tmdbKey) ||
          (catalogKey != null && values.contains(catalogKey))) {
        return true;
      }
    }
    return false;
  }

  Future<void> _fetchDetails() async {
    try {
      final data = await _MovieDetailsCache.getOrLoad(widget.tmdbId, () async {
        final result = await FirebaseFunctions.instance
            .httpsCallable('callTMDB')
            .call({
              'endpoint': '/3/movie/${widget.tmdbId}',
              'params': {
                'language': 'tr-TR',
                'append_to_response': 'credits,release_dates',
              },
            });
        return Map<String, dynamic>.from(result.data as Map);
      });
      if (!mounted) return;

      setState(() {
        _applyDetails(data);
        _loading = false;
      });
      _ensureCatalogRecord(data);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  void _applyDetails(Map<String, dynamic> data) {
    _movieData = data;
    final credits = data['credits'] is Map ? data['credits'] as Map : const {};
    _cast = List<dynamic>.from(credits['cast'] as List? ?? const []);
    _crew = List<dynamic>.from(credits['crew'] as List? ?? const []);
    _directorInfo = null;
    for (final member in _crew) {
      if (member is Map && member['job'] == 'Director') {
        _directorInfo = Map<String, dynamic>.from(member);
        break;
      }
    }
  }

  void _ensureCatalogRecord(Map<String, dynamic> data) {
    unawaited(
      CatalogService().upsertFromTmdb(data).then((docId) {
        if (!mounted || docId == _catalogDocId) return;
        setState(() => _catalogDocId = docId);
        _handleShelfStateChanged();
      }),
    );
  }

  Future<void> _loadAvailability() async {
    final availability = await MovieAvailabilityService.instance.load(
      widget.tmdbId,
    );
    if (!mounted) return;
    setState(() {
      _availability = availability;
      _availabilityLoading = false;
    });
  }

  Future<void> _openExternalUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Bağlantı açılamadı.')));
  }

  void _showAddSheet() {
    if (_movieData == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (_) => MovieActionSheet(
        tmdbId: widget.tmdbId,
        movieData: _movieData!,
        posterUrl: _posterUrl,
        catalogDocId: _catalogDocId,
      ),
    );
  }

  String get _director {
    return (_directorInfo?['name'] ?? 'Bilinmiyor').toString();
  }

  Map<String, dynamic>? get _directorData => _directorInfo;

  String get _rating {
    final vote = _movieData?['vote_average'];
    return vote is num ? vote.toStringAsFixed(1) : '-';
  }

  String get _runtime {
    final mins = _movieData?['runtime'];
    if (mins is! int || mins == 0) return '';
    return '${mins ~/ 60}s ${mins % 60}dk';
  }

  String get _year {
    final date = _movieData?['release_date'];
    return date is String && date.length >= 4 ? date.substring(0, 4) : '';
  }

  String? get _posterUrl {
    if (widget.posterUrl != null && widget.posterUrl!.isNotEmpty) {
      return widget.posterUrl;
    }

    final posterPath = _movieData?['poster_path'];
    if (posterPath is String && posterPath.isNotEmpty) {
      return 'https://image.tmdb.org/t/p/w500$posterPath';
    }

    return null;
  }

  String? get _backdropUrl {
    final backdropPath = _movieData?['backdrop_path'];
    if (backdropPath is! String || backdropPath.isEmpty) return null;
    return 'https://image.tmdb.org/t/p/w1280$backdropPath';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final textColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _circleIconButton(
          icon: Icons.arrow_back,
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isWatched)
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Colors.black26,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: Colors.greenAccent,
                size: 22,
              ),
            ),
          _circleIconButton(
            icon: Icons.playlist_add_rounded,
            onPressed: _showAddSheet,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: bgColor)),
          if (!_loading && _movieData != null)
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              height: 360,
              child: _buildBackdrop(bgColor, isDark),
            ),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_hasError || _movieData == null)
            Center(
              child: Text(
                'Detaylar yüklenemedi',
                style: TextStyle(color: textColor),
              ),
            )
          else
            CustomScrollView(
              cacheExtent: 500.0,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    0,
                    MediaQuery.of(context).padding.top + 60,
                    0,
                    40,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate.fixed([
                      _buildHeader(isDark, textColor),
                      const SizedBox(height: 24),
                      const HairlineDivider(indent: 20, endIndent: 20),
                      const SizedBox(height: 24),
                      _buildOverview(textColor),
                      const SizedBox(height: 24),
                      const HairlineDivider(indent: 20, endIndent: 20),
                      const SizedBox(height: 24),
                      _buildCastSection(textColor),
                      _buildAvailabilitySection(textColor),
                      const SizedBox(height: 30),
                      MovieReviewSection(
                        tmdbId: widget.tmdbId,
                        movieData: _movieData!,
                        posterUrl: _posterUrl,
                      ),
                    ]),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _circleIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Colors.black26,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }

  Widget _buildBackdrop(Color bgColor, bool isDark) {
    final backdropUrl = _backdropUrl;
    if (backdropUrl == null) return const SizedBox.shrink();
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: backdropUrl,
            fit: BoxFit.cover,
            memCacheWidth: 1280,
            fadeInDuration: const Duration(milliseconds: 160),
            fadeOutDuration: Duration.zero,
          ),
          ColoredBox(color: bgColor.withValues(alpha: isDark ? 0.42 : 0.64)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.30),
                  Colors.transparent,
                  bgColor,
                ],
                stops: const [0, 0.48, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark, Color textColor) {
    final posterUrl = _posterUrl;

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'poster_${widget.tmdbId}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: posterUrl == null
                    ? const SizedBox(width: 140, height: 210)
                    : CachedNetworkImage(
                        imageUrl: posterUrl,
                        width: 140,
                        height: 210,
                        fit: BoxFit.cover,
                        memCacheWidth: 280,
                        memCacheHeight: 420,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                      ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (_movieData?['title'] ?? widget.title ?? '').toString(),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (_year.isNotEmpty) _buildTag(_year),
                      if (_runtime.isNotEmpty) _buildTag(_runtime),
                      if (_isWatched) _buildWatchedTag(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Colors.amber,
                        size: 28,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _rating,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildDirectorLink(textColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWatchedTag() {
    return const TintedTag(
      label: 'İzledim',
      icon: Icons.check_rounded,
      color: Colors.greenAccent,
      compact: true,
    );
  }

  Widget _buildDirectorLink(Color textColor) {
    return GestureDetector(
      onTap: () {
        final director = _directorData;
        if (director == null || director['id'] == null) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DirectorScreen(
              directorId: director['id'] as int,
              directorName: (director['name'] ?? '').toString(),
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AccentMetadata(
            text: 'Yönetmen',
            icon: Icons.movie_creation_outlined,
          ),
          const SizedBox(height: 4),
          Text(
            _director,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: textColor,
              decoration: TextDecoration.underline,
              decorationColor: textColor.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverview(Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Özet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            (_movieData?['overview'] ?? 'Özet bulunamadı.').toString(),
            style: TextStyle(
              fontSize: 15,
              color: textColor.withValues(alpha: 0.8),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCastSection(Color textColor) {
    final visibleCastCount = _cast.length > 10 ? 10 : _cast.length;

    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Oyuncular',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 130,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: visibleCastCount,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final actor = _cast[index];
                return _ActorChip(actor: actor, textColor: textColor);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilitySection(Color textColor) {
    if (_availabilityLoading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 132,
              height: 18,
              color: textColor.withValues(alpha: 0.08),
            ),
            const SizedBox(height: 12),
            Container(
              height: 96,
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ],
        ),
      );
    }

    final availability = _availability;
    if (availability == null || availability.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final trailerKey = availability.youtubeTrailerKey;
    final watchLink = availability.watchLink;

    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Nerede İzlenir?',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'TR',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (availability.providers.isNotEmpty || trailerKey != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 78,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount:
                    availability.providers.length +
                    (trailerKey == null ? 0 : 1),
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  if (trailerKey != null && index == 0) {
                    return _TrailerWatchCard(
                      onTap: () => _openExternalUrl(
                        Uri.https('www.youtube.com', '/watch', {
                          'v': trailerKey,
                        }).toString(),
                      ),
                    );
                  }
                  final providerIndex = index - (trailerKey == null ? 0 : 1);
                  final provider = availability.providers[providerIndex];
                  return _WatchProviderCard(
                    provider: provider,
                    onTap: watchLink == null
                        ? null
                        : () => _openExternalUrl(watchLink),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTag(String text) => TintedTag(label: text, compact: true);
}

class _WatchProviderCard extends StatelessWidget {
  const _WatchProviderCard({required this.provider, required this.onTap});

  final MovieWatchProvider provider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SizedBox(
      width: 124,
      child: Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: provider.logoUrl.isEmpty
                        ? ColoredBox(
                            color: colors.surfaceContainerHighest,
                            child: Icon(
                              Icons.live_tv_rounded,
                              color: colors.onSurfaceVariant,
                              size: 19,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: provider.logoUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 102,
                            errorWidget: (_, _, _) => Icon(
                              Icons.live_tv_rounded,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        provider.offerTypes.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrailerWatchCard extends StatelessWidget {
  const _TrailerWatchCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SizedBox(
      width: 124,
      child: Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Color(0xFFE53935),
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fragman',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'YouTube',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActorChip extends StatelessWidget {
  final dynamic actor;
  final Color textColor;

  const _ActorChip({required this.actor, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final profilePath = actor['profile_path'];
    final profileUrl = profilePath is String && profilePath.isNotEmpty
        ? 'https://image.tmdb.org/t/p/w200$profilePath'
        : null;
    final name = (actor['name'] ?? '').toString();

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ActorScreen(actorId: actor['id'], actorName: name),
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 35,
            backgroundColor: Colors.grey.shade800,
            backgroundImage: profileUrl == null
                ? null
                : CachedNetworkImageProvider(
                    profileUrl,
                    maxWidth: 140,
                    maxHeight: 140,
                  ),
            child: profileUrl == null ? const Icon(Icons.person) : null,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 80,
            child: Text(
              name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: textColor.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
