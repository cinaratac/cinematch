import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/user_profile_service.dart';
import '../services/catalog_service.dart';
import '../models/shelf_target.dart';
import '../widgets/poster_image.dart';
import '../screens/profilescreen.dart';

extension ShelfTargetXLocal on ShelfTarget {
  String get userArrayField {
    switch (this) {
      case ShelfTarget.fiveStar:
        return 'fiveStarKeys';
      case ShelfTarget.disliked:
        return 'dislikedKeys';
      case ShelfTarget.favorites:
        return 'favoritesKeys';
      case ShelfTarget.watchlist:
        return 'watchlistKeys';
    }
  }
}

// Global TMDB Arama Fonksiyonu
Future<List<dynamic>> _tmdbSearchMovies(String query, {int page = 1}) async {
  final q = query.trim();
  if (q.isEmpty) return [];

  try {
    final result = await FirebaseFunctions.instance
        .httpsCallable('searchMovies')
        .call({'query': q, 'page': page});

    final data = Map<String, dynamic>.from(result.data as Map);
    final List results = data['results'] ?? [];
    return results.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } catch (e) {
    throw Exception("Arama hatası: $e");
  }
}

class SearchMoviePage extends StatefulWidget {
  final ShelfTarget? target;
  final bool isSelectionMode;
  final String? selectionHint;

  const SearchMoviePage({
    super.key,
    this.target,
    this.isSelectionMode = false,
    this.selectionHint,
  });

  @override
  State<SearchMoviePage> createState() => _SearchMoviePageState();
}

class _SearchMoviePageState extends State<SearchMoviePage> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _movies = [];
  bool _isLoading = false;
  String? _error;
  Timer? _debounce;
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreMovies();
    }
  }

  String get _hintText {
    if (widget.isSelectionMode) {
      return widget.selectionHint ?? 'Listeye eklemek için film ara...';
    }
    if (widget.target == null) return 'Film ara...';
    switch (widget.target!) {
      case ShelfTarget.fiveStar:
        return 'Sevdiğin filmi ara...';
      case ShelfTarget.disliked:
        return 'Sevmediğin filmi ara...';
      case ShelfTarget.favorites:
        return 'Favori filmini ara...';
      case ShelfTarget.watchlist:
        return 'İzlemek istediğin filmi ara...';
    }
  }

  Future<void> _loadMoreMovies() async {
    if (_isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    // KRİTİK: await başlamadan önce messenger'ı tanımlıyoruz
    final messenger = ScaffoldMessenger.of(context);

    try {
      final nextPage = _currentPage + 1;
      final results = await _tmdbSearchMovies(
        _searchController.text,
        page: nextPage,
      );

      if (results.isEmpty) {
        if (mounted) setState(() => _hasMore = false);
      } else {
        if (mounted) {
          setState(() {
            _movies.addAll(results);
            _currentPage = nextPage;
          });
        }
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Hata oluştu: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _searchMovies(String query) async {
    if (query.isEmpty) {
      setState(() {
        _movies = [];
        _currentPage = 1;
        _hasMore = true;
        _error = null;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await _tmdbSearchMovies(query);
      if (mounted) setState(() => _movies = List.from(results));
    } catch (e) {
      if (mounted) setState(() => _error = 'Hata: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showMovieDetails(dynamic movie) async {
    final theme = Theme.of(context);
    final posterPath = movie['poster_path'];
    final posterUrl = (posterPath is String && posterPath.isNotEmpty)
        ? 'https://image.tmdb.org/t/p/w342$posterPath'
        : '';
    final String title = (movie['title'] ?? 'Başlık yok').toString();
    final String originalTitle = (movie['original_title'] ?? '').toString();
    final String release = (movie['release_date'] ?? '').toString();
    final String year = release.length >= 4 ? release.substring(0, 4) : '';
    final String overview = (movie['overview'] ?? '').toString();

    // ÇÖZÜM: BottomSheet sonucunu bir değişkende bekliyoruz
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        bool isSaving = false;

        return StatefulBuilder(
          builder: (BuildContext contextInner, StateSetter setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 60,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.zero,
                        child: PosterImage(
                          posterUrl: posterUrl,
                          title: title,
                          width: 100,
                          height: 150,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (year.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  year,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Orijinal: $originalTitle',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (overview.isNotEmpty) ...[
                    Text(
                      overview,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      icon: isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add_rounded),
                      label: Text(
                        isSaving
                            ? 'Ekleniyor...'
                            : (widget.isSelectionMode
                                  ? 'Bu Filmi Seç'
                                  : 'Listeye Ekle'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              if (widget.isSelectionMode) {
                                final selectedMovie = {
                                  'id': movie['id'],
                                  'title': title,
                                  'original_title': originalTitle,
                                  'poster': posterUrl,
                                  'poster_path': movie['poster_path'],
                                  'release_date': release,
                                  'releaseDate': release,
                                  'overview': overview,
                                };
                                Navigator.pop(contextInner, selectedMovie);
                                return;
                              }

                              setSheetState(() => isSaving = true);
                              final messenger = ScaffoldMessenger.of(context);
                              bool isSuccess = false;

                              try {
                                final uid =
                                    FirebaseAuth.instance.currentUser?.uid;
                                if (uid == null) {
                                  Navigator.pop(contextInner);
                                  return;
                                }

                                final movieMap = Map<String, dynamic>.from(
                                  movie as Map,
                                );
                                final int? tmdbId = movieMap['id'] is int
                                    ? movieMap['id'] as int
                                    : int.tryParse('${movieMap['id'] ?? ''}');
                                if (tmdbId == null || tmdbId <= 0) {
                                  throw StateError(
                                    'Geçersiz film verisi (TMDB id bulunamadı).',
                                  );
                                }

                                // OPTIMISTIC CACHE: resolveCatalogMovie Cloud Function'ının
                                // gecikmesini/geçici hatasını (App Check, ağ vb.) beklemiyoruz.
                                // Kanonik anahtarı yerel olarak üretip RAM cache'e hemen yazıyoruz,
                                // sunucu senkronunu arka planda (await YOK) tetikliyoruz.
                                final primaryKey =
                                    CatalogService.canonicalKeyFromTmdb(tmdbId);
                                CatalogService().injectToCache(primaryKey, {
                                  ...movieMap,
                                  'posterUrl': posterUrl,
                                });
                                // ignore: unawaited_futures
                                CatalogService().upsertFromTmdb(
                                  movieMap,
                                  catalogKey: primaryKey,
                                );

                                if (widget.target != null) {
                                  final previousList = await UserProfileService
                                      .instance
                                      .moveMovieToTarget(
                                        uid: uid,
                                        movieId: primaryKey,
                                        tmdbId: tmdbId,
                                        movieData: movieMap,
                                        target: widget.target!,
                                        posterUrl: posterUrl,
                                      );

                                  final Map<String, String> newLocalItem = {
                                    'title': title,
                                    'poster': posterUrl,
                                    'posterUrl': posterUrl,
                                  };
                                  switch (widget.target!) {
                                    case ShelfTarget.fiveStar:
                                      UserShelfCache.fiveStar = List.from(
                                        UserShelfCache.fiveStar,
                                      )..add(newLocalItem);
                                      break;
                                    case ShelfTarget.favorites:
                                      UserShelfCache.favorites = List.from(
                                        UserShelfCache.favorites,
                                      )..add(newLocalItem);
                                      break;
                                    case ShelfTarget.watchlist:
                                      UserShelfCache.watchlist = List.from(
                                        UserShelfCache.watchlist,
                                      )..add(newLocalItem);
                                      break;
                                    case ShelfTarget.disliked:
                                      UserShelfCache.disliked = List.from(
                                        UserShelfCache.disliked,
                                      )..add(newLocalItem);
                                      break;
                                  }

                                  String targetName = switch (widget.target!) {
                                    ShelfTarget.fiveStar => 'Sevdiklerim',
                                    ShelfTarget.disliked => 'Sevmedim',
                                    ShelfTarget.favorites => 'Favoriler',
                                    ShelfTarget.watchlist => 'İzlenecekler',
                                  };

                                  String message = previousList != null
                                      ? "'$title', $previousList listesinden çıkarılıp $targetName listesine eklendi."
                                      : "'$title', $targetName listesine eklendi.";

                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(message),
                                      backgroundColor: Colors.green.shade700,
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }

                                isSuccess = true;
                              } catch (e) {
                                messenger.showSnackBar(
                                  SnackBar(content: Text('Hata: $e')),
                                );
                              }

                              if (contextInner.mounted) {
                                if (isSuccess) {
                                  Navigator.pop(contextInner, true);
                                } else {
                                  setSheetState(() => isSaving = false);
                                }
                              }
                            },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    // ÇÖZÜMÜN DEVAMI: BottomSheet başarılı şekilde ("true" veya obje ile)
    // kapandıysa arama sayfasını DA o sonuçla güvenle kapat.
    if (result != null && mounted) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Container(
          height: 45,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            textAlignVertical: TextAlignVertical.center,
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: _hintText,
              hintStyle: TextStyle(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.7,
                ),
              ),
              border: InputBorder.none,
              prefixIcon: Icon(
                Icons.search,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        _searchMovies('');
                      },
                    )
                  : null,
            ),
            onChanged: (value) {
              if (_debounce?.isActive ?? false) _debounce!.cancel();
              _debounce = Timer(const Duration(milliseconds: 800), () {
                _searchMovies(value);
              });
            },
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_movies.isEmpty) {
      return const Center(child: Text('Aradığınız filmi yukarı yazın.'));
    }

    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.67,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _movies.length,
            itemBuilder: (context, index) => _buildGridItem(_movies[index]),
          ),
        ),
        if (_isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }

  Widget _buildGridItem(dynamic movie) {
    final posterPath = movie['poster_path'];
    final posterUrl = (posterPath is String && posterPath.isNotEmpty)
        ? 'https://image.tmdb.org/t/p/w342$posterPath'
        : '';
    final title = movie['title'] ?? '';
    final tmdbId = (movie['id'] is int) ? movie['id'] as int : null;

    return InkWell(
      onTap: () => _showMovieDetails(movie),
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PosterImage(
              posterUrl: posterUrl,
              title: title,
              tmdbId: tmdbId,
              fit: BoxFit.cover,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    shadows: [Shadow(color: Colors.black, blurRadius: 2)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
