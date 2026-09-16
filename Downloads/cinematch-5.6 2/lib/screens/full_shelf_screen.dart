import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/catalog_service.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/widgets/movie_action_helper.dart';
import 'package:fluttergirdi/models/shelf_target.dart';

class FullShelfScreen extends StatefulWidget {
  final String title;
  final List<String> filmKeys;
  final ShelfTarget? target;

  const FullShelfScreen({
    super.key,
    required this.title,
    required this.filmKeys,
    this.target,
  });

  @override
  State<FullShelfScreen> createState() => _FullShelfScreenState();
}

class _FullShelfScreenState extends State<FullShelfScreen> {
  // Yüklenen filmleri tutar
  final List<Map<String, dynamic>> _loadedFilms = [];

  // Scroll kontrolcüsü
  final ScrollController _scrollController = ScrollController();

  // Durum değişkenleri
  bool _isLoading = false;
  bool _hasMore = true;

  // Her seferinde kaç film çekilecek? (3'e bölünebilen bir sayı seçtik)
  final int _batchSize = 21;

  @override
  void initState() {
    super.initState();
    // İlk grubu yükle
    _loadNextBatch();

    // Scroll dinleyicisi ekle
    _scrollController.addListener(() {
      // Listenin sonuna 200 piksel kala yeni veriyi yüklemeye başla
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _loadNextBatch();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadNextBatch() async {
    // Zaten yükleniyorsa veya yüklenecek veri kalmadıysa işlem yapma
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Şimdiki konumumuz (listenin neresindeyiz?)
      final int startIndex = _loadedFilms.length;

      // Tüm liste bitti mi kontrol et
      if (startIndex >= widget.filmKeys.length) {
        setState(() {
          _isLoading = false;
          _hasMore = false;
        });
        return;
      }

      // Bir sonraki bitiş noktasını hesapla (Listenin dışına taşmamalı)
      final int endIndex = (startIndex + _batchSize > widget.filmKeys.length)
          ? widget.filmKeys.length
          : startIndex + _batchSize;

      // Sadece bu aralıktaki ID'leri al (Slice işlemi)
      final List<String> keysToFetch = widget.filmKeys.sublist(
        startIndex,
        endIndex,
      );

      // Servisten sadece bu ID'leri çek
      final List<Map<String, dynamic>> fetchedFilms = await CatalogService()
          .getFilmsByKeys(keysToFetch);

      // --- SIRALAMA DÜZELTME ---
      // Firestore 'whereIn' sorgusu bazen ID sırasını karıştırabilir.
      // Bizim 'keysToFetch' listemizdeki sıraya göre yeniden dizelim.
      final List<Map<String, dynamic>> sortedFilms = [];
      for (var key in keysToFetch) {
        // canonicalKey veya docId üzerinden eşleşme arıyoruz
        final match = fetchedFilms.firstWhere(
          (m) =>
              (m['canonicalKey'] == key || m['id'] == key || m['docId'] == key),
          orElse: () => {},
        );
        if (match.isNotEmpty) {
          sortedFilms.add(match);
        }
      }

      if (mounted) {
        setState(() {
          _loadedFilms.addAll(sortedFilms);
          _isLoading = false;
          // Eğer çektiğimiz miktar batch'ten azsa liste bitmiş demektir
          if (keysToFetch.length < _batchSize ||
              endIndex == widget.filmKeys.length) {
            _hasMore = false;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: _loadedFilms.isEmpty && _isLoading
          ? const Center(child: CircularProgressIndicator())
          : widget.filmKeys.isEmpty
          ? const Center(child: Text("Liste boş."))
          : Column(
              children: [
                Expanded(
                  child: GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.67, // Poster oranı
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: _loadedFilms.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _loadedFilms.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      final movie = _loadedFilms[index];
                      final posterUrl =
                          movie['posterUrl'] ?? movie['poster'] ?? '';
                      final title = movie['title'] ?? '';

                      // --- DÜZELTİLEN GÜVENLİ VERİ TİPİ DÖNÜŞTÜRÜCÜ ---
                      // Eğer ID bozuksa 0 verme, null bırak ki isim üzerinden önbelleğe alsın.
                      final rawTmdbId = movie['tmdbId'];
                      int? tmdbId;
                      if (rawTmdbId is int) {
                        tmdbId = rawTmdbId;
                      } else if (rawTmdbId is num) {
                        tmdbId = rawTmdbId.toInt();
                      } else if (rawTmdbId is String) {
                        tmdbId = int.tryParse(rawTmdbId);
                      }
                      if (tmdbId == 0) tmdbId = null;

                      return GestureDetector(
                        onTap: () {
                          if (widget.target == null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MovieDetailScreen(
                                  tmdbId: tmdbId ?? 0,
                                  title: title,
                                  posterUrl: posterUrl,
                                ),
                              ),
                            );
                          } else {
                            MovieActionHelper.show(
                              context,
                              title: title,
                              posterUrl: posterUrl,
                              docId: movie['docId'] ?? movie['id'],
                              tmdbId: tmdbId,
                              target: widget.target,
                              onItemDeleted: () =>
                                  setState(() => _loadedFilms.removeAt(index)),
                            );
                          }
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.zero,
                          child: PosterImage(
                            posterUrl: posterUrl,
                            title: title,
                            tmdbId: tmdbId,
                            fit: BoxFit.cover,
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
}
