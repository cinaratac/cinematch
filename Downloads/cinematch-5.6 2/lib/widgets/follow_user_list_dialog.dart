import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/follow_system_service.dart';

class FollowUserListDialog extends StatefulWidget {
  final String title;
  final String uid;
  final String collection;
  final ValueChanged<String> onOpenProfile;

  const FollowUserListDialog({
    super.key,
    required this.title,
    required this.uid,
    required this.collection,
    required this.onOpenProfile,
  });

  @override
  State<FollowUserListDialog> createState() => _FollowUserListDialogState();
}

class _FollowUserListDialogState extends State<FollowUserListDialog> {
  final Set<String> _myFollowing = {};
  final Set<String> _busyUsers = {};
  List<FollowUserSummary>? _cachedUsers;
  Future<List<FollowUserSummary>>? _usersFuture;
  String? _lastRelationKey;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _followingSub;

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _cachedUsers = FollowSystemService.I.getCachedFollowUsers(
      uid: widget.uid,
      collection: widget.collection,
    );
    _bindMyFollowing();
  }

  @override
  void dispose() {
    _followingSub?.cancel();
    super.dispose();
  }

  void _bindMyFollowing() {
    final myUid = _myUid;
    if (myUid == null) return;

    _followingSub = FirebaseFirestore.instance
        .collection('users')
        .doc(myUid)
        .collection('following')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(() {
            _myFollowing
              ..clear()
              ..addAll(snap.docs.map((doc) => doc.id));
          });
        });
  }

  Future<void> _toggleFollow(String targetUid) async {
    final myUid = _myUid;
    if (myUid == null || myUid == targetUid || _busyUsers.contains(targetUid)) {
      return;
    }

    final wasFollowing = _myFollowing.contains(targetUid);
    setState(() {
      _busyUsers.add(targetUid);
      if (wasFollowing) {
        _myFollowing.remove(targetUid);
      } else {
        _myFollowing.add(targetUid);
      }
    });

    try {
      if (wasFollowing) {
        await FollowSystemService.I.unfollowUser(targetUid);
      } else {
        await FollowSystemService.I.followUser(targetUid);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (wasFollowing) {
          _myFollowing.add(targetUid);
        } else {
          _myFollowing.remove(targetUid);
        }
      });
    } finally {
      if (mounted) {
        setState(() => _busyUsers.remove(targetUid));
      }
    }
  }

  void _openProfile(String uid) {
    Navigator.of(context).pop();
    widget.onOpenProfile(uid);
  }

  Future<List<FollowUserSummary>> _usersFutureFor(
    Iterable<String> relationIds,
  ) {
    final ids = relationIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final relationKey = ids.join('|');

    if (_usersFuture != null && _lastRelationKey == relationKey) {
      return _usersFuture!;
    }

    _lastRelationKey = relationKey;
    _usersFuture = FollowSystemService.I
        .fetchExistingFollowUsers(
          uid: widget.uid,
          collection: widget.collection,
          relationIds: ids,
        )
        .then((users) {
          _cachedUsers = users;
          return users;
        });
    return _usersFuture!;
  }

  Widget _buildUserList(List<FollowUserSummary> users) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: users.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final user = users[index];
        return _FollowUserRow(
          user: user,
          isMe: user.uid == _myUid,
          isFollowing: _myFollowing.contains(user.uid),
          isBusy: _busyUsers.contains(user.uid),
          onOpenProfile: () => _openProfile(user.uid),
          onToggleFollow: () => _toggleFollow(user.uid),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width > 520 ? 480 : width - 36,
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Material(
          color: isDark ? const Color(0xFF171A17) : cs.surface,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(widget.uid)
                      .collection(widget.collection)
                      .snapshots(),
                  builder: (context, snap) {
                    final cachedUsers =
                        _cachedUsers ?? const <FollowUserSummary>[];
                    if (snap.connectionState == ConnectionState.waiting) {
                      if (cachedUsers.isNotEmpty) {
                        return _buildUserList(cachedUsers);
                      }
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = snap.data?.docs ?? const [];
                    if (docs.isEmpty) {
                      return const Center(child: Text('Liste boş.'));
                    }

                    return FutureBuilder<List<FollowUserSummary>>(
                      future: _usersFutureFor(docs.map((doc) => doc.id)),
                      initialData: cachedUsers.isNotEmpty ? cachedUsers : null,
                      builder: (context, usersSnap) {
                        if (!usersSnap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final users =
                            usersSnap.data ?? const <FollowUserSummary>[];
                        if (users.isEmpty) {
                          return const Center(child: Text('Liste boş.'));
                        }

                        return _buildUserList(users);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FollowUserRow extends StatelessWidget {
  final FollowUserSummary user;
  final bool isMe;
  final bool isFollowing;
  final bool isBusy;
  final VoidCallback onOpenProfile;
  final VoidCallback onToggleFollow;

  const _FollowUserRow({
    required this.user,
    required this.isMe,
    required this.isFollowing,
    required this.isBusy,
    required this.onOpenProfile,
    required this.onToggleFollow,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final green = const Color(0xFF2E7D32);

    return InkWell(
      onTap: onOpenProfile,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundImage: user.photoURL.isNotEmpty
                  ? NetworkImage(user.photoURL)
                  : null,
              child: user.photoURL.isEmpty
                  ? const Icon(Icons.person_rounded)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                user.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (isMe)
              Text(
                'Sen',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              SizedBox(
                height: 36,
                child: isFollowing
                    ? OutlinedButton(
                        onPressed: isBusy ? null : onToggleFollow,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: green,
                          side: BorderSide(
                            color: green.withValues(alpha: 0.55),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: isBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Takipten Çık'),
                      )
                    : FilledButton(
                        onPressed: isBusy ? null : onToggleFollow,
                        style: FilledButton.styleFrom(
                          backgroundColor: green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: isBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Takip Et'),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
