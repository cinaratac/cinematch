import 'package:flutter/material.dart';

class StreakBottomSheet extends StatelessWidget {
  final int streak;
  final List<int> activeDays;

  const StreakBottomSheet({
    super.key,
    required this.streak,
    required this.activeDays,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final days = ['P', 'S', 'Ç', 'P', 'C', 'C', 'P'];
    final streakGreen = isDark
        ? const Color(0xFF66BB6A)
        : const Color(0xFF2E7D32);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_rounded,
            color: streakGreen,
            size: 72,
          ),
          const SizedBox(height: 8),
          Text(
            '$streak Günlük Seri!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Harika gidiyorsun! Sinema tutkun böyle devam etsin.',
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(7, (index) {
              final dayNumber = index + 1;
              final isActive = activeDays.contains(dayNumber);

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? streakGreen.withValues(alpha: 0.16)
                          : (isDark ? Colors.grey[800] : Colors.grey[300]),
                      border: isActive
                          ? Border.all(color: streakGreen, width: 2)
                          : null,
                    ),
                    child: isActive
                        ? Icon(
                            Icons.local_fire_department,
                            color: streakGreen,
                            size: 20,
                          )
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    days[index],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isActive
                          ? streakGreen
                          : (isDark ? Colors.white54 : Colors.black54),
                    ),
                  ),
                ],
              );
            }),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Devam Et',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
