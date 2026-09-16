import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class _DirectorCacheData {
  final Map<String, dynamic> details;
  final List<dynamic> movies;
  _DirectorCacheData(this.details, this.movies);
}

final Map<int, _DirectorCacheData> _globalDirectorCache = {};

class DirectorScreen extends StatefulWidget {
  final int directorId;
  final String directorName;

  const DirectorScreen({
    super.key,
    required this.directorId,
    required this.directorName,
  });

  @override
  State<DirectorScreen> createState() => _DirectorScreenState();
}

class _DirectorScreenState extends State<DirectorScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _directorDetails;
  List<dynamic> _directedMovies = [];
  bool _isFavorited = false;
  Future<Map<String, int>>? _watchDataFuture; // YENİ: İzleme Oranı

  @override
  void initState() {
    super.initState();
    _fetchDirectorData();
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
      final List favDirectors = doc.data()?['favDirectors'] ?? [];
      if (mounted) {
        setState(() {
          _isFavorited = favDirectors.any((item) {
            if (item is Map) return item['id'] == widget.directorId;
            return item == widget.directorName;
          });
        });
      }
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

  Future<void> _fetchDirectorData() async {
    if (_globalDirectorCache.containsKey(widget.directorId)) {
      if (mounted) {
        setState(() {
          _directorDetails = _globalDirectorCache[widget.directorId]!.details;
          _directedMovies = _globalDirectorCache[widget.directorId]!.movies;
          _watchDataFuture = _calculateWatchData(_directedMovies);
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final functions = FirebaseFunctions.instance;

      final detailsRes = await functions.httpsCallable('callTMDB').call({
        'endpoint': '/3/person/${widget.directorId}',
        'params': {'language': 'tr-TR'},
      });

      final creditsRes = await functions.httpsCallable('callTMDB').call({
        'endpoint': '/3/person/${widget.directorId}/movie_credits',
        'params': {'language': 'tr-TR'},
      });

      final creditsData = creditsRes.data;
      final List<dynamic> crew = creditsData['crew'] ?? [];

      List<dynamic> directed = crew
          .where((c) => c['job'] == 'Director')
          .toList();

      directed.sort((a, b) {
        final popA = (a['popularity'] as num?) ?? 0;
        final popB = (b['popularity'] as num?) ?? 0;
        return popB.compareTo(popA);
      });

      final seenIds = <int>{};
      _directedMovies = directed.where((movie) {
        final id = movie['id'] as int;
        if (seenIds.contains(id)) return false;
        seenIds.add(id);
        return true;
      }).toList();

      if (mounted) {
        setState(() {
          _directorDetails = detailsRes.data;
          _watchDataFuture = _calculateWatchData(_directedMovies);
          _isLoading = false;
        });

        _globalDirectorCache[widget.directorId] = _DirectorCacheData(
          _directorDetails!,
          _directedMovies,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yönetmen bilgileri yüklenemedi.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.directorName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isFavorited
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: _isFavorited ? Colors.green : Colors.grey,
                size: 22,
              ),
            ),
            onPressed: () async {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) return;

              final bool wasFavorited = _isFavorited;
              setState(() {
                _isFavorited = !wasFavorited;
              });

              final userRef = FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid);
              final directorData = {
                'name': widget.directorName,
                'id': widget.directorId,
                if ((_directorDetails?['profile_path'] ?? '')
                    .toString()
                    .isNotEmpty)
                  'profile_path': _directorDetails!['profile_path'],
              };

              try {
                if (wasFavorited) {
                  final doc = await userRef.get();
                  List favs = List.from(doc.data()?['favDirectors'] ?? []);
                  favs.removeWhere((item) {
                    if (item is Map) return item['id'] == widget.directorId;
                    return item == widget.directorName;
                  });
                  await userRef.update({'favDirectors': favs});
                } else {
                  await userRef.set({
                    'favDirectors': FieldValue.arrayUnion([directorData]),
                    'updatedAt': FieldValue.serverTimestamp(),
                  }, SetOptions(merge: true));
                }

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        !wasFavorited
                            ? '${widget.directorName} favorilere eklendi!'
                            : '${widget.directorName} favorilerden çıkarıldı!',
                      ),
                      backgroundColor: !wasFavorited
                          ? Colors.green.shade700
                          : Colors.redAccent,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  setState(() {
                    _isFavorited = wasFavorited;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Hata oluştu, geri alındı: $e')),
                  );
                }
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _directorDetails == null
          ? const Center(child: Text('Veri bulunamadı.'))
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _directorDetails!['profile_path'] != null
                              ? CachedNetworkImage(
                                  imageUrl:
                                      'https://image.tmdb.org/t/p/w500${_directorDetails!['profile_path']}',
                                  width: 120,
                                  height: 180,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  width: 120,
                                  height: 180,
                                  color: cs.surfaceContainerHighest,
                                  child: const Icon(
                                    Icons.person,
                                    size: 50,
                                    color: Colors.grey,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.directorName,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_directorDetails!['birthday'] != null)
                                _buildInfoRow(
                                  'Doğum',
                                  _directorDetails!['birthday'],
                                ),
                              if (_directorDetails!['place_of_birth'] != null)
                                _buildInfoRow(
                                  'Yer',
                                  _directorDetails!['place_of_birth'],
                                ),
                              if (_directorDetails!['deathday'] != null)
                                _buildInfoRow(
                                  'Ölüm',
                                  _directorDetails!['deathday'],
                                ),

                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF2E7D32,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Yönetmen',
                                  style: TextStyle(
                                    color: Color(0xFF2E7D32),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_directorDetails!['biography'] != null &&
                    _directorDetails!['biography'].toString().isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Biyografi',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _directorDetails!['biography'],
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // --- İZLEME ORANI (YÖNETTİĞİ FİLMLER BAŞLIĞI VE PROGRESS BAR) ---
                if (_directedMovies.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Yönettiği Filmler',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

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
                                    top: 12.0,
                                    bottom: 4.0,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                              const AlwaysStoppedAnimation<
                                                Color
                                              >(Colors.greenAccent),
                                          minHeight: 6,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),

                // -------------------------------------------------------------
                if (_directedMovies.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.65,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final movie = _directedMovies[index];
                        final posterPath = movie['poster_path'];
                        final fullPosterUrl = posterPath != null
                            ? 'https://image.tmdb.org/t/p/w500$posterPath'
                            : '';

                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MovieDetailScreen(
                                  tmdbId: movie['id'],
                                  title: movie['title'],
                                  posterUrl: fullPosterUrl,
                                ),
                              ),
                            );
                          },
                          child: Column(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.zero,
                                  child: PosterImage(
                                    posterUrl: fullPosterUrl,
                                    title: movie['title'],
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                movie['title'] ?? 'Film',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      }, childCount: _directedMovies.length),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
    );
  }

  Widget _buildInfoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title: ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          Expanded(
            child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
