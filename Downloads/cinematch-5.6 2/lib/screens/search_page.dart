import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/news_list_page.dart';
import 'package:fluttergirdi/utils/layout_metrics.dart';
import 'package:fluttergirdi/widgets/discovery_lists_widget.dart';
import 'package:fluttergirdi/widgets/people_recommendations_widget.dart';
import 'package:fluttergirdi/widgets/recommendation_card.dart';
import 'package:fluttergirdi/widgets/ui_polish.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'actors_screen.dart';
import 'director_screen.dart';
import 'movie_detail_screen.dart';
import 'public_profile_screen.dart';

enum _SearchKind { all, movie, actor, director, user }

extension on _SearchKind {
  String get label => switch (this) {
    _SearchKind.all => 'Hepsi',
    _SearchKind.movie => 'Filmler',
    _SearchKind.actor => 'Oyuncular',
    _SearchKind.director => 'Yönetmenler',
    _SearchKind.user => 'Kullanıcılar',
  };

  String get resultLabel => switch (this) {
    _SearchKind.all => '',
    _SearchKind.movie => 'Film',
    _SearchKind.actor => 'Oyuncu',
    _SearchKind.director => 'Yönetmen',
    _SearchKind.user => 'Kullanıcı',
  };

  IconData get icon => switch (this) {
    _SearchKind.all => Icons.apps_rounded,
    _SearchKind.movie => Icons.movie_outlined,
    _SearchKind.actor => Icons.theater_comedy_outlined,
    _SearchKind.director => Icons.video_camera_front_outlined,
    _SearchKind.user => Icons.person_outline_rounded,
  };
}

class _UnifiedSearchItem {
  final _SearchKind kind;
  final String id;
  final String title;
  final String subtitle;
  final String? imageUrl;

  const _UnifiedSearchItem({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.imageUrl,
  });

  String get storageKey => '${kind.name}:$id';

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'id': id,
    'title': title,
    'subtitle': subtitle,
    if (imageUrl != null) 'imageUrl': imageUrl,
  };

  static _UnifiedSearchItem? fromJson(Map<String, dynamic> json) {
    final kindName = json['kind']?.toString();
    final id = json['id']?.toString() ?? '';
    final title = json['title']?.toString() ?? '';
    if (kindName == null || id.isEmpty || title.isEmpty) return null;

    _SearchKind? kind;
    for (final value in _SearchKind.values) {
      if (value.name == kindName && value != _SearchKind.all) {
        kind = value;
        break;
      }
    }
    if (kind == null) return null;

    final rawImageUrl = json['imageUrl']?.toString();
    return _UnifiedSearchItem(
      kind: kind,
      id: id,
      title: title,
      subtitle: json['subtitle']?.toString() ?? '',
      imageUrl: rawImageUrl == null || rawImageUrl.isEmpty ? null : rawImageUrl,
    );
  }
}

class _SearchRecentsCache {
  static const _recentSearchesKey = 'unified_search_recents_v1';
  static const _legacyMoviesKey = 'recent_movies_v1';
  static const _legacyUsersKey = 'recent_users_v1';

  static List<_UnifiedSearchItem>? _memoryItems;
  static Future<List<_UnifiedSearchItem>>? _pendingLoad;
  static int _writeRevision = 0;

  static List<_UnifiedSearchItem>? get snapshot {
    final items = _memoryItems;
    return items == null ? null : List<_UnifiedSearchItem>.from(items);
  }

  static Future<List<_UnifiedSearchItem>> load() async {
    final cachedItems = snapshot;
    if (cachedItems != null) return cachedItems;

    final pendingLoad = _pendingLoad;
    if (pendingLoad != null) {
      final loaded = await pendingLoad;
      return List<_UnifiedSearchItem>.from(_memoryItems ?? loaded);
    }

    final loadFuture = _loadFromDisk();
    _pendingLoad = loadFuture;
    try {
      final loaded = await loadFuture;
      _replaceMemory(loaded);
      return List<_UnifiedSearchItem>.from(_memoryItems!);
    } finally {
      if (identical(_pendingLoad, loadFuture)) _pendingLoad = null;
    }
  }

  static Future<List<_UnifiedSearchItem>> _loadFromDisk() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final storedRecents = preferences.getStringList(_recentSearchesKey);
      final loaded = <_UnifiedSearchItem>[];

      if (storedRecents != null) {
        for (final encoded in storedRecents) {
          try {
            final decoded = Map<String, dynamic>.from(
              jsonDecode(encoded) as Map,
            );
            final item = _UnifiedSearchItem.fromJson(decoded);
            if (item != null) loaded.add(item);
          } catch (_) {}
        }
      } else {
        loaded.addAll(_migrateLegacyMovies(preferences));
        loaded.addAll(_migrateLegacyUsers(preferences));
        await preferences.setStringList(
          _recentSearchesKey,
          loaded.take(20).map((item) => jsonEncode(item.toJson())).toList(),
        );
      }
      return loaded.take(20).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static List<_UnifiedSearchItem> _migrateLegacyMovies(
    SharedPreferences preferences,
  ) {
    final migrated = <_UnifiedSearchItem>[];
    for (final encoded in preferences.getStringList(_legacyMoviesKey) ?? []) {
      try {
        final movie = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
        final id = movie['id']?.toString() ?? '';
        final title = movie['title']?.toString() ?? '';
        if (id.isEmpty || title.isEmpty) continue;
        final posterPath = movie['poster_path']?.toString();
        migrated.add(
          _UnifiedSearchItem(
            kind: _SearchKind.movie,
            id: id,
            title: title,
            imageUrl: posterPath == null || posterPath.isEmpty
                ? null
                : 'https://image.tmdb.org/t/p/w200$posterPath',
          ),
        );
      } catch (_) {}
    }
    return migrated;
  }

  static List<_UnifiedSearchItem> _migrateLegacyUsers(
    SharedPreferences preferences,
  ) {
    final migrated = <_UnifiedSearchItem>[];
    for (final encoded in preferences.getStringList(_legacyUsersKey) ?? []) {
      try {
        final user = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
        final id = user['uid']?.toString() ?? '';
        final username = (user['username'] ?? user['displayName'] ?? '')
            .toString()
            .replaceAll('@', '')
            .trim();
        if (id.isEmpty || username.isEmpty) continue;
        final photoUrl = user['photoURL']?.toString();
        final letterboxd =
            user['letterboxdUsername']?.toString().replaceAll('@', '').trim() ??
            '';
        migrated.add(
          _UnifiedSearchItem(
            kind: _SearchKind.user,
            id: id,
            title: username,
            subtitle: letterboxd.isEmpty ? '' : 'Letterboxd: $letterboxd',
            imageUrl: photoUrl == null || photoUrl.isEmpty ? null : photoUrl,
          ),
        );
      } catch (_) {}
    }
    return migrated;
  }

  static void _replaceMemory(List<_UnifiedSearchItem> items) {
    _memoryItems = List<_UnifiedSearchItem>.unmodifiable(items.take(20));
  }

  static Future<void> persist(
    List<_UnifiedSearchItem> items, {
    bool clearLegacy = false,
  }) async {
    _replaceMemory(items);
    final revision = ++_writeRevision;
    final encodedItems = _memoryItems!
        .map((item) => jsonEncode(item.toJson()))
        .toList(growable: false);
    final preferences = await SharedPreferences.getInstance();
    if (revision != _writeRevision) return;
    await preferences.setStringList(_recentSearchesKey, encodedItems);
    if (clearLegacy && revision == _writeRevision) {
      await Future.wait([
        preferences.remove(_legacyMoviesKey),
        preferences.remove(_legacyUsersKey),
      ]);
    }
  }
}

class _MoviePageResult {
  final List<_UnifiedSearchItem> items;
  final int page;
  final int totalPages;

  const _MoviePageResult({
    required this.items,
    required this.page,
    required this.totalPages,
  });
}

class _PeopleSearchResult {
  final List<_UnifiedSearchItem> actors;
  final List<_UnifiedSearchItem> directors;

  const _PeopleSearchResult({required this.actors, required this.directors});
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.showDiscoverContentWhenEmpty = false});

  final bool showDiscoverContentWhenEmpty;

  static Future<void> preloadRecents() async {
    await _SearchRecentsCache.load();
  }

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const _primaryGreen = Color(0xFF2E7D32);
  static const _contentKinds = {
    _SearchKind.movie,
    _SearchKind.actor,
    _SearchKind.director,
    _SearchKind.user,
  };

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final Map<_SearchKind, List<_UnifiedSearchItem>> _results = {
    _SearchKind.movie: [],
    _SearchKind.actor: [],
    _SearchKind.director: [],
    _SearchKind.user: [],
  };
  final Set<_SearchKind> _loadedKinds = {};
  final Set<_SearchKind> _loadingKinds = {};
  final Set<_SearchKind> _failedKinds = {};

  List<_UnifiedSearchItem> _recentItems = [];
  final Set<_SearchKind> _selectedFilters = {};
  Timer? _debounce;
  String _activeQuery = '';
  int _requestId = 0;
  int _moviePage = 1;
  int _movieTotalPages = 1;
  bool _loadingMoreMovies = false;
  bool _recentsReady = false;

  @override
  void initState() {
    super.initState();
    final cachedRecents = _SearchRecentsCache.snapshot;
    if (cachedRecents != null) {
      _recentItems = cachedRecents;
      _recentsReady = true;
    } else {
      unawaited(_hydrateRecents());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _requestId++;
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 500),
      () => _commitSearch(value),
    );
  }

  void _submitSearch(String value) {
    _debounce?.cancel();
    _commitSearch(value);
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    _commitSearch('');
    _searchFocusNode.requestFocus();
  }

  void _commitSearch(String rawQuery) {
    final query = rawQuery.trim();
    if (query == _activeQuery) {
      if (mounted) setState(() {});
      _loadMissingKinds();
      return;
    }

    final nextRequestId = ++_requestId;
    setState(() {
      _activeQuery = query;
      _loadedKinds.clear();
      _loadingKinds.clear();
      _failedKinds.clear();
      for (final kind in _contentKinds) {
        _results[kind] = [];
      }
      _moviePage = 1;
      _movieTotalPages = 1;
      _loadingMoreMovies = false;
    });

    if (query.isNotEmpty) {
      _loadKinds(_desiredKinds, nextRequestId);
    }
  }

  Set<_SearchKind> get _desiredKinds =>
      _selectedFilters.isEmpty ? _contentKinds : _selectedFilters;

  void _toggleFilter(_SearchKind filter) {
    if (filter == _SearchKind.all) return;
    setState(() {
      if (!_selectedFilters.remove(filter)) {
        _selectedFilters.add(filter);
      }
    });
    _loadMissingKinds();
  }

  void _loadMissingKinds() {
    if (_activeQuery.isEmpty) return;
    final missingKinds = _desiredKinds
        .where(
          (kind) =>
              !_loadedKinds.contains(kind) && !_loadingKinds.contains(kind),
        )
        .toSet();
    if (missingKinds.isNotEmpty) {
      _loadKinds(missingKinds, _requestId);
    }
  }

  Future<void> _loadKinds(
    Set<_SearchKind> requestedKinds,
    int requestId,
  ) async {
    final shouldLoadMovies =
        requestedKinds.contains(_SearchKind.movie) &&
        !_loadedKinds.contains(_SearchKind.movie) &&
        !_loadingKinds.contains(_SearchKind.movie);
    final shouldLoadUsers =
        requestedKinds.contains(_SearchKind.user) &&
        !_loadedKinds.contains(_SearchKind.user) &&
        !_loadingKinds.contains(_SearchKind.user);
    final shouldLoadPeople =
        requestedKinds.any(
          (kind) => kind == _SearchKind.actor || kind == _SearchKind.director,
        ) &&
        !_loadedKinds.contains(_SearchKind.actor) &&
        !_loadedKinds.contains(_SearchKind.director) &&
        !_loadingKinds.contains(_SearchKind.actor) &&
        !_loadingKinds.contains(_SearchKind.director);

    if (!shouldLoadMovies && !shouldLoadUsers && !shouldLoadPeople) return;

    final kindsBeingLoaded = <_SearchKind>{
      if (shouldLoadMovies) _SearchKind.movie,
      if (shouldLoadUsers) _SearchKind.user,
      if (shouldLoadPeople) ...{_SearchKind.actor, _SearchKind.director},
    };
    setState(() {
      _loadingKinds.addAll(kindsBeingLoaded);
      _failedKinds.removeAll(kindsBeingLoaded);
    });

    _MoviePageResult? movies;
    List<_UnifiedSearchItem>? users;
    _PeopleSearchResult? people;
    var moviesFailed = false;
    var usersFailed = false;
    var peopleFailed = false;

    Future<void> loadMovies() async {
      try {
        movies = await _fetchMovies(_activeQuery, 1);
      } catch (_) {
        moviesFailed = true;
      }
    }

    Future<void> loadUsers() async {
      try {
        users = await _fetchUsers(_activeQuery);
      } catch (_) {
        usersFailed = true;
      }
    }

    Future<void> loadPeople() async {
      try {
        people = await _fetchPeople(_activeQuery);
      } catch (_) {
        peopleFailed = true;
      }
    }

    await Future.wait([
      if (shouldLoadMovies) loadMovies(),
      if (shouldLoadUsers) loadUsers(),
      if (shouldLoadPeople) loadPeople(),
    ]);

    if (!mounted || requestId != _requestId) return;
    setState(() {
      if (shouldLoadMovies) {
        if (moviesFailed || movies == null) {
          _failedKinds.add(_SearchKind.movie);
        } else {
          _results[_SearchKind.movie] = movies!.items;
          _moviePage = movies!.page;
          _movieTotalPages = movies!.totalPages;
          _loadedKinds.add(_SearchKind.movie);
        }
      }

      if (shouldLoadUsers) {
        if (usersFailed || users == null) {
          _failedKinds.add(_SearchKind.user);
        } else {
          _results[_SearchKind.user] = users!;
          _loadedKinds.add(_SearchKind.user);
        }
      }

      if (shouldLoadPeople) {
        if (peopleFailed || people == null) {
          _failedKinds.addAll({_SearchKind.actor, _SearchKind.director});
        } else {
          _results[_SearchKind.actor] = people!.actors;
          _results[_SearchKind.director] = people!.directors;
          _loadedKinds.addAll({_SearchKind.actor, _SearchKind.director});
        }
      }
      _loadingKinds.removeAll(kindsBeingLoaded);
    });
  }

  Future<_MoviePageResult> _fetchMovies(String query, int page) async {
    final response = await FirebaseFunctions.instance
        .httpsCallable('searchMovies')
        .call({'query': query, 'page': page});
    final data = Map<String, dynamic>.from(response.data as Map);
    final rawResults = data['results'] is List ? data['results'] as List : [];
    final items = rawResults
        .map((rawMovie) {
          final movie = Map<String, dynamic>.from(rawMovie as Map);
          final id = movie['id']?.toString() ?? '';
          final title = movie['title']?.toString().trim() ?? '';
          final posterPath = movie['poster_path']?.toString();
          final releaseDate = movie['release_date']?.toString() ?? '';
          final year = releaseDate.length >= 4
              ? releaseDate.substring(0, 4)
              : '';
          final originalTitle =
              movie['original_title']?.toString().trim() ?? '';
          final subtitleParts = <String>[
            if (year.isNotEmpty) year,
            if (originalTitle.isNotEmpty && originalTitle != title)
              originalTitle,
          ];
          return _UnifiedSearchItem(
            kind: _SearchKind.movie,
            id: id,
            title: title.isEmpty ? 'İsimsiz film' : title,
            subtitle: subtitleParts.join(' • '),
            imageUrl: posterPath == null || posterPath.isEmpty
                ? null
                : 'https://image.tmdb.org/t/p/w200$posterPath',
          );
        })
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);

    final currentPage = (data['page'] as num?)?.toInt() ?? page;
    final totalPages = (data['total_pages'] as num?)?.toInt() ?? currentPage;
    return _MoviePageResult(
      items: items,
      page: currentPage,
      totalPages: totalPages,
    );
  }

  Future<_PeopleSearchResult> _fetchPeople(String query) async {
    final response = await FirebaseFunctions.instance
        .httpsCallable('callTMDB')
        .call({
          'endpoint': '/3/search/person',
          'params': {
            'query': query,
            'language': 'tr-TR',
            'include_adult': false,
          },
        });
    final data = Map<String, dynamic>.from(response.data as Map);
    final rawResults = data['results'] is List ? data['results'] as List : [];
    final actors = <_UnifiedSearchItem>[];
    final directors = <_UnifiedSearchItem>[];

    for (final rawPerson in rawResults) {
      final person = Map<String, dynamic>.from(rawPerson as Map);
      final department = person['known_for_department']?.toString();
      if (department != 'Acting' && department != 'Directing') continue;

      final id = person['id']?.toString() ?? '';
      final name = person['name']?.toString().trim() ?? '';
      if (id.isEmpty || name.isEmpty) continue;
      final profilePath = person['profile_path']?.toString();
      final knownFor = person['known_for'] is List
          ? (person['known_for'] as List)
                .map((item) {
                  if (item is! Map) return '';
                  return (item['title'] ?? item['name'] ?? '')
                      .toString()
                      .trim();
                })
                .where((title) => title.isNotEmpty)
                .take(2)
                .join(', ')
          : '';
      final kind = department == 'Acting'
          ? _SearchKind.actor
          : _SearchKind.director;
      final result = _UnifiedSearchItem(
        kind: kind,
        id: id,
        title: name,
        subtitle: knownFor,
        imageUrl: profilePath == null || profilePath.isEmpty
            ? null
            : 'https://image.tmdb.org/t/p/w200$profilePath',
      );
      if (kind == _SearchKind.actor) {
        actors.add(result);
      } else {
        directors.add(result);
      }
    }

    return _PeopleSearchResult(actors: actors, directors: directors);
  }

  Future<List<_UnifiedSearchItem>> _fetchUsers(String query) async {
    final normalizedQuery = query.toLowerCase();
    final users = <String, Map<String, dynamic>>{};
    final db = FirebaseFirestore.instance;

    final usernameResult = await db
        .collection('users')
        .orderBy('username_lc')
        .startAt([normalizedQuery])
        .endAt(['$normalizedQuery\uf8ff'])
        .limit(12)
        .get();
    for (final document in usernameResult.docs) {
      users[document.id] = {'uid': document.id, ...document.data()};
    }

    if (users.length < 12) {
      final displayNameResult = await db
          .collection('users')
          .orderBy('displayName_lc')
          .startAt([normalizedQuery])
          .endAt(['$normalizedQuery\uf8ff'])
          .limit(12)
          .get();
      for (final document in displayNameResult.docs) {
        users.putIfAbsent(
          document.id,
          () => {'uid': document.id, ...document.data()},
        );
      }
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null) users.remove(currentUid);
    return users.values
        .take(20)
        .map((user) {
          final username =
              (user['username'] ?? user['displayName'] ?? 'isimsiz')
                  .toString()
                  .replaceAll('@', '')
                  .trim();
          final displayName = user['displayName']?.toString().trim() ?? '';
          final letterboxd =
              user['letterboxdUsername']
                  ?.toString()
                  .replaceAll('@', '')
                  .trim() ??
              '';
          final subtitleParts = <String>[
            if (displayName.isNotEmpty && displayName != username) displayName,
            if (letterboxd.isNotEmpty) 'Letterboxd: $letterboxd',
          ];
          final photoUrl = user['photoURL']?.toString();
          return _UnifiedSearchItem(
            kind: _SearchKind.user,
            id: user['uid'].toString(),
            title: username.isEmpty ? 'isimsiz' : username,
            subtitle: subtitleParts.join(' • '),
            imageUrl: photoUrl == null || photoUrl.isEmpty ? null : photoUrl,
          );
        })
        .toList(growable: false);
  }

  bool _handleResultScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical ||
        !_desiredKinds.contains(_SearchKind.movie) ||
        _activeQuery.isEmpty ||
        _loadingMoreMovies ||
        _moviePage >= _movieTotalPages) {
      return false;
    }
    if (notification.metrics.pixels >=
        notification.metrics.maxScrollExtent - 240) {
      unawaited(_loadMoreMovies());
    }
    return false;
  }

  String get _activeFilterLabel {
    if (_selectedFilters.isEmpty) return 'tüm kategoriler';
    return _selectedFilters.map((kind) => kind.label.toLowerCase()).join(', ');
  }

  IconData get _activeFilterIcon {
    if (_selectedFilters.length == 1) return _selectedFilters.first.icon;
    return Icons.manage_search_rounded;
  }

  List<_UnifiedSearchItem> get _visibleResults {
    final kinds = _desiredKinds;
    return [
      if (kinds.contains(_SearchKind.movie)) ...?_results[_SearchKind.movie],
      if (kinds.contains(_SearchKind.user)) ...?_results[_SearchKind.user],
      if (kinds.contains(_SearchKind.actor)) ...?_results[_SearchKind.actor],
      if (kinds.contains(_SearchKind.director))
        ...?_results[_SearchKind.director],
    ];
  }

  List<_UnifiedSearchItem> get _visibleRecents => _recentItems;

  bool get _isLoadingCurrent => _desiredKinds.any(_loadingKinds.contains);

  bool get _hasCurrentError => _desiredKinds.any(_failedKinds.contains);

  Future<void> _hydrateRecents() async {
    final loaded = await _SearchRecentsCache.load();
    if (!mounted) return;
    setState(() {
      _recentItems = loaded;
      _recentsReady = true;
    });
  }

  Future<void> _rememberResult(_UnifiedSearchItem item) async {
    final updated = List<_UnifiedSearchItem>.from(_recentItems)
      ..removeWhere((recent) => recent.storageKey == item.storageKey)
      ..insert(0, item);
    if (updated.length > 20) updated.removeRange(20, updated.length);
    if (mounted) setState(() => _recentItems = updated);

    await _SearchRecentsCache.persist(updated);
  }

  Future<void> _loadMoreMovies() async {
    if (_loadingMoreMovies || _moviePage >= _movieTotalPages) return;
    final query = _activeQuery;
    final requestId = _requestId;
    setState(() => _loadingMoreMovies = true);
    try {
      final nextPage = await _fetchMovies(query, _moviePage + 1);
      if (!mounted || requestId != _requestId || query != _activeQuery) return;
      final existingIds = _results[_SearchKind.movie]!
          .map((item) => item.id)
          .toSet();
      setState(() {
        _results[_SearchKind.movie]!.addAll(
          nextPage.items.where((item) => existingIds.add(item.id)),
        );
        _moviePage = nextPage.page;
        _movieTotalPages = nextPage.totalPages;
      });
    } catch (_) {
      if (mounted && requestId == _requestId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Daha fazla film yüklenemedi.')),
        );
      }
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loadingMoreMovies = false);
      }
    }
  }

  Future<void> _removeRecent(_UnifiedSearchItem item) async {
    final updated = List<_UnifiedSearchItem>.from(_recentItems)
      ..removeWhere((recent) => recent.storageKey == item.storageKey);
    setState(() => _recentItems = updated);
    await _SearchRecentsCache.persist(updated);
  }

  Future<void> _clearRecents() async {
    setState(() => _recentItems = []);
    await _SearchRecentsCache.persist(const [], clearLegacy: true);
  }

  void _openResult(_UnifiedSearchItem item) {
    unawaited(_rememberResult(item));
    final parsedId = int.tryParse(item.id);
    final Widget destination;
    switch (item.kind) {
      case _SearchKind.movie:
        if (parsedId == null) return;
        destination = MovieDetailScreen(
          tmdbId: parsedId,
          title: item.title,
          posterUrl: item.imageUrl,
        );
      case _SearchKind.actor:
        if (parsedId == null) return;
        destination = ActorScreen(actorId: parsedId, actorName: item.title);
      case _SearchKind.director:
        if (parsedId == null) return;
        destination = DirectorScreen(
          directorId: parsedId,
          directorName: item.title,
        );
      case _SearchKind.user:
        destination = PublicProfileScreen(uid: item.id);
      case _SearchKind.all:
        return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      resizeToAvoidBottomInset: true,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              backgroundColor: colors.surface,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              floating: false,
              pinned: false,
              snap: false,
              toolbarHeight: 66,
              automaticallyImplyLeading: false,
              titleSpacing: 0,
              title: _buildSearchField(context),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(38),
                child: _buildFilterBar(context),
              ),
            ),
          ];
        },
        body: ColoredBox(
          color: colors.surface,
          child: _activeQuery.isEmpty
              ? _recentsReady
                    ? _buildRecents(context)
                    : const Center(
                        child: CircularProgressIndicator(color: _primaryGreen),
                      )
              : _buildSearchResults(context),
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: SizedBox(
            height: 42,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                onSubmitted: _submitSearch,
                textInputAction: TextInputAction.search,
                textAlignVertical: TextAlignVertical.center,
                style: TextStyle(color: colors.onSurface, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Film, ki\u015fi veya kullan\u0131c\u0131 ara',
                  hintStyle: TextStyle(
                    color: colors.onSurfaceVariant.withValues(alpha: 0.82),
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: _primaryGreen,
                    size: 20,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Aramay\u0131 temizle',
                          onPressed: _clearSearch,
                          icon: Icon(
                            Icons.close_rounded,
                            color: colors.onSurfaceVariant,
                            size: 19,
                          ),
                        ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: SizedBox(
        height: 38,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 3, 10, 5),
          child: Row(
            children: _contentKinds
                .map((kind) {
                  final selected = _selectedFilters.contains(kind);
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 30,
                        decoration: BoxDecoration(
                          color: selected
                              ? _primaryGreen
                              : colors.surfaceContainerHighest,
                          border: Border.all(
                            color: selected
                                ? _primaryGreen
                                : colors.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _toggleFilter(kind),
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    kind.icon,
                                    size: 13,
                                    color: selected
                                        ? colors.onPrimary
                                        : colors.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      kind.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      softWrap: false,
                                      style: TextStyle(
                                        color: selected
                                            ? colors.onPrimary
                                            : colors.onSurface,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ),
    );
  }

  Widget _buildRecents(BuildContext context) {
    final recents = _visibleRecents;
    final colors = Theme.of(context).colorScheme;
    if (widget.showDiscoverContentWhenEmpty) {
      return _buildDiscoverEmptyContent(context, recents);
    }

    if (recents.isEmpty) {
      return _EmptySearchState(
        icon: _activeFilterIcon,
        title: 'Aramaya başla',
        message:
            'Filmleri, oyuncular, yönetmenleri ve kullanıcıları tek ekranda bulabilirsin.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Son Aramalar',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ),
              TextButton(
                onPressed: _clearRecents,
                child: const Text('Temizle'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: recents.length,
            separatorBuilder: (_, _) => const HairlineDivider(
              indent: 16,
              endIndent: 16,
              verticalPadding: 4,
            ),
            itemBuilder: (context, index) {
              final item = recents[index];
              return _UnifiedSearchTile(
                item: item,
                onTap: () => _openResult(item),
                onRemove: () => _removeRecent(item),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDiscoverEmptyContent(
    BuildContext context,
    List<_UnifiedSearchItem> recents,
  ) {
    final colors = Theme.of(context).colorScheme;
    final bottomPadding =
        AppLayoutMetrics.bottomNavigationClearance(context) + 16;

    return ListView(
      padding: EdgeInsets.only(top: 8, bottom: bottomPadding),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _buildDiscoverRecents(context, recents, colors),
        const RecommendationCard(key: ValueKey('discover_recommendations')),
        const SizedBox(height: 8),
        const DiscoveryListsWidget(key: ValueKey('discover_lists')),
        const SizedBox(height: 12),
        const PeopleRecommendationsWidget(
          key: ValueKey('discover_people_recommendations'),
        ),
        const SizedBox(height: 12),
        const DiscoverNewsAndBlogSections(
          key: ValueKey('discover_news_and_blogs'),
        ),
      ],
    );
  }

  Widget _buildDiscoverRecents(
    BuildContext context,
    List<_UnifiedSearchItem> recents,
    ColorScheme colors,
  ) {
    if (recents.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Son Aramalar',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
              ),
              TextButton(
                onPressed: _clearRecents,
                child: const Text('Temizle'),
              ),
            ],
          ),
        ),
        for (final item in recents)
          Padding(
            key: ValueKey(item.storageKey),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _UnifiedSearchTile(
              item: item,
              onTap: () => _openResult(item),
              onRemove: () => _removeRecent(item),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    final results = _visibleResults;
    if (_isLoadingCurrent && results.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: _primaryGreen),
      );
    }

    if (results.isEmpty) {
      if (_hasCurrentError) {
        return _EmptySearchState(
          icon: Icons.cloud_off_rounded,
          title: 'Arama tamamlanamadı',
          message: 'Bağlantını kontrol edip tekrar deneyebilirsin.',
          actionLabel: 'Tekrar dene',
          onAction: () {
            _failedKinds.removeAll(_desiredKinds);
            _loadKinds(_desiredKinds, _requestId);
          },
        );
      }
      return _EmptySearchState(
        icon: Icons.search_off_rounded,
        title: 'Sonuç bulunamadı',
        message:
            '"$_activeQuery" için $_activeFilterLabel arasında bir sonuç yok.',
      );
    }

    return Column(
      children: [
        if (_isLoadingCurrent)
          const LinearProgressIndicator(minHeight: 2, color: _primaryGreen),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleResultScroll,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: results.length + (_loadingMoreMovies ? 1 : 0),
              separatorBuilder: (_, _) => const HairlineDivider(
                indent: 16,
                endIndent: 16,
                verticalPadding: 4,
              ),
              itemBuilder: (context, index) {
                if (index == results.length) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _primaryGreen,
                        ),
                      ),
                    ),
                  );
                }
                final item = results[index];
                return _UnifiedSearchTile(
                  item: item,
                  onTap: () => _openResult(item),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _UnifiedSearchTile extends StatelessWidget {
  final _UnifiedSearchItem item;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _UnifiedSearchTile({
    required this.item,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerLow.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _SearchResultImage(item: item),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.1,
                      ),
                    ),
                    if (item.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      AccentMetadata(text: item.subtitle, icon: item.kind.icon),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TintedTag(
                label: item.kind.resultLabel,
                icon: item.kind.icon,
                compact: true,
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 2),
                IconButton(
                  tooltip: 'Son aramalardan kaldır',
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 19,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ] else ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResultImage extends StatelessWidget {
  final _UnifiedSearchItem item;

  const _SearchResultImage({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isMovie = item.kind == _SearchKind.movie;
    final width = isMovie ? 44.0 : 52.0;
    final height = isMovie ? 64.0 : 52.0;
    final borderRadius = BorderRadius.circular(isMovie ? 8 : 26);
    final placeholder = Container(
      width: width,
      height: height,
      color: colors.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(item.kind.icon, color: colors.onSurfaceVariant),
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: item.imageUrl == null
          ? placeholder
          : CachedNetworkImage(
              imageUrl: item.imageUrl!,
              width: width,
              height: height,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 140),
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            ),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptySearchState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 62, color: colors.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
