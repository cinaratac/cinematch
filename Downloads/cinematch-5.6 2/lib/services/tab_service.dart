import 'package:flutter/foundation.dart';

class TabService {
  // Singleton yapısı
  static final TabService instance = TabService._();
  TabService._();

  // Hangi sekmenin aktif olduğunu tutan dinleyici
  // Varsayılan 0 (Ana Sayfa)
  final ValueNotifier<int> indexNotifier = ValueNotifier<int>(0);

  // Sekme değiştirme fonksiyonu
  void changeTab(int index) {
    indexNotifier.value = index;
  }
}