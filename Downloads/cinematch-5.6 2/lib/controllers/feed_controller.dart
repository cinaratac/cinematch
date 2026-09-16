import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/feed_service.dart';
import '../services/user_cache_service.dart';
import '../services/blocking_service.dart';

class FeedController extends ChangeNotifier {
  // SINGLETON MİMARİSİ: Tüm uygulama boyunca tek bir instance olacak
  static final FeedController instance = FeedController._internal();
  FeedController._internal();

  /// Popüler ve takip akışlarının birbirini gereksiz yere yeniden çizmesini
  /// engelleyen, ayrı UI sinyalleri.
  final ValueNotifier<int> popularRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> followingRevision = ValueNotifier<int>(0);

  void _notifyPopular() {
    popularRevision.value++;
    notifyListeners();
  }

  void _notifyFollowing() {
    followingRevision.value++;
    notifyListeners();
  }

  void _notifyBoth() {
    popularRevision.value++;
    followingRevision.value++;
    notifyListeners();
  }

  bool isInitialized = false;
  Future<void>? _initializationFuture;
  Future<void>? _followingInitializationFuture;

  // --- POPÜLER AKIŞ DEĞİŞKENLERİ ---
  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = true;
  List<DocumentSnapshot<Map<String, dynamic>>> posts = [];

  // --- TAKİP EDİLENLER AKIŞI DEĞİŞKENLERİ ---
  bool isFollowingLoading = true;
  bool isFollowingInitialized = false;
  List<DocumentSnapshot<Map<String, dynamic>>> followingPosts = [];

  // Etkileşim verileri (İki akışta da ortak kullanılır)
  Set<String> myLikedPostIds = {};
  Set<String> myFollowingUserIds = {};

  Set<String> _blockedUserIds = {};
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;

  // ==========================================
  // 1. POPÜLER AKIŞ METOTLARI
  // ==========================================
  Future<void> init() {
    if (isInitialized) return Future.value();
    final pending = _initializationFuture;
    if (pending != null) return pending;

    final future = _initializePopularFeed();
    _initializationFuture = future;
    return future.whenComplete(() {
      if (identical(_initializationFuture, future)) {
        _initializationFuture = null;
      }
    });
  }

  Future<void> _initializePopularFeed() async {
    isLoading = true;
    _notifyPopular();
    await _loadData(initial: true);
    isInitialized = true;
  }

  Future<void> refresh() async {
    await _loadData(initial: true);
  }

  Future<void> loadMore() async {
    if (isLoading || isLoadingMore || !hasMore || _lastDoc == null) return;
    isLoadingMore = true;
    _notifyPopular();
    await _loadData(initial: false);
  }

  Future<void> _loadData({required bool initial}) async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      QuerySnapshot<Map<String, dynamic>> postSnapshot;

      // Algoritmanın iyi çalışması ve daha iyi kıyaslama yapması için
      // 20 yerine tek seferde 40 post çekiyoruz.
      final int fetchLimit = 40;

      if (initial) {
        if (userId != null) {
          final results = await Future.wait([
            FeedService.instance.fetchInitial(limit: fetchLimit),
            FeedService.instance.fetchUserLikedPostIds(userId),
            FeedService.instance.fetchUserFollowingIds(userId),
            BlockingService.instance.getBlockedAndBlockerIds(userId),
          ]);

          postSnapshot = results[0] as QuerySnapshot<Map<String, dynamic>>;
          myLikedPostIds = results[1] as Set<String>;
          myFollowingUserIds = results[2] as Set<String>;
          _blockedUserIds = results[3] as Set<String>;
        } else {
          postSnapshot = await FeedService.instance.fetchInitial(
            limit: fetchLimit,
          );
        }
      } else {
        postSnapshot = await FeedService.instance.fetchMore(
          lastDoc: _lastDoc!,
          limit: fetchLimit,
        );
      }

      // KRONOLOJİK SON DÖKÜMANI KAYDET (ÇOK ÖNEMLİ!)
      // Sıralama yapacağımız için sayfa kaydırma (pagination) sisteminin
      // bozulmaması adına tarihe göre en sonuncu dökümanı saklıyoruz.
      if (postSnapshot.docs.isNotEmpty) {
        _lastDoc = postSnapshot.docs.last;
      }

      var newDocs = List<DocumentSnapshot<Map<String, dynamic>>>.from(
        postSnapshot.docs,
      );

      if (_blockedUserIds.isNotEmpty) {
        newDocs = newDocs.where((doc) {
          final authorId = doc.data()!['authorId'] as String?;
          return !_blockedUserIds.contains(authorId);
        }).toList();
      }

      // ==============================================================
      // YENİ: POPÜLERLİK (HOTNESS) ALGORİTMASI İLE SIRALAMA
      // ==============================================================
      newDocs.sort((a, b) {
        final dataA = a.data() ?? {};
        final dataB = b.data() ?? {};

        double scoreA = _calculateHotness(dataA);
        double scoreB = _calculateHotness(dataB);

        // Büyük olan (puanı yüksek olan) üste çıksın
        return scoreB.compareTo(scoreA);
      });
      // ==============================================================

      final authorIds = newDocs
          .map((d) => d.data()!['authorId'] as String?)
          .where((id) => id != null)
          .cast<String>()
          .toList();
      await UserCacheService.instance.fetchUsers(authorIds);

      if (initial) {
        posts = newDocs;
      } else {
        posts.addAll(newDocs);
      }

      hasMore = postSnapshot.docs.length == fetchLimit;
    } catch (e) {
      debugPrint("LoadData Error: $e");
    } finally {
      isLoading = false;
      isLoadingMore = false;
      _notifyPopular();
    }
  }

  // --- YARDIMCI FONKSİYON: POPÜLERLİK HESAPLAYICI ---
  // Bu fonksiyonu _loadData fonksiyonunun hemen altına yapıştırın.
  double _calculateHotness(Map<String, dynamic> data) {
    final likes = (data['likeCount'] ?? 0) as num;
    final replies = (data['replyCount'] ?? 0) as num;
    final createdAt = data['createdAt'] as Timestamp?;

    // 1 Beğeni = 2 Puan, 1 Yorum = 4 Puan (Yorum daha fazla etkileşim demektir)
    double score = (likes * 2.0) + (replies * 4.0);

    if (createdAt != null) {
      // Post atılalı kaç saat olmuş?
      final hoursDiff = DateTime.now().difference(createdAt.toDate()).inHours;

      // ZAMAN CEZASI: Üzerinden geçen her saat için 0.5 puan düşür.
      // Etkileşim almayan ama çok yeni olan bir post,
      // etkileşim almayan ama 10 saat önce atılmış bir postun ÜSTÜNDE çıkar.
      score -= (hoursDiff * 0.5);
    }

    return score;
  }

  // ==========================================
  // 2. TAKİP EDİLENLER AKIŞI METOTLARI
  // ==========================================
  Future<void> initFollowing() {
    if (isFollowingInitialized) return Future.value();
    final pending = _followingInitializationFuture;
    if (pending != null) return pending;

    final future = _initializeFollowingFeed();
    _followingInitializationFuture = future;
    return future.whenComplete(() {
      if (identical(_followingInitializationFuture, future)) {
        _followingInitializationFuture = null;
      }
    });
  }

  Future<void> _initializeFollowingFeed() async {
    isFollowingLoading = true;
    _notifyFollowing();
    await _loadFollowingData();
    isFollowingInitialized = true;
  }

  Future<void> refreshFollowing() async {
    await _loadFollowingData();
  }

  Future<void> _loadFollowingData() async {
    try {
      final me = FirebaseAuth.instance.currentUser?.uid;
      if (me == null) {
        followingPosts = [];
        return;
      }

      final interactionsFuture = Future.wait([
        FeedService.instance.fetchUserLikedPostIds(me),
        FeedService.instance.fetchUserFollowingIds(me),
      ]);

      final feedQs = await FirebaseFirestore.instance
          .collection('feeds')
          .doc(me)
          .collection('user_feed')
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();

      List<DocumentSnapshot<Map<String, dynamic>>> finalItems = [];

      if (feedQs.docs.isNotEmpty) {
        final postIds = feedQs.docs
            .map((d) => d.data()['postId'] as String)
            .toList();

        if (postIds.isNotEmpty) {
          List<Future<QuerySnapshot<Map<String, dynamic>>>> postFutures = [];
          for (var i = 0; i < postIds.length; i += 10) {
            final chunk = postIds.sublist(
              i,
              (i + 10 > postIds.length) ? postIds.length : i + 10,
            );
            postFutures.add(
              FirebaseFirestore.instance
                  .collection('posts')
                  .where(FieldPath.documentId, whereIn: chunk)
                  .get(),
            );
          }

          final postResults = await Future.wait(postFutures);
          for (var qs in postResults) {
            finalItems.addAll(qs.docs);
          }

          finalItems.sort((a, b) {
            final ta = (a.data()?['createdAt'] as Timestamp?)?.toDate();
            final tb = (b.data()?['createdAt'] as Timestamp?)?.toDate();
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });
        }
      } else {
        final followingQs = await FirebaseFirestore.instance
            .collection('users')
            .doc(me)
            .collection('following')
            .limit(50)
            .get();
        final uids = followingQs.docs.map((d) => d.id).toList();

        if (uids.isNotEmpty) {
          List<Future<QuerySnapshot<Map<String, dynamic>>>> futures = [];
          for (var i = 0; i < uids.length; i += 10) {
            final chunk = uids.sublist(
              i,
              (i + 10 > uids.length) ? uids.length : i + 10,
            );
            futures.add(
              FirebaseFirestore.instance
                  .collection('posts')
                  .where('authorId', whereIn: chunk)
                  .orderBy('createdAt', descending: true)
                  .limit(3)
                  .get(),
            );
          }
          final results = await Future.wait(futures);
          for (var qs in results) {
            finalItems.addAll(qs.docs);
          }
          finalItems.sort((a, b) {
            final ta = (a.data()?['createdAt'] as Timestamp?)?.toDate();
            final tb = (b.data()?['createdAt'] as Timestamp?)?.toDate();
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });
          finalItems = finalItems.take(20).toList();
        }
      }

      final uids = <String>{};
      for (var d in finalItems) {
        final u = d.data();
        final id = u?['authorId'] as String?;
        if (id != null) uids.add(id);
      }
      if (uids.isNotEmpty) {
        await UserCacheService.instance.fetchUsers(uids.toList());
      }

      final interactionResults = await interactionsFuture;
      myLikedPostIds = interactionResults[0];
      myFollowingUserIds = interactionResults[1];

      followingPosts = finalItems;
    } catch (e) {
      debugPrint("LoadFollowingData Error: $e");
    } finally {
      isFollowingLoading = false;
      _notifyFollowing();
    }
  }

  // ==========================================
  // 3. ORTAK ETKİLEŞİM METOTLARI
  // ==========================================
  void toggleLike(String postId, bool isLiked) {
    if (isLiked) {
      myLikedPostIds.add(postId);
    } else {
      myLikedPostIds.remove(postId);
    }
    FeedService.instance.toggleLike(postId: postId, like: isLiked);
  }

  Future<void> followUser(String targetUid) async {
    myFollowingUserIds.add(targetUid);
    _notifyBoth();
    await FeedService.instance.followUser(targetUid);
  }

  void removePost(String postId) {
    posts.removeWhere((doc) => doc.id == postId);
    _notifyPopular();
  }

  void removeFollowingPost(String postId) {
    followingPosts.removeWhere((doc) => doc.id == postId);
    _notifyFollowing();
  }
}
