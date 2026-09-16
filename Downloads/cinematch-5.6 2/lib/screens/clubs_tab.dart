import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/create_club_screen.dart';
import 'package:fluttergirdi/services/club_service.dart';
import 'package:fluttergirdi/widgets/club_card.dart';
import 'package:fluttergirdi/widgets/ui_polish.dart';
import 'package:shimmer/shimmer.dart';

enum _RoomFilter { all, joined, public, private }

enum _RoomSort { newest, popular, alphabetical }

class ClubsScreen extends StatelessWidget {
  const ClubsScreen({super.key});

  void _createRoom(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CreateClubScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Odalar',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Yeni oda kur',
            onPressed: () => _createRoom(context),
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: const ClubsTab(isStandalone: true),
    );
  }
}

class ClubsTab extends StatefulWidget {
  const ClubsTab({super.key, this.isStandalone = false});

  final bool isStandalone;

  @override
  State<ClubsTab> createState() => _ClubsTabState();
}

class _ClubsTabState extends State<ClubsTab> {
  final TextEditingController _searchController = TextEditingController();
  late final Stream<QuerySnapshot> _roomsStream;

  String _searchQuery = '';
  _RoomFilter _filter = _RoomFilter.all;
  _RoomSort _sort = _RoomSort.newest;

  @override
  void initState() {
    super.initState();
    _roomsStream = ClubService.instance.getClubsStream();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    FocusScope.of(context).unfocus();
    if (_searchQuery.isNotEmpty) setState(() => _searchQuery = '');
  }

  List<QueryDocumentSnapshot> _visibleRooms(List<QueryDocumentSnapshot> rooms) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final visible = rooms.where((document) {
      final data = document.data() as Map<String, dynamic>;
      final name = (data['name'] ?? '').toString().toLowerCase();
      final description = (data['description'] ?? '').toString().toLowerCase();
      final members = List<dynamic>.from(data['members'] ?? const []);
      final isPrivate = data['isPrivate'] == true;
      final matchesSearch =
          _searchQuery.isEmpty ||
          name.contains(_searchQuery) ||
          description.contains(_searchQuery);
      if (!matchesSearch) return false;

      return switch (_filter) {
        _RoomFilter.all => true,
        _RoomFilter.joined => uid != null && members.contains(uid),
        _RoomFilter.public => !isPrivate,
        _RoomFilter.private => isPrivate,
      };
    }).toList();

    visible.sort((first, second) {
      final a = first.data() as Map<String, dynamic>;
      final b = second.data() as Map<String, dynamic>;
      return switch (_sort) {
        _RoomSort.newest => _dateOf(b).compareTo(_dateOf(a)),
        _RoomSort.popular => _memberCount(b).compareTo(_memberCount(a)),
        _RoomSort.alphabetical =>
          (a['name'] ?? '').toString().toLowerCase().compareTo(
            (b['name'] ?? '').toString().toLowerCase(),
          ),
      };
    });
    return visible;
  }

  DateTime _dateOf(Map<String, dynamic> data) {
    final value = data['createdAt'];
    return value is Timestamp
        ? value.toDate()
        : DateTime.fromMillisecondsSinceEpoch(0);
  }

  int _memberCount(Map<String, dynamic> data) {
    final stored = data['memberCount'];
    if (stored is num) return stored.toInt();
    final members = data['members'];
    return members is List ? members.length : 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (value) {
                final normalized = value.trim().toLowerCase();
                if (normalized != _searchQuery) {
                  setState(() => _searchQuery = normalized);
                }
              },
              decoration: InputDecoration(
                hintText: 'Oda ara',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Aramayı temizle',
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close_rounded, size: 19),
                      ),
                filled: true,
                fillColor: colors.surfaceContainerHighest.withValues(
                  alpha: 0.52,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.22),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.primary, width: 1.2),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<_RoomFilter>(
                segments: const [
                  ButtonSegment(value: _RoomFilter.all, label: Text('Tümü')),
                  ButtonSegment(
                    value: _RoomFilter.joined,
                    label: Text('Odalarım'),
                  ),
                  ButtonSegment(value: _RoomFilter.public, label: Text('Açık')),
                  ButtonSegment(
                    value: _RoomFilter.private,
                    label: Text('Özel'),
                  ),
                ],
                selected: {_filter},
                showSelectedIcon: false,
                onSelectionChanged: (selection) {
                  setState(() => _filter = selection.first);
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: WidgetStatePropertyAll(
                    theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                  ),
                  side: WidgetStatePropertyAll(
                    BorderSide(
                      color: colors.outlineVariant.withValues(alpha: 0.45),
                      width: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const HairlineDivider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _roomsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const _RoomsLoadingList();
                }
                if (snapshot.hasError) {
                  return const _RoomsEmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Odalar yüklenemedi',
                    message: 'Bağlantını kontrol edip tekrar deneyebilirsin.',
                  );
                }

                final allRooms =
                    snapshot.data?.docs
                        .whereType<QueryDocumentSnapshot>()
                        .toList() ??
                    const <QueryDocumentSnapshot>[];
                final rooms = _visibleRooms(allRooms);
                if (allRooms.isEmpty) {
                  return _RoomsEmptyState(
                    icon: Icons.forum_outlined,
                    title: 'Henüz oda yok',
                    message: 'İlk odayı kurarak sohbeti başlatabilirsin.',
                    actionLabel: 'Oda kur',
                    onAction: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CreateClubScreen(),
                      ),
                    ),
                  );
                }
                if (rooms.isEmpty) {
                  return _RoomsEmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Eşleşen oda bulunamadı',
                    message: 'Arama metnini veya filtreyi değiştirebilirsin.',
                    actionLabel: _searchQuery.isNotEmpty
                        ? 'Aramayı temizle'
                        : null,
                    onAction: _searchQuery.isNotEmpty ? _clearSearch : null,
                  );
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 8, 8),
                      child: Row(
                        children: [
                          Text(
                            '${rooms.length} oda',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          PopupMenuButton<_RoomSort>(
                            tooltip: 'Odaları sırala',
                            initialValue: _sort,
                            onSelected: (value) =>
                                setState(() => _sort = value),
                            icon: const Icon(Icons.sort_rounded, size: 21),
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: _RoomSort.newest,
                                child: Text('En yeni'),
                              ),
                              PopupMenuItem(
                                value: _RoomSort.popular,
                                child: Text('En kalabalık'),
                              ),
                              PopupMenuItem(
                                value: _RoomSort.alphabetical,
                                child: Text('Ada göre'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                        itemCount: rooms.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) => ClubCard(
                          key: ValueKey(rooms[index].id),
                          doc: rooms[index],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomsEmptyState extends StatelessWidget {
  const _RoomsEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: colors.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoomsLoadingList extends StatelessWidget {
  const _RoomsLoadingList();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: dark
          ? colors.surfaceContainerHighest
          : const Color(0xFFE1E4E2),
      highlightColor: dark
          ? colors.surfaceContainerHigh
          : const Color(0xFFF4F6F4),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 5,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, _) => Container(
          height: 156,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
