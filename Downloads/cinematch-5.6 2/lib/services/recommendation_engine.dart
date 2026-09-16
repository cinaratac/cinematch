import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class MovieRecommendation {
  final int tmdbId;
  final String title;
  final String posterUrl;
  final String overview;
  final double voteAverage;
  final int voteCount;
  final double popularity;
  final String releaseDate;
  final List<String> genres;
  double matchScore;
  String matchReason;

  MovieRecommendation({
    required this.tmdbId,
    required this.title,
    required this.posterUrl,
    required this.overview,
    required this.voteAverage,
    this.voteCount = 0,
    this.popularity = 0,
    required this.releaseDate,
    required this.genres,
    required this.matchScore,
    required this.matchReason,
  });

  Map<String, dynamic> toMap() => {
    'tmdbId': tmdbId,
    'title': title,
    'posterUrl': posterUrl,
    'overview': overview,
    'voteAverage': voteAverage,
    'voteCount': voteCount,
    'popularity': popularity,
    'releaseDate': releaseDate,
    'genres': genres,
    'matchScore': matchScore,
    'matchReason': matchReason,
    'recommendedAt': Timestamp.now(),
  };

  factory MovieRecommendation.fromMap(Map<String, dynamic> map) {
    return MovieRecommendation(
      tmdbId: _positiveInt(map['tmdbId']) ?? 0,
      title: (map['title'] ?? '').toString(),
      posterUrl: (map['posterUrl'] ?? '').toString(),
      overview: (map['overview'] ?? '').toString(),
      voteAverage: _asDouble(map['voteAverage']),
      voteCount: _positiveInt(map['voteCount']) ?? 0,
      popularity: _asDouble(map['popularity']),
      releaseDate: (map['releaseDate'] ?? '').toString(),
      genres: List<String>.from(map['genres'] ?? const []),
      matchScore: _asDouble(map['matchScore']),
      matchReason: (map['matchReason'] ?? '').toString(),
    );
  }
}

class _UserTasteProfile {
  final List<String> favoriteGenres;
  final List<String> favoriteDirectors;
  final List<String> favoriteActors;
  final List<_MovieSeed> lovedMovies;
  final Set<int> excludedTmdbIds;
  final Set<String> excludedTitles;

  const _UserTasteProfile({
    this.favoriteGenres = const [],
    this.favoriteDirectors = const [],
    this.favoriteActors = const [],
    this.lovedMovies = const [],
    this.excludedTmdbIds = const {},
    this.excludedTitles = const {},
  });
}

class RecommendationEngine {
  RecommendationEngine._();

  static final RecommendationEngine instance = RecommendationEngine._();

  static const Duration _cacheDuration = Duration(days: 7);
  static const int _minimumCachedResults = 10;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final math.Random _random = math.Random();

  List<MovieRecommendation>? _memoryCache;
  String? _cachedUid;
  DateTime? _lastFetchTime;

  DocumentReference<Map<String, dynamic>> _getRecRef(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('recommendations')
        .doc('feed');
  }

  Future<List<MovieRecommendation>> generateRecommendations(
    String uid, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _memoryCache != null &&
        _memoryCache!.isNotEmpty &&
        _usesCurrentScoring(_memoryCache!) &&
        _cachedUid == uid &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
      return _memoryCache!;
    }

    final previousIds = <int>{};
    try {
      final snapshot = await _getRecRef(uid).get();
      if (snapshot.exists) {
        final data = snapshot.data() ?? const <String, dynamic>{};
        final cachedAt = (data['cachedAt'] as Timestamp?)?.toDate();
        final rawCached = data['recommendations'];
        final scoringVersion = _positiveInt(data['scoringVersion']) ?? 0;
        final cached = rawCached is List
            ? rawCached
                  .whereType<Map>()
                  .map(
                    (item) => MovieRecommendation.fromMap(
                      Map<String, dynamic>.from(item),
                    ),
                  )
                  .toList()
            : <MovieRecommendation>[];

        previousIds.addAll(cached.map((movie) => movie.tmdbId));
        if (!forceRefresh &&
            scoringVersion == 2 &&
            cachedAt != null &&
            DateTime.now().difference(cachedAt) < _cacheDuration) {
          if (cached.length >= _minimumCachedResults) {
            _remember(uid, cached, cachedAt);
            return cached;
          }
        }
      }
    } catch (error) {
      debugPrint('Recommendation cache check error: $error');
    }

    // Raflar yalnızca yeni haftalık liste oluşturulurken okunur. Hafta içinde
    // yapılan izledim/watchlist değişiklikleri mevcut keşif listesini bozmaz.
    final profile = await _fetchUserProfile(uid);
    final enrichedProfile = await _enrichTasteProfile(profile);
    final candidates = <MovieRecommendation>[];
    await Future.wait([
      _getGenreBasedRecommendations(enrichedProfile, candidates),
      _getDirectorBasedRecommendations(enrichedProfile, candidates),
      _getActorBasedRecommendations(enrichedProfile, candidates),
      _getSimilarMovieRecommendations(enrichedProfile, candidates),
    ]);

    // Trending is a low-weight safety net. Personalized matches naturally
    // outrank it when the user has enough taste data.
    if (candidates.length < 80) {
      await _getTrendingRecommendations(candidates);
    }

    final ranked = _rankCandidates(
      candidates,
      profile,
      previousIds: forceRefresh ? previousIds : const {},
    );
    final top30 = ranked.take(30).toList(growable: false);

    if (top30.isNotEmpty) {
      try {
        await _getRecRef(uid).set({
          'recommendations': top30.map((movie) => movie.toMap()).toList(),
          'cachedAt': FieldValue.serverTimestamp(),
          'count': top30.length,
          'scoringVersion': 2,
        });
      } catch (error) {
        debugPrint('Recommendation cache write error: $error');
      }
      _remember(uid, top30, DateTime.now());
    }

    return top30;
  }

  Future<_UserTasteProfile> _enrichTasteProfile(
    _UserTasteProfile profile,
  ) async {
    if (profile.lovedMovies.isEmpty) return profile;
    final genres = [...profile.favoriteGenres];
    final directors = [...profile.favoriteDirectors];
    final actors = [...profile.favoriteActors];
    final genreKeys = genres.map((name) => name.toLowerCase()).toSet();
    final directorKeys = directors.map((name) => name.toLowerCase()).toSet();
    final actorKeys = actors.map((name) => name.toLowerCase()).toSet();
    final enrichedSeeds = <_MovieSeed>[];

    final details = await Future.wait(
      profile.lovedMovies.take(4).map((seed) async {
        try {
          return await _callTmdb('/3/movie/${seed.tmdbId}', {
            'language': 'tr-TR',
            'append_to_response': 'credits',
          });
        } catch (_) {
          return <String, dynamic>{};
        }
      }),
    );

    final sourceSeeds = profile.lovedMovies.take(4).toList();
    for (var index = 0; index < sourceSeeds.length; index++) {
      final seed = sourceSeeds[index];
      final movie = details[index];
      final title = seed.title.isNotEmpty
          ? seed.title
          : (movie['title'] ?? movie['original_title'] ?? '').toString().trim();
      enrichedSeeds.add(
        _MovieSeed(tmdbId: seed.tmdbId, title: title, weight: seed.weight),
      );

      final rawGenres = movie['genres'];
      if (rawGenres is List) {
        for (final raw in rawGenres.whereType<Map>()) {
          final name = (raw['name'] ?? '').toString().trim();
          if (name.isNotEmpty && genreKeys.add(name.toLowerCase())) {
            genres.add(name);
          }
        }
      }

      final credits = movie['credits'];
      if (credits is! Map) continue;
      final crew = credits['crew'];
      if (crew is List) {
        for (final raw in crew.whereType<Map>()) {
          if (raw['job'] != 'Director') continue;
          final name = (raw['name'] ?? '').toString().trim();
          if (name.isNotEmpty && directorKeys.add(name.toLowerCase())) {
            directors.add(name);
          }
        }
      }
      final cast = credits['cast'];
      if (cast is List) {
        for (final raw in cast.whereType<Map>().take(3)) {
          final name = (raw['name'] ?? '').toString().trim();
          if (name.isNotEmpty && actorKeys.add(name.toLowerCase())) {
            actors.add(name);
          }
        }
      }
    }

    enrichedSeeds.addAll(profile.lovedMovies.skip(enrichedSeeds.length));
    return _UserTasteProfile(
      favoriteGenres: genres,
      favoriteDirectors: directors,
      favoriteActors: actors,
      lovedMovies: enrichedSeeds,
      excludedTmdbIds: profile.excludedTmdbIds,
      excludedTitles: profile.excludedTitles,
    );
  }

  Future<List<MovieRecommendation>?> getCachedRecommendations(
    String uid,
  ) async {
    if (_memoryCache != null &&
        _memoryCache!.isNotEmpty &&
        _usesCurrentScoring(_memoryCache!) &&
        _cachedUid == uid) {
      return _memoryCache!;
    }

    try {
      final snapshot = await _getRecRef(uid).get();
      if (!snapshot.exists) return null;
      final data = snapshot.data() ?? const <String, dynamic>{};
      if ((_positiveInt(data['scoringVersion']) ?? 0) != 2) return null;
      final cachedAt = (data['cachedAt'] as Timestamp?)?.toDate();
      if (cachedAt != null &&
          DateTime.now().difference(cachedAt) > _cacheDuration) {
        return null;
      }

      final raw = data['recommendations'];
      if (raw is! List) return null;
      final cached = raw
          .whereType<Map>()
          .map(
            (item) =>
                MovieRecommendation.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList();
      if (cached.isEmpty) return null;
      _remember(uid, cached, cachedAt ?? DateTime.now());
      return cached;
    } catch (error) {
      debugPrint('Recommendation cache read error: $error');
      return null;
    }
  }

  void clearMemoryCache() {
    _memoryCache = null;
    _cachedUid = null;
    _lastFetchTime = null;
  }

  bool _usesCurrentScoring(List<MovieRecommendation> recommendations) {
    return recommendations.every(
      (movie) =>
          movie.voteCount > 0 &&
          movie.matchReason.trim().toLowerCase() != 'benzer',
    );
  }

  void _remember(
    String uid,
    List<MovieRecommendation> recommendations,
    DateTime cachedAt,
  ) {
    _memoryCache = List<MovieRecommendation>.unmodifiable(recommendations);
    _cachedUid = uid;
    _lastFetchTime = cachedAt;
  }

  Future<_UserTasteProfile> _fetchUserProfile(String uid) async {
    try {
      final userDoc = await _db.collection('users').doc(uid).get();
      if (!userDoc.exists) return const _UserTasteProfile();
      final data = userDoc.data() ?? const <String, dynamic>{};

      final lovedKeys = <String>{};
      final excludedKeys = <String>{};
      final excludedIds = <int>{};
      final excludedTitles = <String>{};

      void addKeys(Object? raw, Set<String> target) {
        if (raw is! Iterable) return;
        for (final value in raw) {
          final key = value.toString().trim();
          if (key.isEmpty) continue;
          target.add(key);
          final tmdbId = _tmdbIdFromKey(key);
          if (tmdbId != null) excludedIds.add(tmdbId);
        }
      }

      addKeys(data['fiveStarKeys'], lovedKeys);
      addKeys(data['favoritesKeys'], lovedKeys);
      for (final field in const [
        'watchedKeys',
        'watchlistKeys',
        'favoritesKeys',
        'fiveStarKeys',
        'dislikedKeys',
        'recentWatchedIds',
        'watchedMovieIds',
        'watchlistIds',
        'dislikedMovieIds',
      ]) {
        addKeys(data[field], excludedKeys);
      }
      excludedKeys.addAll(lovedKeys);
      _collectEntryTitlesAndIds(
        data['recentDiaryEntries'],
        excludedTitles,
        excludedIds,
        excludedKeys,
      );

      try {
        final history = await _db
            .collection('users')
            .doc(uid)
            .collection('watched')
            .doc('history')
            .get();
        final historyData = history.data();
        if (historyData != null) {
          final ids = historyData['ids'];
          if (ids is Map) addKeys(ids.keys, excludedKeys);
          addKeys(historyData['recentIds'], excludedKeys);
        }
      } catch (error) {
        debugPrint('Watched history exclusion read error: $error');
      }

      // Diary is the final source of truth for legacy and imported watches.
      try {
        final diary = await _db
            .collection('users')
            .doc(uid)
            .collection('diary')
            .get();
        for (final document in diary.docs) {
          final entry = document.data();
          _collectEntryTitlesAndIds(
            [entry],
            excludedTitles,
            excludedIds,
            excludedKeys,
          );
        }
      } catch (error) {
        debugPrint('Diary exclusion read error: $error');
      }

      final catalog = await _resolveCatalogKeys({
        ...excludedKeys,
        ...lovedKeys,
      });
      final lovedById = <int, _MovieSeed>{};
      for (final entry in catalog.entries) {
        final movie = entry.value;
        final tmdbId = _positiveInt(movie['tmdbId']);
        final title = (movie['title'] ?? '').toString().trim();
        if (tmdbId != null) excludedIds.add(tmdbId);
        if (title.isNotEmpty) excludedTitles.add(_normalizeTitle(title));
        if (lovedKeys.contains(entry.key) && tmdbId != null) {
          final weight = _seedWeight(entry.key, data);
          final existing = lovedById[tmdbId];
          if (existing == null || existing.weight < weight) {
            lovedById[tmdbId] = _MovieSeed(
              tmdbId: tmdbId,
              title: title,
              weight: weight,
            );
          }
        }
      }

      for (final key in lovedKeys) {
        final tmdbId = _tmdbIdFromKey(key);
        if (tmdbId == null || lovedById.containsKey(tmdbId)) continue;
        lovedById[tmdbId] = _MovieSeed(
          tmdbId: tmdbId,
          title: '',
          weight: _seedWeight(key, data),
        );
      }

      final lovedMovies = lovedById.values.toList()
        ..sort((a, b) => b.weight.compareTo(a.weight));
      return _UserTasteProfile(
        favoriteGenres: _extractNames(data['favGenres']),
        favoriteDirectors: _extractNames(data['favDirectors']),
        favoriteActors: _extractNames(data['favActors']),
        lovedMovies: lovedMovies,
        excludedTmdbIds: excludedIds,
        excludedTitles: excludedTitles,
      );
    } catch (error) {
      debugPrint('Recommendation profile fetch error: $error');
      return const _UserTasteProfile();
    }
  }

  Future<Map<String, Map<String, dynamic>>> _resolveCatalogKeys(
    Set<String> keys,
  ) async {
    final resolved = <String, Map<String, dynamic>>{};
    final queryKeys = keys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toSet()
        .toList();
    for (var start = 0; start < queryKeys.length; start += 10) {
      final end = math.min(start + 10, queryKeys.length);
      try {
        final snapshot = await _db
            .collection('catalog_films')
            .where(FieldPath.documentId, whereIn: queryKeys.sublist(start, end))
            .get();
        for (final document in snapshot.docs) {
          resolved[document.id] = document.data();
        }
      } catch (error) {
        debugPrint('Catalog exclusion resolve error: $error');
      }
    }
    return resolved;
  }

  void _collectEntryTitlesAndIds(
    Object? raw,
    Set<String> titles,
    Set<int> ids,
    Set<String> keys,
  ) {
    if (raw is! Iterable) return;
    for (final item in raw) {
      if (item is! Map) continue;
      final tmdbId = _positiveInt(item['tmdbId'] ?? item['id']);
      if (tmdbId != null) ids.add(tmdbId);
      final key = (item['movieKey'] ?? '').toString().trim();
      if (key.isNotEmpty) keys.add(key);
      final title = (item['title'] ?? '').toString().trim();
      if (title.isNotEmpty) titles.add(_normalizeTitle(title));
    }
  }

  double _seedWeight(String key, Map<String, dynamic> userData) {
    bool contains(String field) {
      final values = userData[field];
      return values is Iterable &&
          values.any((value) => value.toString().trim() == key);
    }

    var weight = 1.0;
    if (contains('fiveStarKeys')) weight += 1.5;
    if (contains('favoritesKeys')) weight += 2.0;
    return weight;
  }

  List<String> _extractNames(Object? raw) {
    if (raw is! Iterable) return const [];
    final names = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final name = item is Map
          ? (item['name'] ?? '').toString().trim()
          : item.toString().trim();
      if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
      names.add(name);
    }
    return names;
  }

  Future<void> _getGenreBasedRecommendations(
    _UserTasteProfile profile,
    List<MovieRecommendation> recommendations,
  ) async {
    if (profile.favoriteGenres.isEmpty) return;
    final genreMap = _getGenreIdMap();
    await Future.wait(
      profile.favoriteGenres.take(4).map((genre) async {
        final genreId = genreMap[_normalizeGenre(genre)];
        if (genreId == null) return;
        try {
          final response = await _callTmdb('/3/discover/movie', {
            'with_genres': genreId.toString(),
            'sort_by': 'popularity.desc',
            'vote_count.gte': '80',
            'vote_average.gte': '5.5',
            'page': '${_random.nextInt(5) + 1}',
            'language': 'tr-TR',
          });
          final movies = _movieResults(response).take(16).toList();
          for (var index = 0; index < movies.length; index++) {
            _addCandidate(
              recommendations,
              movies[index],
              'Sevdiğin türlerden biri: $genre',
              signalBoost: math.max(0, 3.5 - (index * 0.25)),
            );
          }
        } catch (error) {
          debugPrint('Genre recommendation error ($genre): $error');
        }
      }),
    );
  }

  Future<void> _getDirectorBasedRecommendations(
    _UserTasteProfile profile,
    List<MovieRecommendation> recommendations,
  ) async {
    await Future.wait(
      profile.favoriteDirectors
          .take(4)
          .map(
            (name) => _fetchPersonCredits(
              name,
              department: 'Directing',
              recommendations: recommendations,
              reason: 'Favori yönetmenin $name',
            ),
          ),
    );
  }

  Future<void> _getActorBasedRecommendations(
    _UserTasteProfile profile,
    List<MovieRecommendation> recommendations,
  ) async {
    await Future.wait(
      profile.favoriteActors
          .take(5)
          .map(
            (name) => _fetchPersonCredits(
              name,
              department: 'Acting',
              recommendations: recommendations,
              reason: 'Sevdiğin oyuncu $name',
            ),
          ),
    );
  }

  Future<void> _fetchPersonCredits(
    String name, {
    required String department,
    required List<MovieRecommendation> recommendations,
    required String reason,
  }) async {
    try {
      final search = await _callTmdb('/3/search/person', {
        'query': name,
        'language': 'tr-TR',
      });
      final people = search['results'];
      if (people is! List || people.isEmpty || people.first is! Map) return;
      final personId = _positiveInt((people.first as Map)['id']);
      if (personId == null) return;

      final credits = await _callTmdb('/3/person/$personId/movie_credits', {
        'language': 'tr-TR',
      });
      final rawCredits = department == 'Directing'
          ? credits['crew']
          : credits['cast'];
      if (rawCredits is! List) return;
      final movies =
          rawCredits
              .whereType<Map>()
              .where(
                (movie) =>
                    department != 'Directing' || movie['job'] == 'Director',
              )
              .map((movie) => Map<String, dynamic>.from(movie))
              .where(_isUsefulCandidate)
              .toList()
            ..sort(
              (a, b) => _candidateQuality(b).compareTo(_candidateQuality(a)),
            );

      final pool = movies.take(18).toList()..shuffle(_random);
      final selected = pool.take(9).toList();
      for (var index = 0; index < selected.length; index++) {
        _addCandidate(
          recommendations,
          selected[index],
          reason,
          signalBoost: math.max(0, 4.0 - (index * 0.4)),
        );
      }
    } catch (error) {
      debugPrint('Person recommendation error ($name): $error');
    }
  }

  Future<void> _getSimilarMovieRecommendations(
    _UserTasteProfile profile,
    List<MovieRecommendation> recommendations,
  ) async {
    await Future.wait(
      profile.lovedMovies.take(6).map((seed) async {
        var sourceTitle = seed.title.trim();
        if (sourceTitle.isEmpty) {
          sourceTitle = await _fetchMovieTitle(seed.tmdbId);
        }
        // A generic "Benzer" label is not useful. Skip the signal when its
        // source cannot be named.
        if (sourceTitle.isEmpty) return;
        try {
          final response = await _callTmdb(
            '/3/movie/${seed.tmdbId}/recommendations',
            {'language': 'tr-TR', 'page': '1'},
          );
          final movies = _movieResults(response).take(14).toList();
          for (var index = 0; index < movies.length; index++) {
            _addCandidate(
              recommendations,
              movies[index],
              'Sevdiğin "$sourceTitle" filmine benzer',
              signalBoost: math.min(
                8.0,
                (seed.weight * 1.2) + math.max(0, 4.5 - (index * 0.4)),
              ),
            );
          }
        } catch (error) {
          debugPrint('Similar recommendation error (${seed.tmdbId}): $error');
        }
      }),
    );
  }

  Future<String> _fetchMovieTitle(int tmdbId) async {
    try {
      final movie = await _callTmdb('/3/movie/$tmdbId', {'language': 'tr-TR'});
      return (movie['title'] ?? movie['original_title'] ?? '')
          .toString()
          .trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _getTrendingRecommendations(
    List<MovieRecommendation> recommendations,
  ) async {
    try {
      final response = await _callTmdb('/3/trending/movie/week', {
        'language': 'tr-TR',
        'page': '1',
      });
      final movies = _movieResults(response).take(20).toList();
      for (var index = 0; index < movies.length; index++) {
        _addCandidate(
          recommendations,
          movies[index],
          'Bu hafta öne çıkan filmlerden',
          signalBoost: math.max(0, 2.0 - (index * 0.1)),
        );
      }
    } catch (error) {
      debugPrint('Trending recommendation error: $error');
    }
  }

  Future<Map<String, dynamic>> _callTmdb(
    String endpoint,
    Map<String, String> params,
  ) async {
    final result = await _functions.httpsCallable('callTMDB').call({
      'endpoint': endpoint,
      'params': params,
    });
    return Map<String, dynamic>.from(result.data as Map);
  }

  Iterable<Map<String, dynamic>> _movieResults(Map<String, dynamic> data) {
    final results = data['results'];
    if (results is! List) return const [];
    return results.whereType<Map>().map(Map<String, dynamic>.from);
  }

  void _addCandidate(
    List<MovieRecommendation> recommendations,
    Map<String, dynamic> movie,
    String reason, {
    double signalBoost = 0,
  }) {
    if (!_isUsefulCandidate(movie)) return;
    recommendations.add(
      _createRecommendation(movie, reason, signalBoost: signalBoost),
    );
  }

  bool _isUsefulCandidate(Map movie) {
    final id = _positiveInt(movie['id']);
    final title = (movie['title'] ?? '').toString().trim();
    final poster = (movie['poster_path'] ?? '').toString().trim();
    final vote = _asDouble(movie['vote_average']);
    final voteCount = _positiveInt(movie['vote_count']) ?? 0;
    return id != null &&
        title.isNotEmpty &&
        poster.isNotEmpty &&
        vote >= 5.2 &&
        voteCount >= 20;
  }

  MovieRecommendation _createRecommendation(
    Map<String, dynamic> movie,
    String reason, {
    required double signalBoost,
  }) {
    final posterPath = (movie['poster_path'] ?? '').toString();
    final genreIds = (movie['genre_ids'] as List? ?? const [])
        .map(_positiveInt)
        .whereType<int>()
        .toList();
    return MovieRecommendation(
      tmdbId: _positiveInt(movie['id']) ?? 0,
      title: (movie['title'] ?? '').toString(),
      posterUrl: 'https://image.tmdb.org/t/p/w500$posterPath',
      overview: (movie['overview'] ?? '').toString(),
      voteAverage: _asDouble(movie['vote_average']),
      voteCount: _positiveInt(movie['vote_count']) ?? 0,
      popularity: _asDouble(movie['popularity']),
      releaseDate: (movie['release_date'] ?? '').toString(),
      genres: genreIds.map(_genreIdToName).toList(),
      matchScore: signalBoost,
      matchReason: reason,
    );
  }

  List<MovieRecommendation> _rankCandidates(
    List<MovieRecommendation> candidates,
    _UserTasteProfile profile, {
    required Set<int> previousIds,
  }) {
    final accumulators = <int, _CandidateAccumulator>{};
    for (final candidate in candidates) {
      if (_isKnownMovie(candidate, profile)) continue;
      final accumulator = accumulators.putIfAbsent(
        candidate.tmdbId,
        () => _CandidateAccumulator(candidate),
      );
      accumulator.addReason(candidate.matchReason, candidate.matchScore);
    }

    final ranked = <MovieRecommendation>[];
    for (final accumulator in accumulators.values) {
      final movie = accumulator.movie;
      final signals = accumulator.signals.entries.toList()
        ..sort(
          (a, b) => (_reasonWeight(b.key) + b.value).compareTo(
            _reasonWeight(a.key) + a.value,
          ),
        );
      final signalScore = signals
          .take(3)
          .fold<double>(
            0,
            (total, signal) => total + _reasonWeight(signal.key) + signal.value,
          );
      final voteReliability = movie.voteCount <= 0
          ? 0.0
          : (math.log(movie.voteCount + 1) / math.ln10 * 2.2).clamp(0.0, 7.0);
      final popularityScore = (math.sqrt(math.max(0, movie.popularity)) * 0.35)
          .clamp(0.0, 4.0);
      final multiSignalBonus = signals.length > 1
          ? math.min(6.0, (signals.length - 1) * 2.0)
          : 0.0;
      final refreshPenalty = previousIds.contains(movie.tmdbId) ? 8.0 : 0.0;
      final score =
          24.0 +
          (movie.voteAverage * 2.8) +
          voteReliability +
          popularityScore +
          signalScore +
          multiSignalBonus -
          refreshPenalty;

      movie.matchScore = score.clamp(48.0, 97.0).toDouble();
      movie.matchReason = signals
          .take(2)
          .map((signal) => signal.key)
          .join(' • ');
      ranked.add(movie);
    }

    ranked.sort((a, b) {
      final scoreOrder = b.matchScore.compareTo(a.matchScore);
      if (scoreOrder != 0) return scoreOrder;
      final voteOrder = b.voteAverage.compareTo(a.voteAverage);
      if (voteOrder != 0) return voteOrder;
      return b.voteCount.compareTo(a.voteCount);
    });
    return ranked;
  }

  double _reasonWeight(String reason) {
    if (reason.startsWith('Sevdiğin "')) return 18;
    if (reason.startsWith('Favori yönetmenin')) return 16;
    if (reason.startsWith('Sevdiğin oyuncu')) return 12;
    if (reason.startsWith('Sevdiğin türlerden')) return 8;
    return 2;
  }

  double _candidateQuality(Map<String, dynamic> movie) {
    final vote = _asDouble(movie['vote_average']);
    final count = _positiveInt(movie['vote_count']) ?? 0;
    final popularity = _asDouble(movie['popularity']);
    return (vote * 8) +
        (math.log(count + 1) / math.ln10 * 4) +
        math.sqrt(math.max(0, popularity));
  }

  bool _isKnownMovie(MovieRecommendation movie, _UserTasteProfile profile) {
    if (profile.excludedTmdbIds.contains(movie.tmdbId)) return true;
    return profile.excludedTitles.contains(_normalizeTitle(movie.title));
  }

  Map<String, int> _getGenreIdMap() {
    return const {
      'aksiyon': 28,
      'macera': 12,
      'animasyon': 16,
      'komedi': 35,
      'suç': 80,
      'belgesel': 99,
      'dram': 18,
      'drama': 18,
      'aile': 10751,
      'fantastik': 14,
      'tarih': 36,
      'korku': 27,
      'müzik': 10402,
      'gizem': 9648,
      'romantik': 10749,
      'bilimkurgu': 878,
      'bilim kurgu': 878,
      'gerilim': 53,
      'savaş': 10752,
      'western': 37,
      'klasikler': 18,
    };
  }

  String _genreIdToName(int id) {
    const names = {
      28: 'Aksiyon',
      12: 'Macera',
      16: 'Animasyon',
      35: 'Komedi',
      80: 'Suç',
      99: 'Belgesel',
      18: 'Dram',
      10751: 'Aile',
      14: 'Fantastik',
      36: 'Tarih',
      27: 'Korku',
      10402: 'Müzik',
      9648: 'Gizem',
      10749: 'Romantik',
      878: 'Bilim Kurgu',
      53: 'Gerilim',
      10752: 'Savaş',
      37: 'Western',
    };
    return names[id] ?? 'Diğer';
  }
}

class _MovieSeed {
  final int tmdbId;
  final String title;
  final double weight;

  const _MovieSeed({
    required this.tmdbId,
    required this.title,
    required this.weight,
  });
}

class _CandidateAccumulator {
  final MovieRecommendation movie;
  final Map<String, double> signals = {};

  _CandidateAccumulator(this.movie);

  void addReason(String reason, double strength) {
    final normalized = reason.trim();
    if (normalized.isEmpty) return;
    signals[normalized] = math.max(signals[normalized] ?? 0, strength);
  }
}

int? _positiveInt(Object? value) {
  if (value is int && value > 0) return value;
  if (value is num && value > 0) return value.toInt();
  final parsed = int.tryParse(value?.toString() ?? '');
  return parsed != null && parsed > 0 ? parsed : null;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int? _tmdbIdFromKey(String key) {
  final normalized = key.trim().toLowerCase();
  final canonical = RegExp(r'^tmdb:(\d+)$').firstMatch(normalized);
  if (canonical != null) return _positiveInt(canonical.group(1));
  if (RegExp(r'^\d+$').hasMatch(normalized)) return _positiveInt(normalized);
  return null;
}

String _normalizeTitle(String title) {
  return title
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9çğıöşü]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _normalizeGenre(String genre) {
  return genre
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9çğıöşü]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
