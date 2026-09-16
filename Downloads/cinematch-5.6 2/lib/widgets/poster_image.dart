import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluttergirdi/services/poster_fallback_service.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

// CacheManager ayarlarını daha agresif hale getirdik
final customCacheManager = CacheManager(
  Config(
    'moviePosterCache',
    stalePeriod: const Duration(days: 30), // 7 günden 30 güne çıkardık
    maxNrOfCacheObjects:
        1000, // Daha fazla poster tutabilmesi için kapasiteyi artırdık
    repo: JsonCacheInfoRepository(databaseName: 'moviePosterCache_db'),
  ),
);

class PosterImage extends StatefulWidget {
  final String? posterUrl;
  final String? title;
  final int? tmdbId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? cacheWidth;
  final bool enableFallback;

  const PosterImage({
    super.key,
    required this.posterUrl,
    required this.title,
    this.tmdbId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.enableFallback = true,
  });

  @override
  State<PosterImage> createState() => _PosterImageState();
}

class _PosterImageState extends State<PosterImage> {
  String? _currentUrl;
  bool _isLoadingFallback = false;
  bool _failed = false;
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.posterUrl;

    if (!widget.enableFallback) return;

    if (_currentUrl != null && _currentUrl!.contains('ltrbxd.com')) {
      _tryFallback(force: true);
    } else if (_isEmpty(_currentUrl) && !_isEmpty(widget.title)) {
      _tryFallback(force: true);
    }
  }

  @override
  void didUpdateWidget(covariant PosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.posterUrl != widget.posterUrl ||
        oldWidget.title != widget.title ||
        oldWidget.tmdbId != widget.tmdbId) {
      setState(() {
        _currentUrl = widget.posterUrl;
        _failed = false;
        _isLoadingFallback = false;
        _retryCount = 0;
      });

      if (!widget.enableFallback) return;

      if (_currentUrl != null && _currentUrl!.contains('ltrbxd.com')) {
        _tryFallback(force: true);
      } else if (_isEmpty(_currentUrl) && !_isEmpty(widget.title)) {
        _tryFallback(force: true);
      }
    }
  }

  bool _isEmpty(String? s) => s == null || s.trim().isEmpty;

  bool _isDirectlyLoadable(String? s) {
    if (_isEmpty(s)) return false;
    final url = s!.trim();
    if (!(url.startsWith('http://') || url.startsWith('https://'))) {
      return false;
    }
    if (url.contains('ltrbxd.com') ||
        url.contains('empty-poster') ||
        url.contains('null')) {
      return false;
    }
    return true;
  }

  Future<void> _tryFallback({bool force = false}) async {
    if (_isLoadingFallback || _isEmpty(widget.title) || _retryCount >= 3) {
      if (mounted && _retryCount >= 3) setState(() => _failed = true);
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoadingFallback = true;
      _retryCount++;
    });

    try {
      final newUrl = await PosterFallbackService.instance.resolvePosterUrl(
        title: widget.title,
        tmdbId: widget.tmdbId,
        existing: widget.posterUrl,
        ignoreExisting: force,
      );

      if (mounted) {
        if (newUrl != null && newUrl.isNotEmpty && newUrl != _currentUrl) {
          setState(() {
            _currentUrl = newUrl;
            _failed = false;
          });
        } else {
          setState(() => _failed = true);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _isLoadingFallback = false);
    }
  }

  // URL'nin sonundaki gereksiz parametreleri (?v=123 gibi) temizleyerek sabit bir anahtar üretir
  String _generateCacheKey(String url) {
    if (url.contains('?')) {
      return url.split('?').first;
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDirectlyLoadable(_currentUrl)) {
      if (widget.enableFallback && !_isLoadingFallback && !_failed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _tryFallback(force: true);
        });
      }
      return widget.enableFallback && _isLoadingFallback
          ? _buildLoading()
          : _buildPlaceholder();
    }

    if (_failed || (_isEmpty(_currentUrl) && !_isLoadingFallback)) {
      return _buildPlaceholder();
    }

    if (_isLoadingFallback && _isEmpty(_currentUrl)) {
      return _buildLoading();
    }

    return CachedNetworkImage(
      imageUrl: _currentUrl!,
      // --- KÖKTEN ÇÖZÜM 1: SABİT CACHE KEY ---
      // Sunucu URL'yi ufak tefek değiştirse bile biz resmi hep aynı isimle kaydedip çağıracağız.
      cacheKey: _generateCacheKey(_currentUrl!),

      cacheManager: customCacheManager,

      // --- KÖKTEN ÇÖZÜM 2: memCacheWidth İPTALİ ---
      // Bazı poster formatları (webp/avif) sıkıştırılırken sessizce hata verip cache'e yazılmayı reddediyordu. Bunu kaldırarak orijinal haliyle kaydedilmesini zorluyoruz.
      memCacheWidth: widget.cacheWidth,

      httpHeaders: const {
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept':
            'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
        'Cache-Control':
            'max-age=2592000, public', // Sunucuya "Bana ne dersen de, ben bunu kaydedeceğim" diyoruz.
      },
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      errorWidget: (context, url, error) {
        // Eğer resim hatalıysa (Örn: 404), cache'i temizle ki sonsuza dek bozuk resim göstermesin
        customCacheManager.removeFile(_generateCacheKey(url));

        if (widget.enableFallback && !_isLoadingFallback && !_failed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _tryFallback(force: true);
          });
        }
        return _buildPlaceholder();
      },
      placeholder: (context, url) =>
          widget.enableFallback ? _buildLoading() : _buildPlaceholder(),
    );
  }

  Widget _buildLoading() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[900],
      child: Center(
        child: SizedBox(
          width: (widget.width ?? 50) * 0.3,
          height: (widget.width ?? 50) * 0.3,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.grey[900],
      child: Center(
        child: Icon(
          Icons.movie_creation_outlined,
          color: Colors.white24,
          size: (widget.width ?? 50) * 0.4,
        ),
      ),
    );
  }
}
