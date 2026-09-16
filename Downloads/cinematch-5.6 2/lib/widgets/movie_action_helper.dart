import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../services/chat_service.dart';
import '../services/catalog_service.dart';
import '../controllers/feed_controller.dart';
import '../services/user_cache_service.dart';
import '../widgets/compose_post_sheet.dart';
import '../widgets/poster_image.dart';
import '../models/shelf_target.dart';
import '../services/feed_service.dart';
import '../services/tab_service.dart';
import '../screens/movie_detail_screen.dart';

class MovieActionHelper {
  static void show(
    BuildContext context, {
    required String title,
    required String posterUrl,
    String? docId,
    ShelfTarget? target,
    VoidCallback? onItemDeleted,
    String? overview,
    double? voteAverage,
    String? releaseDate,
    int? tmdbId,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _MovieActionSheet(
        title: title,
        posterUrl: posterUrl,
        docId: docId,
        target: target,
        onItemDeleted: onItemDeleted,
        overview: overview,
        voteAverage: voteAverage,
        releaseDate: releaseDate,
        tmdbId: tmdbId,
      ),
    );
  }
}

class _MovieActionSheet extends StatefulWidget {
  final String title;
  final String posterUrl;
  final String? docId;
  final ShelfTarget? target;
  final VoidCallback? onItemDeleted;
  final String? overview;
  final double? voteAverage;
  final String? releaseDate;
  final int? tmdbId;

  const _MovieActionSheet({
    required this.title,
    required this.posterUrl,
    this.docId,
    this.target,
    this.onItemDeleted,
    this.overview,
    this.voteAverage,
    this.releaseDate,
    this.tmdbId,
  });

  @override
  State<_MovieActionSheet> createState() => _MovieActionSheetState();
}

class _MovieActionSheetState extends State<_MovieActionSheet> {
  bool _isDeleting = false;

  String get title => widget.title;
  String get posterUrl => widget.posterUrl;
  String? get docId => widget.docId;
  ShelfTarget? get target => widget.target;
  VoidCallback? get onItemDeleted => widget.onItemDeleted;
  String? get overview => widget.overview;
  int? get tmdbId => widget.tmdbId;

  String? _getFieldForTarget(ShelfTarget t) {
    switch (t) {
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

  Future<void> _fetchAndNavigateToDetails(BuildContext context) async {
    int? resolvedTmdbId = tmdbId;

    if (resolvedTmdbId == null && docId != null) {
      final doc = await FirebaseFirestore.instance
          .collection('catalog_films')
          .doc(docId)
          .get();
      if (doc.exists) {
        resolvedTmdbId = doc.data()?['tmdbId'];
      }
    }

    if (resolvedTmdbId == null) {
      try {
        final result = await FirebaseFunctions.instance
            .httpsCallable('callTMDB')
            .call({
              'endpoint': '/3/search/movie',
              'params': {'query': title, 'include_adult': 'false'},
            });

        final data = Map<String, dynamic>.from(result.data as Map);
        final results = data['results'] as List?;

        if (results != null && results.isNotEmpty) {
          resolvedTmdbId = results[0]['id'];
          if (docId != null && resolvedTmdbId != null) {
            await CatalogService().resolveAndUpsert(
              tmdbId: resolvedTmdbId,
              title: title,
              catalogKey: docId,
            );
          }
        }
      } catch (e) {
        debugPrint("TMDB Error: $e");
      }
    }

    if (!context.mounted) return;
    Navigator.pop(context);

    if (resolvedTmdbId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MovieDetailScreen(
            tmdbId: resolvedTmdbId!,
            title: title,
            posterUrl: posterUrl,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Film detayları bulunamadı.')),
      );
    }
  }

  Future<void> _deleteFromProfile(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (_isDeleting || uid == null || docId == null || target == null) return;

    final field = _getFieldForTarget(target!);
    if (field == null) return;

    setState(() => _isDeleting = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final keysToRemove = <Object>{docId!};

      int? resolvedTmdbId = tmdbId;
      if (resolvedTmdbId == null) {
        final movieDoc = await db.collection('catalog_films').doc(docId).get();
        resolvedTmdbId = movieDoc.data()?['tmdbId'] as int?;
      }
      if (resolvedTmdbId != null) {
        keysToRemove.add(resolvedTmdbId);
        keysToRemove.add(resolvedTmdbId.toString());
      }

      final userRef = db.collection('users').doc(uid);
      batch.update(userRef, {
        field: FieldValue.arrayRemove(keysToRemove.toList()),
      });

      if (target == ShelfTarget.fiveStar) {
        final tasteRef = db.collection('userTasteProfiles').doc(uid);
        batch.update(tasteRef, {
          'loved': FieldValue.arrayRemove(keysToRemove.toList()),
        });
      } else if (target == ShelfTarget.disliked) {
        final tasteRef = db.collection('userTasteProfiles').doc(uid);
        batch.update(tasteRef, {
          'disliked': FieldValue.arrayRemove(keysToRemove.toList()),
        });
      }

      await batch.commit();
      onItemDeleted?.call();

      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('$title profilinden silindi.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        messenger.showSnackBar(const SnackBar(content: Text('Hata oluştu.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(0, 20, 0, bottomPadding + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.zero,
                  child: SizedBox(
                    width: 50,
                    height: 75,
                    child: PosterImage(
                      posterUrl: posterUrl,
                      title: title,
                      fit: BoxFit.cover,
                      tmdbId: tmdbId ?? 0,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Film Detayları'),
            onTap: () => _fetchAndNavigateToDetails(context),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note_outlined),
            title: const Text('Feed\'de Paylaş'),
            onTap: () {
              Navigator.pop(context);
              _shareOnFeed(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.send_rounded),
            title: const Text('Mesaj Olarak Gönder'),
            onTap: () {
              Navigator.pop(context);
              _showInboxPicker(context);
            },
          ),
          if (docId != null && target != null) ...[
            const Divider(),
            ListTile(
              leading: _isDeleting
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: theme.colorScheme.error,
                      ),
                    )
                  : Icon(Icons.delete_outline, color: theme.colorScheme.error),
              title: Text(
                _isDeleting ? 'Siliniyor...' : 'Profilden Sil',
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
              enabled: !_isDeleting,
              onTap: _isDeleting ? null : () => _deleteFromProfile(context),
            ),
          ],
        ],
      ),
    );
  }

  void _shareOnFeed(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComposePostPage(
          maxChars: 1000,
          initialMovie: {
            'title': title,
            'poster': posterUrl,
            if (tmdbId != null) 'tmdbId': tmdbId,
            if (tmdbId != null) 'id': tmdbId,
            if (docId != null) 'docId': docId,
          },
          onSend:
              ({
                required text,
                movie,
                images,
                rating,
                required isSpoiler,
                tags,
                reviewTitle,
              }) async {
                final user = FirebaseAuth.instance.currentUser;
                if (user == null) return;

                List<String> postImageUrls = [];

                if (images != null && images.isNotEmpty) {
                  for (var i = 0; i < images.length; i++) {
                    final image = images[i];
                    final String fileName =
                        '${user.uid}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
                    final ref = FirebaseStorage.instance
                        .ref()
                        .child('post_images')
                        .child(fileName);
                    await ref.putFile(image);
                    final url = await ref.getDownloadURL();
                    postImageUrls.add(url);
                  }
                }

                await FeedService.instance.createPost(
                  text: text,
                  movie: movie,
                  photoURL: postImageUrls.isNotEmpty
                      ? postImageUrls.first
                      : null,
                  photoURLs: postImageUrls,
                  displayName: user.displayName,
                  handle: user.email?.split('@')[0],
                  rating: rating,
                  isSpoiler: isSpoiler,
                  tags: tags,
                  reviewTitle: reviewTitle,
                );

                if (context.mounted) {
                  FeedController.instance.refresh();
                  TabService.instance.changeTab(0);
                  Future.microtask(
                    () => Navigator.of(
                      context,
                    ).popUntil((route) => route.isFirst),
                  );
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Paylaşıldı!')));
                }
              },
        ),
      ),
    );
  }

  void _showInboxPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _InboxPickerSheet(
        movieTitle: title,
        moviePoster: posterUrl,
        tmdbId: tmdbId,
        overview: overview,
        docId: docId,
      ),
    );
  }
}

class _InboxPickerSheet extends StatefulWidget {
  final String movieTitle;
  final String moviePoster;
  final int? tmdbId;
  final String? overview;
  final String? docId;

  const _InboxPickerSheet({
    required this.movieTitle,
    required this.moviePoster,
    this.tmdbId,
    this.overview,
    this.docId,
  });

  @override
  State<_InboxPickerSheet> createState() => _InboxPickerSheetState();
}

class _InboxPickerSheetState extends State<_InboxPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    if (myUid == null) return const SizedBox.shrink();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Filmi Gönder',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Sohbet veya kişi ara...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withOpacity(0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (val) =>
                      setState(() => _query = val.toLowerCase()),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Liste
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .where('participants', arrayContains: myUid)
                  .orderBy('updatedAt', descending: true)
                  .limit(30)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Hata: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text("Henüz sohbetin yok."));
                }

                return ListView.builder(
                  padding: EdgeInsets.only(bottom: bottomPadding + 20),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final chatData = docs[index].data() as Map<String, dynamic>;
                    final chatId = docs[index].id;
                    final participants = List<String>.from(
                      chatData['participants'] ?? [],
                    );

                    // --- KRİTİK DÜZELTME BURADA ---
                    // ClubService 'isGroup: true' ve 'name: ...' kullanıyor
                    final isClub =
                        (chatData['isGroup'] == true) ||
                        (chatData['isClub'] == true);

                    if (isClub) {
                      // KULÜPLER İÇİN MANTIK (Doğru Alanları Kontrol Et)
                      final displayName =
                          chatData['name'] ?? chatData['clubName'] ?? 'Kulüp';
                      final photoUrl =
                          chatData['imageUrl'] ??
                          chatData['clubImage']; // ClubService henüz image koymuyor olabilir, aşağıda düzelteceğiz

                      if (_query.isNotEmpty &&
                          !displayName.toLowerCase().contains(_query)) {
                        return const SizedBox.shrink();
                      }

                      return _buildListItem(
                        context,
                        chatId,
                        displayName,
                        photoUrl,
                        true, // isClub
                        null, // otherUid yok
                      );
                    } else {
                      // KİŞİSEL SOHBET MANTIĞI
                      final otherUid = participants.firstWhere(
                        (id) => id != myUid,
                        orElse: () => '',
                      );
                      if (otherUid.isEmpty) return const SizedBox.shrink();

                      // Yeni sistemdeki titles'a bak
                      final titles = chatData['titles'] as Map?;
                      final photos = chatData['photos'] as Map?;

                      String? cachedName;
                      String? cachedPhoto;

                      if (titles != null && titles[myUid] != null) {
                        cachedName = titles[myUid]; // Senin göreceğin isim
                        cachedPhoto = photos?[myUid];
                      }

                      // Veri zaten varsa direkt göster (Hızlı)
                      if (cachedName != null) {
                        if (_query.isNotEmpty &&
                            !cachedName.toLowerCase().contains(_query)) {
                          return const SizedBox.shrink();
                        }
                        return _buildListItem(
                          context,
                          chatId,
                          cachedName,
                          cachedPhoto,
                          false,
                          otherUid,
                        );
                      }

                      // Veri yoksa (Eski Sohbetler) UserCacheService'den çek
                      return FutureBuilder(
                        future: UserCacheService.instance.getUser(otherUid),
                        builder: (context, userSnap) {
                          final user = userSnap.data;
                          final displayName = user?.displayName ?? 'Kullanıcı';
                          final photoUrl = user?.photoURL;

                          if (_query.isNotEmpty &&
                              !displayName.toLowerCase().contains(_query)) {
                            return const SizedBox.shrink();
                          }

                          return _buildListItem(
                            context,
                            chatId,
                            displayName,
                            photoUrl,
                            false,
                            otherUid,
                          );
                        },
                      );
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListItem(
    BuildContext context,
    String chatId,
    String displayName,
    String? photoUrl,
    bool isClub,
    String? otherUid,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: cs.primaryContainer,
        backgroundImage: photoUrl != null && photoUrl.isNotEmpty
            ? NetworkImage(photoUrl)
            : null,
        child: (photoUrl == null || photoUrl.isEmpty)
            ? Icon(isClub ? Icons.groups : Icons.person, color: cs.primary)
            : null,
      ),
      title: Text(displayName),
      subtitle: Text(
        isClub ? 'Kulüp Sohbeti' : 'Kişisel Sohbet',
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
      trailing: Icon(Icons.send, color: cs.primary),
      onTap: () {
        _sendMovieMessage(context, chatId, otherUid, displayName);
      },
    );
  }

  Future<void> _sendMovieMessage(
    BuildContext context,
    String chatId,
    String? otherUid,
    String chatName,
  ) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    try {
      final text = "🎬 Film önerisi: ${widget.movieTitle}";

      final movieData = {
        'title': widget.movieTitle,
        'poster': widget.moviePoster,
        if (widget.tmdbId != null) 'tmdbId': widget.tmdbId,
        if (widget.overview != null) 'overview': widget.overview,
        if (widget.docId != null) 'id': widget.docId,
      };

      // Kulübe gönderirken otherUid boş gider
      await ChatService.instance.send(
        chatId,
        myUid,
        text,
        otherUid: otherUid ?? '',
        movie: movieData,
      );

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$chatName grubuna gönderildi.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata oluştu: $e')));
      }
    }
  }
}
