import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:fluttergirdi/models/diary_entry.dart';

import 'package:fluttergirdi/services/catalog_service.dart';
import 'package:fluttergirdi/services/diary_service.dart';

// --- HTTP client & helpers ---------------------------------------------------
const _kDefaultUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36';
const _kAcceptLang = 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7';

class _Http {
  static final http.Client client = http.Client();

  static Map<String, String> baseHeaders({String? referer}) => {
    'User-Agent': _kDefaultUa,
    'Accept-Language': _kAcceptLang,
    if (referer != null) 'Referer': referer,
  };

  /// GET with timeout & retry
  static Future<http.Response?> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 30),
    int retries = 2,
  }) async {
    http.Response? res;
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final h = <String, String>{};
        if (headers != null) h.addAll(headers);
        res = await client.get(uri, headers: h).timeout(timeout);
        if (res.statusCode == 200) return res;
        if (attempt == retries) return res;
      } on TimeoutException {
        if (attempt == retries) rethrow;
      } catch (_) {
        if (attempt == retries) rethrow;
      }
      await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
    }
    return res;
  }
}

class LetterboxdFilm {
  final String title;
  final String url;
  final String posterUrl;
  final String key;
  final int? year;

  LetterboxdFilm({
    required this.title,
    required this.url,
    required this.posterUrl,
    String? key,
    this.year,
  }) : key = key ?? LetterboxdFilm._deriveKey(url, title);

  Map<String, dynamic> toMap() => {
    'title': title,
    'url': url,
    'posterUrl': posterUrl,
    'key': key,
    if (year != null) 'year': year,
  };

  Map<String, dynamic> toJson() => toMap();

  static LetterboxdFilm fromMap(Map<String, dynamic> json) => LetterboxdFilm(
    title: json['title'] ?? '',
    url: json['url'] ?? '',
    // Eski cihaz cache'lerinde Letterboxd CDN URL'leri bulunabilir. Bu URL'ler
    // hotlink koruması nedeniyle yeniden kullanılmaz; TMDB fallback çözer.
    posterUrl: '',
    key: json['key'],
    year: int.tryParse('${json['year'] ?? ''}'),
  );

  static LetterboxdFilm fromJson(Map<String, dynamic> json) => fromMap(json);

  static List<String> keysOf(List<LetterboxdFilm> films) =>
      films.map((f) => f.key).where((k) => k.isNotEmpty).toList();

  static String filmKeyFromHref(String href) => _deriveKey(href, '');

  static String _deriveKey(String href, String titleFallback) {
    try {
      final u = Uri.parse(href);
      final parts = u.path.split('/').where((e) => e.isNotEmpty).toList();
      final idx = parts.indexOf('film');
      if (idx != -1 && idx + 1 < parts.length) {
        final slug = parts[idx + 1].toLowerCase();
        if (slug.isNotEmpty) return 'film:$slug';
      }
    } catch (_) {}
    final slug = titleFallback
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return slug.isNotEmpty ? 'film:$slug' : '';
  }
}

class LetterboxdSyncException implements Exception {
  final String code;
  final String message;

  const LetterboxdSyncException(this.code, this.message);

  @override
  String toString() => message;
}

enum LetterboxdSyncState { completed, inProgress }

class LetterboxdService {
  static final Map<String, Future<LetterboxdSyncState>> _activeClientSyncs = {};

  static String _cacheKeyFor(String username) =>
      'lb_cache_${username.toLowerCase()}';

  static const Map<String, String> _reqHeaders = {
    'User-Agent': _kDefaultUa,
    'Accept-Language': _kAcceptLang,
    'Referer': 'https://letterboxd.com/',
  };

  static Future<T> _retryFirestore<T>(Future<T> Function() op) async {
    int attempts = 0;
    while (true) {
      try {
        return await op();
      } catch (e) {
        if (attempts >= 4) rethrow;
        final err = e.toString().toLowerCase();
        if (err.contains('unavailable') ||
            err.contains('network') ||
            err.contains('offline')) {
          attempts++;
          await Future.delayed(Duration(milliseconds: 500 * attempts));
        } else {
          rethrow;
        }
      }
    }
  }

  static Future<List<LetterboxdFilm>> _parseFilmsFromElements(
    List<dom.Element> elements,
  ) async {
    final items = <LetterboxdFilm>[];
    final seenHref = <String>{};

    for (final li in elements) {
      final a = li.querySelector('a.frame') ?? li.querySelector('a');
      final img = li.querySelector('img.image') ?? li.querySelector('img');
      final rc = li.querySelector('div.react-component');
      final divPoster =
          li.querySelector('div.film-poster') ?? li.querySelector('div.poster');

      if (a == null && rc == null && img == null && divPoster == null) continue;

      String title =
          (divPoster?.attributes['data-film-name'] ??
                  a?.attributes['data-original-title'] ??
                  img?.attributes['alt'] ??
                  rc?.attributes['data-item-name'] ??
                  rc?.attributes['data-item-full-display-name'] ??
                  a?.querySelector('.frame-title')?.text ??
                  '')
              .replaceAll(RegExp(r'^Poster for '), '')
              .trim();

      if (title.isEmpty) continue;

      String href =
          divPoster?.attributes['data-film-link'] ??
          rc?.attributes['data-item-link'] ??
          rc?.attributes['data-target-link'] ??
          a?.attributes['href'] ??
          '';

      if (href.isEmpty) continue;
      if (href.startsWith('//')) href = 'https:$href';
      if (href.startsWith('/')) href = 'https://letterboxd.com$href';
      if (!seenHref.add(href)) continue;

      final rawYear =
          divPoster?.attributes['data-film-release-year'] ??
          divPoster?.attributes['data-release-year'] ??
          rc?.attributes['data-item-year'] ??
          li.attributes['data-film-release-year'];
      final year = int.tryParse(rawYear ?? '');

      items.add(
        LetterboxdFilm(title: title, url: href, posterUrl: '', year: year),
      );
    }
    return items;
  }

  static Future<List<LetterboxdFilm>> _fetchRated(
    String username,
    String rating, {
    required String cacheSuffix,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final tries = [
      Uri.parse('https://letterboxd.com/$username/films/rated/$rating/'),
      Uri.parse('https://letterboxd.com/$username/films/ratings/$rating/'),
    ];
    final items = <LetterboxdFilm>[];
    Uri? next;
    for (final candidate in tries) {
      final response = await _Http.get(candidate, headers: _reqHeaders);
      if (response != null && response.statusCode == 200) {
        next = candidate;
        break;
      }
    }
    if (next == null) throw Exception('$rating★ sayfası alınamadı');

    final visited = <String>{};
    while (next != null &&
        visited.add(next.toString()) &&
        visited.length <= 500) {
      final response = await _Http.get(next, headers: _reqHeaders);
      if (response == null || response.statusCode != 200) {
        throw Exception('$rating★ sayfası alınamadı');
      }
      final doc = html.parse(response.body);
      final candidates = <dom.Element>[
        ...doc.querySelectorAll('div.poster-grid ul.grid li.griditem'),
        ...doc.querySelectorAll(
          'section.col-main .poster-grid ul.grid li.griditem',
        ),
        ...doc.querySelectorAll('section.col-main ul.grid li.griditem'),
        ...doc.querySelectorAll('ul.grid.-p70 li.griditem'),
        ...doc.querySelectorAll('ul.grid li.griditem'),
        ...doc.querySelectorAll('li.poster-container'),
      ];
      items.addAll(await _parseFilmsFromElements(candidates));
      next = _nextProfilePage(doc, username);
    }

    if (items.isEmpty) {
      final cached = prefs.getString('${_cacheKeyFor(username)}$cacheSuffix');
      if (cached != null) {
        final list = (jsonDecode(cached) as List)
            .map((e) => LetterboxdFilm.fromJson(e))
            .toList();
        if (list.isNotEmpty) return list;
      }
      return [];
    }

    final uniq = <String, LetterboxdFilm>{};
    for (final f in items) uniq[f.url] = f;
    final result = uniq.values.toList();

    try {
      await prefs.setString(
        '${_cacheKeyFor(username)}$cacheSuffix',
        jsonEncode(result.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}

    return result;
  }

  static Uri? _nextProfilePage(dom.Document document, String username) {
    final href = document
        .querySelector('.paginate-nextprev a.next, a.next')
        ?.attributes['href']
        ?.trim();
    if (href == null || href.isEmpty) return null;
    final uri = Uri.parse('https://letterboxd.com/').resolve(href);
    final prefix = '/${username.toLowerCase()}/';
    if (uri.scheme != 'https' ||
        uri.host != 'letterboxd.com' ||
        !uri.path.toLowerCase().startsWith(prefix)) {
      return null;
    }
    return uri;
  }

  static Future<List<LetterboxdFilm>> fetchHalfStar(String username) {
    return _fetchRated(username, '.5', cacheSuffix: '_rated05');
  }

  static Future<List<LetterboxdFilm>> fetchOneStar(String username) {
    return _fetchRated(username, '1', cacheSuffix: '_rated1');
  }

  static Future<List<LetterboxdFilm>> fetchDisliked(String username) async {
    // Bu iki sayfa tek bir "beğenmediklerim" kategorisini oluşturuyor. Birisi
    // alınamazsa kısmi sonucu başarılı saymak eski Letterboxd verisini silebilir.
    final results = await Future.wait([
      fetchHalfStar(username),
      fetchOneStar(username),
    ]);
    final half = results[0];
    final one = results[1];
    final map = <String, LetterboxdFilm>{};
    for (final f in [...half, ...one]) map[f.url] = f;
    return map.values.toList();
  }

  static Future<List<LetterboxdFilm>> fetchFiveStar(String username) async {
    return _fetchRated(username, '5', cacheSuffix: '_rated5');
  }

  static Future<List<LetterboxdFilm>> fetchLovedFilms(String username) async {
    final results = await Future.wait([
      _fetchRated(username, '4', cacheSuffix: '_rated4'),
      _fetchRated(username, '4.5', cacheSuffix: '_rated45'),
      fetchFiveStar(username),
    ]);
    final unique = <String, LetterboxdFilm>{};
    for (final films in results) {
      for (final film in films) {
        unique[film.url] = film;
      }
    }
    return unique.values.toList();
  }

  static Future<List<LetterboxdFilm>> fetchFavorites(String username) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final url = Uri.parse('https://letterboxd.com/$username/');
      final res = await _Http.get(
        url,
        headers: _Http.baseHeaders(referer: 'https://letterboxd.com/'),
      );
      if (res == null || res.statusCode != 200)
        throw Exception('HTTP ${res?.statusCode}');

      final doc = html.parse(res.body);

      final section = doc.querySelector('#favourites');
      if (section != null) {
        final lis = section.querySelectorAll('li');
        final films = await _parseFilmsFromElements(lis);

        if (films.isNotEmpty) {
          final deduped = <LetterboxdFilm>[];
          final seen = <String>{};
          for (final f in films) {
            if (seen.add(f.url)) deduped.add(f);
          }
          final result = deduped.take(4).toList();

          await prefs.setString(
            _cacheKeyFor(username),
            jsonEncode(result.map((e) => e.toJson()).toList()),
          );
          return result;
        }
      }
      return [];
    } catch (e) {
      final cached = prefs.getString(_cacheKeyFor(username));
      if (cached != null) {
        return (jsonDecode(cached) as List)
            .map((e) => LetterboxdFilm.fromJson(e))
            .toList();
      }
      if (e.toString().contains('HTTP 404')) {
        throw LetterboxdSyncException(
          'profile-not-found',
          'Letterboxd kullanıcısı bulunamadı: $username',
        );
      }
      rethrow;
    }
  }

  static Future<List<LetterboxdFilm>> fetchWatchlist(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final List<LetterboxdFilm> all = [];
    Uri? next = Uri.parse('https://letterboxd.com/$username/watchlist/');
    final visited = <String>{};

    while (next != null &&
        visited.add(next.toString()) &&
        visited.length <= 500) {
      final res = await _Http.get(next, headers: _reqHeaders);
      if (res == null || res.statusCode != 200) {
        if (all.isEmpty) {
          final cached = prefs.getString('${_cacheKeyFor(username)}_watchlist');
          if (cached != null) {
            return (jsonDecode(cached) as List)
                .map((e) => LetterboxdFilm.fromJson(e))
                .toList();
          }
          throw LetterboxdSyncException(
            'watchlist-unavailable',
            'Letterboxd izleme listesi şu anda alınamıyor.',
          );
        }
        break;
      }

      final doc = html.parse(res.body);

      final candidates = <dom.Element>[
        ...doc.querySelectorAll('ul.poster-list li.poster-container'),
        ...doc.querySelectorAll('ul.grid li.griditem'),
        ...doc.querySelectorAll('div.poster-grid li.griditem'),
      ];

      final items = await _parseFilmsFromElements(candidates);

      if (items.isEmpty) break;
      all.addAll(items);
      next = _nextProfilePage(doc, username);
    }

    if (all.isEmpty) {
      final cached = prefs.getString('${_cacheKeyFor(username)}_watchlist');
      if (cached != null)
        return (jsonDecode(cached) as List)
            .map((e) => LetterboxdFilm.fromJson(e))
            .toList();
    } else {
      prefs.setString(
        '${_cacheKeyFor(username)}_watchlist',
        jsonEncode(all.map((e) => e.toJson()).toList()),
      );
    }
    final unique = <String, LetterboxdFilm>{};
    for (final film in all) {
      unique[film.url] = film;
    }
    return unique.values.toList();
  }

  static Future<Map<String, Map<String, dynamic>>> _upsertCatalog(
    List<LetterboxdFilm> films, {
    Set<String> knownExistingKeys = const <String>{},
  }) {
    return CatalogService().importLetterboxdFilms(
      films
          .where((film) => film.key.isNotEmpty && film.title.isNotEmpty)
          .map(
            (film) => {
              'key': film.key,
              'title': film.title,
              if (film.year != null) 'year': film.year,
              if (knownExistingKeys.contains(film.key)) 'preferExisting': true,
            },
          )
          .toList(),
    );
  }

  static String _diaryEventIdForLetterboxdKey(String key) {
    final encoded = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
    return 'letterboxd_$encoded';
  }

  // =========================================================================
  // KRİTİK GÜNCELLEME: Delta Sync Fonksiyonu
  // MANUEL FİLMLERİ SİLMEZ, SADECE YENİLERİ EKLER VE KORUR.
  // =========================================================================
  static Future<void> fullSyncOnboarding({
    required String uid,
    required String lbUsername,
    String source = 'manual',
  }) async {
    await requestFullSync(uid: uid, lbUsername: lbUsername, source: source);
  }

  static Future<LetterboxdSyncState> requestFullSync({
    required String uid,
    required String lbUsername,
    String source = 'manual',
  }) {
    final normalizedUsername = lbUsername.trim();
    final syncKey = '$uid:${normalizedUsername.toLowerCase()}';
    final running = _activeClientSyncs[syncKey];
    if (running != null) return running;

    final sync = _requestClientSync(
      uid: uid,
      lbUsername: normalizedUsername,
      source: source,
    );
    _activeClientSyncs[syncKey] = sync;
    return sync.whenComplete(() {
      if (identical(_activeClientSyncs[syncKey], sync)) {
        _activeClientSyncs.remove(syncKey);
      }
    });
  }

  static Future<LetterboxdSyncState> _requestClientSync({
    required String uid,
    required String lbUsername,
    required String source,
  }) async {
    if (lbUsername.isEmpty) {
      throw const LetterboxdSyncException(
        'invalid-username',
        'Geçerli bir Letterboxd kullanıcı adı gir.',
      );
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid) {
      throw const LetterboxdSyncException(
        'unauthenticated',
        'Oturumun sona ermiş. Lütfen yeniden giriş yap.',
      );
    }
    await _runTrackedSync(uid: uid, lbUsername: lbUsername, source: source);
    return LetterboxdSyncState.completed;
  }

  // Sunucu tabanlı kazıma yolu geri dönüş/inceleme amacıyla tutuluyor.
  // Letterboxd, Cloud Run isteklerine challenge HTML döndürdüğü için aktif
  // senkronizasyon artık kullanıcının cihaz bağlantısından yapılıyor.
  // ignore: unused_element
  static Future<LetterboxdSyncState> _requestServerSync({
    required String uid,
    required String lbUsername,
    required String source,
  }) async {
    if (lbUsername.isEmpty) {
      throw const LetterboxdSyncException(
        'invalid-username',
        'Geçerli bir Letterboxd kullanıcı adı gir.',
      );
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid) {
      throw const LetterboxdSyncException(
        'unauthenticated',
        'Oturumun sona ermiş. Lütfen yeniden giriş yap.',
      );
    }

    final callable = FirebaseFunctions.instance.httpsCallable(
      'requestLetterboxdSync',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    );
    HttpsCallableResult<dynamic> response;
    try {
      final tokenRefresh = user.getIdToken(true);
      final favoritesFuture = fetchFavorites(lbUsername).timeout(
        const Duration(seconds: 8),
        onTimeout: () => const <LetterboxdFilm>[],
      );
      await tokenRefresh;
      List<LetterboxdFilm> favorites;
      try {
        favorites = await favoritesFuture;
      } catch (_) {
        favorites = const <LetterboxdFilm>[];
      }
      response = await callable.call({
        'username': lbUsername,
        'source': source,
        if (favorites.isNotEmpty)
          'favorites': favorites.take(4).map((film) => film.toMap()).toList(),
      });
    } catch (error) {
      if (kDebugMode && error is FirebaseFunctionsException) {
        debugPrint(
          'Letterboxd callable reddedildi: code=${error.code}, '
          'message=${error.message}, details=${error.details}',
        );
      }
      throw _normalizeSyncError(error);
    }

    final raw = response.data;
    final data = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
    final initialStatus = (data['status'] ?? '').toString();
    if (initialStatus == 'current' || initialStatus == 'not-needed') {
      return LetterboxdSyncState.completed;
    }
    final generation = (data['generation'] as num?)?.toInt();
    if (generation == null || generation <= 0) {
      throw const LetterboxdSyncException(
        'invalid-response',
        'Letterboxd senkronizasyonu başlatılamadı. Lütfen tekrar dene.',
      );
    }

    final integration = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('integrations')
        .doc('letterboxd');
    try {
      final snapshot = await integration
          .snapshots()
          .firstWhere((snapshot) {
            final value = snapshot.data();
            if (value == null ||
                (value['generation'] as num?)?.toInt() != generation) {
              return false;
            }
            final status = (value['status'] ?? '').toString();
            return status == 'success' || status == 'failed';
          })
          // Tam katalog aktarımı büyük hesaplarda arka planda sürebilir. Profil
          // düzenleme ekranını dakikalarca kilitlemeden hızlı sonucu bekle;
          // devam ediyorsa kullanıcıya doğru biçimde "arka planda" durumunu dön.
          .timeout(const Duration(seconds: 20));
      final value = snapshot.data() ?? const <String, dynamic>{};
      if (value['status'] == 'success') {
        return LetterboxdSyncState.completed;
      }
      final error = value['error'];
      final errorMap = error is Map
          ? Map<String, dynamic>.from(error)
          : const <String, dynamic>{};
      throw LetterboxdSyncException(
        (errorMap['code'] ?? 'sync-failed').toString(),
        (errorMap['message'] ??
                'Letterboxd verileri güncellenemedi. Lütfen tekrar dene.')
            .toString(),
      );
    } on TimeoutException {
      return LetterboxdSyncState.inProgress;
    } catch (error) {
      if (error is LetterboxdSyncException) rethrow;
      throw _normalizeSyncError(error);
    }
  }

  static Future<void> disconnect({required String uid}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid) {
      throw const LetterboxdSyncException(
        'unauthenticated',
        'Oturumun sona ermiş. Lütfen yeniden giriş yap.',
      );
    }
    try {
      await user.getIdToken(true);
      await FirebaseFunctions.instance
          .httpsCallable(
            'disconnectLetterboxd',
            options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
          )
          .call();
    } catch (error) {
      throw _normalizeSyncError(error);
    }
  }

  static Future<void> _runTrackedSync({
    required String uid,
    required String lbUsername,
    required String source,
  }) async {
    final statusRef = FirebaseFirestore.instance
        .collection('userTasteProfiles')
        .doc(uid);
    await _writeSyncStatus(statusRef, {
      'status': 'running',
      'username': lbUsername,
      'source': source,
      'startedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    try {
      await _performFullSync(uid: uid, lbUsername: lbUsername);
      await _writeSyncStatus(statusRef, {
        'status': 'success',
        'username': lbUsername,
        'source': source,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error, stackTrace) {
      final failure = _normalizeSyncError(error);
      await _writeSyncStatus(statusRef, {
        'status': 'failed',
        'username': lbUsername,
        'source': source,
        'errorCode': failure.code,
        'message': failure.message,
        'failedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      Error.throwWithStackTrace(failure, stackTrace);
    }
  }

  static Future<void> _writeSyncStatus(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> status,
  ) async {
    try {
      await ref.set({'letterboxdSync': status}, SetOptions(merge: true));
    } catch (error) {
      debugPrint('Letterboxd senkronizasyon durumu yazılamadı: $error');
    }
  }

  static LetterboxdSyncException _normalizeSyncError(Object error) {
    if (error is LetterboxdSyncException) return error;
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'unauthenticated':
          return FirebaseAuth.instance.currentUser == null
              ? const LetterboxdSyncException(
                  'unauthenticated',
                  'Oturumun sona ermiş. Lütfen yeniden giriş yap.',
                )
              : const LetterboxdSyncException(
                  'app-check-failed',
                  'Uygulama güvenlik doğrulaması tamamlanamadı. Uygulamayı yeniden açıp tekrar dene.',
                );
        case 'unavailable':
        case 'deadline-exceeded':
          return const LetterboxdSyncException(
            'unavailable',
            'Senkronizasyon servisine şu anda ulaşılamıyor. Tekrar dene.',
          );
        case 'resource-exhausted':
          return LetterboxdSyncException(
            'rate-limited',
            error.message ??
                'Çok fazla senkronizasyon isteği gönderildi. Biraz sonra tekrar dene.',
          );
        case 'invalid-argument':
        case 'failed-precondition':
        case 'permission-denied':
          return LetterboxdSyncException(
            error.code,
            error.message ??
                'Letterboxd senkronizasyonu başlatılamadı. Lütfen tekrar dene.',
          );
        default:
          return LetterboxdSyncException(
            error.code,
            error.message ??
                'Letterboxd verileri güncellenemedi. Lütfen tekrar dene.',
          );
      }
    }
    final text = error.toString().toLowerCase();
    if (text.contains('404') || text.contains('kullanıcısı bulunamadı')) {
      return const LetterboxdSyncException(
        'profile-not-found',
        'Letterboxd kullanıcısı bulunamadı. Kullanıcı adını kontrol et.',
      );
    }
    if (text.contains('timeout') ||
        text.contains('socket') ||
        text.contains('network')) {
      return const LetterboxdSyncException(
        'network',
        'Letterboxd bağlantısı kurulamadı. İnternetini kontrol edip tekrar dene.',
      );
    }
    return const LetterboxdSyncException(
      'unknown',
      'Letterboxd verileri güncellenemedi. Lütfen tekrar dene.',
    );
  }

  static Future<void> _performFullSync({
    required String uid,
    required String lbUsername,
  }) async {
    // Tüm bölümler yazma başlamadan önce alınır. Herhangi biri başarısızsa
    // mevcut Letterboxd verileri korunur ve senkronizasyon tekrar denenebilir.
    final favs = await fetchFavorites(lbUsername);

    final results = await Future.wait([
      fetchLovedFilms(lbUsername),
      fetchDisliked(lbUsername),
      fetchWatchlist(lbUsername),
    ]);

    final fiveStar = results[0];
    final disliked = results[1];
    final watchlist = results[2];

    final db = FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(uid);
    final tasteRef = db.collection('userTasteProfiles').doc(uid);

    // 2. Kullanıcının MEVCUT (manuel) verilerini Firestore'dan Oku
    final userSnap = await userRef.get();
    final Map<String, dynamic> currentData = userSnap.data() ?? {};

    final existingFavKeys = List<String>.from(
      currentData['favoritesKeys'] ?? [],
    );
    final existingWlKeys = List<String>.from(
      currentData['watchlistKeys'] ?? [],
    );
    final existingFiveKeys = List<String>.from(
      currentData['fiveStarKeys'] ?? [],
    );
    final existingDisKeys = List<String>.from(
      currentData['dislikedKeys'] ?? [],
    );
    final existingWatchedKeys = List<String>.from(
      currentData['watchedKeys'] ?? [],
    );

    final Set<String> allExistingKeys = {
      ...existingFavKeys,
      ...existingWlKeys,
      ...existingFiveKeys,
      ...existingDisKeys,
    };

    final newFavKeys = LetterboxdFilm.keysOf(favs);
    final newWlKeys = LetterboxdFilm.keysOf(watchlist);
    final newFiveKeys = LetterboxdFilm.keysOf(fiveStar);
    final newDisKeys = LetterboxdFilm.keysOf(disliked);
    final letterboxdWatchedKeys = {
      ...newFavKeys,
      ...newFiveKeys,
      ...newDisKeys,
    }.toList();
    final existingWatchedSet = existingWatchedKeys.toSet();
    final newlyWatchedKeys = letterboxdWatchedKeys
        .where((key) => !existingWatchedSet.contains(key))
        .toList();
    final newlyWatchedSet = newlyWatchedKeys.toSet();

    // 3. Yalnız yeni katalog filmlerini ve ilk kez Diary'ye geçirilecek eski
    // Letterboxd filmlerini çöz. Dönen özet Diary belgesine gömüldüğü için
    // ekran daha sonra catalog_films okumaz.
    final allScrapedFilms = [...favs, ...fiveStar, ...disliked, ...watchlist];
    final List<LetterboxdFilm> catalogImportFilms = [];
    final Set<String> processedKeys = {};

    for (final f in allScrapedFilms) {
      if (f.key.isNotEmpty &&
          (!allExistingKeys.contains(f.key) ||
              newlyWatchedSet.contains(f.key)) &&
          processedKeys.add(f.key)) {
        catalogImportFilms.add(f);
      }
    }

    final resolvedCatalogByKey = <String, Map<String, dynamic>>{};
    for (int i = 0; i < catalogImportFilms.length; i += 50) {
      final end = (i + 50 < catalogImportFilms.length)
          ? i + 50
          : catalogImportFilms.length;
      resolvedCatalogByKey.addAll(
        await _upsertCatalog(
          catalogImportFilms.sublist(i, end),
          knownExistingKeys: allExistingKeys,
        ),
      );
    }

    // 4. Listeleri Harmanlama (Merge) - Manuel olanları koru
    List<String> mergeKeyList({
      required List<String> existingKeys,
      required List<String> newLbKeys,
      required Map<String, String> sources,
    }) {
      // sources map'inde 'manual' olarak işaretlenmemiş veya kaynak bilgisi olmayan (eski veri) her şeyi manuel kabul et (esnek koruma)
      final manualKeys = existingKeys
          .where((k) => sources[k] == 'manual' || !sources.containsKey(k))
          .toList();

      for (final k in existingKeys) {
        if (sources[k] == 'letterboxd') {
          sources.remove(k);
        }
      }

      for (final k in newLbKeys) {
        if (sources[k] != 'manual') {
          sources[k] = 'letterboxd';
        }
      }
      return {...manualKeys, ...newLbKeys}.toList();
    }

    final newFavLite = favs
        .take(4)
        .map(
          (f) => {
            'title': f.title,
            'url': f.url,
            'posterUrl': f.posterUrl,
            'key': f.key,
            'source': 'letterboxd',
          },
        )
        .toList();

    final newWLite = watchlist
        .take(30)
        .map(
          (f) => {
            'title': f.title,
            'url': f.url,
            'posterUrl': f.posterUrl,
            'key': f.key,
            'source': 'letterboxd',
          },
        )
        .toList();

    List<Map<String, dynamic>> mergeLiteList({
      required List<Map<String, dynamic>> existingLite,
      required List<Map<String, dynamic>> newLbLite,
    }) {
      // Manuel işaretlileri veya source etiketi olmayan (eski kayıtları) koru
      final manualLite = existingLite
          .where(
            (item) => item['source'] == 'manual' || !item.containsKey('source'),
          )
          .map((item) {
            final sanitized = Map<String, dynamic>.from(item);
            for (final field in ['poster', 'posterUrl', 'image']) {
              if ((sanitized[field] ?? '').toString().contains('ltrbxd.com')) {
                sanitized[field] = '';
              }
            }
            return sanitized;
          })
          .toList();

      final Map<String, Map<String, dynamic>> uniqMap = {};
      for (final item in manualLite) {
        final k = (item['key'] ?? '').toString();
        if (k.isNotEmpty) uniqMap[k] = item;
      }
      for (final item in newLbLite) {
        final k = (item['key'] ?? '').toString();
        if (k.isNotEmpty && !uniqMap.containsKey(k)) {
          uniqMap[k] = item;
        }
      }
      return uniqMap.values.toList();
    }

    final watchedFilmsByKey = <String, LetterboxdFilm>{};
    for (final film in [...favs, ...fiveStar, ...disliked]) {
      if (film.key.isNotEmpty)
        watchedFilmsByKey.putIfAbsent(film.key, () => film);
    }
    final syncTime = DateTime.now();
    final newDiaryEntries = <DiaryEntry>[];
    for (var i = 0; i < newlyWatchedKeys.length; i++) {
      final key = newlyWatchedKeys[i];
      final film = watchedFilmsByKey[key];
      if (film == null) continue;
      final resolvedMovie = resolvedCatalogByKey[key];
      newDiaryEntries.add(
        DiaryEntry.fromMovie(
          movieData: {
            ...film.toMap(),
            if (resolvedMovie != null) ...resolvedMovie,
          },
          posterUrl: resolvedMovie?['posterUrl']?.toString() ?? film.posterUrl,
          source: 'letterboxd_sync',
          watchedAt: syncTime.add(Duration(microseconds: i)),
          movieKey: key,
          eventId: _diaryEventIdForLetterboxdKey(key),
        ),
      );
    }

    // Çok büyük ilk senkronlarda Diary olaylarını önce kararlı belge
    // kimlikleriyle yaz. Son kullanıcı özeti en son commit edilir; uygulama
    // yarıda kesilirse sonraki deneme aynı belgeleri günceller, kopya üretmez
    // ve watchedKeys erken ilerleyip olayların kalıcı olarak atlanmasına yol
    // açmaz.
    const maxInlineDiaryWrites = 450;
    final shouldStageDiaryWrites =
        newDiaryEntries.length > maxInlineDiaryWrites;
    if (shouldStageDiaryWrites) {
      for (var i = 0; i < newDiaryEntries.length; i += 450) {
        final end = (i + 450).clamp(0, newDiaryEntries.length);
        final chunk = newDiaryEntries.sublist(i, end);
        await _retryFirestore(() async {
          final diaryBatch = db.batch();
          for (final entry in chunk) {
            DiaryService.instance.addToBatch(diaryBatch, uid, entry);
          }
          await diaryBatch.commit();
        });
      }
    }

    // 5. Final raf/özet yazımından hemen önce güncel kullanıcı ve taste
    // belgelerini transaction içinde yeniden oku. Letterboxd ağ/katalog
    // işlemleri sürerken başka cihazda yapılan manuel değişiklikler böylece
    // eski snapshot tarafından ezilmez.
    await _retryFirestore(() async {
      await db.runTransaction<void>((transaction) async {
        final latestUserSnap = await transaction.get(userRef);
        final latestTasteSnap = await transaction.get(tasteRef);
        final latestUserData = latestUserSnap.data() ?? <String, dynamic>{};
        final latestTasteData = latestTasteSnap.data() ?? <String, dynamic>{};

        final filmSources = Map<String, String>.from(
          latestUserData['filmSources'] ?? {},
        );
        final finalFavKeys = mergeKeyList(
          existingKeys: List<String>.from(
            latestUserData['favoritesKeys'] ?? [],
          ),
          newLbKeys: newFavKeys,
          sources: filmSources,
        );
        final finalWlKeys = mergeKeyList(
          existingKeys: List<String>.from(
            latestUserData['watchlistKeys'] ?? [],
          ),
          newLbKeys: newWlKeys,
          sources: filmSources,
        );
        final finalFiveKeys = mergeKeyList(
          existingKeys: List<String>.from(latestUserData['fiveStarKeys'] ?? []),
          newLbKeys: newFiveKeys,
          sources: filmSources,
        );
        final finalDisKeys = mergeKeyList(
          existingKeys: List<String>.from(latestUserData['dislikedKeys'] ?? []),
          newLbKeys: newDisKeys,
          sources: filmSources,
        );
        final finalFavLite = mergeLiteList(
          existingLite: List<Map<String, dynamic>>.from(
            latestUserData['favorites'] ?? [],
          ),
          newLbLite: newFavLite,
        );
        final finalWlite = mergeLiteList(
          existingLite: List<Map<String, dynamic>>.from(
            latestUserData['watchlist'] ?? [],
          ),
          newLbLite: newWLite,
        );

        final dynamic rawPosters = latestTasteData['posters'];
        final existingPosters = rawPosters is Map
            ? Map<String, String>.from(rawPosters)
            : <String, String>{};
        existingPosters.removeWhere((_, url) => url.contains('ltrbxd.com'));
        final postersMap = <String, String>{}..addAll(existingPosters);
        for (final film in [...fiveStar, ...disliked]) {
          if (film.key.isNotEmpty && film.posterUrl.isNotEmpty) {
            postersMap[film.key] = film.posterUrl;
          }
        }

        final latestWatchedKeys = List<String>.from(
          latestUserData['watchedKeys'] ?? [],
        ).toSet();
        final entriesToCommit = shouldStageDiaryWrites
            ? newDiaryEntries
            : newDiaryEntries.where((entry) {
                final tmdbKey = entry.tmdbId?.toString();
                return !latestWatchedKeys.contains(entry.movieKey) &&
                    (tmdbKey == null ||
                        (!latestWatchedKeys.contains(tmdbKey) &&
                            !latestWatchedKeys.contains('tmdb:$tmdbKey')));
              }).toList();

        Object? recentDiary = latestUserData['recentDiaryEntries'];
        for (final entry in entriesToCommit) {
          recentDiary = DiaryService.instance.mergeRecent(recentDiary, entry);
        }
        final recentDiaryEntries = recentDiary is List
            ? List<Map<String, dynamic>>.from(recentDiary)
            : <Map<String, dynamic>>[];
        final recentIds = recentDiaryEntries
            .map((item) => item['movieKey']?.toString() ?? '')
            .where((key) => key.isNotEmpty)
            .toList();

        transaction.set(userRef, {
          'letterboxdUsername': lbUsername,
          'letterboxdUsername_lc': lbUsername.toLowerCase(),
          'lbUsername': lbUsername,
          'pendingLetterboxdUsername': FieldValue.delete(),
          'filmSources': filmSources,
          'favoritesKeys': finalFavKeys,
          'favorites': finalFavLite,
          'watchlistKeys': finalWlKeys,
          'watchlist': finalWlite,
          'watchlistUpdatedAt': FieldValue.serverTimestamp(),
          'fiveStarKeys': finalFiveKeys,
          'dislikedKeys': finalDisKeys,
          'watchedKeys': FieldValue.arrayUnion(letterboxdWatchedKeys),
          if (entriesToCommit.isNotEmpty) ...{
            'recentWatchedIds': recentIds,
            'recentWatchedUpdatedAt': FieldValue.serverTimestamp(),
            'recentDiaryEntries': recentDiaryEntries,
            'diaryUpdatedAt': FieldValue.serverTimestamp(),
          },
          'updatedAt': FieldValue.serverTimestamp(),
          'lastSyncedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.set(tasteRef, {
          'letterboxdUsername': lbUsername,
          'loved': finalFiveKeys,
          'disliked': finalDisKeys,
          'posters': postersMap,
          'computedAtMs': DateTime.now().millisecondsSinceEpoch,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (!shouldStageDiaryWrites) {
          for (final entry in entriesToCommit) {
            DiaryService.instance.addToTransaction(transaction, uid, entry);
          }
        }
      });
    });
  }
}
