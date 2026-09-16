import 'package:cloud_functions/cloud_functions.dart';

class PosterFallbackService {
  PosterFallbackService._();

  static final PosterFallbackService instance = PosterFallbackService._();

  final Map<String, String> _resolvedCache = {};

  bool _looksValid(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final value = url.trim();
    if (!(value.startsWith('http://') || value.startsWith('https://'))) {
      return false;
    }
    if (value.contains('empty-poster') || value.contains('null')) return false;
    if (value.contains('ltrbxd.com')) return false;
    return true;
  }

  Future<String?> resolvePosterUrl({
    String? existing,
    int? tmdbId,
    String? imdbId,
    String? title,
    int? year,
    bool ignoreExisting = false,
  }) async {
    // Sadece başlığa göre cache anahtarı oluşturuyoruz
    final cacheKey = title?.toLowerCase().trim() ?? tmdbId?.toString() ?? '';
    
    if (_resolvedCache.containsKey(cacheKey)) {
      return _resolvedCache[cacheKey];
    }

    if (!ignoreExisting && _looksValid(existing)) {
      return existing;
    }

    // KÖKTEN ÇÖZÜM: Elimizde tmdbId veya hiçbir şey olmasa bile, sadece filmin ADI (title) varsa
    // arama ekranında tıkır tıkır çalışan 'searchMovies' fonksiyonunu tetikleyip afişi zorla çekiyoruz!
    if (title != null && title.trim().isNotEmpty) {
      try {
        final response = await FirebaseFunctions.instance
            .httpsCallable('searchMovies') // TMDB'den arama yapan sağlam fonksiyonumuz
            .call({'query': title.trim()});

        final data = response.data;
        if (data != null && data['results'] != null) {
          final results = data['results'] as List;
          if (results.isNotEmpty) {
            // Arama sonucundaki ilk filmin afişini al
            final posterPath = results[0]['poster_path'];
            if (posterPath != null && posterPath.toString().isNotEmpty) {
              final posterUrl = 'https://image.tmdb.org/t/p/w500$posterPath';
              
              if (cacheKey.isNotEmpty) {
                _resolvedCache[cacheKey] = posterUrl;
              }
              return posterUrl;
            }
          }
        }
      } catch (e) {
        // Fonksiyon patlarsa sessizce geç
      }
    }

    return null;
  }
}