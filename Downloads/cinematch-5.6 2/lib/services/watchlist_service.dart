import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/widgets/watchlist_wheel.dart'; // WatchlistMovie tanımı için
import 'package:fluttergirdi/screens/profilescreen.dart'; // UserShelfCache için

class WatchlistService {
  WatchlistService._();
  static final WatchlistService instance = WatchlistService._();
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  // Normalleştirme (Küçük harf ve trim)
  static String _norm(String s) => s.toLowerCase().trim();

  // Herhangi bir QuerySnapshot'tan film verilerini güvenli bir şekilde ayıklayan yardımcı fonksiyon
  void _processSnapshot(QuerySnapshot qs, List<Map<String, dynamic>> res) {
    for (final d in qs.docs) {
      final m = d.data() as Map<String, dynamic>?;
      if (m == null) continue;
      
      final title = (m['title'] ?? m['name'] ?? '').toString();
      final poster = (m['poster'] ?? m['posterUrl'] ?? m['image'] ?? '').toString();
      // YENİ: ID'yi de ayıklıyoruz
      final id = (m['id'] ?? m['tmdbId'] ?? '').toString();
      
      if (title.isNotEmpty) {
        res.add({'title': title, 'poster': poster, 'id': id});
      }
    }
  }

 /// Kullanıcının Watchlist verilerini doğru konumdan (watchlistKeys) çeker
  Future<List<Map<String, dynamic>>> _fetchUserWatchlist(String uid) async {
    final res = <Map<String, dynamic>>[];
    
    try {
      // 1. Kullanıcının ana dokümanını çek
      final userDoc = await _fs.collection('users').doc(uid).get();
      
      if (userDoc.exists) {
        final data = userDoc.data() ?? {};
        
        // 2. watchlistKeys dizisini al (Profil ekranında buraya kaydediliyor)
        final keys = List<dynamic>.from(data['watchlistKeys'] ?? [])
            .map((e) => e.toString())
            .where((k) => k.isNotEmpty)
            .toList();
            
        // 3. Her bir ID (key) için catalog_films'den filmin isim ve posterini çek
        if (keys.isNotEmpty) {
          // Future.wait ile hepsini aynı anda hızlıca çekiyoruz
          final futures = keys.map((k) async {
            try {
              final filmDoc = await _fs.collection('catalog_films').doc(k).get();
              if (filmDoc.exists) {
                final filmData = filmDoc.data() ?? {};
                return {
                  'title': (filmData['title'] ?? filmData['name'] ?? '').toString(),
                  'poster': (filmData['poster'] ?? filmData['posterUrl'] ?? filmData['image'] ?? '').toString(),
                  'id': (filmData['tmdbId'] ?? filmData['id'] ?? k).toString(),
                };
              }
            } catch (_) {}
            return null;
          });
          
          final results = await Future.wait(futures);
          
          // Gelen sonuçları listeye ekle
          for (final r in results) {
            if (r != null && (r['title'] ?? '').toString().isNotEmpty) {
              res.add(r);
            }
          }
        }
      }
    } catch (e) {
      print('WATCHLIST ÇEKME HATASI ($uid): $e');
    }

    // (Eski sistemde kalmış veriler varsa diye eski sorguları da yedek olarak tutuyoruz)
    try {
      final qs = await _fs.collection('users').doc(uid).collection('watchlist').get();
      _processSnapshot(qs, res);
    } catch (_) {}

    // Filmleri tekilleştir ve poster varsa koru
    final byKey = <String, Map<String, dynamic>>{};
    for (final m in res) {
      final key = _norm((m['title'] ?? '').toString());
      if (key.isEmpty) continue;
      
      if (!byKey.containsKey(key)) {
        byKey[key] = m;
      } else {
        final hasPoster = ((byKey[key]!['poster'] ?? '').toString()).isNotEmpty;
        final newPoster = ((m['poster'] ?? '').toString()).isNotEmpty;
        if (!hasPoster && newPoster) {
          byKey[key] = m;
        }
      }
    }
    
    return byKey.values.toList();
  }

  Future<List<WatchlistMovie>> loadSharedWatchlist(
      String myUid, String otherUid) async {
    
    // 1. Verileri Çek
    List<Map<String, dynamic>> listA = await _fetchUserWatchlist(myUid);
    final listB = await _fetchUserWatchlist(otherUid);

    // Kendi listemiz için Cache Fallback
    if (listA.isEmpty && UserShelfCache.watchlist.isNotEmpty) {
      final cachedMovies = UserShelfCache.watchlist.map((m) {
        return {
          'title': (m['title'] ?? '').toString(),
          'poster': (m['poster'] ?? '').toString(),
          'id': (m['id'] ?? m['tmdbId'] ?? '').toString(),
        };
      }).toList();
      listA.addAll(cachedMovies.where((m) => (m['title'] ?? '').isNotEmpty));
    }

    // --- 🚨 HATA AYIKLAMA (DEBUG) LOGLARI ---
    print('=== ÇARK DEBUG BAŞLADI ===');
    print('A (Benim) Liste Boyutu: ${listA.length}');
    print('B (Karşı Taraf) Liste Boyutu: ${listB.length}');

    // 2. Eşleştirme Hazırlığı
    final setB_ids = listB.map((m) => (m['id'] ?? '').toString()).where((id) => id.isNotEmpty).toSet();
    final setB_titles = listB.map((m) => _norm((m['title'] ?? '').toString())).where((key) => key.isNotEmpty).toSet(); 
        
    final out = <WatchlistMovie>[];
    final addedIds = <String>{}; 

    // 3. Eşleştirme İşlemi
    for (final m in listA) {
      final t = (m['title'] ?? '').toString();
      final id = (m['id'] ?? '').toString();
      if (t.isEmpty) continue;
      
      bool isMatch = false;
      if (id.isNotEmpty && setB_ids.contains(id)) {
        isMatch = true;
      } else if (setB_titles.contains(_norm(t))) {
        isMatch = true;
      }

      if (isMatch && !addedIds.contains(id.isNotEmpty ? id : _norm(t))) {
        out.add(
          WatchlistMovie(
            title: t,
            posterUrl: (m['poster'] ?? m['posterUrl'] ?? '').toString(),
            id: id, 
          ),
        );
        addedIds.add(id.isNotEmpty ? id : _norm(t));
      }
    }
    
    print('Bulunan ORTAK Film Sayısı: ${out.length}');
    if (out.isNotEmpty) {
      print('Ortak Filmler: ${out.map((e) => e.title).toList()}');
    }

    // 4. FALLBACK: Ortak film yoksa karma liste oluştur
    if (out.isEmpty) {
      print('⚠️ Ortak film YOK! 10+10 Karma listeye geçiliyor...');
      if (listA.isEmpty && listB.isEmpty) return [];

      final fallbackList = <WatchlistMovie>[];
      final seenTitles = <String>{};

      listA.shuffle();
      listB.shuffle();

      int countA = 0;
      for (final m in listA) {
        if (countA >= 10) break;
        final t = (m['title'] ?? '').toString();
        if (t.isEmpty) continue;
        if (seenTitles.add(_norm(t))) { 
          fallbackList.add(WatchlistMovie(title: t, posterUrl: (m['poster'] ?? m['posterUrl'] ?? '').toString(), id: (m['id'] ?? '').toString()));
          countA++;
        }
      }

      int countB = 0;
      for (final m in listB) {
        if (countB >= 10) break;
        final t = (m['title'] ?? '').toString();
        if (t.isEmpty) continue;
        if (seenTitles.add(_norm(t))) { 
          fallbackList.add(WatchlistMovie(title: t, posterUrl: (m['poster'] ?? m['posterUrl'] ?? '').toString(), id: (m['id'] ?? '').toString()));
          countB++;
        }
      }

      fallbackList.shuffle();
      return fallbackList;
    }
    
    return out;
  }
}