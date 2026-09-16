import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/gamification.dart';

class GamificationService {
  GamificationService._();
  static final instance = GamificationService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final Map<String, DateTime> _lastCheckByUid = {};

  // --- ROZET KONTROL SİSTEMİ ---
  Future<void> checkAndAwardBadges({bool force = false}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final lastCheck = _lastCheckByUid[user.uid];
    if (!force &&
        lastCheck != null &&
        lastCheck.year == now.year &&
        lastCheck.month == now.month &&
        lastCheck.day == now.day) {
      return;
    }

    final userDocRef = _db.collection('users').doc(user.uid);
    final userDoc = await userDocRef.get();
    if (!userDoc.exists) return;

    final data = userDoc.data()!;
    final currentBadges = List<String>.from(data['badges'] ?? []);
    final List<String> newBadges = [];

    // 1. Film Kurdu Kontrolü (Benzersiz Film Sayısı)
    final favs = List<String>.from(data['favoritesKeys'] ?? []);
    final fives = List<String>.from(data['fiveStarKeys'] ?? []);
    final watch = List<String>.from(data['watchlistKeys'] ?? []);
    final disliked = List<String>.from(data['dislikedKeys'] ?? []);

    final watched = List<String>.from(data['watchedKeys'] ?? []);
    // Benzersiz film sayısını hesapla
    final uniqueMovies = {
      ...favs,
      ...fives,
      ...watch,
      ...disliked,
      ...watched,
    }.length;

    // ÖNEMLİ: Bu sayıyı veritabanına yaz ki liderlik tablosunda kullanabilelim
    if ((data['totalMovies'] as num?)?.toInt() != uniqueMovies) {
      await userDocRef.update({'totalMovies': uniqueMovies});
    }

    final filmBuffBadge = AppBadge.allBadges.firstWhere(
      (b) => b.type == BadgeType.filmBuff,
    );
    _checkRule(filmBuffBadge, uniqueMovies, currentBadges, newBadges);

    // 2. Eleştirmen Kontrolü
    final criticBadge = AppBadge.allBadges.firstWhere(
      (b) => b.type == BadgeType.critic,
    );
    if (!currentBadges.contains(criticBadge.id)) {
      final postsQuery = await _db
          .collection('posts')
          .where('authorId', isEqualTo: user.uid)
          .where('isReview', isEqualTo: true)
          .count()
          .get();
      final reviewCount = postsQuery.count ?? 0;
      _checkRule(criticBadge, reviewCount, currentBadges, newBadges);
    }

    // 3. Arşivci Kontrolü
    final archivistBadge = AppBadge.allBadges.firstWhere(
      (b) => b.type == BadgeType.archivist,
    );
    if (!currentBadges.contains(archivistBadge.id)) {
      final listQuery = await _db
          .collection('custom_lists')
          .where('ownerId', isEqualTo: user.uid)
          .count()
          .get();
      final listCount = listQuery.count ?? 0;
      _checkRule(archivistBadge, listCount, currentBadges, newBadges);
    }

    // 4. Popülerlik (Takipçi) Kontrolü
    final followers = (data['followersCount'] ?? 0) as int;
    final socialiteBadge = AppBadge.allBadges.firstWhere(
      (b) => b.type == BadgeType.socialite,
    );
    _checkRule(socialiteBadge, followers, currentBadges, newBadges);

    // Yeni rozet varsa kaydet
    if (newBadges.isNotEmpty) {
      await userDocRef.update({'badges': FieldValue.arrayUnion(newBadges)});
    }
    _lastCheckByUid[user.uid] = now;
  }

  void _checkRule(
    AppBadge badge,
    int currentValue,
    List<String> owned,
    List<String> toAdd,
  ) {
    if (currentValue >= badge.threshold && !owned.contains(badge.id)) {
      toAdd.add(badge.id);
    }
  }

  // --- LİDERLİK TABLOLARI ---

  // 1. En Popüler (Takipçi Sayısına Göre)
  Future<List<LeaderboardUser>> getWeeklyTopUsers() async {
    try {
      final qs = await _db
          .collection('users')
          .orderBy('followersCount', descending: true)
          .limit(20) // Listeyi biraz genişletelim
          .get();

      return _mapToLeaderboard(qs, 'followersCount');
    } catch (e) {
      return [];
    }
  }

  // 2. Film Kurtları (İzlenen Film Sayısına Göre)
  Future<List<LeaderboardUser>> getTopFilmBuffs() async {
    try {
      // Not: 'totalMovies' alanı için Firestore'da index oluşturmanız gerekebilir.
      // Hata alırsanız logdaki linke tıklayın.
      final qs = await _db
          .collection('users')
          .orderBy('totalMovies', descending: true)
          .limit(20)
          .get();

      return _mapToLeaderboard(qs, 'totalMovies');
    } catch (e) {
      return [];
    }
  }

  List<LeaderboardUser> _mapToLeaderboard(
    QuerySnapshot<Map<String, dynamic>> qs,
    String scoreField,
  ) {
    return qs.docs.asMap().entries.map((entry) {
      final idx = entry.key;
      final d = entry.value.data();
      return LeaderboardUser(
        uid: entry.value.id,
        rank: idx + 1,
        displayName: d['displayName'] ?? d['username'] ?? 'Kullanıcı',
        photoURL: d['photoURL'],
        score: (d[scoreField] ?? 0) as int,
      );
    }).toList();
  }
}
