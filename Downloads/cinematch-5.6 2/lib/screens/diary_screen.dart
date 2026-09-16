import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/diary_entry.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/services/diary_service.dart';

class DiaryScreen extends StatefulWidget {
  final String uid;
  final String displayName;

  const DiaryScreen({super.key, required this.uid, required this.displayName});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<DiaryEntry> _entries = [];

  DocumentSnapshot<Map<String, dynamic>>? _lastDocument;
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  Object? _loadError;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _loadFirstPage();
  }

  @override
  void didUpdateWidget(covariant DiaryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _entries.clear();
      _lastDocument = null;
      _hasMore = true;
      _loadFirstPage();
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients ||
        _isInitialLoading ||
        _isLoadingMore ||
        !_hasMore) {
      return;
    }
    if (_scrollController.position.extentAfter < 420) {
      _loadNextPage();
    }
  }

  Future<void> _loadFirstPage({bool forceRefresh = false}) async {
    final generation = ++_loadGeneration;
    final requestedUid = widget.uid;
    if (mounted) {
      setState(() {
        _isInitialLoading = true;
        _isLoadingMore = false;
        _loadError = null;
      });
    }

    try {
      final page = await DiaryService.instance.fetchPage(
        uid: requestedUid,
        forceRefresh: forceRefresh,
      );
      if (!mounted ||
          generation != _loadGeneration ||
          widget.uid != requestedUid) {
        return;
      }
      setState(() {
        _entries
          ..clear()
          ..addAll(page.entries);
        _lastDocument = page.lastDocument;
        _hasMore = page.hasMore;
        _isInitialLoading = false;
      });
    } catch (error) {
      if (!mounted ||
          generation != _loadGeneration ||
          widget.uid != requestedUid) {
        return;
      }
      setState(() {
        _loadError = error;
        _isInitialLoading = false;
      });
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasMore || _lastDocument == null) return;
    final generation = _loadGeneration;
    final requestedUid = widget.uid;
    final cursor = _lastDocument;
    setState(() => _isLoadingMore = true);

    try {
      final page = await DiaryService.instance.fetchPage(
        uid: requestedUid,
        startAfter: cursor,
      );
      if (!mounted ||
          generation != _loadGeneration ||
          widget.uid != requestedUid) {
        return;
      }
      setState(() {
        _appendUnique(page.entries);
        _lastDocument = page.lastDocument ?? _lastDocument;
        _hasMore = page.hasMore;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted ||
          generation != _loadGeneration ||
          widget.uid != requestedUid) {
        return;
      }
      setState(() {
        _loadError = error;
        _isLoadingMore = false;
      });
    }
  }

  void _appendUnique(Iterable<DiaryEntry> additions) {
    final existingIds = _entries.map((entry) => entry.id).toSet();
    for (final entry in additions) {
      if (existingIds.add(entry.id)) _entries.add(entry);
    }
  }

  Future<void> _refresh() async {
    await _loadFirstPage(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : const Color(0xFF171717);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.displayName.trim().isEmpty
                  ? 'Film Günlüğü'
                  : widget.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              'FİLM GÜNLÜĞÜ',
              style: TextStyle(
                color: foreground.withValues(alpha: 0.50),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
              ),
            ),
          ],
        ),
      ),
      body: _buildBody(foreground),
    );
  }

  Widget _buildBody(Color foreground) {
    if (_isInitialLoading && _entries.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_loadError != null && _entries.isEmpty) {
      return _DiaryError(
        foreground: foreground,
        onRetry: () => _loadFirstPage(forceRefresh: true),
      );
    }

    if (_entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            left: 28,
            right: 28,
            top: 120,
            bottom: MediaQuery.paddingOf(context).bottom + 20,
          ),
          children: [
            Icon(
              Icons.calendar_month_outlined,
              size: 46,
              color: foreground.withValues(alpha: 0.26),
            ),
            const SizedBox(height: 14),
            Text(
              'Henüz günlük kaydı yok',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: foreground,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'İzlenen filmler tarihleriyle burada görünecek.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: foreground.withValues(alpha: 0.55),
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    final rows = _buildRows();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 10,
          bottom: MediaQuery.paddingOf(context).bottom + 16,
        ),
        itemCount: rows.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == rows.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return rows[index];
        },
      ),
    );
  }

  List<Widget> _buildRows() {
    final rows = <Widget>[];
    int? previousYear;
    for (final entry in _entries) {
      final localDate = entry.watchedAt.toLocal();
      if (localDate.year != previousYear) {
        rows.add(_YearHeader(year: localDate.year));
        previousYear = localDate.year;
      }
      rows.add(
        _DiaryEntryRow(
          entry: entry,
          month: _turkishMonth(localDate.month),
          day: localDate.day,
        ),
      );
    }
    return rows;
  }

  String _turkishMonth(int month) {
    const months = [
      'OCA',
      'ŞUB',
      'MAR',
      'NİS',
      'MAY',
      'HAZ',
      'TEM',
      'AĞU',
      'EYL',
      'EKİ',
      'KAS',
      'ARA',
    ];
    return months[(month - 1).clamp(0, 11)];
  }
}

class _YearHeader extends StatelessWidget {
  final int year;

  const _YearHeader({required this.year});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : const Color(0xFF171717);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 9),
      child: Row(
        children: [
          Text(
            '$year',
            style: TextStyle(
              color: foreground,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(
              color: foreground.withValues(alpha: 0.13),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiaryEntryRow extends StatelessWidget {
  final DiaryEntry entry;
  final String month;
  final int day;

  const _DiaryEntryRow({
    required this.entry,
    required this.month,
    required this.day,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : const Color(0xFF171717);
    final divider = foreground.withValues(alpha: 0.10);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: entry.tmdbId == null || entry.tmdbId! <= 0
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MovieDetailScreen(
                    tmdbId: entry.tmdbId!,
                    title: entry.title,
                    posterUrl: entry.posterUrl,
                  ),
                ),
              );
            },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: divider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 48,
              child: Column(
                children: [
                  Text(
                    month,
                    style: TextStyle(
                      color: foreground.withValues(alpha: 0.48),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    day.toString().padLeft(2, '0'),
                    style: TextStyle(
                      color: foreground,
                      fontSize: 22,
                      height: 1,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                width: 42,
                height: 63,
                child: entry.posterUrl.isEmpty
                    ? _PosterPlaceholder(foreground: foreground)
                    : CachedNetworkImage(
                        imageUrl: entry.posterUrl,
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 130),
                        placeholder: (_, _) =>
                            _PosterPlaceholder(foreground: foreground),
                        errorWidget: (_, _, _) =>
                            _PosterPlaceholder(foreground: foreground),
                      ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (entry.releaseYear != null) ...[
                    const SizedBox(width: 7),
                    Text(
                      '${entry.releaseYear}',
                      style: TextStyle(
                        color: foreground.withValues(alpha: 0.48),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 19,
              color: foreground.withValues(alpha: 0.24),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  final Color foreground;

  const _PosterPlaceholder({required this.foreground});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: foreground.withValues(alpha: 0.08),
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          size: 20,
          color: foreground.withValues(alpha: 0.25),
        ),
      ),
    );
  }
}

class _DiaryError extends StatelessWidget {
  final Color foreground;
  final VoidCallback onRetry;

  const _DiaryError({required this.foreground, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: foreground.withValues(alpha: 0.45),
              size: 38,
            ),
            const SizedBox(height: 12),
            Text(
              'Film günlüğü yüklenemedi.',
              style: TextStyle(
                color: foreground,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tekrar dene'),
            ),
          ],
        ),
      ),
    );
  }
}
