import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class PostSkeleton extends StatelessWidget {
  const PostSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final baseColor = Colors.grey.shade300;
    final highlightColor = Colors.grey.shade100;
    
    // Dark mode kontrolü
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.grey.shade800 : baseColor;
    final highlight = isDark ? Colors.grey.shade700 : highlightColor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Shimmer.fromColors(
        baseColor: color,
        highlightColor: highlight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header (Avatar + İsim)
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 120, height: 14, color: Colors.white),
                    const SizedBox(height: 6),
                    Container(width: 80, height: 12, color: Colors.white),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Metin Satırları
            Container(width: double.infinity, height: 14, color: Colors.white),
            const SizedBox(height: 6),
            Container(width: 200, height: 14, color: Colors.white),
            const SizedBox(height: 12),
            // Büyük Resim Alanı
            Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}