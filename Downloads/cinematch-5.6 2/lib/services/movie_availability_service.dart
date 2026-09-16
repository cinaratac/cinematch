import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class MovieAvailability {
  const MovieAvailability({
    required this.providers,
    required this.watchLink,
    required this.youtubeTrailerKey,
  });

  static const empty = MovieAvailability(
    providers: [],
    watchLink: null,
    youtubeTrailerKey: null,
  );

  final List<MovieWatchProvider> providers;
  final String? watchLink;
  final String? youtubeTrailerKey;

  bool get isEmpty => providers.isEmpty && youtubeTrailerKey == null;
}

class MovieWatchProvider {
  const MovieWatchProvider({
    required this.id,
    required this.name,
    required this.logoUrl,
    required this.offerTypes,
    required this.displayPriority,
  });

  final int id;
  final String name;
  final String logoUrl;
  final List<String> offerTypes;
  final int displayPriority;
}

class MovieAvailabilityService {
  MovieAvailabilityService._();

  static final MovieAvailabilityService instance = MovieAvailabilityService._();
  static const _cacheDuration = Duration(hours: 6);

  final Map<int, MovieAvailability> _cache = {};
  final Map<int, DateTime> _cacheTimes = {};
  final Map<int, Future<MovieAvailability>> _pending = {};

  Future<MovieAvailability> load(int tmdbId) {
    final cachedAt = _cacheTimes[tmdbId];
    if (cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheDuration) {
      return Future.value(_cache[tmdbId] ?? MovieAvailability.empty);
    }

    final pending = _pending[tmdbId];
    if (pending != null) return pending;

    final future = _load(tmdbId);
    _pending[tmdbId] = future;
    return future.whenComplete(() {
      if (identical(_pending[tmdbId], future)) _pending.remove(tmdbId);
    });
  }

  Future<MovieAvailability> _load(int tmdbId) async {
    final responses = await Future.wait([
      _call('/3/movie/$tmdbId/watch/providers', const {}),
      _call('/3/movie/$tmdbId/videos', const {'language': 'en-US'}),
    ]);

    final availability = MovieAvailability(
      providers: _parseProviders(responses[0]),
      watchLink: _parseWatchLink(responses[0]),
      youtubeTrailerKey: _parseTrailerKey(responses[1]),
    );
    _cache[tmdbId] = availability;
    _cacheTimes[tmdbId] = DateTime.now();
    return availability;
  }

  Future<Map<String, dynamic>> _call(
    String endpoint,
    Map<String, String> params,
  ) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('callTMDB')
          .call({'endpoint': endpoint, 'params': params});
      return Map<String, dynamic>.from(result.data as Map);
    } catch (error) {
      debugPrint('Movie availability request failed ($endpoint): $error');
      return const {};
    }
  }

  Map<String, dynamic>? _turkeyData(Map<String, dynamic> response) {
    final results = response['results'];
    if (results is! Map) return null;
    final turkey = results['TR'];
    return turkey is Map ? Map<String, dynamic>.from(turkey) : null;
  }

  String? _parseWatchLink(Map<String, dynamic> response) {
    final link = _turkeyData(response)?['link']?.toString().trim() ?? '';
    return link.isEmpty ? null : link;
  }

  List<MovieWatchProvider> _parseProviders(Map<String, dynamic> response) {
    final turkey = _turkeyData(response);
    if (turkey == null) return const [];

    final providers = <int, _MutableProvider>{};
    const groups = <String, String>{
      'flatrate': 'Abonelik',
      'free': 'Ücretsiz',
      'ads': 'Reklamlı',
      'rent': 'Kirala',
      'buy': 'Satın al',
    };

    for (final group in groups.entries) {
      final rawProviders = turkey[group.key];
      if (rawProviders is! List) continue;
      for (final raw in rawProviders) {
        if (raw is! Map) continue;
        final data = Map<String, dynamic>.from(raw);
        final id = _positiveInt(data['provider_id']);
        final name = (data['provider_name'] ?? '').toString().trim();
        if (id == null || name.isEmpty) continue;
        final logoPath = (data['logo_path'] ?? '').toString();
        final provider = providers.putIfAbsent(
          id,
          () => _MutableProvider(
            id: id,
            name: name,
            logoUrl: logoPath.isEmpty
                ? ''
                : 'https://image.tmdb.org/t/p/w154$logoPath',
            displayPriority: _nonNegativeInt(data['display_priority']),
          ),
        );
        provider.offerTypes.add(group.value);
      }
    }

    final sorted = providers.values.toList()
      ..sort((a, b) => a.displayPriority.compareTo(b.displayPriority));
    return sorted.map((provider) => provider.freeze()).toList(growable: false);
  }

  String? _parseTrailerKey(Map<String, dynamic> response) {
    final rawResults = response['results'];
    if (rawResults is! List) return null;
    final videos = rawResults
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .where(
          (video) =>
              video['site'] == 'YouTube' &&
              (video['key'] ?? '').toString().trim().isNotEmpty,
        )
        .toList();
    if (videos.isEmpty) return null;

    videos.sort((a, b) {
      int score(Map<String, dynamic> video) {
        var value = video['type'] == 'Trailer'
            ? 4
            : video['type'] == 'Teaser'
            ? 2
            : 0;
        if (video['official'] == true) value += 2;
        return value;
      }

      return score(b).compareTo(score(a));
    });
    return videos.first['key'].toString();
  }
}

class _MutableProvider {
  _MutableProvider({
    required this.id,
    required this.name,
    required this.logoUrl,
    required this.displayPriority,
  });

  final int id;
  final String name;
  final String logoUrl;
  final int displayPriority;
  final Set<String> offerTypes = {};

  MovieWatchProvider freeze() => MovieWatchProvider(
    id: id,
    name: name,
    logoUrl: logoUrl,
    offerTypes: offerTypes.toList(growable: false),
    displayPriority: displayPriority,
  );
}

int? _positiveInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed != null && parsed > 0 ? parsed : null;
}

int _nonNegativeInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed != null && parsed >= 0 ? parsed : 999;
}
