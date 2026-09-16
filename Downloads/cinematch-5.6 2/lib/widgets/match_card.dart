import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:fluttergirdi/services/match_service.dart' as global_match;
import 'package:fluttergirdi/services/catalog_service.dart';
import 'package:fluttergirdi/services/follow_system_service.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/widgets/ui_polish.dart';

// --- YENİ EKLENEN IMPORTLAR ---
import 'package:fluttergirdi/screens/actors_screen.dart';
import 'package:fluttergirdi/screens/director_screen.dart';

// ==========================================
// 1. FİLM VERİSİ VE CACHE MANTIĞI
// ==========================================
class FilmItem {
  final String id;
  final String title;
  final String posterUrl;
  final int? tmdbId;

  const FilmItem({
    required this.id,
    required this.title,
    required this.posterUrl,
    this.tmdbId,
  });
}

final Map<String, FilmItem> _filmItemCache = {};
final Set<String> _missingFilmKeys = {};
final Map<String, Future<Map<String, dynamic>?>> _matchUserCache = {};
final Map<String, Future<bool>> _matchFollowCache = {};

FilmItem _filmItemFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data();
  final rawTmdbId = data['tmdbId'];
  return FilmItem(
    id: doc.id,
    title: (data['title'] ?? data['name'] ?? '').toString(),
    posterUrl: (data['posterUrl'] ?? data['poster'] ?? '').toString(),
    tmdbId: rawTmdbId is num ? rawTmdbId.toInt() : null,
  );
}

Future<List<FilmItem>> fetchFilmsByKeys(List<String> keys) async {
  if (keys.isEmpty) return [];
  final db = FirebaseFirestore.instance;
  final cleanKeys = keys
      .map((k) => k.trim())
      .where((k) => k.isNotEmpty)
      .toSet()
      .toList();
  final missingKeys = cleanKeys
      .where((key) => !_filmItemCache.containsKey(key))
      .where((key) => !_missingFilmKeys.contains(key))
      .toList();

  for (var i = 0; i < missingKeys.length; i += 10) {
    final chunk = missingKeys.sublist(i, math.min(i + 10, missingKeys.length));
    try {
      final qs = await db
          .collection('catalog_films')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      final foundIds = <String>{};
      for (final doc in qs.docs) {
        foundIds.add(doc.id);
        _filmItemCache[doc.id] = _filmItemFromDoc(doc);
      }
      for (final id in chunk) {
        if (!foundIds.contains(id)) {
          _missingFilmKeys.add(id);
        }
      }
    } catch (_) {}
  }

  return [
    for (final key in cleanKeys)
      if (_filmItemCache[key] != null) _filmItemCache[key]!,
  ];
}

Future<Map<String, dynamic>?> _loadMatchUserData(String uid) {
  return _matchUserCache.putIfAbsent(uid, () async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));
      return doc.data();
    } catch (_) {
      return null;
    }
  });
}

Future<bool> _loadMatchFollowStatus(String myUid, String otherUid) {
  final cacheKey = '${myUid}_$otherUid';
  return _matchFollowCache.putIfAbsent(cacheKey, () async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(myUid)
          .collection('following')
          .doc(otherUid)
          .get(const GetOptions(source: Source.serverAndCache));
      return doc.exists;
    } catch (_) {
      return false;
    }
  });
}

// ==========================================
// 2. GELİŞMİŞ EŞLEŞME KARTI WIDGET'I
// ==========================================
class MatchCard extends StatefulWidget {
  final global_match.MatchResult result;

  const MatchCard({super.key, required this.result});

  @override
  State<MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<MatchCard>
    with AutomaticKeepAliveClientMixin {
  bool _isAdded = false;
  bool _isLoading = false;

  Map<String, dynamic>? _userData;
  List<FilmItem>? _commonFilms;
  List<FilmItem>? _favoriteFilms;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;

    final m = widget.result;
    final commonKeys = <String>{
      ...m.commonFavorites,
      ...m.commonFiveStars,
      ...m.commonWatchlist,
    }.take(18).toList();

    final commonFuture = commonKeys.isEmpty
        ? Future.value(<FilmItem>[])
        : fetchFilmsByKeys(commonKeys);
    final userFuture = _loadMatchUserData(widget.result.uid);
    final followFuture = _loadMatchFollowStatus(me, widget.result.uid);

    List<FilmItem> commonFilms = [];
    List<FilmItem> favoriteFilms = [];
    Map<String, dynamic>? userData;
    bool isFollowing = false;

    try {
      commonFilms = await commonFuture;
    } catch (_) {}

    try {
      userData = await userFuture;
      if (userData != null) {
        var favKeys = List<String>.from(userData['favoritesKeys'] ?? []);
        if (favKeys.isEmpty) {
          favKeys = List<String>.from(userData['fiveStarKeys'] ?? []);
        }
        favoriteFilms = favKeys.isEmpty
            ? <FilmItem>[]
            : await fetchFilmsByKeys(favKeys.take(18).toList());
      }
    } catch (_) {}

    try {
      isFollowing = await followFuture;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _commonFilms = commonFilms;
      _userData = userData;
      _favoriteFilms = favoriteFilms;
      _isAdded = isFollowing;
    });
  }

  Future<void> _addFriend() async {
    setState(() => _isLoading = true);
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me != null) {
      try {
        await FollowSystemService.I.followUser(widget.result.uid);
        _matchFollowCache['${me}_${widget.result.uid}'] = Future.value(true);
        if (mounted) setState(() => _isAdded = true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Hata: $e')));
        }
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _handleFilmTap(BuildContext context, FilmItem film) async {
    int? id = film.tmdbId;
    String currentPoster = film.posterUrl;

    if (id == null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) =>
            const Center(child: CircularProgressIndicator(color: Colors.green)),
      );

      try {
        final result = await FirebaseFunctions.instance
            .httpsCallable('callTMDB')
            .call({
              'endpoint': '/3/search/movie',
              'params': {
                'query': film.title,
                'language': 'tr-TR',
                'include_adult': 'false',
              },
            });

        if (!context.mounted) return;
        Navigator.pop(context);

        final data = result.data as Map<String, dynamic>;
        final results = data['results'] as List?;

        if (results != null && results.isNotEmpty) {
          final firstResult = Map<String, dynamic>.from(results[0] as Map);
          id = firstResult['id'];
          final fetchedPosterPath = firstResult['poster_path'];
          if (fetchedPosterPath != null) {
            currentPoster = 'https://image.tmdb.org/t/p/w342$fetchedPosterPath';
          }

          if (film.id.isNotEmpty && id != null) {
            await CatalogService().upsertFromTmdb(
              firstResult,
              catalogKey: film.id,
            );
          }
        } else {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Film detayları bulunamadı.')),
          );
          return;
        }
      } catch (e) {
        if (!context.mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
        return;
      }
    }

    if (currentPoster.startsWith('/')) {
      currentPoster = 'https://image.tmdb.org/t/p/w342$currentPoster';
    } else if (currentPoster.contains('ltrbxd.com')) {
      currentPoster = '';
    }

    if (id != null && context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MovieDetailScreen(
            tmdbId: id!,
            title: film.title,
            posterUrl: currentPoster,
          ),
        ),
      );
    }
  }

  // --- UI YARDIMCI METOTLARI ---

  Widget _buildFilmRow(String title, List<FilmItem> films) {
    if (films.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.76),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 70,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              primary: false,
              physics: const BouncingScrollPhysics(),
              clipBehavior: Clip.none,
              itemCount: films.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final film = films[index];
                return RepaintBoundary(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _handleFilmTap(context, film),
                    child: Tooltip(
                      message: film.title,
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.zero,
                          child: PosterImage(
                            posterUrl: film.posterUrl,
                            title: film.title,
                            tmdbId: film.tmdbId,
                            enableFallback: true,
                            cacheWidth: 120,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrefChip(String text, Color color) {
    return TintedTag(label: text, color: color, compact: true);
  }

  // Tıklama desteği için güncellenmiş çip fonksiyonu
  Widget _buildDetailRowWithChips(
    String title,
    List<dynamic> items,
    Color chipColor, {
    void Function(int id, String name)? onTapChip,
  }) {
    // ID ve isimleri korumak için filtreleme yapıyoruz
    final validItems = items
        .where((e) {
          if (e is Map) return (e['name'] ?? '').toString().trim().isNotEmpty;
          return e.toString().trim().isNotEmpty;
        })
        .take(3)
        .toList();

    if (validItems.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: validItems.map((item) {
                String name = '';
                int? id;

                // Map objesiyse ID'yi ve İsmi al, düz metinse sadece ismi al
                if (item is Map) {
                  name = (item['name'] ?? '').toString();
                  id = item['id'] is num ? (item['id'] as num).toInt() : null;
                } else {
                  name = item.toString();
                }

                return GestureDetector(
                  onTap: () {
                    if (onTapChip != null) {
                      if (id != null) {
                        onTapChip(id, name);
                      } else {
                        // Uygulamanın eski versiyonlarında sadece String olarak kaydedildiyse:
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Bu kişi için detay bulunamadı.'),
                          ),
                        );
                      }
                    }
                  },
                  child: _buildPrefChip(name, chipColor),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(uid: widget.result.uid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final m = widget.result;
    final pct = m.score.clamp(0, 100).toStringAsFixed(0);
    final String? photoUrl = (_userData?['photoURL'] ?? m.photoURL)?.toString();
    final displayName = (m.displayName?.trim().isNotEmpty ?? false)
        ? m.displayName!
        : 'İsimsiz Sinefil';

    final int? age = _userData?['age'];
    final String bio = (_userData?['bio'] ?? '').toString().trim();
    final List<dynamic> genres = _userData?['favGenres'] ?? [];
    final List<dynamic> directors = _userData?['favDirectors'] ?? [];
    final List<dynamic> actors = _userData?['favActors'] ?? [];

    return Stack(
      fit: StackFit.expand,
      children: [
        if (photoUrl != null && photoUrl.isNotEmpty)
          RepaintBoundary(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Transform.scale(
                scale: 1.03,
                child: CachedNetworkImage(
                  imageUrl: photoUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 480,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  errorWidget: (_, _, _) => Container(
                    color: const Color(0xFF101510),
                    child: const Icon(
                      Icons.person,
                      size: 120,
                      color: Colors.white24,
                    ),
                  ),
                ),
              ),
            ),
          )
        else
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1E1E1E), Color(0xFF121212)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: const Icon(Icons.person, size: 120, color: Colors.white24),
          ),

        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.black.withValues(alpha: 0.10),
                const Color(0xFF06150D).withValues(alpha: 0.72),
                Colors.black.withValues(alpha: 0.96),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.46, 1.0],
            ),
          ),
        ),

        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10.0, 10.0, 10.0, 6.0),
              child: RepaintBoundary(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.50),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.greenAccent,
                            width: 1.2,
                          ),
                        ),
                        child: Text(
                          '%$pct Sinema Uyumu',
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: _openProfile,
                            child: CircleAvatar(
                              radius: 40,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.14,
                              ),
                              backgroundImage:
                                  photoUrl != null && photoUrl.isNotEmpty
                                  ? CachedNetworkImageProvider(
                                      photoUrl,
                                      maxWidth: 160,
                                      maxHeight: 160,
                                    )
                                  : null,
                              child: photoUrl == null || photoUrl.isEmpty
                                  ? const Icon(
                                      Icons.person,
                                      color: Colors.white70,
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: _openProfile,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                      height: 1.1,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (bio.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6.0, bottom: 2.0),
                          child: Text(
                            bio,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.25,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (age != null && age > 0)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: _buildPrefChip('$age Yaş', Colors.white),
                              ),

                            // TÜR TIKLANAMAZ (ID'si yok)
                            if (genres.isNotEmpty)
                              _buildDetailRowWithChips(
                                'Sevilen Türler:',
                                genres,
                                Colors.white,
                              ),

                            // YÖNETMENE TIKLAYINCA YÖNETMEN SAYFASINA GİDER
                            if (directors.isNotEmpty)
                              _buildDetailRowWithChips(
                                'Yönetmenler:',
                                directors,
                                Colors.white,
                                onTapChip: (id, name) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DirectorScreen(
                                        directorId: id,
                                        directorName: name,
                                      ),
                                    ),
                                  );
                                },
                              ),

                            // OYUNCUYA TIKLAYINCA OYUNCU SAYFASINA GİDER
                            if (actors.isNotEmpty)
                              _buildDetailRowWithChips(
                                'Oyuncular:',
                                actors,
                                Colors.white,
                                onTapChip: (id, name) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ActorScreen(
                                        actorId: id,
                                        actorName: name,
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),

                      if (_commonFilms == null && _favoriteFilms == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20.0),
                          child: Center(
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        )
                      else if (_commonFilms != null && _commonFilms!.isNotEmpty)
                        _buildFilmRow('Ortak Filmleriniz', _commonFilms!)
                      else if (_favoriteFilms != null &&
                          _favoriteFilms!.isNotEmpty)
                        _buildFilmRow('Favori Filmleri', _favoriteFilms!),

                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isAdded || _isLoading ? null : _addFriend,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isAdded
                                ? Colors.white24
                                : const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.white24,
                            disabledForegroundColor: Colors.white70,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  _isAdded
                                      ? Icons.how_to_reg_rounded
                                      : Icons.person_add_alt_1_rounded,
                                  size: 20,
                                ),
                          label: Text(
                            _isAdded ? 'Takip Edildi' : 'Takip Et',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
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
      ],
    );
  }
}
