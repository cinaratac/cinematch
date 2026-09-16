import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:fluttergirdi/services/user_cache_service.dart';

class FriendsPopularWatchedService {
  FriendsPopularWatchedService._();
  static final FriendsPopularWatchedService instance =
      FriendsPopularWatchedService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<List<FriendPopularMovie>> loadPopularWatched({
    required Iterable<String> followingUids,
    int userLimit = 40,
    int recentPerUser = 6,
    int resultLimit = 12,
  }) async {
    final uids = followingUids
        .map((uid) => uid.trim())
        .where((uid) => uid.isNotEmpty)
        .toSet()
        .take(userLimit)
        .toList();
    if (uids.isEmpty) return const [];

    final histories = await _fetchHistories(uids, recentPerUser);
    if (histories.isEmpty) return const [];

    final movieKeys = histories
        .expand((history) => history.entries.map((entry) => entry.movieKey))
        .toSet()
        .toList();
    final moviesByKey = await _resolveMovies(movieKeys);
    if (moviesByKey.isEmpty) return const [];

    await UserCacheService.instance.fetchUsers(
      histories.map((history) => history.uid).toList(),
    );

    final groups = <String, _PopularGroup>{};
    for (final history in histories) {
      final user = UserCacheService.instance.getFromCache(history.uid);
      final watcher = FriendMovieWatcher(
        uid: history.uid,
        displayName: user?.displayName ?? 'Kullanıcı',
        photoURL: user?.photoURL ?? '',
      );

      for (final entry in history.entries) {
        final movie = moviesByKey[entry.movieKey];
        if (movie == null || movie.tmdbId == null) continue;

        final groupKey = movie.tmdbId!.toString();
        final group = groups.putIfAbsent(
          groupKey,
          () => _PopularGroup(movie: movie),
        );
        group.addWatcher(watcher, entry.rank);
      }
    }

    final result = groups.values
        .where((group) => group.watchers.isNotEmpty)
        .map((group) => group.toMovie())
        .toList();

    result.sort((a, b) {
      final byWatcherCount = b.watchers.length.compareTo(a.watchers.length);
      if (byWatcherCount != 0) return byWatcherCount;

      final byRecency = a.bestRank.compareTo(b.bestRank);
      if (byRecency != 0) return byRecency;

      return a.title.compareTo(b.title);
    });

    return result.take(resultLimit).toList();
  }

  Future<List<_UserWatchHistory>> _fetchHistories(
    List<String> uids,
    int recentPerUser,
  ) async {
    final futures = uids.map((uid) async {
      try {
        final doc = await _db
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.serverAndCache));
        final data = doc.data() ?? {};

        final rawRecent = data['recentWatchedIds'];
        final entries = <_WatchedEntry>[];
        if (rawRecent is List) {
          final seen = <String>{};
          for (var i = 0; i < rawRecent.length; i++) {
            final key = _cleanKey(rawRecent[i]);
            if (key.isEmpty || !seen.add(key)) continue;
            entries.add(_WatchedEntry(movieKey: key, rank: i));
            if (entries.length >= recentPerUser) break;
          }
        }
        if (entries.isEmpty) {
          final seen = <String>{};
          final keys = [
            ...List<dynamic>.from(data['fiveStarKeys'] ?? []),
            ...List<dynamic>.from(data['favoritesKeys'] ?? []),
            ...List<dynamic>.from(data['dislikedKeys'] ?? []),
            ...List<dynamic>.from(data['watchedKeys'] ?? []),
          ].map(_cleanKey).where((key) => key.isNotEmpty);
          for (final key in keys) {
            if (!seen.add(key)) continue;
            entries.add(_WatchedEntry(movieKey: key, rank: entries.length));
            if (entries.length >= recentPerUser) break;
          }
        }
        return _UserWatchHistory(uid: uid, entries: entries);
      } catch (e) {
        debugPrint('FriendsPopularWatchedService history error: $e');
        return _UserWatchHistory(uid: uid, entries: const []);
      }
    });

    final histories = await Future.wait(futures);
    return histories.where((history) => history.entries.isNotEmpty).toList();
  }

  Future<Map<String, _MovieInfo>> _resolveMovies(List<String> keys) async {
    final cleanKeys = keys
        .map(_cleanKey)
        .where((key) => key.isNotEmpty)
        .toSet();
    if (cleanKeys.isEmpty) return const {};

    final byLookupKey = <String, _MovieInfo>{};
    final keyList = cleanKeys.toList();

    for (var i = 0; i < keyList.length; i += 10) {
      final chunk = keyList.sublist(i, math.min(i + 10, keyList.length));
      try {
        final qs = await _db
            .collection('catalog_films')
            .where(FieldPath.documentId, whereIn: chunk)
            .get(const GetOptions(source: Source.serverAndCache));

        for (final doc in qs.docs) {
          final movie = _movieFromData(doc.id, doc.data());
          byLookupKey[doc.id.toLowerCase()] = movie;
          if (movie.tmdbId != null) {
            byLookupKey[movie.tmdbId!.toString()] = movie;
          }
        }
      } catch (e) {
        debugPrint('FriendsPopularWatchedService doc lookup error: $e');
      }

      final numericIds = chunk
          .map((key) => int.tryParse(key))
          .whereType<int>()
          .toSet()
          .toList();
      if (numericIds.isEmpty) continue;

      try {
        final qs = await _db
            .collection('catalog_films')
            .where('tmdbId', whereIn: numericIds.take(10).toList())
            .get(const GetOptions(source: Source.serverAndCache));

        for (final doc in qs.docs) {
          final movie = _movieFromData(doc.id, doc.data());
          byLookupKey[doc.id.toLowerCase()] = movie;
          if (movie.tmdbId != null) {
            byLookupKey[movie.tmdbId!.toString()] = movie;
          }
        }
      } catch (e) {
        debugPrint('FriendsPopularWatchedService tmdb lookup error: $e');
      }
    }

    return {
      for (final key in cleanKeys)
        if (byLookupKey[key] != null) key: byLookupKey[key]!,
    };
  }

  _MovieInfo _movieFromData(String docId, Map<String, dynamic> data) {
    final rawTmdbId = data['tmdbId'];
    return _MovieInfo(
      key: docId,
      title:
          (data['title'] ??
                  data['titleTr'] ??
                  data['originalTitle'] ??
                  data['name'] ??
                  'Film')
              .toString(),
      posterUrl: (data['posterUrl'] ?? data['poster'] ?? data['image'] ?? '')
          .toString(),
      tmdbId: rawTmdbId is num
          ? rawTmdbId.toInt()
          : int.tryParse(rawTmdbId?.toString() ?? ''),
    );
  }

  String _cleanKey(Object? value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }
}

class FriendPopularMovie {
  final String key;
  final String title;
  final String posterUrl;
  final int tmdbId;
  final int bestRank;
  final List<FriendMovieWatcher> watchers;

  const FriendPopularMovie({
    required this.key,
    required this.title,
    required this.posterUrl,
    required this.tmdbId,
    required this.bestRank,
    required this.watchers,
  });
}

class FriendMovieWatcher {
  final String uid;
  final String displayName;
  final String photoURL;

  const FriendMovieWatcher({
    required this.uid,
    required this.displayName,
    required this.photoURL,
  });
}

class _PopularGroup {
  final _MovieInfo movie;
  final Map<String, FriendMovieWatcher> _watchers = {};
  int bestRank = 9999;

  _PopularGroup({required this.movie});

  List<FriendMovieWatcher> get watchers => _watchers.values.toList();

  void addWatcher(FriendMovieWatcher watcher, int rank) {
    _watchers.putIfAbsent(watcher.uid, () => watcher);
    if (rank < bestRank) bestRank = rank;
  }

  FriendPopularMovie toMovie() {
    return FriendPopularMovie(
      key: movie.key,
      title: movie.title,
      posterUrl: movie.posterUrl,
      tmdbId: movie.tmdbId!,
      bestRank: bestRank,
      watchers: watchers,
    );
  }
}

class _UserWatchHistory {
  final String uid;
  final List<_WatchedEntry> entries;

  const _UserWatchHistory({required this.uid, required this.entries});
}

class _WatchedEntry {
  final String movieKey;
  final int rank;

  const _WatchedEntry({required this.movieKey, required this.rank});
}

class _MovieInfo {
  final String key;
  final String title;
  final String posterUrl;
  final int? tmdbId;

  const _MovieInfo({
    required this.key,
    required this.title,
    required this.posterUrl,
    required this.tmdbId,
  });
}
