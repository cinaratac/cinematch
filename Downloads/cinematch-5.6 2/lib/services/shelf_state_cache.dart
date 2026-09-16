import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:fluttergirdi/models/custom_list.dart';

/// Uygulama genelinde tek in-memory shelf cache.
/// movie_action_sheet, movie_detail_screen ve diğer ekranlar buradan okur.
class ShelfStateCache extends ChangeNotifier {
  static final ShelfStateCache instance = ShelfStateCache._();
  ShelfStateCache._();

  // uid → field → Set<normalizedKey>
  final Map<String, Map<String, Set<String>>> _data = {};

  // uid → List<CustomList>
  final Map<String, List<CustomList>> _lists = {};

  // Profil dokümanında tutulan, en fazla 5 elemanlı Diary özeti.
  // Böylece profil ekranı ayrı bir Firestore sorgusu yapmadan son izlenenleri
  // gösterebilir ve yeni bir izleme yazılırken mevcut özet zaten bellektedir.
  final Map<String, List<Map<String, dynamic>>> _recentDiary = {};

  // -------------------------------------------------------------------------
  bool hasData(String uid) => _data.containsKey(uid);

  Set<String> get(String uid, String field) => _data[uid]?[field] ?? const {};

  void updateAll(String uid, Map<String, dynamic> data) {
    _data[uid] = {
      'watchedKeys': _toSet(data['watchedKeys']),
      'watchlistKeys': _toSet(data['watchlistKeys']),
      'favoritesKeys': _toSet(data['favoritesKeys']),
      'fiveStarKeys': _toSet(data['fiveStarKeys']),
      'dislikedKeys': _toSet(data['dislikedKeys']),
    };
    _recentDiary[uid] = _toMapList(data['recentDiaryEntries']);
    notifyListeners();
  }

  List<CustomList> getLists(String uid) => _lists[uid] ?? [];
  void setLists(String uid, List<CustomList> lists) => _lists[uid] = lists;

  List<Map<String, dynamic>> getRecentDiary(String uid) =>
      List<Map<String, dynamic>>.from(_recentDiary[uid] ?? const []);

  void setRecentDiary(String uid, List<Map<String, dynamic>> entries) {
    _recentDiary[uid] = List<Map<String, dynamic>>.from(entries);
  }

  // Optimistic update — UI anında tepki verir, Firestore bitmesini beklemez
  void optimisticAdd(String uid, String field, String key) {
    final changed = _data
        .putIfAbsent(uid, () => {})
        .putIfAbsent(field, () => {})
        .add(key);
    if (changed) notifyListeners();
  }

  void optimisticRemove(String uid, String field, String key) {
    final changed = _data[uid]?[field]?.remove(key) ?? false;
    if (changed) notifyListeners();
  }

  // -------------------------------------------------------------------------
  static Set<String> _toSet(dynamic raw) {
    if (raw == null) return {};
    return List<dynamic>.from(
      raw as List,
    ).map((e) => e.toString().trim().toLowerCase()).toSet();
  }

  static List<Map<String, dynamic>> _toMapList(dynamic raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  // Firestore doc'tan direkt güncelle (listener callback'lerinde kullan)
  void applyDoc(String uid, DocumentSnapshot doc) {
    if (!doc.exists) return;
    updateAll(uid, (doc.data() as Map<String, dynamic>?) ?? {});
  }
}
