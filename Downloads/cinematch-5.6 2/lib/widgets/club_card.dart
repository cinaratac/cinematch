import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';
import 'package:fluttergirdi/services/club_service.dart';
import 'package:fluttergirdi/widgets/ui_polish.dart';

class ClubCard extends StatefulWidget {
  const ClubCard({super.key, required this.doc, this.isJoinedView = false});

  final DocumentSnapshot doc;
  final bool isJoinedView;

  @override
  State<ClubCard> createState() => _ClubCardState();
}

class _ClubCardState extends State<ClubCard> {
  bool _joining = false;

  Map<String, dynamic> get _data =>
      (widget.doc.data() as Map<String, dynamic>?) ?? const {};

  String get _roomId {
    final stored = (_data['id'] ?? '').toString().trim();
    return stored.isEmpty ? widget.doc.id : stored;
  }

  void _openRoom(String name) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          chatId: _roomId,
          otherUid: '',
          otherTitle: name,
          isGroup: true,
        ),
      ),
    );
  }

  Future<void> _joinRoom(bool isPrivate) async {
    if (_joining) return;
    setState(() => _joining = true);
    try {
      await ClubService.instance.joinClub(_roomId, isPrivate);
      if (!mounted || !isPrivate) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Katılma isteğin gönderildi.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Odaya katılınamadı. Lütfen tekrar dene.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final data = _data;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final name = (data['name'] ?? 'İsimsiz Oda').toString().trim();
    final description = (data['description'] ?? '').toString().trim();
    final imageUrl = (data['imageUrl'] ?? '').toString().trim();
    final isPrivate = data['isPrivate'] == true;
    final members = List<dynamic>.from(data['members'] ?? const []);
    final pending = List<dynamic>.from(data['pendingRequests'] ?? const []);
    final isMember = uid != null && members.contains(uid);
    final isPending = uid != null && pending.contains(uid);
    final isOwner = uid != null && data['ownerId'] == uid;
    final storedCount = data['memberCount'];
    final memberCount = storedCount is num
        ? (storedCount.toInt() > members.length
              ? storedCount.toInt()
              : members.length)
        : members.length;
    final featuredMovie = data['featuredMovie'] is Map
        ? Map<String, dynamic>.from(data['featuredMovie'] as Map)
        : null;
    final featuredTitle =
        (featuredMovie?['title'] ?? featuredMovie?['name'] ?? '')
            .toString()
            .trim();

    return Material(
      color: colors.surfaceContainerLow.withValues(alpha: 0.72),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: colors.outlineVariant.withValues(alpha: 0.32),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isMember ? () => _openRoom(name) : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RoomCover(imageUrl: imageUrl, roomName: name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                        ),
                        if (isOwner) ...[
                          const SizedBox(width: 6),
                          TintedTag(
                            label: 'Kurucu',
                            color: colors.secondary,
                            compact: true,
                          ),
                        ],
                      ],
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      children: [
                        TintedTag(
                          label: isPrivate ? 'Özel' : 'Açık',
                          icon: isPrivate
                              ? Icons.lock_outline_rounded
                              : Icons.public_rounded,
                          color: isPrivate
                              ? colors.tertiary
                              : const Color(0xFF3FAE66),
                          compact: true,
                        ),
                        TintedTag(
                          label: '$memberCount üye',
                          icon: Icons.group_outlined,
                          color: colors.primary,
                          compact: true,
                        ),
                      ],
                    ),
                    if (featuredTitle.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      AccentMetadata(
                        text: featuredTitle,
                        icon: Icons.local_movies_outlined,
                        maxLines: 1,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _RoomAction(
                        isMember: isMember,
                        isPending: isPending,
                        isPrivate: isPrivate,
                        isLoading: _joining,
                        onOpen: () => _openRoom(name),
                        onJoin: () => _joinRoom(isPrivate),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomCover extends StatelessWidget {
  const _RoomCover({required this.imageUrl, required this.roomName});

  final String imageUrl;
  final String roomName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 104,
      height: 146,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: imageUrl.isEmpty
            ? ColoredBox(
                color: colors.surfaceContainerHighest,
                child: Center(
                  child: Text(
                    roomName.isEmpty
                        ? 'O'
                        : roomName.characters.first.toUpperCase(),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              )
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                memCacheWidth: 312,
                placeholder: (_, _) =>
                    ColoredBox(color: colors.surfaceContainerHighest),
                errorWidget: (_, _, _) => ColoredBox(
                  color: colors.surfaceContainerHighest,
                  child: Icon(
                    Icons.forum_outlined,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
      ),
    );
  }
}

class _RoomAction extends StatelessWidget {
  const _RoomAction({
    required this.isMember,
    required this.isPending,
    required this.isPrivate,
    required this.isLoading,
    required this.onOpen,
    required this.onJoin,
  });

  final bool isMember;
  final bool isPending;
  final bool isPrivate;
  final bool isLoading;
  final VoidCallback onOpen;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    if (isMember) {
      return FilledButton.icon(
        onPressed: onOpen,
        icon: const Icon(Icons.arrow_forward_rounded, size: 17),
        label: const Text('Odaya gir'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          visualDensity: VisualDensity.compact,
        ),
      );
    }
    if (isPending) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.schedule_rounded, size: 16),
        label: const Text('İstek bekliyor'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          visualDensity: VisualDensity.compact,
        ),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: isLoading ? null : onJoin,
      icon: isLoading
          ? const SizedBox.square(
              dimension: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              isPrivate ? Icons.mail_outline_rounded : Icons.add_rounded,
              size: 17,
            ),
      label: Text(isPrivate ? 'İstek gönder' : 'Katıl'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 13),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
