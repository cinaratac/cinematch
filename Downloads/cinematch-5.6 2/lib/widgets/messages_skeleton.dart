import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class MessagesSkeleton extends StatelessWidget {
  const MessagesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // Tema renklerine göre iskelet rengini ayarla
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey.shade800 : Colors.grey.shade300;
    final highlightColor = isDark ? Colors.grey.shade700 : Colors.grey.shade100;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 10, // Ekrana sığacak kadar sahte eleman
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Shimmer.fromColors(
            baseColor: baseColor,
            highlightColor: highlightColor,
            child: Row(
              children: [
                // 1. Avatar Yuvarlağı
                Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 16),
                
                // 2. İsim ve Mesaj Satırları
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // İsim Satırı (Kısa)
                      Container(
                        width: 120,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Mesaj Satırı (Uzun)
                      Container(
                        width: double.infinity,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // 3. Sağ taraftaki Tarih/Badge alanı
                Container(
                  width: 40,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
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