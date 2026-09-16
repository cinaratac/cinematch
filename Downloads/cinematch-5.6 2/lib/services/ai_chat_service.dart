import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;

/// askAi() çağrısının sonucu: görünür metin + (varsa) önerilen film adları.
class AiAnswer {
  final String text;
  final List<String> recommendedMovies;
  const AiAnswer(this.text, this.recommendedMovies);
}

/// cinematchbotai (Flask/Python) backend'i ile konuşan servis.
///
/// Backend tarafında zaten hazır bir REST endpoint var: POST /api/chat
/// Body:   { "message": "...", "user_id": "...", "username": "..." }
/// Cevap:  { "status": "success", "bot_response": "...", "recommended_movies": [...] }
class AiChatService {
  AiChatService._();
  static final AiChatService instance = AiChatService._();

  // --- ÖNEMLİ: BURAYI KENDİ BACKEND ADRESİNLE DEĞİŞTİR ---
  // Flask uygulamasını (main.py) çalıştırdığın makinenin dışarıdan
  // erişilebilir adresi. Geliştirme sırasında ngrok kullanıyorsan
  // (main.py içindeki NGROK_URL gibi) o adresi buraya yaz. Ücretsiz
  // ngrok URL'leri her yeniden başlatmada DEĞİŞİR; kalıcı bir ortam
  // için botu bir sunucuya (Railway, Render, VPS vb.) deploy edip
  // sabit bir domain kullanman gerekir.
  static const String baseUrl = 'https://cinematchbotai.onrender.com';

  /// Firestore'daki chat dokümanlarında bot'u temsil eden sabit kullanıcı id'si.
  static const String aiUid = 'ai_cinebot';
  static const String aiName = 'CineBot AI';
  // İstersen bota bir avatar url'i ver (public/images altına koyup URL verebilirsin).
  static const String aiPhotoUrl = '';

  final _fs = FirebaseFirestore.instance;

  /// Kullanıcı ile bot arasındaki sohbetin id'si her zaman deterministik.
  String chatIdFor(String uid) => '${uid}_$aiUid';

  /// AI sohbet odasını Firestore'da yoksa oluşturur, varsa dokunmadan id döner.
  ///
  /// NOT: Bilerek ChatService.getOrCreateChat() kullanılmıyor; o metot
  /// "users" koleksiyonunda karşı tarafın profilini arıyor ama bot gerçek
  /// bir kullanıcı olmadığı için oradan veri gelmeyecek ve isim/foto boş
  /// kalacaktı. Burada bot bilgilerini doğrudan biz basıyoruz.
  Future<String> getOrCreateAiChat(String myUid) async {
    final id = chatIdFor(myUid);
    final ref = _fs.collection('chats').doc(id);
    final snap = await ref.get();

    if (!snap.exists) {
      await ref.set({
        'participants': [myUid, aiUid],
        'isAiChat': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        // Kullanıcının sohbet listesinde göreceği isim/foto:
        'titles': {myUid: aiName},
        'photos': {myUid: aiPhotoUrl},
        // Oda henüz boşken listede "Fotoğraf / Medya" gibi yanlış bir
        // önizleme görünmesin diye karşılama metni koyuyoruz.
        'lastMessage': 'Merhaba! Film önerileri için buradayım 🎬',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageAuthorId': aiUid,
      }, SetOptions(merge: true));
    }
    return id;
  }

  /// Kullanıcının mesajını backend'e gönderir, botun cevap metnini VE
  /// (varsa) önerdiği filmlerin adlarını döner. Hata durumunda kullanıcı
  /// dostu bir Türkçe metinle boş film listesi döner (exception fırlatmaz).
  ///
  /// [tasteProfile] verilirse (bkz. fetchTasteProfile), backend'e favori
  /// tür/oyuncu/yönetmen/film bilgisi de gönderilir ki AI kullanıcının
  /// zevkine göre öneri yapabilsin.
  Future<AiAnswer> askAi(
    String message, {
    required String userId,
    String username = 'flutter_user',
    Map<String, dynamic>? tasteProfile,
  }) async {
    final uri = Uri.parse('$baseUrl/api/chat');
    try {
      final body = <String, dynamic>{
        'message': message,
        'user_id': userId,
        'username': username,
      };
      if (tasteProfile != null) body.addAll(tasteProfile);

      final res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          // Render gibi ücretsiz servisler uykudan uyanırken yavaş
          // kalabiliyor, bu yüzden makul bir üst sınır veriyoruz.
          .timeout(const Duration(seconds: 60));

      if (res.statusCode != 200) {
        return AiAnswer(
          'Üzgünüm, asistana şu an ulaşamıyorum (kod: ${res.statusCode}). Birazdan tekrar dener misin?',
          const [],
        );
      }

      final data =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final answer = data['bot_response'] as String?;
      final movies =
          (data['recommended_movies'] as List?)
              ?.map((e) => e.toString())
              .where((s) => s.trim().isNotEmpty)
              .toList() ??
          const [];

      if (answer == null || answer.trim().isEmpty) {
        return AiAnswer(
          'Üzgünüm, boş bir cevap geldi, tekrar dener misin?',
          const [],
        );
      }
      return AiAnswer(answer, movies);
    } catch (_) {
      return AiAnswer(
        'Üzgünüm, asistana bağlanırken bir sorun oluştu. İnternet bağlantını kontrol edip tekrar dener misin?',
        const [],
      );
    }
  }

  /// Bir film adını TMDB'de arar, ilk sonucu (varsa) film kartı için
  /// gereken alanlarla ({id, title, poster}) döner. Bulamazsa null döner.
  Future<Map<String, dynamic>?> searchMovieOnTmdb(String title) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('callTMDB')
          .call({
            'endpoint': '/3/search/movie',
            'params': {'query': title, 'language': 'tr-TR'},
          });
      final data = Map<String, dynamic>.from(result.data as Map);
      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return null;

      final first = Map<String, dynamic>.from(results.first as Map);
      final posterPath = first['poster_path'] as String?;
      return {
        'id': (first['id'] as num).toString(),
        'title': (first['title'] ?? first['original_title'] ?? title)
            .toString(),
        'poster': (posterPath != null && posterPath.isNotEmpty)
            ? 'https://image.tmdb.org/t/p/w500$posterPath'
            : '',
      };
    } catch (_) {
      return null;
    }
  }

  /// Kullanıcının Cinematch profilindeki zevk verilerini (favori tür,
  /// oyuncu, yönetmen ve 5 yıldız/favori verdiği filmler) çeker.
  ///
  /// Bunlar AI'ya gönderilip daha isabetli, kişiselleştirilmiş öneriler
  /// yapması için kullanılacak. Hata olursa boş map döner (sohbeti bozmaz).
  Future<Map<String, dynamic>> fetchTasteProfile(String uid) async {
    try {
      final userDoc = await _fs.collection('users').doc(uid).get();
      if (!userDoc.exists) return {};
      final data = userDoc.data()!;

      List<String> extractNames(dynamic listData) {
        if (listData is! List) return [];
        return listData
            .map((e) => e is Map ? (e['name'] ?? '').toString() : e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList();
      }

      final genres = extractNames(data['favGenres']);
      final directors = extractNames(data['favDirectors']);
      final actors = extractNames(data['favActors']);

      // 5 yıldız verdiği + favorilere eklediği filmlerin başlıklarını
      // katalogdan çek (RecommendationEngine'deki mantıkla aynı).
      final keys = <String>{
        ...List<String>.from(
          data['fiveStarKeys'] ?? const [],
        ).map((e) => e.toString()),
        ...List<String>.from(
          data['favoritesKeys'] ?? const [],
        ).map((e) => e.toString()),
      }.toList();

      final movieTitles = <String>[];
      for (var i = 0; i < keys.length; i += 10) {
        final chunk = keys.sublist(
          i,
          i + 10 > keys.length ? keys.length : i + 10,
        );
        if (chunk.isEmpty) continue;
        final qs = await _fs
            .collection('catalog_films')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in qs.docs) {
          final title = doc.data()['title'] as String?;
          if (title != null && title.isNotEmpty) movieTitles.add(title);
        }
      }

      return {
        'favorite_genres': genres,
        'favorite_directors': directors,
        'favorite_actors': actors,
        'favorite_movies': movieTitles,
      };
    } catch (_) {
      return {};
    }
  }

  /// Botun cevabını mesaj koleksiyonuna yazar. [movie] verilirse (id/title/
  /// poster alanlarıyla), mesaj insan-insan sohbetlerdeki gibi tıklanabilir
  /// bir film kartı olarak Firestore'a yazılır.
  ///
  /// Bilerek ChatService.send() kullanılmıyor: o metot "gönderen ben (Firebase
  /// Auth'taki gerçek kullanıcı)" varsayımıyla chat dokümanındaki titles/foto
  /// alanlarını günceller. Bot mesajı için bunu kullanırsak, kullanıcının
  /// kendi adı yanlışlıkla "titles" alanına yazılıp botun ismini ezebilir.
  /// Bu yüzden bot mesajları için sade, kendi yazma mantığımızı kullanıyoruz.
  Future<void> sendBotMessage(
    String chatId,
    String text, {
    Map<String, dynamic>? movie,
  }) async {
    final chatRef = _fs.collection('chats').doc(chatId);
    final msgRef = chatRef.collection('messages').doc();
    final batch = _fs.batch();

    final msgData = <String, dynamic>{
      'authorId': aiUid,
      'from': aiUid,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (movie != null) {
      msgData['type'] = 'movie';
      msgData['movie'] = movie;
    }
    batch.set(msgRef, msgData);

    final lastMsgText = text.isNotEmpty
        ? text
        : (movie != null ? '🎬 ${movie['title'] ?? 'Film'} önerdi' : text);

    batch.set(chatRef, {
      'lastMessage': lastMsgText,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageAuthorId': aiUid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }
}
