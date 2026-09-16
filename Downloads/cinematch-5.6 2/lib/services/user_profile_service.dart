import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/models/diary_entry.dart';
import 'package:fluttergirdi/services/diary_service.dart';
import 'package:fluttergirdi/services/shelf_state_cache.dart';
import '../models/shelf_target.dart';
import 'package:fluttergirdi/services/catalog_service.dart';

class TasteProfile {
  final String? letterboxdUsername;
  final List<String> loved;
  final List<String> disliked;
  final Map<String, String> posters;
  final List<double>? vector;
  final int? computedAtMs;

  const TasteProfile({
    this.letterboxdUsername,
    this.loved = const [],
    this.disliked = const [],
    this.posters = const {},
    this.vector,
    this.computedAtMs,
  });

  static String _norm(String v) => (v).trim().toLowerCase();

  static List<String> _dedupe(Iterable<String> items) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in items) {
      final k = _norm(raw);
      if (k.isEmpty) continue;
      if (seen.add(k)) out.add(k);
    }
    return out;
  }

  TasteProfile copyWith({
    String? letterboxdUsername,
    List<String>? loved,
    List<String>? disliked,
    Map<String, String>? posters,
    List<double>? vector,
    int? computedAtMs,
  }) {
    return TasteProfile(
      letterboxdUsername: letterboxdUsername ?? this.letterboxdUsername,
      loved: _dedupe(loved ?? this.loved),
      disliked: _dedupe(disliked ?? this.disliked),
      posters: (posters ?? this.posters).map((k, v) => MapEntry(_norm(k), v)),
      vector: vector ?? this.vector,
      computedAtMs: computedAtMs ?? this.computedAtMs,
    );
  }

  Map<String, dynamic> toMap() {
    final lovedClean = _dedupe(loved);
    final dislikedClean = _dedupe(disliked);
    final allowed = {...lovedClean, ...dislikedClean};
    final postersClean = {
      for (final entry in posters.entries)
        if (allowed.contains(_norm(entry.key))) _norm(entry.key): entry.value,
    };
    return {
      if (letterboxdUsername != null) 'letterboxdUsername': letterboxdUsername,
      'loved': lovedClean,
      'disliked': dislikedClean,
      'posters': postersClean,
      if (vector != null) 'vector': vector,
      if (computedAtMs != null) 'computedAtMs': computedAtMs,
    };
  }

  static TasteProfile fromMap(Map<String, dynamic> data) {
    List<String> stringList(dynamic v) {
      if (v is Iterable) {
        final seen = <String>{};
        final out = <String>[];
        for (final e in v) {
          final s = (e?.toString() ?? '').trim();
          if (s.isEmpty) continue;
          final norm = _norm(s);
          if (seen.add(norm)) out.add(norm);
        }
        return out;
      }
      return <String>[];
    }

    Map<String, String> stringMap(dynamic v) {
      if (v is Map) {
        return v.map((k, val) => MapEntry(k.toString(), val?.toString() ?? ''));
      }
      return <String, String>{};
    }

    List<double>? doubleList(dynamic v) {
      if (v is Iterable) {
        return v.map((e) {
          if (e is num) return e.toDouble();
          return double.tryParse(e.toString()) ?? 0.0;
        }).toList();
      }
      return null;
    }

    final tp = TasteProfile(
      letterboxdUsername: (data['letterboxdUsername'] as String?)?.trim(),
      loved: stringList(data['loved']),
      disliked: stringList(data['disliked']),
      posters: stringMap(data['posters']),
      vector: doubleList(data['vector']),
      computedAtMs: (data['computedAtMs'] is num)
          ? (data['computedAtMs'] as num).toInt()
          : int.tryParse('${data['computedAtMs'] ?? ''}'),
    );
    final lovedClean = _dedupe(tp.loved);
    final dislikedClean = _dedupe(tp.disliked);
    final allowed = {...lovedClean, ...dislikedClean};
    final postersClean = {
      for (final e in tp.posters.entries)
        if (allowed.contains(_norm(e.key))) _norm(e.key): e.value,
    };
    return tp.copyWith(
      loved: lovedClean,
      disliked: dislikedClean,
      posters: postersClean,
    );
  }

  factory TasteProfile.fromLists({
    String? letterboxdUsername,
    Iterable<String> loved = const [],
    Iterable<String> disliked = const [],
    Map<String, String> posters = const {},
    List<double>? vector,
    int? computedAtMs,
  }) {
    final lovedClean = _dedupe(loved);
    final dislikedClean = _dedupe(disliked);
    final allowed = {...lovedClean, ...dislikedClean};
    final postersClean = {
      for (final entry in posters.entries)
        if (allowed.contains(_norm(entry.key))) _norm(entry.key): entry.value,
    };
    return TasteProfile(
      letterboxdUsername: letterboxdUsername,
      loved: lovedClean,
      disliked: dislikedClean,
      posters: postersClean,
      vector: vector,
      computedAtMs: computedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  TasteProfile merge(TasteProfile other) {
    final lovedMerged = _dedupe([...loved, ...other.loved]);
    final dislikedMerged = _dedupe([...disliked, ...other.disliked]);
    final postersMerged = Map<String, String>.from(posters);
    postersMerged.addAll(other.posters.map((k, v) => MapEntry(_norm(k), v)));
    return copyWith(
      loved: lovedMerged,
      disliked: dislikedMerged,
      posters: postersMerged,
      vector: other.vector ?? vector,
      computedAtMs: (other.computedAtMs ?? 0) > (computedAtMs ?? 0)
          ? other.computedAtMs
          : computedAtMs,
    );
  }

  TasteProfile addLoved(String filmKey, {String? posterUrl}) {
    final key = _norm(filmKey);
    final nextLoved = _dedupe([...loved, key]);
    final nextPosters = Map<String, String>.from(posters);
    if (posterUrl != null && posterUrl.isNotEmpty) nextPosters[key] = posterUrl;
    return copyWith(loved: nextLoved, posters: nextPosters);
  }

  TasteProfile addDisliked(String filmKey, {String? posterUrl}) {
    final key = _norm(filmKey);
    final nextDisliked = _dedupe([...disliked, key]);
    final nextPosters = Map<String, String>.from(posters);
    if (posterUrl != null && posterUrl.isNotEmpty) nextPosters[key] = posterUrl;
    return copyWith(disliked: nextDisliked, posters: nextPosters);
  }

  static const empty = TasteProfile();
}

class UserProfileService {
  UserProfileService._();
  static final UserProfileService instance = UserProfileService._();

  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _tasteRef(String uid) =>
      _fs.collection('userTasteProfiles').doc(uid);

  DocumentReference<Map<String, dynamic>> _usersRef(String uid) =>
      _fs.collection('users').doc(uid);

  String _lc(Object? v) => v == null ? '' : v.toString().trim().toLowerCase();

  List<Map<String, dynamic>> _recentDiaryWith(String uid, DiaryEntry entry) {
    final recent = DiaryService.instance.mergeRecent(
      ShelfStateCache.instance.getRecentDiary(uid),
      entry,
    );
    ShelfStateCache.instance.setRecentDiary(uid, recent);
    return recent;
  }

  Future<void> ensureSearchableUserFields({required String uid}) async {
    final ref = _usersRef(uid);
    var snap = await ref.get(const GetOptions(source: Source.cache));
    if (!snap.exists)
      snap = await ref.get(const GetOptions(source: Source.server));
    final data = snap.data() ?? <String, dynamic>{};

    final update = <String, dynamic>{
      if (data['username'] != null &&
          (data['username_lc'] as String? ?? '').isEmpty)
        'username_lc': _lc(data['username']),
      if (data['displayName'] != null &&
          (data['displayName_lc'] as String? ?? '').isEmpty)
        'displayName_lc': _lc(data['displayName']),
      if (data['letterboxdUsername'] != null &&
          (data['letterboxdUsername_lc'] as String? ?? '').isEmpty)
        'letterboxdUsername_lc': _lc(data['letterboxdUsername']),
    };
    if (data['createdAt'] == null)
      update['createdAt'] = FieldValue.serverTimestamp();
    update['updatedAt'] = FieldValue.serverTimestamp();
    if (update.isNotEmpty) await ref.set(update, SetOptions(merge: true));
  }

  Future<void> _mirrorFiveStarKeysToUsers({
    required String uid,
    required List<String> fiveStarKeys,
  }) async {
    await _usersRef(uid).set({
      'fiveStarKeys': _normKeys(fiveStarKeys),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _mirrorDislikedKeysToUsers({
    required String uid,
    required List<String> dislikedKeys,
  }) async {
    await _usersRef(uid).set({
      'dislikedKeys': _normKeys(dislikedKeys),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> mirrorWatchlistKeysToUsers({
    required String uid,
    required List<String> watchlistKeys,
  }) async {
    await _usersRef(uid).set({
      'watchlistKeys': _normKeys(watchlistKeys),
      'watchlistUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveWatchlistKeys({
    required String uid,
    required List<String> keys,
  }) async {
    await mirrorWatchlistKeysToUsers(uid: uid, watchlistKeys: keys);
    await ensureSearchableUserFields(uid: uid);
  }

  Future<void> saveTasteProfile({
    required String uid,
    required TasteProfile profile,
    String? syncReason,
    bool setLastSyncedAt = false,
  }) async {
    final map = profile.toMap()..['updatedAt'] = FieldValue.serverTimestamp();
    if (setLastSyncedAt) map['lastSyncedAt'] = FieldValue.serverTimestamp();
    if (syncReason != null) map['syncReason'] = syncReason;

    final loved = _normKeys(profile.loved);
    final disliked = _normKeys(profile.disliked);
    final batch = _fs.batch();

    batch.set(_tasteRef(uid), map, SetOptions(merge: true));

    final mirrorPayload = <String, dynamic>{
      if (profile.letterboxdUsername != null)
        'letterboxdUsername': profile.letterboxdUsername,
      'fiveStarKeys': loved,
      'dislikedKeys': disliked,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (setLastSyncedAt)
      mirrorPayload['lastSyncedAt'] = FieldValue.serverTimestamp();
    if (syncReason != null) mirrorPayload['syncReason'] = syncReason;
    batch.set(_usersRef(uid), mirrorPayload, SetOptions(merge: true));

    await batch.commit();
  }

  Future<void> patchTasteProfile({
    required String uid,
    List<String>? loved,
    List<String>? disliked,
    Map<String, String>? posters,
    List<double>? vector,
    int? computedAtMs,
    String? letterboxdUsername,
  }) async {
    final update = <String, dynamic>{};
    if (loved != null) update['loved'] = loved;
    if (disliked != null) update['disliked'] = disliked;
    if (posters != null) update['posters'] = posters;
    if (vector != null) update['vector'] = vector;
    if (computedAtMs != null) update['computedAtMs'] = computedAtMs;
    if (letterboxdUsername != null)
      update['letterboxdUsername'] = letterboxdUsername;
    update['updatedAt'] = FieldValue.serverTimestamp();
    if (update.isEmpty) return;
    await _tasteRef(uid).set(update, SetOptions(merge: true));

    if (loved != null)
      await _mirrorFiveStarKeysToUsers(uid: uid, fiveStarKeys: loved);
    if (letterboxdUsername != null) {
      await _usersRef(uid).set({
        'letterboxdUsername': letterboxdUsername,
        'letterboxdUsername_lc': _lc(letterboxdUsername),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    if (disliked != null)
      await _mirrorDislikedKeysToUsers(uid: uid, dislikedKeys: disliked);
  }

  Future<TasteProfile> loadTasteProfile(String uid) async {
    var snap = await _tasteRef(uid).get(const GetOptions(source: Source.cache));
    if (!snap.exists)
      snap = await _tasteRef(uid).get(const GetOptions(source: Source.server));
    final data = snap.data();
    if (data == null) return TasteProfile.empty;
    try {
      return TasteProfile.fromMap(data);
    } catch (_) {
      return TasteProfile.empty;
    }
  }

  Stream<TasteProfile> watchTasteProfile(String uid) {
    return _tasteRef(uid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return TasteProfile.empty;
      try {
        return TasteProfile.fromMap(data);
      } catch (_) {
        return TasteProfile.empty;
      }
    });
  }

  Future<void> setLetterboxdUsername({
    required String uid,
    required String username,
  }) async {
    final clean = username.trim();
    final lower = clean.toLowerCase();
    final batch = _fs.batch();
    batch.set(_fs.collection('users').doc(uid), {
      'letterboxdUsername': clean,
      'letterboxdUsername_lc': lower,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(_tasteRef(uid), {
      'letterboxdUsername': clean,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
    await ensureSearchableUserFields(uid: uid);
  }

  Future<void> saveUserPreferences({
    required String uid,
    int? age,
    List<String>? favGenres,
    List<String>? favDirectors,
    List<String>? favActors,
  }) async {
    final payload = <String, dynamic>{
      if (age != null) 'age': age,
      if (favGenres != null) 'favGenres': _cleanGenres(favGenres),
      if (favDirectors != null) 'favDirectors': _dedupePretty(favDirectors),
      if (favActors != null) 'favActors': _dedupePretty(favActors),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (payload.isEmpty) return;
    await _usersRef(uid).set(payload, SetOptions(merge: true));
    await ensureSearchableUserFields(uid: uid);
  }

  List<String> _normKeys(Iterable<String> keys) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in keys) {
      final k = raw.trim().toLowerCase();
      if (k.isEmpty) continue;
      if (seen.add(k)) out.add(k);
    }
    return out;
  }

  List<String> _dedupePretty(Iterable<String> items) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in items) {
      final s = raw.toString().trim();
      if (s.isEmpty) continue;
      if (seen.add(s.toLowerCase())) out.add(s);
    }
    return out;
  }

  List<String> _cleanGenres(Iterable<String> items) => _dedupePretty(items);

  Map<String, String> _mergePosters({
    required Map<String, String> base,
    required Map<String, String> incoming,
    required Set<String> allowedKeys,
  }) {
    final out = Map<String, String>.from(base);
    for (final e in incoming.entries) {
      final k = e.key.trim().toLowerCase();
      final v = e.value.toString();
      if (k.isEmpty || v.isEmpty) continue;
      if (allowedKeys.contains(k)) out[k] = v;
    }
    return out;
  }

  Future<void> saveFromLetterboxd({
    required String uid,
    String? username,
    String? lbUsername,
    List<String> lovedKeys = const [],
    List<String> dislikedKeys = const [],
    Map<String, String> posters = const {},
    int? computedAtMs,
    bool merge = true,
  }) async {
    final uname = username ?? lbUsername;
    final current = merge ? await loadTasteProfile(uid) : TasteProfile.empty;
    final lovedClean = _normKeys(lovedKeys);
    final dislikedClean = _normKeys(dislikedKeys);
    final incoming = TasteProfile.fromLists(
      letterboxdUsername: uname ?? current.letterboxdUsername,
      loved: lovedClean,
      disliked: dislikedClean,
      posters: posters,
      vector: current.vector,
      computedAtMs: computedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    );
    final merged = merge ? current.merge(incoming) : incoming;
    final mergedAllowed = {...merged.loved, ...merged.disliked}.toSet();
    final cleanedPosters = _mergePosters(
      base: merged.posters,
      incoming: posters,
      allowedKeys: mergedAllowed,
    );
    final finalProfile = merged.copyWith(
      posters: cleanedPosters,
      letterboxdUsername: uname ?? merged.letterboxdUsername,
      computedAtMs: computedAtMs ?? merged.computedAtMs,
    );
    await saveTasteProfile(uid: uid, profile: finalProfile);
  }

  Future<void> addLovedKeys({
    required String uid,
    required List<String> filmKeys,
    Map<String, String> posters = const {},
  }) async {
    final current = await loadTasteProfile(uid);
    final incoming = _normKeys(filmKeys);
    final next = current.copyWith(
      loved: TasteProfile._dedupe([...current.loved, ...incoming]),
      posters: _mergePosters(
        base: current.posters,
        incoming: posters,
        allowedKeys: {
          ...current.loved,
          ...current.disliked,
          ...incoming,
        }.toSet(),
      ),
      computedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await saveTasteProfile(uid: uid, profile: next);
  }

  Future<void> addDislikedKeys({
    required String uid,
    required List<String> filmKeys,
    Map<String, String> posters = const {},
  }) async {
    final current = await loadTasteProfile(uid);
    final incoming = _normKeys(filmKeys);
    final next = current.copyWith(
      disliked: TasteProfile._dedupe([...current.disliked, ...incoming]),
      posters: _mergePosters(
        base: current.posters,
        incoming: posters,
        allowedKeys: {
          ...current.loved,
          ...current.disliked,
          ...incoming,
        }.toSet(),
      ),
      computedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await saveTasteProfile(uid: uid, profile: next);
  }

  Future<void> clearTasteProfile(String uid) async {
    await _tasteRef(uid).set({
      'loved': <String>[],
      'disliked': <String>[],
      'posters': <String, String>{},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> reportUser({
    required String reporterId,
    required String reportedId,
    required String reason,
    String? details,
  }) async {
    await _fs.collection('reports').add({
      'reporterId': reporterId,
      'reportedId': reportedId,
      'reason': reason,
      'details': details ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }

 Future<void> fastToggleWatched({
    required String uid,
    required Map<String, dynamic> movieData,
    required int tmdbId,
    required String? catalogDocId,
    required bool isCurrentlyAdded,
    bool removeFromLoved = false,
    bool removeFromDisliked = false,
  }) async {
    // 1. ID'yi TMDB formatında standartlaştırıyoruz — her zaman tmdb:{id}
    final String primaryKey = (catalogDocId != null && catalogDocId.trim().isNotEmpty)
        ? catalogDocId.trim()
        : CatalogService.canonicalKeyFromTmdb(tmdbId);
    final String tmdbStr = tmdbId.toString();

    // 2. OPTIMISTIC CACHE + fire-and-forget sunucu senkronu
    if (!isCurrentlyAdded) {
      CatalogService().injectToCache(primaryKey, movieData);
      // ignore: unawaited_futures
      CatalogService().upsertFromTmdb(movieData, catalogKey: primaryKey);
    }
    final userRef = _fs.collection('users').doc(uid);
    final batch = _fs.batch();

    if (isCurrentlyAdded) {
      final keys = [primaryKey, tmdbId, tmdbStr];
      batch.set(userRef, {
        'watchedKeys': FieldValue.arrayRemove(keys),
        'favoritesKeys': FieldValue.arrayRemove(keys),
        'fiveStarKeys': FieldValue.arrayRemove(keys),
        'dislikedKeys': FieldValue.arrayRemove(keys),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (removeFromLoved || removeFromDisliked) {
        batch.set(_tasteRef(uid), {
          if (removeFromLoved) 'loved': FieldValue.arrayRemove(keys),
          if (removeFromDisliked) 'disliked': FieldValue.arrayRemove(keys),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    } else {
      final entry = DiaryEntry.fromMovie(
        movieData: movieData,
        posterUrl: (movieData['posterUrl'] ?? movieData['poster'])?.toString(),
        source: 'watched',
        movieKey: primaryKey,
        tmdbId: tmdbId,
      );
      final recentDiary = _recentDiaryWith(uid, entry);

      batch.set(userRef, {
        'watchedKeys': FieldValue.arrayUnion([primaryKey, tmdbStr]),
        'watchlistKeys': FieldValue.arrayRemove([primaryKey, tmdbId, tmdbStr]),
        'recentWatchedIds': recentDiary
            .map((item) => item['movieKey']?.toString() ?? '')
            .where((key) => key.isNotEmpty)
            .toList(),
        'recentDiaryEntries': recentDiary,
        'diaryUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      DiaryService.instance.addToBatch(batch, uid, entry);
      await batch.commit();
    }
  }

  Future<void> fastToggleStandardList({
    required String uid,
    required Map<String, dynamic> movieData,
    required int tmdbId,
    required String? catalogDocId,
    required ShelfTarget target,
    required bool isCurrentlyAdded,
    String? posterUrl,
    bool logToDiary = true,
  }) async {
    // 1. ID'yi TMDB formatında standartlaştırıyoruz — her zaman tmdb:{id}
    final String primaryKey = (catalogDocId != null && catalogDocId.trim().isNotEmpty)
        ? catalogDocId.trim()
        : CatalogService.canonicalKeyFromTmdb(tmdbId);
    final String tmdbStr = tmdbId.toString();

    // 2. OPTIMISTIC CACHE: Firestore'a hiç dokunmadan filmi anında RAM'e yaz,
    //    Profil/Watchlist ekranı bu key'i artık kara listede bulamayacak.
    if (!isCurrentlyAdded) {
      CatalogService().injectToCache(primaryKey, {
        ...movieData,
        if (posterUrl != null && posterUrl.trim().isNotEmpty)
          'posterUrl': posterUrl,
      });
      // 3. Sunucu tarafını fire-and-forget tetikle (await YOK) — UI beklemesin.
      // ignore: unawaited_futures
      CatalogService().upsertFromTmdb(movieData, catalogKey: primaryKey);
    }
    final userRef = _fs.collection('users').doc(uid);

    // ShelfTarget → Firestore alan adı eşleşmesi
    final String shelfKey = switch (target) {
      ShelfTarget.fiveStar => 'fiveStar',
      ShelfTarget.disliked => 'disliked',
      ShelfTarget.favorites => 'favorites',
      ShelfTarget.watchlist => 'watchlist',
    };
    final String listField = '${shelfKey}Keys';

    if (isCurrentlyAdded) {
      // --- ÇIKARMA: Sadece ilgili listeden sil ---
      final batch = _fs.batch();

      batch.set(userRef, {
        listField: FieldValue.arrayRemove([primaryKey, tmdbId, tmdbStr]),
      }, SetOptions(merge: true));

      if (shelfKey == 'fiveStar') {
        batch.set(_tasteRef(uid), {
          'loved': FieldValue.arrayRemove([primaryKey, tmdbId, tmdbStr]),
        }, SetOptions(merge: true));
      } else if (shelfKey == 'disliked') {
        batch.set(_tasteRef(uid), {
          'disliked': FieldValue.arrayRemove([primaryKey, tmdbId, tmdbStr]),
        }, SetOptions(merge: true));
      }

      await batch.commit();
    } else {
      // --- EKLEME: Listeye ekle, izlendiyse izleneceklerden çıkar ---
      final batch = _fs.batch();

      final Map<String, dynamic> userUpdates = {
        listField: FieldValue.arrayUnion([primaryKey]),
      };

      if (target != ShelfTarget.watchlist) {
        userUpdates['watchedKeys'] = FieldValue.arrayUnion([
          primaryKey,
          tmdbStr,
        ]);
        userUpdates['watchlistKeys'] = FieldValue.arrayRemove([
          primaryKey,
          tmdbId,
          tmdbStr,
        ]);
      }

      DiaryEntry? diaryEntry;
      if (target != ShelfTarget.watchlist && logToDiary) {
        diaryEntry = DiaryEntry.fromMovie(
          movieData: movieData,
          posterUrl: posterUrl,
          source: shelfKey,
          movieKey: primaryKey,
          tmdbId: tmdbId,
        );
        final recentDiary = _recentDiaryWith(uid, diaryEntry);
        userUpdates['recentWatchedIds'] = recentDiary
            .map((item) => item['movieKey']?.toString() ?? '')
            .where((key) => key.isNotEmpty)
            .toList();
        userUpdates['recentDiaryEntries'] = recentDiary;
        userUpdates['diaryUpdatedAt'] = FieldValue.serverTimestamp();
      }

      batch.set(userRef, userUpdates, SetOptions(merge: true));

      if (shelfKey == 'fiveStar') {
        final poster =
            posterUrl ??
            (movieData['poster_path'] != null
                ? 'https://image.tmdb.org/t/p/w500${movieData['poster_path']}'
                : null);
        final tasteUpdate = <String, dynamic>{
          'loved': FieldValue.arrayUnion([primaryKey]),
        };
        if (poster != null) tasteUpdate['posters.$primaryKey'] = poster;
        batch.set(_tasteRef(uid), tasteUpdate, SetOptions(merge: true));
      } else if (shelfKey == 'disliked') {
        batch.set(_tasteRef(uid), {
          'disliked': FieldValue.arrayUnion([primaryKey]),
        }, SetOptions(merge: true));
      }

      if (diaryEntry != null) {
        DiaryService.instance.addToBatch(batch, uid, diaryEntry);
      }

      await batch.commit();
    }
  }
  // moveMovieToTarget – Diğer ekranlar kullanıyorsa dursun, ama fastToggle'dan
  // artık ÇAĞRILMIYOR. Bu sayede gereksiz Firestore okumaları ortadan kalktı.
  Future<String?> moveMovieToTarget({
    required String uid,
    required String movieId,
    required int tmdbId,
    required Map<String, dynamic> movieData,
    required ShelfTarget target,
    String? posterUrl,
  }) async {
    final key = movieId.trim().toLowerCase();
    if (key.isEmpty) return null;

    final tmdbKey = tmdbId.toString();
    final cache = ShelfStateCache.instance;
    bool isCachedIn(String field) {
      final values = cache.get(uid, field);
      return values.contains(key) || values.contains(tmdbKey);
    }

    final wasFiveStar = isCachedIn('fiveStarKeys');
    final wasDisliked = isCachedIn('dislikedKeys');
    final wasWatched =
        isCachedIn('watchedKeys') ||
        isCachedIn('favoritesKeys') ||
        wasFiveStar ||
        wasDisliked;

    final userRef = _fs.collection('users').doc(uid);
    final batch = _fs.batch();

    final String targetField = switch (target) {
      ShelfTarget.fiveStar => 'fiveStarKeys',
      ShelfTarget.disliked => 'dislikedKeys',
      ShelfTarget.favorites => 'favoritesKeys',
      ShelfTarget.watchlist => 'watchlistKeys',
    };

    final userUpdates = <String, dynamic>{
      if (target != ShelfTarget.fiveStar)
        'fiveStarKeys': FieldValue.arrayRemove([key, tmdbId, tmdbKey]),
      if (target != ShelfTarget.disliked)
        'dislikedKeys': FieldValue.arrayRemove([key, tmdbId, tmdbKey]),
      if (target != ShelfTarget.favorites)
        'favoritesKeys': FieldValue.arrayRemove([key, tmdbId, tmdbKey]),
      if (target != ShelfTarget.watchlist)
        'watchlistKeys': FieldValue.arrayRemove([key, tmdbId, tmdbKey]),
      targetField: FieldValue.arrayUnion([key]),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    DiaryEntry? diaryEntry;
    if (target != ShelfTarget.watchlist && !wasWatched) {
      diaryEntry = DiaryEntry.fromMovie(
        movieData: movieData,
        posterUrl: posterUrl,
        source: target.name,
        movieKey: key,
        tmdbId: tmdbId,
      );
      final recentDiary = _recentDiaryWith(uid, diaryEntry);
      userUpdates['watchedKeys'] = FieldValue.arrayUnion([key, tmdbKey]);
      userUpdates['recentWatchedIds'] = recentDiary
          .map((item) => item['movieKey']?.toString() ?? '')
          .where((movieKey) => movieKey.isNotEmpty)
          .toList();
      userUpdates['recentDiaryEntries'] = recentDiary;
      userUpdates['diaryUpdatedAt'] = FieldValue.serverTimestamp();
    }
    batch.set(userRef, userUpdates, SetOptions(merge: true));

    if (target == ShelfTarget.fiveStar ||
        target == ShelfTarget.disliked ||
        wasFiveStar ||
        wasDisliked) {
      final tasteRef = _fs.collection('userTasteProfiles').doc(uid);
      final tasteUpdates = <String, dynamic>{
        if (target != ShelfTarget.fiveStar)
          'loved': FieldValue.arrayRemove([key, tmdbId, tmdbKey]),
        if (target != ShelfTarget.disliked)
          'disliked': FieldValue.arrayRemove([key, tmdbId, tmdbKey]),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (target == ShelfTarget.fiveStar) {
        tasteUpdates['loved'] = FieldValue.arrayUnion([key]);
        if (posterUrl != null) tasteUpdates['posters.$key'] = posterUrl;
      } else if (target == ShelfTarget.disliked) {
        tasteUpdates['disliked'] = FieldValue.arrayUnion([key]);
        if (posterUrl != null) tasteUpdates['posters.$key'] = posterUrl;
      }
      batch.set(tasteRef, tasteUpdates, SetOptions(merge: true));
    }

    if (diaryEntry != null) {
      DiaryService.instance.addToBatch(batch, uid, diaryEntry);
    }

    await batch.commit();
    return null;
  }
}
