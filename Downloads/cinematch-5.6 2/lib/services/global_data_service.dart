import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/services/match_service.dart' as global_match;
import 'package:fluttergirdi/services/message_avatar_cache_service.dart';
import 'package:fluttergirdi/services/shelf_state_cache.dart';
import 'package:fluttergirdi/services/streak_service.dart';
import 'package:fluttergirdi/services/user_cache_service.dart';

class GlobalDataService {
  static final GlobalDataService instance = GlobalDataService._internal();
  GlobalDataService._internal();

  Map<String, dynamic>? myProfileData;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? myChats;
  List<global_match.MatchResult>? myMatches;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? myFeed;

  StreamSubscription? _profileSub;
  StreamSubscription? _chatSub;
  StreamSubscription? _matchSub;
  StreamSubscription? _feedSub;

  Completer<void>? _profileReady;
  Future<void> get profileReady => _profileReady?.future ?? Future.value();
  Completer<void>? _chatsReady;
  Future<void> get chatsReady => _chatsReady?.future ?? Future.value();

  void startPreloading() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _profileReady ??= Completer<void>();
    _chatsReady ??= Completer<void>();

    // 1. Profil + ShelfStateCache + StreakService
    _profileSub ??= FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
          if (!snap.exists) return;
          final data = snap.data()!;
          myProfileData = data;
          ShelfStateCache.instance.updateAll(uid, data);
          StreakService.instance.applyProfileData(data);
          if (_profileReady != null && !_profileReady!.isCompleted) {
            _profileReady!.complete();
          }
        });

    // 2. Sohbetler — gelince kullanıcıları UserCacheService'e ısıt
    _chatSub ??= FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .listen((snap) async {
          myChats = snap.docs;
          await _prewarmUsersFromChats(uid, snap.docs);
          await MessageAvatarCacheService.instance.preloadChats(
            uid,
            snap.docs.map((doc) => doc.data()),
          );
          if (_chatsReady != null && !_chatsReady!.isCompleted) {
            _chatsReady!.complete();
          }
        });

    // 3. Eşleşmeler
    _matchSub ??= global_match.MatchService.instance
        .findMatchesStream(uid)
        .listen((results) => myMatches = results);

    // 4. Feed
    _feedSub ??= FirebaseFirestore.instance
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(15)
        .snapshots()
        .listen((snap) => myFeed = snap.docs);
  }

  /// Chat listesindeki karşı taraf uid'lerini UserCacheService'e önceden yükle.
  /// titles/photos denormalize verisi varsa Firestore çağrısı bile yapmaz.
  Future<void> _prewarmUsersFromChats(
    String myUid,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final uidsToFetch = <String>[];

    for (final doc in docs) {
      final data = doc.data();
      if (data['isGroup'] == true || data['isClub'] == true) continue;

      final parts = List<String>.from(data['participants'] ?? []);
      final otherUid = parts.firstWhere((id) => id != myUid, orElse: () => '');
      if (otherUid.isEmpty) continue;
      if (UserCacheService.instance.getFromCache(otherUid) != null) continue;

      final titles = data['titles'] as Map?;
      final photos = data['photos'] as Map?;
      final name = titles?[myUid] as String?;
      final photo = photos?[myUid] as String?;

      if (name != null && name.isNotEmpty) {
        // Denormalize veri var — direkt cache'e yaz, Firestore çağrısı yok
        UserCacheService.instance.injectToCache(
          uid: otherUid,
          displayName: name,
          photoURL: photo ?? '',
        );
      } else {
        uidsToFetch.add(otherUid);
      }
    }

    if (uidsToFetch.isNotEmpty) {
      await UserCacheService.instance.fetchUsers(uidsToFetch);
    }
  }

  void stopPreloading() {
    _profileSub?.cancel();
    _profileSub = null;
    _chatSub?.cancel();
    _chatSub = null;
    _matchSub?.cancel();
    _matchSub = null;
    _feedSub?.cancel();
    _feedSub = null;
    myProfileData = null;
    myChats = null;
    myMatches = null;
    myFeed = null;
    _profileReady = null;
    _chatsReady = null;
  }
}
