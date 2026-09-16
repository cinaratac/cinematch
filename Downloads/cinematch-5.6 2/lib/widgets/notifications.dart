import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import 'package:fluttergirdi/screens/post_detail_screen.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';

// --- YENİ EKLENEN: Merkezi Önbellek Servisi ---
import '../services/user_cache_service.dart';

/// AppBar içinde kullan: NotificationsButton()
class NotificationsButton extends StatelessWidget {
  const NotificationsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final cs = Theme.of(context).colorScheme;
    
    if (uid == null) {
      return IconButton(
        icon: const Icon(Icons.favorite_border), // Instagram tarzı kalp ikonu
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bildirimler için giriş yapmalısın.')),
          );
        },
      );
    }

    final q = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(20);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        final unread = snap.data?.docs.length ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Bildirimler',
              icon: Icon(unread > 0 ? Icons.favorite : Icons.favorite_border, color: unread > 0 ? cs.error : null),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => NotificationsScreen(uid: uid)),
                );
              },
            ),
            if (unread > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.error,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2), // IG tarzı çerçeve
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Text(
                    unread > 9 ? '9+' : unread.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// TAM SAYFA BİLDİRİM EKRANI
// ============================================================================
class NotificationsScreen extends StatefulWidget {
  final String uid;
  const NotificationsScreen({super.key, required this.uid});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final Query<Map<String, dynamic>> _q;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _notificationsStream;

  @override
  void initState() {
    super.initState();
    final threeMonthsAgo = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 90)));

    _q = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('notifications')
        .where('createdAt', isGreaterThanOrEqualTo: threeMonthsAgo)
        .orderBy('createdAt', descending: true)
        .limit(100);

    _notificationsStream = _q.snapshots();

    // Sayfa açıldığında arka planda okundu işaretle
    NotificationService.I.markAllAsRead(widget.uid);
    NotificationService.I.deleteOldNotifications(widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Bildirimler',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _notificationsStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_border, size: 64, color: cs.onSurfaceVariant.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  Text(
                    'Hareket Yok', 
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Henüz bildirimin bulunmuyor.', 
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)
                  )
                ],
              ),
            );
          }

          // --- MERKEZİ CACHE KULLANIMI ---
          final Set<String> actorIds = {};
          for (var doc in docs) {
            final aId = doc.data()['actorId'];
            if (aId != null && aId.toString().isNotEmpty) {
              actorIds.add(aId.toString());
            }
          }
          final missingIds = actorIds.where((id) => UserCacheService.instance.getFromCache(id) == null).toList();
          if (missingIds.isNotEmpty) {
            Future.microtask(() async {
              await UserCacheService.instance.fetchUsers(missingIds);
              if (mounted) setState(() {}); 
            });
          }
          // ----------------------------------------------------------------------------------

          // BEĞENİLERİ GRUPLA
          final List<dynamic> displayItems = [];
          final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> likeGroups = {};

          for (var doc in docs) {
            final data = doc.data();
            final type = (data['type'] ?? '').toString();
            final postId = (data['postId'] ?? '').toString();

            if (type == 'like' && postId.isNotEmpty && postId != '-') {
              likeGroups.putIfAbsent(postId, () => []).add(doc);
            } else {
              displayItems.add(doc);
            }
          }

          likeGroups.forEach((postId, groupDocs) {
            if (groupDocs.length == 1) {
              displayItems.add(groupDocs.first);
            } else {
              displayItems.add({
                'isGroupedLike': true,
                'postId': postId,
                'docs': groupDocs,
              });
            }
          });

          // TARİHE GÖRE SIRALA
          displayItems.sort((a, b) {
            Timestamp? tA = a is QueryDocumentSnapshot 
                ? (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp? 
                : a['createdAt'] as Timestamp?;
            Timestamp? tB = b is QueryDocumentSnapshot 
                ? (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp? 
                : b['createdAt'] as Timestamp?;
                
            if (tA == null || tB == null) return 0;
            return tB.compareTo(tA);
          });

          return ListView.builder(
            itemCount: displayItems.length,
            // Instagram'da çizgiler yoktur, Padding ile ferah bir görünüm sağlanır
            padding: const EdgeInsets.symmetric(vertical: 8), 
            itemBuilder: (context, i) {
              final item = displayItems[i];

              if (item is Map && item['isGroupedLike'] == true) {
                return _GroupedNotificationTile(
                  postId: item['postId'],
                  docs: item['docs'],
                );
              } else {
                return _SingleNotificationTile(
                  doc: item as QueryDocumentSnapshot<Map<String, dynamic>>,
                );
              }
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// 1. TEKİL BİLDİRİM KARTI (Instagram Stili)
// ============================================================================
class _SingleNotificationTile extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _SingleNotificationTile({required this.doc});

  @override
  State<_SingleNotificationTile> createState() => _SingleNotificationTileState();
}

class _SingleNotificationTileState extends State<_SingleNotificationTile> {
  CachedUser? actor;

  @override
  void initState() {
    super.initState();
    _loadActor();
  }

  void _loadActor() async {
    final m = widget.doc.data();
    final actorId = (m['actorId'] ?? '').toString();
    
    if (actorId.isEmpty) return;

    final cached = UserCacheService.instance.getFromCache(actorId);
    if (cached != null) {
      if (mounted) setState(() => actor = cached);
      return; 
    }

    final fallback = CachedUser(
      uid: actorId,
      displayName: (m['actorName'] ?? '').toString(),
      handle: (m['actorHandle'] ?? '').toString(),
      photoURL: (m['actorPhotoURL'] ?? '').toString(),
    );
    if (mounted) setState(() => actor = fallback);

    final fetched = await UserCacheService.instance.getUser(actorId);
    if (fetched != null && mounted) {
      setState(() => actor = fetched);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final m = widget.doc.data();
    final type = (m['type'] ?? '').toString();
    final actorId = (m['actorId'] ?? '').toString();
    final count = (m['count'] as num?)?.toInt() ?? 1;
    final createdAt = m['createdAt'] as Timestamp?;
    final read = (m['read'] ?? false) == true;

    final timeLabel = createdAt != null ? _timeAgoShort(createdAt.toDate()) : '';
    final actionText = _actionTextFor(type, count);

    void goToProfile() {
      if (actorId.isNotEmpty) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: actorId)));
      }
    }

    void goToContent() {
      final postId = (m['postId'] ?? '').toString();
      if (type == 'follow') {
        goToProfile();
      } else if ((type == 'like' || type == 'comment' || type == 'comment_reply') && postId.isNotEmpty && postId != '-') {
        Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)));
      } else if (type == 'club_request') {
        final clubId = (m['clubId'] ?? '').toString();
        final clubName = (m['clubName'] ?? '').toString();
        if (clubId.isNotEmpty) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => ChatRoomScreen(
            chatId: clubId, otherUid: '', otherTitle: clubName, isGroup: true, groupName: clubName,
          )));
        }
      }
    }

    final displayName = actor?.handle.isNotEmpty == true ? actor!.handle : (actor?.displayName.isNotEmpty == true ? actor!.displayName : 'Kullanıcı');

    return InkWell(
      onTap: () {
        widget.doc.reference.update({'read': true});
        goToContent(); 
      },
      child: Container(
        color: read ? Colors.transparent : (isDark ? Colors.blue.withOpacity(0.1) : Colors.blue.withOpacity(0.05)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: goToProfile,
              child: _Avatar(url: actor?.photoURL, radius: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.3),
                  children: [
                    TextSpan(
                      text: displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(text: ' $actionText. '),
                    TextSpan(
                      text: timeLabel,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            // Opsiyonel: Sağ tarafa postun küçük resmini koymak istersen burayı kullanabilirsin.
            // Şimdilik sadece okunmamışsa ufak bir mavi nokta koyuyoruz.
            if (!read)
              Container(
                margin: const EdgeInsets.only(left: 8),
                width: 8, height: 8, 
                decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle)
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 2. ÇOKLU (GRUPLANMIŞ) BİLDİRİM KARTI (Instagram Stili)
// ============================================================================
class _GroupedNotificationTile extends StatefulWidget {
  final String postId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  
  const _GroupedNotificationTile({required this.postId, required this.docs});

  @override
  State<_GroupedNotificationTile> createState() => _GroupedNotificationTileState();
}

class _GroupedNotificationTileState extends State<_GroupedNotificationTile> {
  CachedUser? actor1;
  CachedUser? actor2;

  @override
  void initState() {
    super.initState();
    _loadActors();
  }

  void _loadActors() async {
    final firstData = widget.docs[0].data();
    final secondData = widget.docs[1].data();
    
    final id1 = (firstData['actorId'] ?? '').toString();
    final id2 = (secondData['actorId'] ?? '').toString();

    actor1 = await _resolveActor(id1, firstData);
    actor2 = await _resolveActor(id2, secondData);
    
    if (mounted) setState(() {});
  }

  Future<CachedUser> _resolveActor(String actorId, Map<String, dynamic> m) async {
    if (actorId.isEmpty) return CachedUser(uid: '', displayName: '', handle: '', photoURL: '');
    
    final cached = UserCacheService.instance.getFromCache(actorId);
    if (cached != null) return cached;

    final tempActor = CachedUser(
      uid: actorId,
      displayName: (m['actorName'] ?? '').toString(),
      handle: (m['actorHandle'] ?? '').toString(),
      photoURL: (m['actorPhotoURL'] ?? '').toString(),
    );

    try {
      final fetched = await UserCacheService.instance.getUser(actorId);
      if (fetched != null) return fetched;
    } catch (_) {}
    return tempActor;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final firstData = widget.docs[0].data();
    final createdAt = firstData['createdAt'] as Timestamp?;
    final timeLabel = createdAt != null ? _timeAgoShort(createdAt.toDate()) : '';
    final othersCount = widget.docs.length - 1;

    String name = 'Bir kullanıcı';
    if (actor1 != null) {
      if (actor1!.handle.isNotEmpty) name = actor1!.handle;
      else if (actor1!.displayName.isNotEmpty) name = actor1!.displayName;
    }

    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: widget.postId)));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                      ),
                      child: _Avatar(url: actor2?.photoURL, radius: 18),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    bottom: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                      ),
                      child: _Avatar(url: actor1?.photoURL, radius: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: RichText(
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.3),
                  children: [
                    TextSpan(
                      text: name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextSpan(
                      text: ' ve ',
                    ),
                    TextSpan(
                      text: '$othersCount diğer kişi',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(text: ' gönderini beğendi. '),
                    TextSpan(
                      text: timeLabel,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// YARDIMCI FONKSİYONLAR
// ============================================================================

String _actionTextFor(String type, int count) {
  final suffix = count > 1 ? ' ve ${count - 1} diğer kişi' : '';
  switch (type) {
    case 'like': return 'gönderini beğendi$suffix';
    case 'comment': return 'gönderine yorum yaptı$suffix';
    case 'comment_reply': return 'yorumunu yanıtladı';
    case 'follow': return 'seni takip etmeye başladı';
    case 'club_request': return 'kulübüne katılmak istiyor';
    default: return 'bir etkinlikte bulundu';
  }
}

String _timeAgoShort(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y';
  if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}a';
  if (diff.inDays > 0) return '${diff.inDays}g';
  if (diff.inHours > 0) return '${diff.inHours}s';
  if (diff.inMinutes > 0) return '${diff.inMinutes}d';
  return 'Az önce';
}

// Avatar widgetı boyutlandırma desteği ile
class _Avatar extends StatelessWidget {
  final String? url;
  final double radius;
  const _Avatar({this.url, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    if (url != null && url!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: url!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(color: Colors.grey.shade200, width: size, height: size, child: Icon(Icons.person, color: Colors.grey, size: radius)),
          errorWidget: (context, url, error) => Container(color: Colors.grey.shade200, width: size, height: size, child: Icon(Icons.person, color: Colors.grey, size: radius)),
        ),
      );
    }
    return CircleAvatar(radius: radius, child: Icon(Icons.person, size: radius));
  }
}
