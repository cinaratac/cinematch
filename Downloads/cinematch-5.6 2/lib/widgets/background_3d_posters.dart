import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/scheduler.dart';

class Background3DPosters extends StatefulWidget {
  const Background3DPosters({super.key});

  @override
  State<Background3DPosters> createState() => _Background3DPostersState();
}

const _posterWidth = 342;
const _posterHeight = 513;
const _maxPosterCount = 30;
List<String> _globalCachedPosters = [];

class _Background3DPostersState extends State<Background3DPosters>
    with TickerProviderStateMixin {
  final _posterUrls = <String>[];
  final _failedUrls = <String>{};
  final _scrollController1 = ScrollController();
  final _scrollController2 = ScrollController();
  final _scrollController3 = ScrollController();

  bool _isLoading = true;
  late final AnimationController _entranceController;
  late final Animation<Offset> _entranceAnimation;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  bool _dependenciesReady = false;
  bool _disableAnimations = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _entranceAnimation =
        Tween<Offset>(begin: const Offset(0, 0.7), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entranceController,
            curve: Curves.easeOutQuart,
          ),
        );
    _ticker = createTicker(_onTick);
    _fetchPosters();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dependenciesReady = true;
    _disableAnimations = MediaQuery.of(context).disableAnimations;

    if (_disableAnimations) {
      if (_ticker.isActive) _ticker.stop();
      _entranceController.value = 1;
    } else {
      _startPosterMotion();
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final delta = elapsed - _lastTick;
    if (delta < const Duration(milliseconds: 32)) return;
    _lastTick = elapsed;
    final seconds = delta.inMicroseconds / Duration.microsecondsPerSecond;
    _scroll(_scrollController1, 30 * seconds);
    _scroll(_scrollController2, 45 * seconds);
    _scroll(_scrollController3, 24 * seconds);
  }

  Future<void> _fetchPosters() async {
    if (_globalCachedPosters.isNotEmpty) {
      _showPosters(List<String>.from(_globalCachedPosters)..shuffle(Random()));
      return;
    }

    final urls = <String>{};
    final db = FirebaseFirestore.instance;

    // Tercih edilen kaynak: yalnızca sunucu/admin tarafından hazırlanan liste.
    try {
      final curated = await db
          .collection('login_posters')
          .where('enabled', isEqualTo: true)
          .limit(40)
          .get();
      for (final doc in curated.docs) {
        final url = _trustedTmdbUrl(doc.data());
        if (url != null) urls.add(url);
      }
    } catch (error) {
      debugPrint('Login poster koleksiyonu okunamadı: $error');
    }

    // Koleksiyon henüz hazırlanmamışsa güvenilir TMDB katalog kayıtlarını kullan.
    if (urls.length < 12) {
      await _appendCatalogPosters(urls, field: 'posterSource', value: 'tmdb');
    }
    if (urls.length < 12) {
      await _appendCatalogPosters(urls, field: 'source', value: 'tmdb');
    }

    final result = urls.take(_maxPosterCount).toList()..shuffle(Random());
    if (result.isNotEmpty) _globalCachedPosters = List<String>.from(result);
    _showPosters(result);
  }

  Future<void> _appendCatalogPosters(
    Set<String> urls, {
    required String field,
    required String value,
  }) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('catalog_films')
          .where(field, isEqualTo: value)
          .limit(60)
          .get();
      for (final doc in snapshot.docs) {
        final url = _trustedTmdbUrl(doc.data());
        if (url != null) urls.add(url);
      }
    } catch (error) {
      debugPrint('TMDB katalog posterleri okunamadı: $error');
    }
  }

  String? _trustedTmdbUrl(Map<String, dynamic> data) {
    var path = data['posterPath']?.toString().trim() ?? '';
    if (!RegExp(r'^/[A-Za-z0-9._-]+$').hasMatch(path)) {
      path = '';
    }

    if (path.isEmpty) {
      final rawUrl = data['posterUrl']?.toString().trim() ?? '';
      final uri = Uri.tryParse(rawUrl);
      if (uri != null &&
          uri.scheme == 'https' &&
          uri.host == 'image.tmdb.org') {
        final match = RegExp(
          r'^/t/p/(?:w\d+|original)(/[A-Za-z0-9._-]+)$',
        ).firstMatch(uri.path);
        path = match?.group(1) ?? '';
      }
    }

    return path.isEmpty
        ? null
        : 'https://image.tmdb.org/t/p/w$_posterWidth$path';
  }

  void _showPosters(List<String> urls) {
    if (!mounted) return;
    setState(() {
      _posterUrls
        ..clear()
        ..addAll(urls);
      _isLoading = false;
    });
    _startPosterMotion();
  }

  void _startPosterMotion() {
    if (!_dependenciesReady || _disableAnimations || _posterUrls.isEmpty) {
      return;
    }
    if (!_ticker.isActive) _ticker.start();
    if (_entranceController.status == AnimationStatus.dismissed) {
      _entranceController.forward();
    }
  }

  void _scroll(ScrollController controller, double delta) {
    if (!controller.hasClients) return;
    final position = controller.position;
    if (position.maxScrollExtent <= 0) return;
    if (position.pixels >= position.maxScrollExtent * 0.9) {
      controller.jumpTo(0);
    } else {
      controller.jumpTo(
        (position.pixels + delta).clamp(0, position.maxScrollExtent),
      );
    }
  }

  String? _posterFor(int index, int columnOffset) {
    if (_posterUrls.isEmpty || _failedUrls.length >= _posterUrls.length) {
      return null;
    }
    for (var attempt = 0; attempt < _posterUrls.length; attempt++) {
      final realIndex =
          (index + (columnOffset * 5) + attempt) % _posterUrls.length;
      final candidate = _posterUrls[realIndex];
      if (!_failedUrls.contains(candidate)) return candidate;
    }
    return null;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _entranceController.dispose();
    _scrollController1.dispose();
    _scrollController2.dispose();
    _scrollController3.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _posterUrls.isEmpty) {
      return const ColoredBox(color: Colors.black);
    }

    return ExcludeSemantics(
      child: IgnorePointer(
        child: SlideTransition(
          position: _entranceAnimation,
          child: Row(
            children: [
              Expanded(child: _buildInfiniteColumn(_scrollController1, 0)),
              Expanded(child: _buildInfiniteColumn(_scrollController2, 1)),
              Expanded(child: _buildInfiniteColumn(_scrollController3, 2)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfiniteColumn(ScrollController controller, int offsetIndex) {
    return RepaintBoundary(
      child: ListView.builder(
        controller: controller,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 10000,
        cacheExtent: 200.0,
        padding: EdgeInsets.zero,
        itemBuilder: (context, index) {
          final url = _posterFor(index, offsetIndex);
          return Container(
            height: 180,
            margin: const EdgeInsets.all(4),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFF101510),
              borderRadius: BorderRadius.circular(8),
            ),
            child: url == null
                ? const SizedBox.shrink()
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    memCacheWidth: _posterWidth,
                    memCacheHeight: _posterHeight,
                    fadeInDuration: const Duration(milliseconds: 180),
                    fadeOutDuration: Duration.zero,
                    placeholder: (_, _) =>
                        const ColoredBox(color: Color(0xFF101510)),
                    errorWidget: (_, failedUrl, _) {
                      _failedUrls.add(failedUrl);
                      return const ColoredBox(color: Color(0xFF101510));
                    },
                  ),
          );
        },
      ),
    );
  }
}
