import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/custom_list.dart';
import 'package:fluttergirdi/services/custom_list_service.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/screens/search_movie.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';

class CustomListDetailScreen extends StatelessWidget {
  final CustomList list;
  final bool isMyList;

  const CustomListDetailScreen({
    super.key,
    required this.list,
    this.isMyList = false,
  });

  @override
  Widget build(BuildContext context) {
    // --- YENİ EKLENEN KESİN KONTROL ---
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final bool isActuallyMyList = list.ownerId == currentUid;
    // ---------------------------------

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // --- 1. Kapak, Başlık ve Açıklama ---
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              // ... (Buralar aynı kalıyor, titlePadding, title, background vb.)
              titlePadding: const EdgeInsets.only(
                left: 16,
                bottom: 12,
                right: 16,
              ),
              title: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    list.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: [Shadow(color: Colors.black, blurRadius: 10)],
                    ),
                  ),
                  if (list.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text(
                        list.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.normal,
                          color: Colors.white,
                          shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                        ),
                      ),
                    ),
                ],
              ),
              background: list.coverImageUrl != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(list.coverImageUrl!, fit: BoxFit.cover),
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      color: Colors.grey.shade900,
                      child: const Center(
                        child: Icon(
                          Icons.movie_filter,
                          size: 64,
                          color: Colors.white24,
                        ),
                      ),
                    ),
            ),
            actions: [
              // isMyList YERİNE ARTIK KESİN OLAN isActuallyMyList KULLANIYORUZ
              if (isActuallyMyList)
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Film Ekle',
                  onPressed: () => _navigateToAddMovie(context),
                ),
              if (isActuallyMyList)
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                  onPressed: () => _confirmDelete(context),
                ),

              // --- KAYDET BUTONU SADECE LİSTE BAŞKASININSA ÇIKAR ---
              if (!isActuallyMyList)
                StreamBuilder<bool>(
                  stream: CustomListService.instance.isListSaved(list.id),
                  builder: (context, snapshot) {
                    final isSaved = snapshot.data ?? false;

                    return IconButton(
                      icon: Icon(
                        isSaved ? Icons.bookmark : Icons.bookmark_border,
                        color: isSaved ? Colors.greenAccent : Colors.white,
                      ),
                      onPressed: () async {
                        if (isSaved) {
                          await CustomListService.instance.unsaveList(list.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Liste kaydedilenlerden çıkarıldı.',
                                ),
                              ),
                            );
                          }
                        } else {
                          final listData = {
                            'title': list.title,
                            'description': list.description,
                            'coverImageUrl': list.coverImageUrl,
                            'ownerName': list.ownerName,
                            'ownerId': list.ownerId,
                            'movieCount': list.movieCount,
                          };
                          await CustomListService.instance.saveList(
                            list.id,
                            listData,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Liste kaydedildi!'),
                              ),
                            );
                          }
                        }
                      },
                    );
                  },
                ),
            ],
          ),

          // ... Kodun geri kalanı tamamen aynı ...

          // --- 2. Liste Bilgileri, Hazırlayan ve İZLEME ORANI ---
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // LİSTE SAHİBİ
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PublicProfileScreen(uid: list.ownerId),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance
                              .collection('users')
                              .doc(list.ownerId)
                              .get(),
                          builder: (context, snapshot) {
                            String? photoUrl;
                            if (snapshot.hasData && snapshot.data!.exists) {
                              final data =
                                  snapshot.data!.data()
                                      as Map<String, dynamic>?;
                              photoUrl = data?['photoURL'] as String?;
                            }

                            return CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.grey.shade800,
                              backgroundImage:
                                  (photoUrl != null && photoUrl.isNotEmpty)
                                  ? NetworkImage(photoUrl)
                                  : null,
                              child: (photoUrl == null || photoUrl.isEmpty)
                                  ? const Icon(
                                      Icons.person,
                                      size: 16,
                                      color: Colors.white70,
                                    )
                                  : null,
                            );
                          },
                        ),
                        const SizedBox(width: 6),
                        RichText(
                          text: TextSpan(
                            children: [
                              const TextSpan(
                                text: "Hazırlayan: ",
                                style: TextStyle(color: Colors.grey),
                              ),
                              TextSpan(
                                text: list.ownerName,
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // İstatistikler
                  Row(
                    children: [
                      Icon(Icons.movie, size: 16, color: Colors.grey.shade400),
                      const SizedBox(width: 4),
                      Text(
                        '${list.movieCount} Film',
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                      const SizedBox(width: 16),
                      if (!list.isPublic) ...[
                        Icon(Icons.lock, size: 16, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(
                          'Gizli Liste',
                          style: TextStyle(color: Colors.grey.shade400),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 20),

                  // --- İZLEME ORANI (SENİN DEDİĞİN DOĞRUDAN YÖNTEM) ---
                  StreamBuilder<QuerySnapshot>(
                    stream: CustomListService.instance.getListItems(list.id),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      final docs = snapshot.data!.docs;

                      return FutureBuilder<Map<String, int>>(
                        // SADECE bu listedeki filmleri kontrol eden yepyeni fonksiyonumuz
                        future: _calculateWatchData(docs),
                        builder: (context, futureSnap) {
                          if (futureSnap.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.greenAccent,
                                  ),
                                ),
                              ),
                            );
                          }

                          final watchedCount = futureSnap.data?['watched'] ?? 0;
                          final totalCount =
                              futureSnap.data?['total'] ?? docs.length;
                          final double percentage = totalCount > 0
                              ? (watchedCount / totalCount) * 100
                              : 0;

                          return Column(
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
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: totalCount > 0 ? percentage / 100 : 0,
                                  backgroundColor: Colors.white24,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        Colors.greenAccent,
                                      ),
                                  minHeight: 8,
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  // -------------------------------------------------------------
                ],
              ),
            ),
          ),

          // --- 3. Filmler Grid ---
          StreamBuilder<QuerySnapshot>(
            stream: CustomListService.instance.getListItems(list.id),
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                );

              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.format_list_bulleted,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "Bu listede henüz film yok.",
                          style: TextStyle(color: Colors.grey),
                        ),
                        if (isMyList)
                          TextButton(
                            onPressed: () => _navigateToAddMovie(context),
                            child: const Text("Film Ekle"),
                          ),
                      ],
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;

                    int tmdbId = 0;
                    if (data['id'] is int) {
                      tmdbId = data['id'];
                    } else if (data['id'] != null) {
                      tmdbId = int.tryParse(data['id'].toString()) ?? 0;
                    }

                    return GestureDetector(
                      onTap: () {
                        if (tmdbId != 0) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MovieDetailScreen(
                                tmdbId: tmdbId,
                                title: data['title'],
                                posterUrl: data['poster'],
                              ),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Film detayları yüklenemedi."),
                            ),
                          );
                        }
                      },
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.zero,
                              child: PosterImage(
                                posterUrl: data['poster'] ?? '',
                                title: data['title'] ?? '',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),

                          if (data['poster'] == null)
                            Center(
                              child: Text(
                                data['title'] ?? '',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),

                          if (isMyList)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: InkWell(
                                onTap: () => CustomListService.instance
                                    .removeMovieFromList(
                                      list.id,
                                      docs[index].id,
                                    ),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }, childCount: docs.length),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.67,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  // SENİN MANTIĞINLA ÇALIŞAN, SADECE LİSTEYE ODAKLANAN YENİ FONKSİYON
  Future<Map<String, int>> _calculateWatchData(
    List<QueryDocumentSnapshot> listDocs,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || listDocs.isEmpty)
      return {'watched': 0, 'total': listDocs.length};

    try {
      // 1. O anki listede bulunan filmlerin TMDB ID'lerini topla
      List<int> tmdbIds = [];
      for (var doc in listDocs) {
        final data = doc.data() as Map<String, dynamic>;
        int tmdbId = 0;
        if (data['id'] is int)
          tmdbId = data['id'];
        else if (data['id'] != null)
          tmdbId = int.tryParse(data['id'].toString()) ?? 0;
        else if (data['tmdbId'] != null)
          tmdbId = int.tryParse(data['tmdbId'].toString()) ?? 0;

        if (tmdbId != 0) tmdbIds.add(tmdbId);
      }

      if (tmdbIds.isEmpty) return {'watched': 0, 'total': listDocs.length};

      // 2. Bu TMDB ID'lerin Firebase'deki karşılıklarını (Firebase Doc ID) bul
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

      // 3. Kullanıcının halihazırda var olan Sevdiklerini/Favorilerini tek seferde çek
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

      // 4. Listedeki filmlerden kaç tanesi kullanıcının profilinde var?
      int watchedCount = 0;
      for (var docId in listDocIds) {
        if (myWatchedIds.contains(docId)) {
          watchedCount++;
        }
      }

      return {'watched': watchedCount, 'total': listDocs.length};
    } catch (e) {
      return {'watched': 0, 'total': listDocs.length};
    }
  }

  // ... (Geri kalan AddMovie ve ConfirmDelete fonksiyonları orijinal haliyle burada kalmaya devam ediyor)
  Future<void> _navigateToAddMovie(BuildContext context) async {
    final selectedMovie = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SearchMoviePage(isSelectionMode: true),
      ),
    );

    if (selectedMovie != null && selectedMovie is Map<String, dynamic>) {
      await CustomListService.instance.addMovieToList(list.id, selectedMovie);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${selectedMovie['title']} eklendi.")),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Listeyi Sil"),
        content: const Text(
          "Bu listeyi silmek istediğinize emin misiniz? Bu işlem geri alınamaz.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("İptal"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await CustomListService.instance.deleteList(list.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text("Sil", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
