// lib/services/text_filter_service.dart

class TextFilterService {
  // Bu listeyi istediğiniz kadar genişletebilirsiniz.
  // Not: Gerçek hayatta buraya yüzlerce kelime eklemeniz gerekebilir.
  static final List<String> _bannedWords = [
  // Yaygın Kısaltmalar
  'aq', 'amk', 'mq', 'mk', 'amq', 'oç', 'oc', 'o.ç', 'a.q', 'a.m.k',
  'sik', 's.i.k', 's1k', 'sg', 'siktir', 'hassiktir', 'hasiktir',
  
  // Anahtar Kelimeler (Kökler ve Türevler)
  'amcık', 'amcik', 'yarrak', 'yarak', 'yaraq',
  'göt', 'got', 'götveren', 'götlek', 'götoş',
  'orospu', 'ospu', 'orosbu','oropsu', 'orosbucocugu', 'orospuçocuğu', 'orospu çocuğu',
  'sikmek', 'sikiyim', 'sikerim', 'sikiyorum', 'sikiyom', 'sikeyim',
  'sik', 's1k', 's1kik', 's1kikim', 's1keyim', 's1kecem',
  'piç', 'pic', 'piç kurusu',
  'yavşak', 'yavsak',
  'kahpe', 'kaltak', 'kaşar', 'fahişe', 'sürtük',
  'sikik', 'sikiş', 'sikişmek', 'sokuş', 'sokarım', 'sokayım',
  'ibne', 'ipne', 'puşt', 'pezevenk',
  'sikem', 'sikiyim', 'sikim',
  'ananı', 'bacını', 'avradını', 'sülaleni',
  
  // Hakaret / Aşağılama
  'gerizekalı', 'gerizekali', 'salak', 'aptal', 'mal', 'mall', 
  'öküz', 'beyinsiz', 'ezik', 'bok', 'boktan',
  
  // İngilizce (Genel)
  // İngilizce (Genişletilmiş)
  'fuck', 'shit', 'bitch', 'asshole', 'dick', 'pussy', 'bastard',
  'cunt', 'motherfucker', 'slut', 'whore', 'crap', 'bullshit',
  
  // Diğer Varyasyonlar
  'aq', 'aqw', 'amq', 'ams', 'amck', 'yarrk', 'yrrk',
  'p.i.ç', 'o.ç.', 's.g', 'a.q.', 
];

  /// Metinde yasaklı kelime var mı kontrol eder.
  /// Varsa TRUE döner (Engellenmeli).
  static bool hasProfanity(String text) {
    if (text.isEmpty) return false;
    
    // 1. Metni küçük harfe çevir ve Türkçe karakterleri normalize et
    // (Örn: 'Ş' -> 's', 'İ' -> 'i' gibi)
    String cleanText = text.toLowerCase()
        .replaceAll('ş', 's')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c');

    // 2. Kelimeleri ayır (boşluklara göre)
    final words = cleanText.split(RegExp(r'\s+'));

    for (var word in words) {
      // Noktalama işaretlerini temizle (örn: "aptal!" -> "aptal")
      final pureWord = word.replaceAll(RegExp(r'[^\w]'), ''); 
      
      if (_bannedWords.contains(pureWord)) {
        return true;
      }
      
      // Ekstra Güvenlik: Kelime içinde yasaklı kök var mı?
      // (Dikkat: Bu bazen yanlış pozitif verebilir, örn: "siktir" -> "sik" kökü)
      // Bu kısmı çok agresif filtreleme isterseniz açabilirsiniz:
      /*
      for (var banned in _bannedWords) {
         if (pureWord.contains(banned)) return true;
      }
      */
    }
    return false;
  }
}