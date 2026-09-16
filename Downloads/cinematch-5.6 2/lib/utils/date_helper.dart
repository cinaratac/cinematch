import 'package:cloud_firestore/cloud_firestore.dart';

class DateHelper {
  /// Firestore Timestamp veya DateTime objesini alıp
  /// "Şimdi, 5d, 2s, 3g, 4h, 7a, 1y" formatına çevirir.
  static String timeAgo(dynamic timestamp) {
    if (timestamp == null) return '';

    DateTime date;
    
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else if (timestamp is DateTime) {
      date = timestamp;
    } else {
      return '';
    }

    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.isNegative || difference.inSeconds < 60) {
      return 'Şimdi';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}d';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}s';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}g';
    } else if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()}h';
    } else if (difference.inDays < 365) {
      return '${(difference.inDays / 30).floor()}a';
    } else {
      return '${(difference.inDays / 365).floor()}y';
    }
  }

  /// Verilen herhangi bir tarihin (DateTime) haftalık ID'sini döndürür.
  /// Admin Trivia ekranı geçmiş/gelecek haftaları hesaplamak için bunu kullanır.
  static String getWeekIdFor(DateTime date) {
    // ISO 8601 haftalık hesaplama mantığı (Pazartesi başlangıçlı)
    final thursday = date.add(Duration(days: 4 - date.weekday));
    final firstDayOfYear = DateTime(thursday.year, 1, 1);
    final days = thursday.difference(firstDayOfYear).inDays;
    final weekNumber = 1 + (days / 7).floor();
    
    return '${thursday.year}_W$weekNumber';
  }

  /// Mevcut haftanın benzersiz ID'sini döndürür (Örn: "2026_W16")
  static String getCurrentWeekId() {
    return getWeekIdFor(DateTime.now());
  }

  /// Mevcut günün benzersiz ID'sini döndürür (Örn: "2026-04-19")
  static String getCurrentDayId() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
  
  /// Mevcut ayın benzersiz ID'sini döndürür (Örn: "2026_M04")
  static String getCurrentMonthId() {
    final now = DateTime.now();
    return '${now.year}_M${now.month.toString().padLeft(2, '0')}';
  }
}