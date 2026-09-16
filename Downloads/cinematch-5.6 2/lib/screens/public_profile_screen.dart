import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/services/catalog_service.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';
import 'package:fluttergirdi/services/follow_system_service.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'dart:async';
import 'package:fluttergirdi/services/match_service.dart';
import 'package:fluttergirdi/screens/post_detail_screen.dart';
import 'package:fluttergirdi/screens/full_shelf_screen.dart';
import 'package:fluttergirdi/services/custom_list_service.dart';
import 'package:fluttergirdi/models/custom_list.dart';
import 'package:fluttergirdi/screens/custom_list_detail_screen.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fluttergirdi/screens/actors_screen.dart';
import 'package:fluttergirdi/screens/director_screen.dart';
import 'package:fluttergirdi/services/blocking_service.dart';
import 'package:fluttergirdi/widgets/report_user_sheet.dart';
import 'package:fluttergirdi/widgets/follow_user_list_dialog.dart';
import 'package:fluttergirdi/widgets/recent_watched_movies.dart';
import 'package:fluttergirdi/widgets/profile_overview_components.dart';
import 'package:fluttergirdi/widgets/streak_bottom_sheet.dart';
import 'package:fluttergirdi/widgets/ui_polish.dart';

// Aktivite Verisi Modeli
class _ActivityItemData {
  final String id;
  final String text;
  final DateTime? createdAt;
  final String posterUrl;
  final String title;
  final int likeCount;
  final int replyCount;
  final int? tmdbId;

  const _ActivityItemData({
    required this.id,
    required this.text,
    required this.createdAt,
    this.posterUrl = '',
    this.title = '',
    this.likeCount = 0,
    this.replyCount = 0,
    this.tmdbId,
  });
}

enum _PublicProfileAction { report, block, unblock }

class _PublicProfileActionsSheet extends StatelessWidget {
  final bool isBlocked;

  const _PublicProfileActionsSheet({required this.isBlocked});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariant.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),
                _PublicProfileActionTile(
                  title: 'Kişiyi bildir',
                  color: colors.onSurface,
                  onTap: () =>
                      Navigator.pop(context, _PublicProfileAction.report),
                ),
                const SizedBox(height: 8),
                _PublicProfileActionTile(
                  title: isBlocked ? 'Engeli kaldır' : 'Kişiyi engelle',
                  color: isBlocked ? const Color(0xFF2E7D32) : colors.error,
                  onTap: () => Navigator.pop(
                    context,
                    isBlocked
                        ? _PublicProfileAction.unblock
                        : _PublicProfileAction.block,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PublicProfileActionTile extends StatelessWidget {
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _PublicProfileActionTile({
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PublicProfileScreen extends StatefulWidget {
  final String uid;
  const PublicProfileScreen({super.key, required this.uid});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  bool? _isFollowing;
  bool _followBusy = false;
  int? _followersCount;
  int? _followingCount;
  StreamSubscription<FollowEvent>? _followSub;
  bool _isBlocked = false;
  bool _hasBlockedMe = false;
  bool _isLoadingBlock = true;
  int? _matchScore;

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream;

  // Katalog önbelleği
  final Map<String, Future<List<Map<String, dynamic>?>>> _catalogFutureCache =
      {};

  int? _extractTmdbId(Map<String, dynamic> m) {
    final val = m['tmdbId'];
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val);
    return null;
  }

  Future<void> _handleFilmTap(
    String title,
    String posterUrl,
    String? docId,
    int? existingTmdbId,
  ) async {
    int? id = existingTmdbId;

    if (id == null) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
        ),
      );

      try {
        // YENİ: Cloud Functions Kullanımı
        final result = await FirebaseFunctions.instance
            .httpsCallable('callTMDB')
            .call({
              'endpoint': '/3/search/movie',
              'params': {
                'query': title,
                'language': 'tr-TR',
                'include_adult': 'false',
              },
            });

        if (!mounted) return;
        Navigator.pop(context); // Loading kapat

        final data = result.data as Map<String, dynamic>;
        final results = data['results'] as List?;

        if (results != null && results.isNotEmpty) {
          id = results[0]['id'];
          if (docId != null && docId.isNotEmpty && id != null) {
            await CatalogService().resolveAndUpsert(
              tmdbId: id,
              title: title,
              catalogKey: docId,
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Film detayları bulunamadı.')),
          );
          return;
        }
      } catch (e) {
        if (!mounted) return;
        Navigator.pop(context); // Hata olsa da loading kapat
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata oluştu: $e')));
        return;
      }
    }

    if (id != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MovieDetailScreen(
            tmdbId: id!,
            title: title,
            posterUrl: posterUrl,
          ),
        ),
      );
    }
  }

  void _showEnlargedImage(String imageUrl) {
    if (imageUrl.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (ctx) {
        return GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: InteractiveViewer(
            child: Center(child: Image.network(imageUrl, fit: BoxFit.contain)),
          ),
        );
      },
    );
  }

  void _showUserList(String title, String collection) {
    showDialog(
      context: context,
      builder: (_) => FollowUserListDialog(
        title: title,
        uid: widget.uid,
        collection: collection,
        onOpenProfile: (uid) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: uid)),
          );
        },
      ),
    );
  }

  String _catalogTitle(Map<String, dynamic> m) {
    return (m['title'] ?? m['name'] ?? m['t'] ?? '') as String;
  }

  Widget _shelfSectionFromKeys(
    String title,
    List<String> keys, {
    int maxItems = 30,
    Color? accentColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final posterWidth = profilePosterWidth(context);
    final posterHeight = profilePosterHeight(context);
    if (keys.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '$title bulunamadı.',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        ),
      );
    }
    final limited = keys.take(maxItems).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(title, keys, accentColor: accentColor),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>?>>(
          future: (() {
            final k = 'shelf:${title.toLowerCase()}:${limited.join('|')}';
            return _catalogFutureCache[k] ??= _fetchCatalogForKeys(limited);
          })(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return SizedBox(
                height: posterHeight,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final films = (snap.data ?? [])
                .where((m) => m != null)
                .map((m) => m!)
                .toList();
            if (films.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '$title bulunamadı.',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              );
            }
            return SizedBox(
              height: posterHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: films.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final m = films[i];
                  final poster =
                      (m['poster'] ?? m['posterUrl'] ?? m['image'] ?? '')
                          as String;
                  final t = _catalogTitle(m);
                  final tmdbId = _extractTmdbId(m);
                  final docId = limited[i];

                  return GestureDetector(
                    onTap: () => _handleFilmTap(t, poster, docId, tmdbId),
                    child: SizedBox(
                      width: posterWidth,
                      child: ClipRRect(
                        borderRadius: BorderRadius.zero,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            PosterImage(
                              posterUrl: poster,
                              tmdbId: tmdbId,
                              title: t,
                              fit: BoxFit.cover,
                            ),
                            if (t.isNotEmpty)
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  color: Colors.black54,
                                  child: Text(
                                    t,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  final Map<String, Future<List<Map<String, dynamic>?>>> _watchlistFutureCache =
      {};

  Widget _buildSectionHeader(
    String title,
    List<String> keys, {
    Color? accentColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (accentColor != null) ...[
                Container(width: 18, height: 2, color: accentColor),
                const SizedBox(width: 8),
              ],
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
          if (keys.isNotEmpty)
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FullShelfScreen(
                      title: title,
                      filmKeys: keys,
                      target: null,
                    ),
                  ),
                );
              },
              child: const Text(
                'Tümü',
                style: TextStyle(
                  color: Color(0xFF2E7D32),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>?>> _fetchCatalogForKeys(
    List<String> keys,
  ) async {
    final fs = FirebaseFirestore.instance;
    final ordered = <String>[];
    final clean = <String>[];
    for (final raw in keys) {
      final s = raw.trim();
      if (s.isEmpty) continue;
      ordered.add(s);
      clean.add(s);
    }
    final found = <String, Map<String, dynamic>>{};
    const int chunk = 10;
    for (int i = 0; i < clean.length; i += chunk) {
      final part = clean.sublist(
        i,
        i + chunk > clean.length ? clean.length : i + chunk,
      );
      if (part.isEmpty) continue;
      try {
        final qs = await fs
            .collection('catalog_films')
            .where(FieldPath.documentId, whereIn: part)
            .get();
        for (final d in qs.docs) {
          found[d.id] = d.data();
        }
      } catch (_) {}
    }
    final missing = ordered.where((id) => !found.containsKey(id)).toList();
    for (final id in missing) {
      try {
        final snap = await fs.collection('catalog_films').doc(id).get();
        if (snap.exists) found[id] = snap.data()!;
      } catch (_) {}
    }
    final out = <Map<String, dynamic>?>[];
    for (final id in ordered) {
      out.add(found[id]);
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _userStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .snapshots(includeMetadataChanges: false);
    _loadFollowing();
    _bootstrapFollowCounts();
    _loadBlockStatus();

    _followSub = FollowSystemService.I.events.listen((e) {
      if (e.targetUid != widget.uid) return;
      if (!mounted) return;
      int? newFollowers = _followersCount;
      bool? newIsFollowing = _isFollowing;
      if (newFollowers != null) {
        newFollowers = (newFollowers + (e.followed ? 1 : -1));
        if (newFollowers < 0) newFollowers = 0;
      }
      if (FirebaseAuth.instance.currentUser?.uid == e.actorUid) {
        newIsFollowing = e.followed;
      }
      if ((newFollowers != _followersCount) ||
          (newIsFollowing != _isFollowing)) {
        setState(() {
          _followersCount = newFollowers;
          _isFollowing = newIsFollowing;
        });
      }
    });
    _calcScore();
  }

  Future<void> _calcScore() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || myUid == widget.uid) return;
    final score = await MatchService.instance.calculateMatchScore(
      myUid,
      widget.uid,
    );
    if (mounted) setState(() => _matchScore = score);
  }

  Future<void> _loadFollowing() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || myUid == widget.uid) {
      if (_isFollowing != null) setState(() => _isFollowing = null);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(myUid)
          .collection('following')
          .doc(widget.uid)
          .get(const GetOptions(source: Source.server));
      if (!mounted) return;
      final v = snap.exists;
      if (_isFollowing != v) setState(() => _isFollowing = v);
    } catch (_) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(myUid)
            .collection('following')
            .doc(widget.uid)
            .get(const GetOptions(source: Source.cache));
        if (!mounted) return;
        final v = snap.exists;
        if (_isFollowing != v) setState(() => _isFollowing = v);
      } catch (_) {
        if (!mounted) return;
        if (_isFollowing != null) setState(() => _isFollowing = null);
      }
    }
  }

  Future<void> _toggleFollow() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || myUid == widget.uid) return;
    if (_followBusy) return;
    setState(() => _followBusy = true);
    try {
      if (_isFollowing == true) {
        await FollowSystemService.I.unfollowUser(widget.uid);
      } else {
        await FollowSystemService.I.followUser(widget.uid);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _bootstrapFollowCounts() async {
    try {
      final followers = await FollowSystemService.I.fetchFollowerCountOnce(
        widget.uid,
      );
      final following = await FollowSystemService.I.fetchFollowingCountOnce(
        widget.uid,
      );
      if (!mounted) return;
      if (_followersCount != followers || _followingCount != following) {
        setState(() {
          _followersCount = followers;
          _followingCount = following;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadBlockStatus() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) {
      if (mounted) setState(() => _isLoadingBlock = false); // <-- EKLE
      return;
    }
    final other = widget.uid;
    try {
      // YENİ FONSİYONU ÇAĞIRIYORUZ
      final status = await BlockingService.instance.checkBlockStatus(
        currentUserId: myUid,
        targetUserId: other,
      );

      if (!mounted) return;
      setState(() {
        // Artık kimin kimi engellediğini kesin olarak biliyoruz
        _isBlocked = status['iBlockedThem'] ?? false;
        _hasBlockedMe = status['theyBlockedMe'] ?? false;
        _isLoadingBlock = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingBlock = false);
    }
  }

  Future<void> _showProfileActions(String userName) async {
    final action = await showModalBottomSheet<_PublicProfileAction>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      useSafeArea: true,
      builder: (_) => _PublicProfileActionsSheet(isBlocked: _isBlocked),
    );

    if (!mounted || action == null) return;

    if (action == _PublicProfileAction.report) {
      ReportUserSheet.show(context, widget.uid, userName);
      return;
    }

    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    try {
      if (action == _PublicProfileAction.block) {
        await BlockingService.instance.blockUser(
          currentUserId: myUid,
          targetUserId: widget.uid,
        );
        if (!mounted) return;
        setState(() => _isBlocked = true);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Kullanıcı engellendi. İçerikleri gizlendi.'),
            ),
          );
      } else {
        await BlockingService.instance.unblockUser(
          currentUserId: myUid,
          targetUserId: widget.uid,
        );
        if (!mounted) return;
        setState(() => _isBlocked = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Kullanıcının engeli kaldırıldı.')),
          );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('İşlem tamamlanamadı: $error')));
    }
  }

  @override
  void dispose() {
    _followSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGreen = const Color(0xFF2E7D32);
    final bgGradientEnd = isDark ? const Color(0xFF000000) : Colors.white;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        // DİKKAT: Container'ı buradan sildik ve içeri taşıdık.
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _userStream,
          builder: (context, snap) {
            if (_isLoadingBlock) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
              );
            }
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
              );
            }
            if (!snap.hasData || !snap.data!.exists) {
              return const Center(child: Text('Kullanıcı bulunamadı'));
            }

            final data = snap.data!.data()!;
            final displayName = (data['displayName'] ?? '') as String;
            final lb = (data['letterboxdUsername'] ?? '') as String;
            final photoURL = (data['photoURL'] ?? '') as String;
            final appUsername = (data['username'] ?? '') as String;
            final badgeIds = List<String>.from(data['badges'] ?? const []);
            final streakCount = (data['streakCount'] as num?)?.toInt() ?? 0;
            final activeDays = List<int>.from(
              data['weeklyActiveDays'] ?? const [],
            );

            void showStreakDetails() {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => StreakBottomSheet(
                  streak: streakCount,
                  activeDays: activeDays,
                ),
              );
            }

            final titleText = appUsername.isNotEmpty
                ? appUsername
                : (displayName.isNotEmpty
                      ? displayName
                      : (lb.isNotEmpty ? '@$lb' : '(İsimsiz)'));

            // --- YENİ EKLENEN KISIM: Rengi Firebase verisinden alıyoruz ---
            final bannerHex = data['bannerColor'] as String?;
            Color? parsedBannerColor;
            if (bannerHex != null && bannerHex.isNotEmpty) {
              parsedBannerColor = Color(
                int.parse('FF${bannerHex.replaceAll('#', '')}', radix: 16),
              );
            }

            final bgGradientStart =
                parsedBannerColor ??
                (isDark ? const Color(0xFF0D2410) : const Color(0xFFE8F5E9));

            // GRADIENT ARKA PLAN BURAYA GELDİ (Böylece veriye göre anında güncellenir)
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [bgGradientStart, bgGradientEnd],
                  stops: const [0.0, 0.3], // 0.3 banner hissi için idealdir
                ),
              ),
              child: NestedScrollView(
                headerSliverBuilder: (context, inner) {
                  return [
                    SliverAppBar(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      scrolledUnderElevation: 0,
                      surfaceTintColor: Colors.transparent,
                      automaticallyImplyLeading: true,
                      leading: IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.arrow_back,
                            color: isDark
                                ? const Color.fromARGB(255, 255, 255, 255)
                                : const Color.fromARGB(255, 0, 0, 0),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      actions: [
                        IconButton(
                          tooltip: 'Profil seçenekleri',
                          onPressed: () => _showProfileActions(titleText),
                          icon: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: 0.72),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                            child: Icon(
                              Icons.more_horiz_rounded,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                    SliverToBoxAdapter(
                      child: Stack(
                        children: [
                          Column(
                            children: [
                              // Devasa boşluğu burada kaldırmıştık
                              const SizedBox(height: 16),

                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: ProfileAchievementsBar(
                                  streak: streakCount,
                                  badgeIds: badgeIds,
                                  onStreakTap: streakCount > 0
                                      ? showStreakDetails
                                      : null,
                                ),
                              ),

                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    GestureDetector(
                                      onTap: () => _showEnlargedImage(photoURL),
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: primaryGreen,
                                            width: 2,
                                          ),
                                        ),
                                        child: CircleAvatar(
                                          radius: 36,
                                          backgroundColor: Colors.grey.shade800,
                                          backgroundImage: photoURL.isNotEmpty
                                              ? NetworkImage(photoURL)
                                              : null,
                                          child: photoURL.isEmpty
                                              ? Text(
                                                  displayName.isNotEmpty
                                                      ? displayName[0]
                                                            .toUpperCase()
                                                      : '?',
                                                  style: const TextStyle(
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : null,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            titleText,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                  color: isDark
                                                      ? const Color.fromARGB(
                                                          255,
                                                          255,
                                                          255,
                                                          255,
                                                        )
                                                      : const Color.fromARGB(
                                                          255,
                                                          0,
                                                          0,
                                                          0,
                                                        ),
                                                  fontWeight: FontWeight.w600,
                                                  shadows: [
                                                    Shadow(
                                                      color: Colors.black
                                                          .withOpacity(0.5),
                                                      blurRadius: 4,
                                                    ),
                                                  ],
                                                ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (displayName.isNotEmpty &&
                                              titleText != displayName)
                                            Text(
                                              displayName,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: isDark
                                                        ? Colors.white70
                                                        : Colors.black54,
                                                  ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          const SizedBox(height: 7),
                                          Row(
                                            children: [
                                              ProfileStat(
                                                label: 'Takipçi',
                                                value: _followersCount ?? 0,
                                                onTap: () => _showUserList(
                                                  'Takipçiler',
                                                  'followers',
                                                ),
                                              ),
                                              const SizedBox(width: 24),
                                              ProfileStat(
                                                label: 'Takip edilen',
                                                value: _followingCount ?? 0,
                                                onTap: () => _showUserList(
                                                  'Takip Edilenler',
                                                  'following',
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (lb.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                                bottom: 4,
                                              ),
                                              child: Text(
                                                'Letterboxd: @$lb',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      color: isDark
                                                          ? Colors.white
                                                          : Colors.black,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 16),

                              if (_isBlocked || _hasBlockedMe)
                                Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error.withOpacity(0.4),
                                    ),
                                  ),
                                  child: Row(
                                    children: const [
                                      Icon(Icons.block, size: 16),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Bu kullanıcıyla etkileşim engellendi.',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    if (!_isBlocked &&
                                        !_hasBlockedMe &&
                                        FirebaseAuth
                                                .instance
                                                .currentUser
                                                ?.uid !=
                                            widget.uid) ...[
                                      Expanded(
                                        child: FilledButton.tonalIcon(
                                          onPressed: () {
                                            final myUid = FirebaseAuth
                                                .instance
                                                .currentUser
                                                ?.uid;
                                            if (myUid == null) return;
                                            final chatId = ChatService.instance
                                                .chatIdFor(myUid, widget.uid);
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => ChatRoomScreen(
                                                  chatId: chatId,
                                                  otherUid: widget.uid,
                                                ),
                                              ),
                                            );
                                          },
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                            backgroundColor: isDark
                                                ? Colors.white24
                                                : Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          icon: Icon(
                                            Icons.message_rounded,
                                            size: 20,
                                            color: primaryGreen,
                                          ),
                                          label: Text(
                                            'Mesaj',
                                            style: TextStyle(
                                              color: primaryGreen,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (FirebaseAuth
                                                  .instance
                                                  .currentUser
                                                  ?.uid !=
                                              null &&
                                          FirebaseAuth
                                                  .instance
                                                  .currentUser!
                                                  .uid !=
                                              widget.uid)
                                        const SizedBox(width: 10),
                                    ],
                                    if (FirebaseAuth
                                                .instance
                                                .currentUser
                                                ?.uid !=
                                            null &&
                                        FirebaseAuth
                                                .instance
                                                .currentUser!
                                                .uid !=
                                            widget.uid)
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed:
                                              (_followBusy ||
                                                  _isBlocked ||
                                                  _hasBlockedMe)
                                              ? null
                                              : _toggleFollow,
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                _isFollowing == true
                                                ? Colors.grey.shade800
                                                : primaryGreen,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          icon: _followBusy
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                )
                                              : Icon(
                                                  _isFollowing == true
                                                      ? Icons.check
                                                      : Icons.person_add,
                                                  size: 20,
                                                ),
                                          label: Text(
                                            _isFollowing == true
                                                ? 'Takip Ediliyor'
                                                : 'Takip Et',
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              if (!_isBlocked && !_hasBlockedMe)
                                _buildProfileOverview(data),

                              if (!_isBlocked && !_hasBlockedMe)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Container(
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.black45
                                          : Colors.white.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: TabBar(
                                      isScrollable: false,
                                      indicator: BoxDecoration(
                                        color: primaryGreen,
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: primaryGreen.withOpacity(
                                              0.4,
                                            ),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      indicatorSize: TabBarIndicatorSize.tab,
                                      dividerColor: Colors.transparent,
                                      labelPadding: EdgeInsets.zero,
                                      labelStyle: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                      unselectedLabelStyle: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13,
                                      ),
                                      labelColor: Colors.white,
                                      unselectedLabelColor: isDark
                                          ? Colors.white60
                                          : Colors.black54,
                                      overlayColor: WidgetStateProperty.all(
                                        Colors.transparent,
                                      ),
                                      tabs: const [
                                        Tab(text: 'Filmler', height: 40),
                                        Tab(text: 'Aktiviteler', height: 40),
                                        Tab(text: 'Listeler', height: 40),
                                      ],
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 8),
                            ],
                          ),
                          if (_matchScore != null && _matchScore! > 0)
                            Positioned(
                              top:
                                  MediaQuery.of(context).padding.top +
                                  kToolbarHeight +
                                  10,
                              right: 16,
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Colors.green.shade600,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 6,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '%$_matchScore',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                        height: 1.0,
                                      ),
                                    ),
                                    const Text(
                                      'UYUM',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 7,
                                        fontWeight: FontWeight.w500,
                                        height: 1.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ];
                },
                body: (_isBlocked || _hasBlockedMe)
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 48,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Bu profil gizlidir.',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : TabBarView(
                        children: [
                          _buildMoviesTab(data),
                          _ActivitiesTab(uid: widget.uid),
                          _PublicListsTab(uid: widget.uid),
                        ],
                      ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProfileOverview(Map<String, dynamic> data) {
    final favKeys = List<String>.from(data['favoritesKeys'] ?? const []);
    final bio = (data['bio'] ?? '').toString();
    final age = data['age'];
    final genres = List<dynamic>.from(data['favGenres'] ?? const []);
    final directors = List<dynamic>.from(data['favDirectors'] ?? const []);
    final actors = List<dynamic>.from(data['favActors'] ?? const []);
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bio.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                bio,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.4, color: textColor),
              ),
            ),
          if (age is num && age > 0)
            Row(
              children: [
                Icon(Icons.cake_outlined, size: 18, color: textColor),
                const SizedBox(width: 6),
                Text('Yaş: ${age.toInt()}', style: TextStyle(color: textColor)),
              ],
            ),
          if (favKeys.isNotEmpty)
            _shelfSectionFromKeys('Favori Filmler', favKeys, maxItems: 30),
          ProfilePreferenceSection(title: 'Favori türler', items: genres),
          ProfilePreferenceSection(
            title: 'Favori yönetmenler',
            items: directors,
            showPortraits: true,
            onPersonTap: (id, name) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      DirectorScreen(directorId: id, directorName: name),
                ),
              );
            },
          ),
          ProfilePreferenceSection(
            title: 'Favori oyuncular',
            items: actors,
            showPortraits: true,
            onPersonTap: (id, name) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ActorScreen(actorId: id, actorName: name),
                ),
              );
            },
          ),
          RecentWatchedMovies(
            uid: widget.uid,
            displayName:
                (data['displayName'] ?? data['username'] ?? 'Kullanıcı')
                    .toString(),
            entries: List<dynamic>.from(data['recentDiaryEntries'] ?? const []),
          ),
        ],
      ),
    );
  }

  Widget _buildMoviesTab(Map<String, dynamic> data) {
    final fiveKeys = List<String>.from(data['fiveStarKeys'] ?? const []);
    final disKeys = List<String>.from(data['dislikedKeys'] ?? const []);
    final watchlistKeys = List<String>.from(data['watchlistKeys'] ?? const []);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        MediaQuery.paddingOf(context).bottom + 8,
      ),
      children: [
        if (fiveKeys.isNotEmpty) ...[
          _shelfSectionFromKeys(
            'Sevdiği Filmler',
            fiveKeys,
            maxItems: 30,
            accentColor: const Color(0xFFFF9800),
          ),
          if (disKeys.isNotEmpty || watchlistKeys.isNotEmpty)
            const HairlineDivider(),
        ],
        if (disKeys.isNotEmpty) ...[
          _shelfSectionFromKeys(
            'Sevmediği Filmler',
            disKeys,
            maxItems: 30,
            accentColor: const Color(0xFFE53935),
          ),
          if (watchlistKeys.isNotEmpty) const HairlineDivider(),
        ],

        if (watchlistKeys.isNotEmpty) ...[
          _buildSectionHeader(
            'Watchlist',
            watchlistKeys,
            accentColor: const Color(0xFF2196F3),
          ),
          _WatchlistSection(
            data: data,
            watchlistFutureCache: _watchlistFutureCache,
            fetchCatalog: _fetchCatalogForKeys,
            onFilmTap: _handleFilmTap,
          ),
        ],
      ],
    );
  }
}

// --- YARDIMCI WIDGETLAR ---

class _WatchlistSection extends StatelessWidget {
  final Map<String, dynamic> data;
  final Map<String, Future<List<Map<String, dynamic>?>>> watchlistFutureCache;
  final Future<List<Map<String, dynamic>?>> Function(List<String>) fetchCatalog;
  final Function(String, String, String?, int?) onFilmTap;

  const _WatchlistSection({
    required this.data,
    required this.watchlistFutureCache,
    required this.fetchCatalog,
    required this.onFilmTap,
  });

  int? _extractTmdbId(Map<String, dynamic> m) {
    final val = m['tmdbId'];
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final posterWidth = profilePosterWidth(context);
    final posterHeight = profilePosterHeight(context);
    final List<dynamic> keysDyn =
        (data['watchlistKeys'] ?? []) as List<dynamic>;
    final keys = keysDyn
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
    final limited = keys.take(30).toList();
    final hash = limited.join('|');

    return FutureBuilder<List<Map<String, dynamic>?>>(
      future: limited.isEmpty
          ? Future.value([])
          : (watchlistFutureCache[hash] ??= fetchCatalog(limited)),
      builder: (context, fsnap) {
        if (fsnap.connectionState == ConnectionState.waiting)
          return SizedBox(
            height: posterHeight,
            child: Center(child: CircularProgressIndicator()),
          );
        final films = (fsnap.data ?? [])
            .where((m) => m != null)
            .map((m) => m!)
            .toList();
        if (films.isEmpty) return const Text('Watchlist boş.');
        return SizedBox(
          height: posterHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: films.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final film = films[i];
              final poster =
                  (film['poster'] ?? film['posterUrl'] ?? '') as String;
              final title = (film['title'] ?? '') as String;
              final tmdbId = _extractTmdbId(film);
              final docId = (film['docId'] ?? limited[i]).toString();

              return GestureDetector(
                onTap: () => onFilmTap(title, poster, docId, tmdbId),
                child: SizedBox(
                  width: posterWidth,
                  child: ClipRRect(
                    borderRadius: BorderRadius.zero,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PosterImage(
                          posterUrl: poster,
                          tmdbId: tmdbId,
                          title: title,
                          fit: BoxFit.cover,
                        ),
                        if (title.isNotEmpty)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              color: Colors.black54,
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// --- DİĞER SEKME İÇERİKLERİ ---

class _ActivitiesTab extends StatefulWidget {
  final String uid;
  const _ActivitiesTab({required this.uid});

  @override
  State<_ActivitiesTab> createState() => _ActivitiesTabState();
}

class _ActivitiesTabState extends State<_ActivitiesTab>
    with AutomaticKeepAliveClientMixin {
  bool _loadingActivities = false;
  List<_ActivityItemData> _activities = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (mounted) setState(() => _loadingActivities = true);
    final db = FirebaseFirestore.instance;
    final List<_ActivityItemData> items = [];
    try {
      final q = db
          .collection('posts')
          .where('authorId', isEqualTo: widget.uid)
          .orderBy('createdAt', descending: true)
          .limit(30);
      final qs = await q.get();
      for (final d in qs.docs) {
        final m = d.data();
        final ts = m['createdAt'];
        final poster =
            (m['moviePoster'] ??
                    m['moviePosterUrl'] ??
                    m['poster'] ??
                    (m['movie'] is Map
                        ? (m['movie']['poster'] ?? m['movie']['posterUrl'])
                        : '') ??
                    '')
                .toString();
        final title =
            (m['movieTitle'] ??
                    m['title'] ??
                    (m['movie'] is Map ? (m['movie']['title'] ?? '') : '') ??
                    '')
                .toString();

        final tmdbId =
            (m['movie'] is Map ? m['movie']['id'] : null) ?? m['tmdbId'];

        items.add(
          _ActivityItemData(
            id: d.id,
            text: (m['text'] ?? '').toString(),
            createdAt: ts is Timestamp ? ts.toDate() : null,
            posterUrl: poster,
            title: title,
            likeCount: ((m['likeCount'] ?? 0) as num).toInt(),
            replyCount: ((m['replyCount'] ?? 0) as num).toInt(),
            tmdbId: (tmdbId is int) ? tmdbId : null,
          ),
        );
      }
    } catch (_) {}

    items.sort(
      (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
        a.createdAt?.millisecondsSinceEpoch ?? 0,
      ),
    );

    if (mounted) {
      setState(() {
        _activities = items;
        _loadingActivities = false;
      });
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}g';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return RefreshIndicator(
      onRefresh: _loadActivities,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.paddingOf(context).bottom + 8,
        ),
        children: [
          Row(
            children: [
              Text(
                'Aktiviteler',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingActivities)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_activities.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Henüz aktivite yok.',
                style: TextStyle(color: textColor.withOpacity(0.7)),
              ),
            )
          else
            ListView.separated(
              itemCount: _activities.length,
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              separatorBuilder: (_, _) => const Column(
                children: [
                  SizedBox(height: 6),
                  HairlineDivider(),
                  SizedBox(height: 6),
                ],
              ),
              itemBuilder: (context, i) {
                final a = _activities[i];
                final when = a.createdAt;
                String timeLabel = '';
                if (when != null) {
                  timeLabel = _timeAgo(when);
                }
                return _ActivityWidget(item: a, timeLabel: timeLabel);
              },
            ),
        ],
      ),
    );
  }
}

class _ActivityWidget extends StatelessWidget {
  final _ActivityItemData item;
  final String timeLabel;
  const _ActivityWidget({required this.item, required this.timeLabel});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PostDetailScreen(postId: item.id)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((item.posterUrl).isNotEmpty || item.tmdbId != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.zero,
                child: PosterImage(
                  posterUrl: item.posterUrl,
                  title: item.title,
                  tmdbId: item.tmdbId,
                  width: 44,
                  height: 66,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        item.text,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: textColor),
                      ),
                    ),
                  if (item.title.isNotEmpty &&
                      item.posterUrl.isEmpty &&
                      item.tmdbId == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.local_movies,
                            size: 16,
                            color: subTextColor,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: subTextColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.favorite_border,
                          size: 16,
                          color: subTextColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${item.likeCount}',
                          style: TextStyle(color: subTextColor),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.mode_comment_outlined,
                          size: 16,
                          color: subTextColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${item.replyCount}',
                          style: TextStyle(color: subTextColor),
                        ),
                        const Spacer(),
                        if (timeLabel.isNotEmpty)
                          Text(
                            'Paylaştı $timeLabel',
                            style: TextStyle(color: subTextColor, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicListsTab extends StatefulWidget {
  final String uid;
  const _PublicListsTab({required this.uid});

  @override
  State<_PublicListsTab> createState() => _PublicListsTabState();
}

class _PublicListsTabState extends State<_PublicListsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
        setState(() {});
      },
      child: StreamBuilder<List<CustomList>>(
        stream: CustomListService.instance.getUserLists(widget.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          final lists = snapshot.data ?? [];

          final publicLists = lists.where((l) => l.isPublic).toList();

          if (publicLists.isEmpty) {
            return Center(
              child: Text(
                "Henüz liste oluşturulmamış.",
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              MediaQuery.paddingOf(context).bottom + 8,
            ),
            itemCount: publicLists.length,
            itemBuilder: (context, index) {
              final list = publicLists[index];
              return _CustomListCard(list: list);
            },
          );
        },
      ),
    );
  }
}

class _CustomListCard extends StatelessWidget {
  final CustomList list;
  const _CustomListCard({required this.list});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CustomListDetailScreen(list: list, isMyList: false),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 100,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.zero,
              child: SizedBox(
                width: 70,
                height: double.infinity,
                child: list.coverImageUrl != null
                    ? PosterImage(
                        posterUrl: list.coverImageUrl!,
                        title: list.title,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: Colors.grey.shade800,
                        child: const Icon(Icons.list, color: Colors.white24),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    list.title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${list.movieCount} film',
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

class _UserListSheet extends StatefulWidget {
  final String title;
  final String uid;
  final String collection;

  const _UserListSheet({
    required this.title,
    required this.uid,
    required this.collection,
  });

  @override
  State<_UserListSheet> createState() => _UserListSheetState();
}

class _UserListSheetState extends State<_UserListSheet> {
  final Map<String, Future<DocumentSnapshot>> _userFutureCache = {};
  final Map<String, DocumentSnapshot> _userSnapshotCache = {};

  Future<DocumentSnapshot> _loadUser(String uid) {
    return _userFutureCache.putIfAbsent(uid, () async {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      _userSnapshotCache[uid] = snap;
      return snap;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final uid = widget.uid;
    final collection = widget.collection;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const HairlineDivider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection(collection)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('Liste boş.'));
                }
                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, _) =>
                      const HairlineDivider(indent: 72, endIndent: 16),
                  itemBuilder: (context, index) {
                    final docId = docs[index].id;
                    return FutureBuilder<DocumentSnapshot>(
                      future: _loadUser(docId),
                      initialData: _userSnapshotCache[docId],
                      builder: (context, userSnap) {
                        if (!userSnap.hasData)
                          return const ListTile(title: Text('Yükleniyor...'));
                        if (!userSnap.data!.exists) {
                          return const SizedBox.shrink();
                        }
                        final data =
                            userSnap.data!.data() as Map<String, dynamic>?;
                        final name =
                            data?['displayName'] ??
                            data?['username'] ??
                            'Kullanıcı';
                        final photo = data?['photoURL'];

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: (photo != null)
                                ? NetworkImage(photo)
                                : null,
                            child: photo == null
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          title: Text(name),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PublicProfileScreen(uid: docId),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
