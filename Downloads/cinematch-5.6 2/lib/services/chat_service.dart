import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:fluttergirdi/services/notification_service.dart';

class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();
  factory ChatService() => instance;
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  static const List<String> supportedReactions = [
    '❤️',
    '👍',
    '😂',
    '😮',
    '😢',
    '🙏',
  ];

  String chatIdFor(String a, String b) {
    final s = [a, b]..sort();
    return '${s[0]}_${s[1]}';
  }

  // GÜNCELLENDİ: Sohbet oluştururken veya açarken isimleri/resimleri de kaydediyoruz (Denormalizasyon)
  Future<String> getOrCreateChat(String uidA, String uidB) async {
    final id = chatIdFor(uidA, uidB);
    final chatRef = _fs.collection('chats').doc(id);

    final chatSnap = await chatRef.get();
    if (!chatSnap.exists) {
      // Kullanıcı bilgilerini çekip sohbet dokümanına gömüyoruz
      final userA = await _fs.collection('users').doc(uidA).get();
      final userB = await _fs.collection('users').doc(uidB).get();

      final dataA = userA.data() ?? {};
      final dataB = userB.data() ?? {};

      await chatRef.set({
        'participants': FieldValue.arrayUnion([uidA, uidB]),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        // Denormalize Veri:
        'titles': {
          uidA:
              dataB['displayName'] ??
              dataB['username'] ??
              'Kullanıcı', // A, B'yi ne diye görecek?
          uidB:
              dataA['displayName'] ??
              dataA['username'] ??
              'Kullanıcı', // B, A'yı ne diye görecek?
        },
        'photos': {
          uidA: dataB['photoURL'] ?? '', // A, B'nin hangi fotosunu görecek?
          uidB: dataA['photoURL'] ?? '', // B, A'nın hangi fotosunu görecek?
        },
      }, SetOptions(merge: true));
    }
    return id;
  }

  String getChatId(String uidA, String uidB) {
    return chatIdFor(uidA, uidB);
  }

  Future<void> sendEventMessage(
    String chatId,
    String myUid,
    Map<String, dynamic> eventData,
  ) async {
    await send(
      chatId,
      myUid,
      "📅 Yeni Etkinlik: ${eventData['title']}", // Bildirimlerde görünecek metin
      otherUid: "", // Gruplarda genellikle boştur ama gerekirse doldurulabilir
      customType: 'event',
      customData: eventData,
    );
  }

  // --- YENİ: Anket Mesajı Gönderme ---
  Future<void> sendPollMessage(
    String chatId,
    String myUid,
    Map<String, dynamic> pollData,
  ) async {
    await send(
      chatId,
      myUid,
      "📊 Yeni Anket: ${pollData['question']}",
      otherUid: "",
      customType: 'poll',
      customData: pollData,
    );
  }

  // GÜNCELLENDİ: Mesaj atarken de güncel profil bilgilerini basıyoruz
  Future<void> send(
    String chatId,
    String fromUid,
    String text, {
    required String otherUid,
    Map<String, dynamic>? movie,
    String? imageUrl,
    String? customType,
    Map<String, dynamic>? customData,
    Map<String, dynamic>? replyTo,
  }) async {
    final chatRef = _fs.collection('chats').doc(chatId);
    final msgRef = chatRef.collection('messages').doc();

    final batch = _fs.batch();
    final trimmed = text.trim();

    // 1. Mesaj Verisi
    final Map<String, dynamic> msgData = {
      'authorId': fromUid,
      'from': fromUid,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (replyTo != null && replyTo.isNotEmpty) {
      msgData['replyTo'] = Map<String, dynamic>.from(replyTo);
    }

    if (movie != null) {
      msgData['type'] = 'movie';
      msgData['movie'] = movie;
    } else if (imageUrl != null) {
      msgData['type'] = 'image';
      msgData['imageUrl'] = imageUrl;
    } else if (customType != null) {
      msgData['type'] = customType;
      if (customData != null) {
        msgData[customType] = customData;
      }
    }

    batch.set(msgRef, msgData);

    // 2. Sohbet Verisi
    String lastMsgText = trimmed;
    if (lastMsgText.isEmpty) {
      if (movie != null)
        lastMsgText = '🎬 Film paylaştı';
      else if (imageUrl != null)
        lastMsgText = '📷 Fotoğraf';
      else if (customType == 'event')
        lastMsgText = '📅 Etkinlik';
      else if (customType == 'poll')
        lastMsgText = '📊 Anket';
    }

    final me = _auth.currentUser;

    // DİKKAT: .set() içinde nokta notasyonu kullanmıyoruz! Sadece temel alanlar.
    final Map<String, dynamic> chatUpdate = {
      'lastMessage': lastMsgText,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageAuthorId': fromUid,
      'updatedAt': FieldValue.serverTimestamp(),
      'participants': FieldValue.arrayUnion([fromUid, otherUid]),
    };

    batch.set(chatRef, chatUpdate, SetOptions(merge: true));
    await batch.commit();

    // 3. Nokta notasyonu (İç içe map güncellemeleri) sadece update() ile güvenli çalışır:
    final Map<String, dynamic> nestedUpdates = {
      'hiddenFor.$fromUid':
          FieldValue.delete(), // Mesaj atan kişi sildiyse sohbet tekrar görünsün
    };

    if (otherUid.isNotEmpty) {
      nestedUpdates['unreadCounts.$otherUid'] = FieldValue.increment(1);
      nestedUpdates['hiddenFor.$otherUid'] =
          FieldValue.delete(); // Karşı taraf sildiyse ona da tekrar görünsün

      if (me != null) {
        nestedUpdates['titles.$otherUid'] = me.displayName ?? 'Kullanıcı';
        nestedUpdates['photos.$otherUid'] = me.photoURL ?? '';
      }
    }

    try {
      await chatRef.update(nestedUpdates);
    } catch (_) {}

    if (otherUid.isNotEmpty) {
      try {
        final likes = _fs.collection('likes');
        var qs = await likes
            .where('a', isEqualTo: fromUid)
            .where('b', isEqualTo: otherUid)
            .limit(1)
            .get();
        if (qs.docs.isEmpty) {
          qs = await likes
              .where('a', isEqualTo: otherUid)
              .where('b', isEqualTo: fromUid)
              .limit(1)
              .get();
        }
        if (qs.docs.isNotEmpty) {
          await qs.docs.first.reference.set({
            'aSeen': true,
            'bSeen': true,
            'lastInteractedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (_) {}
    }
  }

  Future<void> markAsRead(String chatId, String uid) async {
    final chatRef = _fs.collection('chats').doc(chatId);

    try {
      await chatRef.update({'unreadCounts.$uid': 0});
    } catch (_) {}

    // Okundu bilgisini güncelle...
    final readRef = chatRef.collection('reads').doc(uid);
    try {
      await readRef.set({
        'uid': uid,
        'lastReadAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      // Eski/bozuk bir sohbet belgesinde participants alanı yoksa güvenlik
      // kuralı yazımı reddedebilir. Fire-and-forget çağrıyı uygulama hatasına
      // dönüştürmeden okunmamış sayacı çalıştırmaya devam et.
      debugPrint('Sohbet okundu bilgisi yazılamadı: $error');
    }
  }

  /// Bir kullanıcının mesaj başına tek reaksiyonunu tek yazmayla günceller.
  /// Seçili emojiye tekrar basılırsa reaksiyon kaldırılır. Ek belge okuması
  /// yapılmaz; UI mevcut snapshot'tan seçili durumu gönderir.
  Future<void> toggleReaction({
    required String chatId,
    required String messageId,
    required String userId,
    required String emoji,
    required bool remove,
  }) async {
    if (chatId.isEmpty || messageId.isEmpty || userId.isEmpty) return;
    if (!supportedReactions.contains(emoji)) return;

    final updates = <Object, Object?>{};
    for (final supportedEmoji in supportedReactions) {
      updates[FieldPath([
        'reactions',
        supportedEmoji,
      ])] = supportedEmoji == emoji && !remove
          ? FieldValue.arrayUnion([userId])
          : FieldValue.arrayRemove([userId]);
    }

    await _fs
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update(updates);
  }

  // --- YENİ EKLENEN: TESLİM EDİLDİ SİSTEMİ ---
  // Mesaj sayısından bağımsız, sohbet dokümanında TEK bir alanı güncelliyor.
  // Bu yüzden 100 mesaj da gelse 1000 mesaj da gelse maliyet sabittir.
  Future<void> markDelivered(String chatId, String uid) async {
    if (chatId.isEmpty || uid.isEmpty) return;
    try {
      await _fs.collection('chats').doc(chatId).update({
        'deliveredUpTo.$uid': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Sohbet dokümanı henüz yoksa veya erişim yoksa sessizce geç
    }
  }

  /// Karşı tarafın sohbeti en son ne zaman okuduğunu dinler (mavi çift tik için).
  Stream<DateTime?> otherReadAtStream(String chatId, String otherUid) {
    if (chatId.isEmpty || otherUid.isEmpty) {
      return Stream.value(null);
    }
    return _fs
        .collection('chats')
        .doc(chatId)
        .collection('reads')
        .doc(otherUid)
        .snapshots()
        .map((snap) => (snap.data()?['lastReadAt'] as Timestamp?)?.toDate());
  }

  /// Karşı tarafın cihazına en son hangi ana kadar mesaj ulaştığını dinler
  /// (gri çift tik için). Sohbet dokümanındaki tek bir alanı dinlediği için ucuzdur.
  Stream<DateTime?> otherDeliveredAtStream(String chatId, String otherUid) {
    if (chatId.isEmpty || otherUid.isEmpty) {
      return Stream.value(null);
    }
    return _fs.collection('chats').doc(chatId).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      final map = data['deliveredUpTo'];
      if (map is Map) {
        final ts = map[otherUid];
        if (ts is Timestamp) return ts.toDate();
      }
      return null;
    });
  }

  Future<void> setTyping(String chatId, String uid, bool isTyping) async {
    if (chatId.isEmpty || uid.isEmpty) return;

    final chatRef = _fs.collection('chats').doc(chatId);
    final updates = <String, dynamic>{};

    if (isTyping) {
      updates['typing.$uid'] = true;
      updates['typingUpdatedAt.$uid'] = FieldValue.serverTimestamp();
    } else {
      updates['typing.$uid'] = FieldValue.delete();
      updates['typingUpdatedAt.$uid'] = FieldValue.delete();
    }

    try {
      await chatRef.update(updates);
    } catch (_) {}
  }

  Future<void> hideChatFor(String chatId, String uid) async {
    if (uid.isEmpty) return;
    try {
      await _fs.collection('chats').doc(chatId).update({
        'hiddenFor.$uid': true,
        'unreadCounts.$uid':
            0, // Sadece bu kullanıcının okunmamış sayısını sıfırla
      });
    } catch (e) {
      // Belge henüz yoksa oluşabilecek hatayı yoksayıyoruz
    }
  }

  Stream<int> unreadCountForChat(String chatId, String myUid) {
    return _fs.collection('chats').doc(chatId).snapshots().map((chatSnap) {
      final data = chatSnap.data();
      if (data == null) return 0;
      final counts = data['unreadCounts'];
      if (counts is Map) {
        final v = counts[myUid];
        if (v is num && v > 0) return v.toInt();
      }
      return 0;
    });
  }

  // --- KRİTİK OPTİMİZASYON ---
  // Eskiden tüm sohbetleri dinliyordu. Şimdi sadece kullanıcının kendi profilindeki tek bir alanı dinliyor.
  // Bu alan Cloud Functions tarafından güncelleniyor.
  Stream<int> totalUnreadMessagesFor(String myUid) {
    return _fs.collection('users').doc(myUid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) return 0;
      return (data['totalUnreadCount'] as num?)?.toInt() ?? 0;
    });
  }
  // ---------------------------

  Future<void> startChatNotifications() async {
    await NotificationService.I.start();
  }

  Future<void> stopChatNotifications() async {
    await NotificationService.I.dispose();
  }

  Future<void> deleteIfEmpty(String chatId) async {
    // Boş temizleme mantığı aynen kalabilir
    try {
      final chatRef = _fs.collection('chats').doc(chatId);
      final msgSnap = await chatRef.collection('messages').limit(1).get();
      if (msgSnap.docs.isEmpty) {
        await chatRef.delete();
      }
    } catch (_) {}
  }
}
