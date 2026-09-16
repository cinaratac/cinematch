import 'package:cloud_firestore/cloud_firestore.dart';

/// A denormalized diary event.
///
/// Everything needed to render the diary is stored on the event so opening a
/// diary never needs an additional catalog lookup.
class DiaryEntry {
  final String id;
  final String movieKey;
  final int? tmdbId;
  final String title;
  final String posterUrl;
  final int? releaseYear;
  final DateTime watchedAt;
  final String source;

  const DiaryEntry({
    required this.id,
    required this.movieKey,
    required this.tmdbId,
    required this.title,
    required this.posterUrl,
    required this.releaseYear,
    required this.watchedAt,
    required this.source,
  });

  /// Creates an entry directly from data already available on the movie
  /// action. No Firestore/catalog resolution is performed here.
  factory DiaryEntry.fromMovie({
    required Map<String, dynamic> movieData,
    String? posterUrl,
    required String source,
    DateTime? watchedAt,
    String? movieKey,
    int? tmdbId,
    String? eventId,
  }) {
    final resolvedTmdbId =
        tmdbId ??
        _asInt(movieData['tmdbId']) ??
        _asInt(movieData['id']) ??
        _asInt(movieData['movieId']);
    final resolvedWatchedAt = watchedAt ?? DateTime.now();
    final rawMovieKey = _firstNonEmpty([
      movieKey,
      movieData['movieKey'],
      movieData['catalogDocId'],
      movieData['docId'],
      resolvedTmdbId?.toString(),
    ]);
    final resolvedTitle = _clip(
      _firstNonEmpty([
        movieData['title'],
        movieData['titleTr'],
        movieData['name'],
        movieData['original_title'],
        movieData['originalTitle'],
        'Film',
      ]),
      180,
    );
    final resolvedMovieKey = _clip(
      rawMovieKey.isEmpty ? _eventSafeKey(resolvedTitle) : rawMovieKey,
      300,
    );

    final eventKey =
        resolvedTmdbId?.toString() ?? _eventSafeKey(resolvedMovieKey);
    final explicitEventId = _clip(
      eventId?.trim().replaceAll('/', '_') ?? '',
      500,
    );

    return DiaryEntry(
      id: explicitEventId.isEmpty
          ? '${eventKey}_${resolvedWatchedAt.microsecondsSinceEpoch}'
          : explicitEventId,
      movieKey: resolvedMovieKey,
      tmdbId: resolvedTmdbId,
      title: resolvedTitle,
      posterUrl: _clip(_resolvePosterUrl(movieData, posterUrl), 1200),
      releaseYear: _releaseYear(movieData),
      watchedAt: resolvedWatchedAt,
      source: _clip(source.trim().isEmpty ? 'watched' : source.trim(), 64),
    );
  }

  factory DiaryEntry.fromMap(Map<String, dynamic> data, {String? documentId}) {
    final tmdbId =
        _asInt(data['tmdbId']) ??
        _asInt(data['id']?.toString().split('_').first);
    final watchedAt = _asDateTime(data['watchedAt']);

    return DiaryEntry(
      id: _firstNonEmpty([documentId, data['id']]),
      movieKey: _firstNonEmpty([data['movieKey'], tmdbId?.toString()]),
      tmdbId: tmdbId,
      title: _firstNonEmpty([data['title'], 'Film']),
      posterUrl: _firstNonEmpty([data['posterUrl']]),
      releaseYear: _asInt(data['releaseYear']),
      watchedAt: watchedAt,
      source: _firstNonEmpty([data['source'], 'watched']),
    );
  }

  factory DiaryEntry.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return DiaryEntry.fromMap(
      document.data() ?? const <String, dynamic>{},
      documentId: document.id,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'movieKey': movieKey,
      'tmdbId': tmdbId,
      'title': title,
      'posterUrl': posterUrl,
      if (releaseYear != null) 'releaseYear': releaseYear,
      'watchedAt': Timestamp.fromDate(watchedAt),
      'source': source,
    };
  }

  static String _resolvePosterUrl(
    Map<String, dynamic> movieData,
    String? explicitPosterUrl,
  ) {
    final direct = _firstNonEmpty([
      explicitPosterUrl,
      movieData['posterUrl'],
      movieData['poster'],
      movieData['image'],
    ]);
    if (direct.isNotEmpty) {
      if (direct.startsWith('/')) {
        return 'https://image.tmdb.org/t/p/w500$direct';
      }
      return direct;
    }

    final posterPath = _firstNonEmpty([movieData['poster_path']]);
    if (posterPath.isEmpty) return '';
    if (posterPath.startsWith('http://') || posterPath.startsWith('https://')) {
      return posterPath;
    }
    return 'https://image.tmdb.org/t/p/w500$posterPath';
  }

  static int? _releaseYear(Map<String, dynamic> movieData) {
    final explicit =
        _asInt(movieData['releaseYear']) ?? _asInt(movieData['year']);
    if (explicit != null && explicit > 1800) return explicit;

    final releaseDate = _firstNonEmpty([
      movieData['release_date'],
      movieData['releaseDate'],
      movieData['first_air_date'],
    ]);
    if (releaseDate.length < 4) return null;
    return int.tryParse(releaseDate.substring(0, 4));
  }

  static DateTime _asDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String _firstNonEmpty(Iterable<dynamic> values) {
    for (final value in values) {
      final string = value?.toString().trim() ?? '';
      if (string.isNotEmpty && string != 'null') return string;
    }
    return '';
  }

  static String _eventSafeKey(String value) {
    final safe = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return safe.isEmpty ? 'movie' : safe;
  }

  static String _clip(String value, int maxCharacters) {
    if (value.runes.length <= maxCharacters) return value;
    return String.fromCharCodes(value.runes.take(maxCharacters));
  }
}
