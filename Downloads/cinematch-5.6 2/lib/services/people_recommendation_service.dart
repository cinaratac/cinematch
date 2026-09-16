import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

enum RecommendedPersonKind { actor, director }

class RecommendedPerson {
  const RecommendedPerson({
    required this.id,
    required this.name,
    required this.profileUrl,
    required this.kind,
    required this.score,
    required this.matchedMovieTitles,
  });

  final int id;
  final String name;
  final String profileUrl;
  final RecommendedPersonKind kind;
  final double score;
  final List<String> matchedMovieTitles;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'profileUrl': profileUrl,
    'kind': kind.name,
    'score': score,
    'matchedMovieTitles': matchedMovieTitles,
  };

  factory RecommendedPerson.fromMap(Map<String, dynamic> map) {
    return RecommendedPerson(
      id: _positiveInt(map['id']) ?? 0,
      name: (map['name'] ?? '').toString(),
      profileUrl: (map['profileUrl'] ?? '').toString(),
      kind: map['kind'] == RecommendedPersonKind.director.name
          ? RecommendedPersonKind.director
          : RecommendedPersonKind.actor,
      score: (map['score'] as num?)?.toDouble() ?? 0,
      matchedMovieTitles: List<String>.from(
        map['matchedMovieTitles'] ?? const [],
      ),
    );
  }
}

class PeopleRecommendations {
  const PeopleRecommendations({required this.actors, required this.directors});

  static const empty = PeopleRecommendations(actors: [], directors: []);

  final List<RecommendedPerson> actors;
  final List<RecommendedPerson> directors;

  bool get isEmpty => actors.isEmpty && directors.isEmpty;
}

class PeopleRecommendationService {
  PeopleRecommendationService._();

  static final PeopleRecommendationService instance =
      PeopleRecommendationService._();

  static const _cacheDuration = Duration(days: 7);
  static const _resultLimit = 10;
  static const _primaryMovieLimit = 12;
  static const _relatedMovieLimit = 16;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Map<String, PeopleRecommendations> _memoryCache = {};
  final Map<String, DateTime> _memoryCacheTimes = {};
  final Map<String, Future<PeopleRecommendations>> _pending = {};

  Future<PeopleRecommendations> loadForUser(
    String uid, {
    bool forceRefresh = false,
  }) {
    if (uid.isEmpty) return Future.value(PeopleRecommendations.empty);

    final cachedAt = _memoryCacheTimes[uid];
    if (!forceRefresh &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheDuration) {
      return Future.value(_memoryCache[uid] ?? PeopleRecommendations.empty);
    }

    final pending = _pending[uid];
    if (pending != null) return pending;

    final future = _load(uid, forceRefresh: forceRefresh);
    _pending[uid] = future;
    return future.whenComplete(() {
      if (identical(_pending[uid], future)) _pending.remove(uid);
    });
  }

  Future<PeopleRecommendations> _load(
    String uid, {
    required bool forceRefresh,
  }) async {
    if (!forceRefresh) {
      final cached = await _readFirestoreCache(uid);
      if (cached != null) {
        _remember(uid, cached);
        return cached;
      }
    }

    try {
      final userSnapshot = await _db.collection('users').doc(uid).get();
      final userData = userSnapshot.data();
      if (userData == null) return PeopleRecommendations.empty;

      final seeds = await _resolveFavoriteMovies(userData);
      if (seeds.isEmpty) return PeopleRecommendations.empty;

      final actorScores = <int, _PersonScore>{};
      final directorScores = <int, _PersonScore>{};
      final primarySeeds = seeds.take(_primaryMovieLimit).toList();
      final primaryCredits = await Future.wait(
        primarySeeds.map((seed) => _loadCredits(seed.tmdbId)),
      );

      for (var i = 0; i < primarySeeds.length; i++) {
        final credits = primaryCredits[i];
        if (credits == null) continue;
        _scoreCredits(
          credits,
          source: primarySeeds[i],
          actors: actorScores,
          directors: directorScores,
        );
      }

      if (actorScores.length < _resultLimit ||
          directorScores.length < _resultLimit) {
        final relatedSeeds = await _loadRelatedMovieSeeds(primarySeeds);
        final relatedCredits = await Future.wait(
          relatedSeeds.map((seed) => _loadCredits(seed.tmdbId)),
        );
        for (var i = 0; i < relatedSeeds.length; i++) {
          final credits = relatedCredits[i];
          if (credits == null) continue;
          _scoreCredits(
            credits,
            source: relatedSeeds[i],
            actors: actorScores,
            directors: directorScores,
          );
        }
      }

      final recommendations = PeopleRecommendations(
        actors: _rankPeople(actorScores.values),
        directors: _rankPeople(directorScores.values),
      );
      _remember(uid, recommendations);
      await _writeFirestoreCache(uid, recommendations);
      return recommendations;
    } catch (error) {
      debugPrint('PeopleRecommendationService load error: $error');
      return PeopleRecommendations.empty;
    }
  }

  Future<List<_MovieSeed>> _resolveFavoriteMovies(
    Map<String, dynamic> userData,
  ) async {
    final weights = <String, double>{};

    void addKeys(Object? value, double weight) {
      if (value is! List) return;
      for (final raw in value) {
        final key = raw.toString().trim();
        if (key.isEmpty) continue;
        weights[key] = (weights[key] ?? 0) + weight;
      }
    }

    addKeys(userData['fiveStarKeys'], 2.0);
    addKeys(userData['favoritesKeys'], 3.0);
    if (weights.isEmpty) return const [];

    final seeds = <_MovieSeed>[];
    final keys = weights.keys.toList();
    for (var i = 0; i < keys.length; i += 10) {
      final end = math.min(i + 10, keys.length);
      final snapshot = await _db
          .collection('catalog_films')
          .where(FieldPath.documentId, whereIn: keys.sublist(i, end))
          .get();
      for (final document in snapshot.docs) {
        final data = document.data();
        final tmdbId = _positiveInt(data['tmdbId']);
        final title = (data['title'] ?? '').toString().trim();
        if (tmdbId == null || title.isEmpty) continue;
        seeds.add(
          _MovieSeed(
            tmdbId: tmdbId,
            reasonTitle: title,
            weight: weights[document.id] ?? 1,
          ),
        );
      }
    }

    seeds.sort((a, b) => b.weight.compareTo(a.weight));
    return seeds;
  }

  Future<Map<String, dynamic>?> _loadCredits(int tmdbId) async {
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('callTMDB')
          .call({
            'endpoint': '/3/movie/$tmdbId/credits',
            'params': {'language': 'tr-TR'},
          });
      return Map<String, dynamic>.from(response.data as Map);
    } catch (error) {
      debugPrint('People credits load error ($tmdbId): $error');
      return null;
    }
  }

  Future<List<_MovieSeed>> _loadRelatedMovieSeeds(
    List<_MovieSeed> primarySeeds,
  ) async {
    final sourceSeeds = primarySeeds.take(5).toList();
    if (sourceSeeds.isEmpty) return const [];
    final moviesPerSeed = (_relatedMovieLimit / sourceSeeds.length).ceil();
    final results = await Future.wait(
      sourceSeeds.map((seed) async {
        try {
          final response = await FirebaseFunctions.instance
              .httpsCallable('callTMDB')
              .call({
                'endpoint': '/3/movie/${seed.tmdbId}/recommendations',
                'params': {'language': 'tr-TR', 'page': '1'},
              });
          final data = Map<String, dynamic>.from(response.data as Map);
          final movies = data['results'] is List
              ? data['results'] as List
              : const [];
          return movies
              .take(moviesPerSeed)
              .map((raw) {
                final movie = Map<String, dynamic>.from(raw as Map);
                return _MovieSeed(
                  tmdbId: _positiveInt(movie['id']) ?? 0,
                  reasonTitle: seed.reasonTitle,
                  weight: seed.weight * 0.35,
                );
              })
              .where((movie) => movie.tmdbId > 0)
              .toList();
        } catch (_) {
          return <_MovieSeed>[];
        }
      }),
    );

    final primaryIds = primarySeeds.map((seed) => seed.tmdbId).toSet();
    final unique = <int, _MovieSeed>{};
    for (final group in results) {
      for (final movie in group) {
        if (!primaryIds.contains(movie.tmdbId)) unique[movie.tmdbId] = movie;
      }
    }
    return unique.values.take(_relatedMovieLimit).toList();
  }

  void _scoreCredits(
    Map<String, dynamic> credits, {
    required _MovieSeed source,
    required Map<int, _PersonScore> actors,
    required Map<int, _PersonScore> directors,
  }) {
    final cast = credits['cast'] is List ? credits['cast'] as List : const [];
    for (var index = 0; index < math.min(15, cast.length); index++) {
      final raw = cast[index];
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw);
      final id = _positiveInt(data['id']);
      final name = (data['name'] ?? '').toString().trim();
      if (id == null || name.isEmpty) continue;
      final popularity = (data['popularity'] as num?)?.toDouble() ?? 0;
      final contribution =
          (source.weight * 12) +
          ((15 - index) * 0.7) +
          (math.sqrt(math.max(0, popularity)) * 0.8);
      _addPerson(
        actors,
        data: data,
        kind: RecommendedPersonKind.actor,
        contribution: contribution,
        reasonTitle: source.reasonTitle,
      );
    }

    final crew = credits['crew'] is List ? credits['crew'] as List : const [];
    for (final raw in crew) {
      if (raw is! Map || raw['job'] != 'Director') continue;
      final data = Map<String, dynamic>.from(raw);
      final popularity = (data['popularity'] as num?)?.toDouble() ?? 0;
      _addPerson(
        directors,
        data: data,
        kind: RecommendedPersonKind.director,
        contribution:
            (source.weight * 18) + (math.sqrt(math.max(0, popularity)) * 1.2),
        reasonTitle: source.reasonTitle,
      );
    }
  }

  void _addPerson(
    Map<int, _PersonScore> scores, {
    required Map<String, dynamic> data,
    required RecommendedPersonKind kind,
    required double contribution,
    required String reasonTitle,
  }) {
    final id = _positiveInt(data['id']);
    final name = (data['name'] ?? '').toString().trim();
    if (id == null || name.isEmpty) return;

    final profilePath = (data['profile_path'] ?? '').toString();
    final profileUrl = profilePath.isEmpty
        ? ''
        : 'https://image.tmdb.org/t/p/w342$profilePath';
    final popularity = (data['popularity'] as num?)?.toDouble() ?? 0;
    final person = scores.putIfAbsent(
      id,
      () => _PersonScore(
        id: id,
        name: name,
        profileUrl: profileUrl,
        kind: kind,
        popularity: popularity,
      ),
    );
    person.score += contribution;
    if (person.profileUrl.isEmpty && profileUrl.isNotEmpty) {
      person.profileUrl = profileUrl;
    }
    if (reasonTitle.isNotEmpty) person.matchedMovieTitles.add(reasonTitle);
  }

  List<RecommendedPerson> _rankPeople(Iterable<_PersonScore> values) {
    final ranked = values.toList()
      ..sort((a, b) {
        final scoreComparison = b.score.compareTo(a.score);
        if (scoreComparison != 0) return scoreComparison;
        return b.popularity.compareTo(a.popularity);
      });
    final withPortrait = ranked.where((person) => person.profileUrl.isNotEmpty);
    final withoutPortrait = ranked.where((person) => person.profileUrl.isEmpty);
    return [...withPortrait, ...withoutPortrait]
        .take(_resultLimit)
        .map((person) => person.toRecommendation())
        .toList(growable: false);
  }

  DocumentReference<Map<String, dynamic>> _cacheRef(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('recommendations')
      .doc('people');

  Future<PeopleRecommendations?> _readFirestoreCache(String uid) async {
    try {
      final snapshot = await _cacheRef(uid).get();
      final data = snapshot.data();
      final cachedAt = (data?['cachedAt'] as Timestamp?)?.toDate();
      if (data == null ||
          cachedAt == null ||
          DateTime.now().difference(cachedAt) >= _cacheDuration) {
        return null;
      }
      final actors = _peopleFromRaw(data['actors']);
      final directors = _peopleFromRaw(data['directors']);
      if (actors.isEmpty && directors.isEmpty) return null;
      return PeopleRecommendations(actors: actors, directors: directors);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeFirestoreCache(
    String uid,
    PeopleRecommendations recommendations,
  ) async {
    if (recommendations.isEmpty) return;
    try {
      await _cacheRef(uid).set({
        'actors': recommendations.actors
            .map((person) => person.toMap())
            .toList(),
        'directors': recommendations.directors
            .map((person) => person.toMap())
            .toList(),
        'cachedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      debugPrint('People recommendations cache write error: $error');
    }
  }

  List<RecommendedPerson> _peopleFromRaw(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => RecommendedPerson.fromMap(Map<String, dynamic>.from(item)),
        )
        .where((person) => person.id > 0 && person.name.isNotEmpty)
        .take(_resultLimit)
        .toList(growable: false);
  }

  void _remember(String uid, PeopleRecommendations recommendations) {
    _memoryCache[uid] = recommendations;
    _memoryCacheTimes[uid] = DateTime.now();
  }
}

class _MovieSeed {
  const _MovieSeed({
    required this.tmdbId,
    required this.reasonTitle,
    required this.weight,
  });

  final int tmdbId;
  final String reasonTitle;
  final double weight;
}

class _PersonScore {
  _PersonScore({
    required this.id,
    required this.name,
    required this.profileUrl,
    required this.kind,
    required this.popularity,
  });

  final int id;
  final String name;
  String profileUrl;
  final RecommendedPersonKind kind;
  final double popularity;
  final Set<String> matchedMovieTitles = {};
  double score = 0;

  RecommendedPerson toRecommendation() => RecommendedPerson(
    id: id,
    name: name,
    profileUrl: profileUrl,
    kind: kind,
    score: score,
    matchedMovieTitles: matchedMovieTitles.take(3).toList(growable: false),
  );
}

int? _positiveInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed != null && parsed > 0 ? parsed : null;
}
