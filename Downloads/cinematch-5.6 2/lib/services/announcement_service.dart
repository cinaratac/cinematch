import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AnnouncementService {
  // Tek instance (Singleton)
  static final AnnouncementService instance = AnnouncementService._();
  AnnouncementService._();

  /// Bu fonksiyonu uygulamanın ana ekranı (HomeShell) açıldığında çağıracağız.
  Future<void> checkAndShowAnnouncement(BuildContext context) async {
    try {
      // 1. Firestore'dan duyuru verisini çek
      final doc = await FirebaseFirestore.instance
          .collection('system')
          .doc('announcement')
          .get();

      if (!doc.exists) return;

      final data = doc.data();
      if (data == null) return;

      final bool isActive = data['isActive'] ?? false;
      if (!isActive) return; // Duyuru aktif değilse gösterme

      final String serverId = data['id'] ?? 'v0';

      // 2. Yerel hafızada en son gösterilen duyuru ID'sine bak
      final prefs = await SharedPreferences.getInstance();
      final String? lastSeenId = prefs.getString('last_seen_announcement_id');

      // 3. Eğer kullanıcı bu duyuruyu daha önce görmediyse (ID'ler farklıysa) göster
      if (serverId != lastSeenId) {
        if (context.mounted) {
          await _showDialog(context, data);

          // 4. Gösterdikten sonra ID'yi kaydet ki bir daha çıkmasın
          await prefs.setString('last_seen_announcement_id', serverId);
        }
      }
    } catch (e) {
      debugPrint('');
    }
  }

  Future<void> _showDialog(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final title = data['title'] ?? 'Duyuru';
    final message = data['message'] ?? '';
    final imageUrl = data['imageUrl']; // Opsiyonel resim

    return showDialog(
      context: context,
      barrierDismissible: false, // Kullanıcı butona basmadan kapatamasın
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          backgroundColor: const Color(0xFF1E1E1E), // Koyu tema arkaplan
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // İkon veya Görsel
                if (imageUrl != null && imageUrl.toString().isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      imageUrl,
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.info,
                        size: 60,
                        color: Color.fromARGB(117, 41, 202, 44),
                      ),
                    ),
                  )
                else
                  const Icon(
                    Icons.campaign,
                    size: 60,
                    color: Color.fromARGB(117, 41, 202, 44),
                  ),

                const SizedBox(height: 16),

                // Başlık
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                // Mesaj
                Text(
                  message,
                  style: const TextStyle(fontSize: 16, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 24),

                // Tamam Butonu
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color.fromARGB(117, 41, 202, 44),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Harika!',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
