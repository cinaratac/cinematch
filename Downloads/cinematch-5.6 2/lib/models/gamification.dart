import 'package:flutter/material.dart';

enum BadgeType {
  filmBuff,    // Film Kurdu
  critic,      // Eleştirmen
  archivist,   // Arşivci
  socialite,   // Fenomen (Takipçi)
  trendsetter, // Trend Belirleyici (Beğeni)
}

class AppBadge {
  final String id;
  final BadgeType type;
  final String name;
  final String description;
  final IconData icon;
  final Color color;
  final int threshold; // Kazanmak için gereken sayı

  const AppBadge({
    required this.id,
    required this.type,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
    required this.threshold,
  });

  // Rozet Tanımları (METİNLER DÜZELTİLDİ)
  static const List<AppBadge> allBadges = [
    AppBadge(
      id: 'film_buff_1',
      type: BadgeType.filmBuff,
      name: 'Film Kurdu',
      description: '100 film kaydedin.',
      icon: Icons.movie_filter_rounded,
      color: Colors.blueAccent,
      threshold: 100,
    ),
    AppBadge(
      id: 'critic_1',
      type: BadgeType.critic,
      name: 'Eleştirmen',
      description: '10 detaylı inceleme yazın.',
      icon: Icons.rate_review_rounded,
      color: Colors.purpleAccent,
      threshold: 10,
    ),
    AppBadge(
      id: 'archivist_1',
      type: BadgeType.archivist,
      name: 'Arşivci',
      description: '5 tematik liste oluşturun.',
      icon: Icons.folder_special_rounded,
      color: Colors.amber,
      threshold: 5,
    ),
    AppBadge(
      id: 'social_1',
      type: BadgeType.socialite,
      name: 'Popüler',
      description: '50 takipçiye ulaşın.',
      icon: Icons.groups_rounded,
      color: Colors.pinkAccent,
      threshold: 50,
    ),
  ];
}

class LeaderboardUser {
  final String uid;
  final String displayName;
  final String? photoURL;
  final int score; 
  final int rank;

  LeaderboardUser({
    required this.uid,
    required this.displayName,
    this.photoURL,
    required this.score,
    required this.rank,
  });
}