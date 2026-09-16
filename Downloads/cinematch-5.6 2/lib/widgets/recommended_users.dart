import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:cached_network_image/cached_network_image.dart'; // EKLENDİ

class RecommendedUsers extends StatefulWidget {
  final int limit;
  final String? title;
  final Set<String> excludeUserIds;

  const RecommendedUsers({
    super.key,
    this.limit = 12,
    this.title,
    this.excludeUserIds = const {},
  });

  @override
  State<RecommendedUsers> createState() => _RecommendedUsersState();
}

class _RecommendedUsersState extends State<RecommendedUsers> {
  // GLOBAL RAM CACHE: Bu sayede scroll yaparken tekrar tekrar internete gitmez!
  static List<Map<String, dynamic>>? _globalCachedUsers;

  bool _loading = true;
  List<Map<String, dynamic>> _users = [];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    // 1. Hafızada varsa beklemeden (0 saniye) anında çiz!
    if (_globalCachedUsers != null && _globalCachedUsers!.isNotEmpty) {
      if (mounted) {
        setState(() {
          _users = _globalCachedUsers!;
          _loading = false;
        });
      }
      return;
    }

    final me = FirebaseAuth.instance.currentUser?.uid;
    final pullSize = math.min(100, widget.limit * 8);

    try {
      // 2. Gereksiz yere "Source.server" zorlamasını kaldırdık, çok daha hızlı çalışır.
      final qs = await FirebaseFirestore.instance
          .collection('users')
          .limit(pullSize)
          .get();

      final pool = <Map<String, dynamic>>[];
      for (final d in qs.docs) {
        final uid = d.id;
        final data = d.data();

        final username = data['username'] as String?;
        if (username == null || username.trim().isEmpty) continue;

        if (uid == me) continue;
        if (widget.excludeUserIds.contains(uid)) continue;

        // UID'yi kolay erişim için datanın içine ekliyoruz
        data['uid'] = uid;
        pool.add(data);
      }

      pool.shuffle(math.Random());

      final finalUsers = pool.length > widget.limit
          ? pool.take(widget.limit).toList()
          : pool;

      // 3. Bir dahaki sefere anında açılsın diye RAM'e kaydet
      _globalCachedUsers = finalUsers;

      if (mounted) {
        setState(() {
          _users = finalUsers;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return SizedBox(
        height: 122,
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(cs.primary),
          ),
        ),
      );
    }

    if (_users.isEmpty) {
      return const SizedBox(height: 8);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              widget.title!,
              style: theme.textTheme.titleMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        if (widget.title != null) const SizedBox(height: 6),
        SizedBox(
          height: 150,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) {
              final u = _users[index];
              final uid = u['uid'] as String;
              final displayName = (u['displayName'] ?? '') as String;
              final username = (u['username'] ?? '') as String;
              final lb = (u['letterboxdUsername'] ?? '') as String;
              final photoURL = (u['photoURL'] ?? '') as String;

              final subtitle = username.isNotEmpty
                  ? '@$username'
                  : (lb.isNotEmpty ? '@$lb' : '');

              return _UserChip(
                uid: uid,
                name: displayName.isNotEmpty
                    ? displayName
                    : (username.isNotEmpty ? username : 'Kullanıcı'),
                subtitle: subtitle,
                photoURL: photoURL,
              );
            },
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemCount: _users.length,
          ),
        ),
      ],
    );
  }
}

class _UserChip extends StatelessWidget {
  final String uid;
  final String name;
  final String subtitle;
  final String photoURL;

  const _UserChip({
    required this.uid,
    required this.name,
    required this.subtitle,
    required this.photoURL,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: uid)),
        );
      },
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // PERFORMANS İÇİN DÜZELTİLDİ: NetworkImage yerine CachedNetworkImage kullanıldı
            ClipOval(
              child: SizedBox(
                width: 76, // radius 38 * 2
                height: 76,
                child: photoURL.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: photoURL,
                        memCacheWidth: 228,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.person, color: Colors.grey),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.person, color: Colors.grey),
                        ),
                      )
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(
                          Icons.person,
                          color: Colors.grey,
                          size: 40,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: theme.textTheme.labelLarge,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}
