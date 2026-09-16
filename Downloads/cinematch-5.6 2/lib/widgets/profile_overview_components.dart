import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/widgets/ui_polish.dart';
import 'package:fluttergirdi/models/gamification.dart';

final Map<int, Future<String>> _personPortraitCache = {};

Future<String> _loadPersonPortrait(int personId) {
  return _personPortraitCache.putIfAbsent(personId, () async {
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('callTMDB')
          .call({
            'endpoint': '/3/person/$personId',
            'params': {'language': 'tr-TR'},
          });
      final data = Map<String, dynamic>.from(response.data as Map);
      final profilePath = (data['profile_path'] ?? '').toString();
      if (profilePath.isEmpty) return '';
      return profilePath.startsWith('/')
          ? 'https://image.tmdb.org/t/p/w200$profilePath'
          : profilePath;
    } catch (_) {
      return '';
    }
  });
}

double profilePosterWidth(
  BuildContext context, {
  double horizontalPadding = 32,
  double spacing = 8,
}) {
  final available = MediaQuery.sizeOf(context).width - horizontalPadding;
  return ((available - (spacing * 3)) / 4).clamp(64.0, 92.0);
}

double profilePosterHeight(BuildContext context) {
  return profilePosterWidth(context) * 1.5;
}

class ProfileAchievementsBar extends StatelessWidget {
  const ProfileAchievementsBar({
    super.key,
    required this.streak,
    required this.badgeIds,
    this.onStreakTap,
  });

  final int streak;
  final List<String> badgeIds;
  final VoidCallback? onStreakTap;

  @override
  Widget build(BuildContext context) {
    if (streak <= 0 && badgeIds.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final streakColor = isDark
        ? const Color(0xFF66BB6A)
        : const Color(0xFF2E7D32);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: SizedBox(
        height: 30,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            if (streak > 0)
              Tooltip(
                message: '$streak günlük film serisi',
                child: InkWell(
                  onTap: onStreakTap,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: streakColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: streakColor, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: streakColor.withValues(alpha: 0.12),
                          blurRadius: 7,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_fire_department_rounded,
                          color: streakColor,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$streak Gün',
                          style: TextStyle(
                            color: streakColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (streak > 0 && badgeIds.isNotEmpty) const SizedBox(width: 7),
            ...badgeIds.map((badgeId) {
              final badge = AppBadge.allBadges.firstWhere(
                (item) => item.id == badgeId,
                orElse: () => AppBadge.allBadges.first,
              );
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: '${badge.name}: ${badge.description}',
                  triggerMode: TooltipTriggerMode.tap,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: badge.color.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: badge.color.withValues(alpha: 0.62),
                      ),
                    ),
                    child: Icon(badge.icon, size: 15, color: badge.color),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class ProfileStat extends StatelessWidget {
  const ProfileStat({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(right: 18, top: 4, bottom: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _compactCount(value),
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: textColor.withValues(alpha: 0.72),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _compactCount(int count) {
    if (count < 1000) return count.toString();
    if (count < 1000000) {
      final value = count / 1000;
      return '${value.toStringAsFixed(value >= 10 || value == value.roundToDouble() ? 0 : 1)}B';
    }
    final value = count / 1000000;
    return '${value.toStringAsFixed(value >= 10 || value == value.roundToDouble() ? 0 : 1)}M';
  }
}

class ProfilePreferenceSection extends StatelessWidget {
  const ProfilePreferenceSection({
    super.key,
    required this.title,
    required this.items,
    this.showPortraits = false,
    this.onPersonTap,
  });

  final String title;
  final List<dynamic> items;
  final bool showPortraits;
  final void Function(int id, String name)? onPersonTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HairlineDivider(),
          const SizedBox(height: 8),
          AccentMetadata(text: title),
          const SizedBox(height: 7),
          if (showPortraits)
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final person = _ProfilePerson.from(items[index]);
                  return _PersonPortrait(
                    person: person,
                    onTap: person.id > 0 && onPersonTap != null
                        ? () => onPersonTap!(person.id, person.name)
                        : null,
                  );
                },
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items.map((item) {
                final name = item is Map
                    ? (item['name'] ?? '').toString()
                    : item.toString();
                return TintedTag(label: name);
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _PersonPortrait extends StatelessWidget {
  const _PersonPortrait({required this.person, this.onTap});

  final _ProfilePerson person;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            _PersonPortraitImage(
              person: person,
              backgroundColor: isDark ? Colors.white12 : Colors.black12,
              placeholderColor: textColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 6),
            Text(
              person.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor.withValues(alpha: 0.82),
                fontSize: 10,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonPortraitImage extends StatelessWidget {
  const _PersonPortraitImage({
    required this.person,
    required this.backgroundColor,
    required this.placeholderColor,
  });

  final _ProfilePerson person;
  final Color backgroundColor;
  final Color placeholderColor;

  @override
  Widget build(BuildContext context) {
    if (person.imageUrl.isNotEmpty) {
      return _buildAvatar(person.imageUrl);
    }
    if (person.id <= 0) return _buildAvatar('');

    return FutureBuilder<String>(
      future: _loadPersonPortrait(person.id),
      builder: (context, snapshot) => _buildAvatar(snapshot.data ?? ''),
    );
  }

  Widget _buildAvatar(String imageUrl) {
    return CircleAvatar(
      radius: 31,
      backgroundColor: backgroundColor,
      backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
      child: imageUrl.isEmpty
          ? Icon(Icons.person_rounded, color: placeholderColor, size: 28)
          : null,
    );
  }
}

class _ProfilePerson {
  const _ProfilePerson({
    required this.id,
    required this.name,
    required this.imageUrl,
  });

  final int id;
  final String name;
  final String imageUrl;

  factory _ProfilePerson.from(dynamic raw) {
    if (raw is! Map) {
      return _ProfilePerson(id: 0, name: raw.toString(), imageUrl: '');
    }

    final rawId = raw['id'];
    final id = rawId is num
        ? rawId.toInt()
        : int.tryParse(rawId?.toString() ?? '') ?? 0;
    final name = (raw['name'] ?? '').toString();
    final rawImage =
        (raw['profile_path'] ??
                raw['profilePath'] ??
                raw['photoURL'] ??
                raw['imageUrl'] ??
                '')
            .toString();
    final imageUrl = rawImage.startsWith('/')
        ? 'https://image.tmdb.org/t/p/w200$rawImage'
        : rawImage;

    return _ProfilePerson(id: id, name: name, imageUrl: imageUrl);
  }
}
