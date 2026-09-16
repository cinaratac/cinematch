import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/services/watchlist_service.dart';
import 'package:fluttergirdi/screens/profilescreen.dart'; // UserShelfCache için
import 'package:fluttergirdi/widgets/watchlist_wheel.dart';
import 'package:fluttergirdi/widgets/poster_image.dart'; // EKLENDİ: PosterImage
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

// --- FİLM SEÇİCİ ---
class FilmPickerSheet extends StatelessWidget {
  const FilmPickerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Filmlerim',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Divider(height: 16),
          Expanded(
            child: Builder(
              builder: (context) {
                final merged = <Map<String, String>>[
                  ...UserShelfCache.fiveStar,
                  ...UserShelfCache.favorites,
                  ...UserShelfCache.watchlist,
                  ...UserShelfCache.disliked,
                ];
                final seen = <String>{};
                final items = <Map<String, String>>[];
                for (final m in merged) {
                  final t = (m['title'] ?? '').trim();
                  if (t.isNotEmpty && seen.add(t.toLowerCase())) {
                    items.add({
                      'title': t,
                      'poster': (m['poster'] ?? '').toString(),
                      'id': (m['id'] ?? m['tmdbId'] ?? '').toString(),
                    });
                  }
                }
                if (items.isEmpty)
                  return const Center(
                    child: Text(
                      'Listen boş. Profilinden senkronize et.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: items.length,
                  separatorBuilder: (_, i) =>
                      const Divider(indent: 16, endIndent: 16),
                  itemBuilder: (_, i) => ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.zero,
                      // --- KENDİ POSTERIMAGE WIDGET'INIZ KULLANILDI ---
                      child: items[i]['poster']!.isNotEmpty
                          ? PosterImage(
                              posterUrl: items[i]['poster']!,
                              title: items[i]['title'],
                              tmdbId: int.tryParse(items[i]['id'] ?? ''),
                              width: 40,
                              height: 60,
                              fit: BoxFit.cover,
                            )
                          : const Icon(Icons.movie),
                    ),
                    title: Text(items[i]['title']!),
                    onTap: () => Navigator.pop(context, items[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- WATCHLIST ÇARKI ---
class WatchlistWheelSheet extends StatefulWidget {
  final String chatId;
  final String myUid;
  final String otherUid;
  const WatchlistWheelSheet({
    super.key,
    required this.chatId,
    required this.myUid,
    required this.otherUid,
  });

  @override
  State<WatchlistWheelSheet> createState() => _WatchlistWheelSheetState();
}

class _WatchlistWheelSheetState extends State<WatchlistWheelSheet> {
  late Future<List<WatchlistMovie>> _loader;

  @override
  void initState() {
    super.initState();
    _loader = WatchlistService.instance.loadSharedWatchlist(
      widget.myUid,
      widget.otherUid,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      height: MediaQuery.of(context).size.height * 0.9,
      child: FutureBuilder<List<WatchlistMovie>>(
        future: _loader,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());

          final items = snap.data ?? [];

          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'İkinizin de watchlistinde film bulunmuyor.\nÇarkı kullanabilmek için önce listenize film eklemelisiniz.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                ),
              ),
            );
          }

          return Column(
            children: [
              const SizedBox(height: 20),
              Text(
                'Watchlist Çarkı',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Expanded(
                child: Center(
                  child: WatchlistWheel(
                    items: items,
                    size: 340,
                    onChosen: (m) async {
                      final send = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => Dialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          backgroundColor: Theme.of(ctx).colorScheme.surface,
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (m.posterUrl != null &&
                                    m.posterUrl!.isNotEmpty)
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 10,
                                          offset: const Offset(0, 5),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.zero,
                                      // --- KENDİ POSTERIMAGE WIDGET'INIZ KULLANILDI ---
                                      child: PosterImage(
                                        posterUrl: m.posterUrl,
                                        title: m.title,
                                        tmdbId: int.tryParse(m.id ?? ''),
                                        width: 130,
                                        height: 190,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    width: 130,
                                    height: 190,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.movie,
                                      size: 60,
                                      color: Colors.grey,
                                    ),
                                  ),
                                const SizedBox(height: 20),
                                Text(
                                  m.title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Bu filmi sohbete göndermek istiyor musunuz?',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Theme.of(
                                      ctx,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                        ),
                                        child: const Text('İptal'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF2E7D32,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                        ),
                                        child: const Text('Gönder'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );

                      // GÖNDER'E BASILDIYSA:
                      if (send == true && mounted) {
                        Navigator.pop(
                          context,
                        ); // Anında ekranı kapat ve sohbete dön

                        String finalId = m.id ?? '';
                        String finalPoster = m.posterUrl ?? '';

                        // --- KÖKTEN ÇÖZÜM: LETTERBOXD LİNKİNİ TMDB LİNKİYLE DEĞİŞTİR ---
                        try {
                          int? foundTmdbId;

                          // 1. Önce kendi veritabanımızdan temiz bir poster arayalım
                          if (finalId.isNotEmpty) {
                            final doc = await FirebaseFirestore.instance
                                .collection('catalog_films')
                                .doc(finalId)
                                .get();
                            if (doc.exists && doc.data() != null) {
                              if (doc.data()!['tmdbId'] != null) {
                                foundTmdbId = (doc.data()!['tmdbId'] as num)
                                    .toInt();
                              }
                              // Eğer veritabanında sağlam bir poster varsa onu al
                              final p =
                                  doc.data()!['poster'] ??
                                  doc.data()!['posterUrl'] ??
                                  doc.data()!['image'];
                              if (p != null &&
                                  p.toString().isNotEmpty &&
                                  !p.toString().contains('ltrbxd.com')) {
                                finalPoster = p.toString();
                              }
                            }
                          }

                          // 2. Bulamadıysak veya poster hala letterboxd ise TMDB'den anlık çekelim
                          if ((foundTmdbId == null ||
                                  finalPoster.contains('ltrbxd.com')) &&
                              m.title.isNotEmpty) {
                            final res = await FirebaseFunctions.instance
                                .httpsCallable('searchMovies')
                                .call({'query': m.title, 'page': 1});
                            final data = Map<String, dynamic>.from(
                              res.data as Map,
                            );
                            final results = data['results'] as List?;
                            if (results != null && results.isNotEmpty) {
                              final firstMovie = Map<String, dynamic>.from(
                                results.first as Map,
                              );
                              foundTmdbId = (firstMovie['id'] as num).toInt();
                              if (firstMovie['poster_path'] != null) {
                                // Orijinal TMDB poster linkini oluştur
                                finalPoster =
                                    'https://image.tmdb.org/t/p/w500${firstMovie['poster_path']}';
                              }
                            }
                          }
                          if (foundTmdbId != null)
                            finalId = foundTmdbId.toString();
                        } catch (_) {}

                        // Mesajı sohbete ilet
                        ChatService.instance.send(
                          widget.chatId,
                          widget.myUid,
                          '🎯 Çark seçimi: ${m.title}',
                          otherUid: widget.otherUid,
                          movie: {
                            'title': m.title,
                            // ARTIK SOHBETE KESİNLİKLE TMDB LİNKİ GİDECEK
                            'poster': finalPoster,
                            'id': finalId,
                          },
                        );
                      }
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
