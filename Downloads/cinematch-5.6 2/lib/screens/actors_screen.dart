import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'movie_detail_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class _ActorCacheData {
  final Map<String, dynamic> details;
  final List<dynamic> movies;
  _ActorCacheData(this.details, this.movies);
}

final Map<int, _ActorCacheData> _globalActorCache = {};

class ActorScreen extends StatefulWidget {
  final int actorId;
  final String actorName;

  const ActorScreen({
    super.key,
    required this.actorId,
    required this.actorName,
  });

  @override
  State<ActorScreen> createState() => _ActorScreenState();
}

class _ActorScreenState extends State<ActorScreen> {
  Map<String, dynamic>? _actorDetails;
  List<dynamic> _movies = [];
  bool _loading = true;
  bool _isFavorited = false;
  Future<Map<String, int>>?
  _watchDataFuture; // YENİ: İzleme oranını tutacak gelecek veri

  @override
  void initState() {
    super.initState();
    _fetchActorData();
    _checkIfFavorited();
  }

  Future<void> _checkIfFavorited() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (doc.exists) {
      final List favActors = doc.data()?['favActors'] ?? [];
      if (mounted) {
        setState(() {
          _isFavorited = favActors.any((item) {
            if (item is Map) return item['id'] == widget.actorId;
            return item == widget.actorName;
          });
        });
      }
    }
  }

  Future<void> _fetchActorData() async {
    if (_globalActorCache.containsKey(widget.actorId)) {
      if (mounted) {
        setState(() {
          _actorDetails = _globalActorCache[widget.actorId]!.details;
          _movies = _globalActorCache[widget.actorId]!.movies;

          // Listedeki ilk 30 filmi (ekranda görünenleri) baz alarak oranı hesapla
          final visibleMovies = _movies.length > 30
              ? _movies.take(30).toList()
              : _movies;
          _watchDataFuture = _calculateWatchData(visibleMovies);

          _loading = false;
        });
      }
      return;
    }

    try {
      final detailsResult = await FirebaseFunctions.instance
          .httpsCallable('callTMDB')
          .call({
            'endpoint': '/3/person/${widget.actorId}',
            'params': {'language': 'tr-TR'},
          });

      final moviesResult = await FirebaseFunctions.instance
          .httpsCallable('callTMDB')
          .call({
            'endpoint': '/3/person/${widget.actorId}/movie_credits',
            'params': {'language': 'tr-TR'},
          });

      if (mounted) {
        setState(() {
          _actorDetails = Map<String, dynamic>.from(detailsResult.data as Map);
          _movies = (moviesResult.data['cast'] as List);
          _movies.sort(
            (a, b) => (b['popularity'] ?? 0).compareTo(a['popularity'] ?? 0),
          );

          final visibleMovies = _movies.length > 30
              ? _movies.take(30).toList()
              : _movies;
          _watchDataFuture = _calculateWatchData(visibleMovies);

          _loading = false;
        });

        _globalActorCache[widget.actorId] = _ActorCacheData(
          _actorDetails!,
          _movies,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- YENİ EKLENEN FONKSİYON: İZLEME ORANINI HESAPLAR ---
  Future<Map<String, int>> _calculateWatchData(List<dynamic> tmdbMovies) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || tmdbMovies.isEmpty)
      return {'watched': 0, 'total': tmdbMovies.length};

    try {
      List<int> tmdbIds = [];
      for (var m in tmdbMovies) {
        if (m['id'] != null) tmdbIds.add(m['id']);
      }

      if (tmdbIds.isEmpty) return {'watched': 0, 'total': tmdbMovies.length};

      Set<String> listDocIds = {};
      final _fs = FirebaseFirestore.instance;

      for (var i = 0; i < tmdbIds.length; i += 30) {
        final chunk = tmdbIds.sublist(
          i,
          i + 30 > tmdbIds.length ? tmdbIds.length : i + 30,
        );
        final qs = await _fs
            .collection('catalog_films')
            .where('tmdbId', whereIn: chunk)
            .get();
        for (var doc in qs.docs) {
          listDocIds.add(doc.id.trim().toLowerCase());
        }
      }

      Set<String> myWatchedIds = {};
      final userDoc = await _fs.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final data = userDoc.data() ?? {};

        // Buraya sistemdeki tüm 'izlenmiş sayılan' koleksiyonları ekliyoruz
        final keysList = [
          ...List<dynamic>.from(data['favoritesKeys'] ?? []),
          ...List<dynamic>.from(data['fiveStarKeys'] ?? []),
          ...List<dynamic>.from(
            data['dislikedKeys'] ?? [],
          ), // <-- Sevmediklerim eklendi
          ...List<dynamic>.from(
            data['watchedKeys'] ?? [],
          ), // <-- Sadece izledim butonu eklendi
        ];

        for (var id in keysList) {
          if (id != null) myWatchedIds.add(id.toString().trim().toLowerCase());
        }
      }

      int watchedCount = 0;
      for (var docId in listDocIds) {
        if (myWatchedIds.contains(docId)) {
          watchedCount++;
        }
      }

      return {'watched': watchedCount, 'total': tmdbMovies.length};
    } catch (e) {
      return {'watched': 0, 'total': tmdbMovies.length};
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 300,
                  pinned: true,
                  actions: [
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isFavorited
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: _isFavorited ? Colors.green : Colors.white,
                          size: 22,
                        ),
                      ),
                      onPressed: () async {
                        // Favoriye alma işlemi kodları (Aynı)
                        final uid = FirebaseAuth.instance.currentUser?.uid;
                        if (uid == null) return;
                        final userRef = FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid);

                        final actorData = {
                          'name': widget.actorName,
                          'id': widget.actorId,
                          if ((_actorDetails?['profile_path'] ?? '')
                              .toString()
                              .isNotEmpty)
                            'profile_path': _actorDetails!['profile_path'],
                        };

                        try {
                          if (_isFavorited) {
                            final doc = await userRef.get();
                            List favs = List.from(
                              doc.data()?['favActors'] ?? [],
                            );
                            favs.removeWhere((item) {
                              if (item is Map)
                                return item['id'] == widget.actorId;
                              return item == widget.actorName;
                            });
                            await userRef.update({'favActors': favs});
                          } else {
                            await userRef.set({
                              'favActors': FieldValue.arrayUnion([actorData]),
                              'updatedAt': FieldValue.serverTimestamp(),
                            }, SetOptions(merge: true));
                          }

                          if (mounted) {
                            setState(() => _isFavorited = !_isFavorited);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _isFavorited
                                      ? '${widget.actorName} favorilere eklendi!'
                                      : '${widget.actorName} favorilerden çıkarıldı!',
                                ),
                                backgroundColor: _isFavorited
                                    ? Colors.green.shade700
                                    : Colors.redAccent,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted)
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text('Hata: $e')));
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(
                      widget.actorName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    background: _actorDetails?['profile_path'] != null
                        ? CachedNetworkImage(
                            imageUrl:
                                'https://image.tmdb.org/t/p/w500${_actorDetails!['profile_path']}',
                            fit: BoxFit.cover,
                          )
                        : Container(color: Colors.grey),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_actorDetails?['biography'] != null &&
                            _actorDetails!['biography'].isNotEmpty) ...[
                          const Text(
                            "Biyografi",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _actorDetails!['biography'],
                            style: TextStyle(
                              color: textColor.withOpacity(0.8),
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 30),
                        ],
                        Text(
                          "${widget.actorName} Filmleri",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        // --- YENİ EKLENEN İZLEME ORANI (PROGRESS BAR) ---
                        if (_watchDataFuture != null)
                          FutureBuilder<Map<String, int>>(
                            future: _watchDataFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.only(top: 12.0),
                                  child: SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.greenAccent,
                                    ),
                                  ),
                                );
                              }

                              final watchedCount =
                                  snapshot.data?['watched'] ?? 0;
                              final totalCount = snapshot.data?['total'] ?? 0;
                              if (totalCount == 0)
                                return const SizedBox.shrink();

                              final double percentage =
                                  (watchedCount / totalCount) * 100;

                              return Padding(
                                padding: const EdgeInsets.only(
                                  top: 8.0,
                                  bottom: 8.0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "İzleme Oranı",
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade400,
                                          ),
                                        ),
                                        Text(
                                          "%${percentage.toStringAsFixed(0)} ($watchedCount/$totalCount)",
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.greenAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: percentage / 100,
                                        backgroundColor: Colors.white24,
                                        valueColor:
                                            const AlwaysStoppedAnimation<Color>(
                                              Colors.greenAccent,
                                            ),
                                        minHeight: 6,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.6,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final movie = _movies[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MovieDetailScreen(
                                tmdbId: movie['id'],
                                title: movie['title'],
                                posterUrl: movie['poster_path'] != null
                                    ? 'https://image.tmdb.org/t/p/w500${movie['poster_path']}'
                                    : null,
                              ),
                            ),
                          );
                        },
                        child: Column(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: movie['poster_path'] != null
                                      ? 'https://image.tmdb.org/t/p/w200${movie['poster_path']}'
                                      : 'https://via.placeholder.com/200x300',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              movie['title'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    }, childCount: _movies.length > 30 ? 30 : _movies.length),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 50)),
              ],
            ),
    );
  }
}
