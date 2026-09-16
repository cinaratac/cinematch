import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/services/club_service.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/widgets/club_sheets.dart';
import '../services/user_cache_service.dart';

// =============================================================================
// HAFTANIN FİLMİ BANNERI
// =============================================================================
class FeaturedMovieBannerWidget extends StatelessWidget {
  final Map<String, dynamic> movie;
  const FeaturedMovieBannerWidget({super.key, required this.movie});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF252525) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final border = isDark
        ? Colors.amber.withOpacity(0.3)
        : Colors.amber.withOpacity(0.5);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 1),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(bottom: BorderSide(color: border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (movie['id'] != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MovieDetailScreen(tmdbId: movie['id']),
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.amber,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.star, color: Colors.black, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'HAFTANIN FİLMİ',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.amber,
                          fontSize: 10,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        movie['title'] ?? 'Film',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: textColor,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// BOŞ SOHBET GÖRÜNÜMÜ
// =============================================================================
class EmptyChatView extends StatelessWidget {
  const EmptyChatView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white54 : Colors.black54;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 48, color: color),
          const SizedBox(height: 16),
          Text('Sohbete başla!', style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

// =============================================================================
// GÜN AYIRICI (Instagram DM tarzı: Bugün / Dün / Çrş, 25 Haziran)
// =============================================================================
class DateSeparator extends StatelessWidget {
  final DateTime date;

  const DateSeparator({super.key, required this.date});

  static const _dayNames = ['Pzt', 'Sal', 'Çrş', 'Prş', 'Cum', 'Cmt', 'Paz'];

  static const _monthNames = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final thatDay = DateTime(date.year, date.month, date.day);

    if (thatDay == today) return 'Bugün';
    if (thatDay == yesterday) return 'Dün';

    final dayName = _dayNames[date.weekday - 1];
    final monthName = _monthNames[date.month - 1];

    if (date.year == now.year) {
      return '$dayName, ${date.day} $monthName';
    }
    return '$dayName, ${date.day} $monthName ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.06);
    final textColor = isDark ? Colors.white70 : Colors.black54;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _label(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// MESAJ TESLİM DURUMU (Gönderildi / Teslim Edildi / Görüldü)
// =============================================================================
enum MessageDeliveryStatus { sent, delivered, read }

// =============================================================================
// MESAJ SATIRI
// =============================================================================
class MessageRow extends StatelessWidget {
  final String text;
  final dynamic movie;
  final bool isMine;
  final DateTime? timestamp;
  final String authorId;
  final String? type;
  final dynamic eventData;
  final dynamic pollData;
  final String? chatId;
  final MessageDeliveryStatus? deliveryStatus;
  final Map<String, dynamic>? replyTo;
  final Map<String, List<String>> reactions;
  final String currentUserId;
  final ValueChanged<String>? onReactionTap;

  const MessageRow({
    super.key,
    required this.text,
    this.movie,
    required this.isMine,
    this.timestamp,
    required this.authorId,
    this.type,
    this.eventData,
    this.pollData,
    this.chatId,
    this.deliveryStatus,
    this.replyTo,
    this.reactions = const {},
    this.currentUserId = '',
    this.onReactionTap,
  });

  @override
  Widget build(BuildContext context) {
    final bubble = type == 'event' && eventData != null
        ? _EventMessageBubble(
            data: eventData,
            isMine: isMine,
            timestamp: timestamp,
            chatId: chatId,
          )
        : type == 'poll' && pollData != null
        ? _PollMessageBubble(
            initialData: pollData,
            isMine: isMine,
            timestamp: timestamp,
            chatId: chatId,
          )
        : MessageBubble(
            text: text,
            movie: movie,
            isMine: isMine,
            timestamp: timestamp,
            deliveryStatus: isMine ? deliveryStatus : null,
            replyTo: replyTo,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isMine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMine) ...[
                UserAvatar(uid: authorId, size: 16),
                const SizedBox(width: 8),
              ],
              bubble,
              if (isMine) const SizedBox(width: 8),
            ],
          ),
          if (reactions.values.any((users) => users.isNotEmpty))
            Padding(
              padding: EdgeInsets.only(
                top: 3,
                left: isMine ? 0 : 40,
                right: isMine ? 8 : 0,
              ),
              child: _MessageReactionSummary(
                reactions: reactions,
                currentUserId: currentUserId,
                onTap: onReactionTap,
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageReactionSummary extends StatelessWidget {
  final Map<String, List<String>> reactions;
  final String currentUserId;
  final ValueChanged<String>? onTap;

  const _MessageReactionSummary({
    required this.reactions,
    required this.currentUserId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final entries = reactions.entries
        .where((entry) => entry.value.isNotEmpty)
        .toList(growable: false);

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: entries
          .map((entry) {
            final selected = entry.value.contains(currentUserId);
            return Material(
              color: selected
                  ? colors.primaryContainer
                  : colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap == null ? null : () => onTap!(entry.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  child: Text(
                    '${entry.key} ${entry.value.length}',
                    style: TextStyle(
                      color: selected
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

// =============================================================================
// MESAJ BALONU
// =============================================================================
// =============================================================================
// TESLİM/OKUNDU TİKLERİ (WhatsApp tarzı)
// =============================================================================
class _DeliveryTicks extends StatelessWidget {
  final MessageDeliveryStatus status;
  final Color baseColor;

  const _DeliveryTicks({required this.status, required this.baseColor});

  @override
  Widget build(BuildContext context) {
    // Görüldü: mavi/vurgu renginde çift tik
    // Teslim edildi: soluk renkte çift tik
    // Gönderildi: soluk renkte tek tik
    final readColor = Colors.lightBlueAccent.shade100;

    switch (status) {
      case MessageDeliveryStatus.sent:
        return Icon(Icons.done, size: 14, color: baseColor);
      case MessageDeliveryStatus.delivered:
        return Icon(Icons.done_all, size: 14, color: baseColor);
      case MessageDeliveryStatus.read:
        return Icon(Icons.done_all, size: 14, color: readColor);
    }
  }
}

class MessageBubble extends StatelessWidget {
  final String text;
  final dynamic movie;
  final bool isMine;
  final DateTime? timestamp;
  final MessageDeliveryStatus? deliveryStatus;
  final Map<String, dynamic>? replyTo;

  const MessageBubble({
    super.key,
    required this.text,
    this.movie,
    required this.isMine,
    this.timestamp,
    this.deliveryStatus,
    this.replyTo,
  });

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thatDay = DateTime(dt.year, dt.month, dt.day);
    if (thatDay == today) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String posterUrl = '';
    String movieTitle = '';
    bool hasMovie = false;
    int? parsedMovieId;

    if (movie is Map) {
      final mm = Map<String, dynamic>.from(movie);
      posterUrl = (mm['poster'] ?? mm['posterUrl'] ?? '').toString();
      movieTitle = (mm['title'] ?? mm['name'] ?? '').toString();
      for (final key in ['id', 'tmdbId', 'movieId', 'movie_id']) {
        if (mm[key] != null) {
          parsedMovieId = int.tryParse(mm[key].toString());
          if (parsedMovieId != null) break;
        }
      }
      hasMovie = true;
    }

    final myGradient = LinearGradient(
      colors: [
        Theme.of(context).colorScheme.primary,
        Theme.of(context).colorScheme.primary.withOpacity(0.8),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    final otherColor = isDark ? const Color(0xFF2C2C2E) : Colors.grey.shade200;
    final textColor = isMine
        ? Colors.white
        : (isDark ? Colors.white : Colors.black87);
    final timeColor = isMine
        ? Colors.white70
        : (isDark ? Colors.white60 : Colors.black54);
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.70;
    const movieCardWidth = 200.0;

    return Container(
      constraints: BoxConstraints(maxWidth: maxBubbleWidth, minWidth: 40),
      decoration: BoxDecoration(
        gradient: isMine ? myGradient : null,
        color: isMine ? null : otherColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMine ? 20 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (replyTo != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
                  decoration: BoxDecoration(
                    color: isMine
                        ? Colors.black.withValues(alpha: 0.14)
                        : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border(
                      left: BorderSide(
                        color: isMine
                            ? Colors.white.withValues(alpha: 0.8)
                            : Theme.of(context).colorScheme.primary,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (replyTo!['authorName'] ?? 'Mesaj').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isMine
                              ? Colors.white
                              : Theme.of(context).colorScheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        (replyTo!['text'] ?? '').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: timeColor,
                          fontSize: 11,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              if (hasMovie)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  width: movieCardWidth,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.black26,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (parsedMovieId != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MovieDetailScreen(
                                tmdbId: parsedMovieId!,
                                title: movieTitle.isNotEmpty
                                    ? movieTitle
                                    : null,
                                posterUrl: posterUrl.isNotEmpty
                                    ? posterUrl
                                    : null,
                              ),
                            ),
                          );
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (posterUrl.isNotEmpty)
                            AspectRatio(
                              aspectRatio: 2 / 3,
                              child: PosterImage(
                                posterUrl: posterUrl,
                                title: movieTitle,
                                fit: BoxFit.cover,
                              ),
                            )
                          else
                            Container(
                              height: 120,
                              width: double.infinity,
                              color: Colors.grey.shade900,
                              child: const Center(
                                child: Icon(
                                  Icons.movie,
                                  size: 32,
                                  color: Colors.white24,
                                ),
                              ),
                            ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            color: Colors.black38,
                            child: Text(
                              movieTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: hasMovie ? movieCardWidth : maxBubbleWidth - 24,
                    ),
                    child: Text(
                      text,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              if (timestamp != null)
                Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(timestamp!),
                          style: TextStyle(fontSize: 10, color: timeColor),
                        ),
                        if (isMine && deliveryStatus != null) ...[
                          const SizedBox(width: 3),
                          _DeliveryTicks(
                            status: deliveryStatus!,
                            baseColor: timeColor,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// KULLANICI AVATARI
//
// DÜZELTME: initState'te senkron cache kontrolü → setState yok → rebuild yok.
// Sadece async fetch tamamlanınca ve değer gerçekten değiştiyse setState çağrılır.
// AutomaticKeepAliveClientMixin sayesinde liste scroll edilince fetch tekrarlanmaz.
// =============================================================================
class UserAvatar extends StatefulWidget {
  final String uid;
  final double size;
  const UserAvatar({super.key, required this.uid, this.size = 20});

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar>
    with AutomaticKeepAliveClientMixin {
  String? _photoUrl;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant UserAvatar old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid) _resolve();
  }

  void _resolve() {
    // Önce senkron RAM kontrolü — setState çağrısı yok, ekstra rebuild yok
    final cached = UserCacheService.instance.getFromCache(widget.uid);
    if (cached != null) {
      _photoUrl = cached.photoURL;
      return;
    }
    // RAM'de yoksa async fetch — sadece o zaman setState
    UserCacheService.instance.getUser(widget.uid).then((user) {
      if (mounted && user != null && _photoUrl != user.photoURL) {
        setState(() => _photoUrl = user.photoURL);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return CircleAvatar(
      radius: widget.size,
      backgroundImage: (_photoUrl != null && _photoUrl!.isNotEmpty)
          ? NetworkImage(_photoUrl!)
          : null,
      child: (_photoUrl == null || _photoUrl!.isEmpty)
          ? Icon(Icons.person, size: widget.size)
          : null,
    );
  }
}

// =============================================================================
// SOHBET AppBar BAŞLIĞI
//
// DÜZELTME 1 — Yanlış isim:
//   ESKİ: title = handle ?? displayName  (handle = "@username" — yanlış)
//   YENİ: title = initialTitle (titles[currentUid] = karşı tarafın adı — doğru)
//         Cache sadece FOTOĞRAF için kullanılır, ismi asla ezmez.
//
// DÜZELTME 2 — Yavaş açılma:
//   ESKİ: async getUser() → setState → rebuild (görünür gecikme)
//   YENİ: initState'te senkron cache okuma, setState sadece foto için
// =============================================================================
class ChatAppBarTitle extends StatefulWidget {
  final String chatId;
  final String otherUid;
  final String? initialTitle;
  final bool isGroup;
  final String? groupName;

  const ChatAppBarTitle({
    super.key,
    required this.chatId,
    required this.otherUid,
    this.initialTitle,
    required this.isGroup,
    this.groupName,
  });

  @override
  State<ChatAppBarTitle> createState() => _ChatAppBarTitleState();
}

class _ChatAppBarTitleState extends State<ChatAppBarTitle> {
  static final Map<String, Map<String, dynamic>> _groupCache = {};
  String? _photoUrl;

  @override
  void initState() {
    super.initState();
    if (!widget.isGroup) _resolvePhoto();
  }

  void _resolvePhoto() {
    // Senkron RAM kontrolü — initState içinde setState çağrılmaz
    final cached = UserCacheService.instance.getFromCache(widget.otherUid);
    if (cached != null) {
      _photoUrl = cached.photoURL;
      return;
    }
    // Sadece fotoğraf için async fetch
    UserCacheService.instance.getUser(widget.otherUid).then((user) {
      if (mounted && user != null && _photoUrl != user.photoURL) {
        setState(() => _photoUrl = user.photoURL);
      }
    });
  }

  void _openClubDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ClubDetailSheet(clubId: widget.chatId),
    );
  }

  bool _isOtherTyping(Map<String, dynamic>? data) {
    if (data == null || widget.otherUid.isEmpty) return false;

    final typing = data['typing'];
    if (typing is! Map || typing[widget.otherUid] != true) return false;

    final updatedAtMap = data['typingUpdatedAt'];
    final rawUpdatedAt = updatedAtMap is Map
        ? updatedAtMap[widget.otherUid]
        : null;
    if (rawUpdatedAt is! Timestamp) return false;

    return DateTime.now().difference(rawUpdatedAt.toDate()) <
        const Duration(seconds: 8);
  }

  @override
  Widget build(BuildContext context) {
    // -------------------------------------------------------------------------
    // GRUP SOHBETİ
    // -------------------------------------------------------------------------
    if (widget.isGroup) {
      return StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('clubs')
            .doc(widget.chatId)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasData && snap.data!.exists) {
            _groupCache[widget.chatId] =
                snap.data!.data() as Map<String, dynamic>;
          }
          final d = _groupCache[widget.chatId];
          final imageUrl = d?['imageUrl'] as String?;
          final displayName =
              (d?['name'] as String?) ?? widget.groupName ?? 'Kulüp Sohbeti';

          return InkWell(
            onTap: () => _openClubDetails(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.grey.shade800,
                  backgroundImage: (imageUrl != null && imageUrl.isNotEmpty)
                      ? NetworkImage(imageUrl)
                      : null,
                  child: (imageUrl == null || imageUrl.isEmpty)
                      ? const Icon(Icons.groups, color: Colors.white, size: 20)
                      : null,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    displayName,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    // -------------------------------------------------------------------------
    // KİŞİSEL SOHBETİ
    //
    // İsim kaynağı öncelik sırası:
    //   1. widget.initialTitle  → titles[currentUid] → karşı tarafın displayName'i
    //                             Bu Firestore'daki en doğru kaynak. Asla ezme.
    //   2. cachedUser.displayName → fallback (initialTitle boş gelirse)
    //
    // Fotoğraf: _photoUrl (cache'den) — isimle karıştırma.
    // -------------------------------------------------------------------------
    final cachedUser = UserCacheService.instance.getFromCache(widget.otherUid);
    final photo = _photoUrl ?? cachedUser?.photoURL ?? '';

    final title =
        (widget.initialTitle != null && widget.initialTitle!.isNotEmpty)
        ? widget.initialTitle!
        : (cachedUser?.displayName ?? 'Kullanıcı');

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PublicProfileScreen(uid: widget.otherUid),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.grey.shade800,
            backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
            child: photo.isEmpty
                ? Text(
                    title.isNotEmpty ? title[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ETKİNLİK MESAJ BALONU
// =============================================================================
class _EventMessageBubble extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool isMine;
  final DateTime? timestamp;
  final String? chatId;

  const _EventMessageBubble({
    required this.data,
    required this.isMine,
    this.timestamp,
    this.chatId,
  });

  @override
  State<_EventMessageBubble> createState() => _EventMessageBubbleState();
}

class _EventMessageBubbleState extends State<_EventMessageBubble>
    with AutomaticKeepAliveClientMixin {
  Stream<DocumentSnapshot>? _eventStream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  void _initStream() {
    final eventId = widget.data['id'];
    final chatId = widget.chatId;
    if (eventId != null && chatId != null) {
      _eventStream = FirebaseFirestore.instance
          .collection('clubs')
          .doc(chatId)
          .collection('events')
          .doc(eventId)
          .snapshots();
    }
  }

  @override
  void didUpdateWidget(covariant _EventMessageBubble old) {
    super.didUpdateWidget(old);
    if (widget.data['id'] != old.data['id'] || widget.chatId != old.chatId)
      _initStream();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_eventStream == null)
      return _buildContent(context, widget.data, null, false);
    return StreamBuilder<DocumentSnapshot>(
      stream: _eventStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.active &&
            snap.hasData &&
            !snap.data!.exists) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Bu etkinlik silindi.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          );
        }
        final liveData = (snap.hasData && snap.data!.exists)
            ? snap.data!.data() as Map<String, dynamic>
            : widget.data;
        final myUid = FirebaseAuth.instance.currentUser?.uid;
        final participants = List<String>.from(liveData['participants'] ?? []);
        return _buildContent(
          context,
          liveData,
          widget.data['id'],
          participants.contains(myUid),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    Map<String, dynamic> eventMap,
    String? eventId,
    bool isJoined,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? Colors.white10 : Colors.black12;
    final primaryTextColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;

    final date = (eventMap['date'] as Timestamp?)?.toDate() ?? DateTime.now();
    final difference = date.difference(DateTime.now());
    final bool isStarted = difference.isNegative;
    final bool isLive = isStarted && difference.abs().inHours < 3;
    final bool isExpired = isStarted && !isLive;

    String timeText;
    Color statusColor;
    Color statusBgColor;

    if (isLive) {
      timeText = 'Etkinlik Saati Geldi 🎬';
      statusColor = Colors.green;
      statusBgColor = Colors.green.withOpacity(0.1);
    } else if (isExpired) {
      timeText = 'Sona Erdi';
      statusColor = Colors.red;
      statusBgColor = Colors.red.withOpacity(0.1);
    } else {
      statusColor = Colors.amber.shade700;
      statusBgColor = Colors.amber.withOpacity(0.1);
      timeText = difference.inDays > 0
          ? '${difference.inDays} Gün Kaldı'
          : '${difference.inHours} Saat Kaldı';
    }

    final btnColor = isExpired
        ? Colors.grey
        : (isJoined
              ? Colors.redAccent
              : (isLive ? Colors.green : Colors.amber));
    final btnText = isExpired
        ? 'Sona Erdi'
        : (isJoined ? 'Etkinlikten Ayrıl' : 'Etkinliğe Katıl');

    return Container(
      width: 260,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLive ? Colors.green.withOpacity(0.5) : borderColor,
          width: isLive ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: statusBgColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: statusColor, size: 20),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${date.day}.${date.month}.${date.year}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: primaryTextColor,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(color: subTextColor, fontSize: 11),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cardBg.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    timeText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventMap['title'] ?? 'Etkinlik',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: btnColor,
                      foregroundColor: isJoined ? Colors.white : Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.zero,
                      elevation: 0,
                    ),
                    onPressed: isExpired
                        ? null
                        : () {
                            if (widget.chatId != null && eventId != null) {
                              final myUid =
                                  FirebaseAuth.instance.currentUser?.uid;
                              if (myUid != null)
                                ClubService.instance.joinEvent(
                                  widget.chatId!,
                                  eventId,
                                  myUid,
                                );
                            }
                          },
                    child: Text(
                      btnText,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ANKET MESAJ BALONU
// =============================================================================
class _PollMessageBubble extends StatefulWidget {
  final Map<String, dynamic> initialData;
  final bool isMine;
  final DateTime? timestamp;
  final String? chatId;

  const _PollMessageBubble({
    required this.initialData,
    required this.isMine,
    this.timestamp,
    this.chatId,
  });

  @override
  State<_PollMessageBubble> createState() => _PollMessageBubbleState();
}

class _PollMessageBubbleState extends State<_PollMessageBubble>
    with AutomaticKeepAliveClientMixin {
  Stream<DocumentSnapshot>? _pollStream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  void _initStream() {
    final pollId = widget.initialData['id'];
    final chatId = widget.chatId;
    if (pollId != null && chatId != null) {
      _pollStream = FirebaseFirestore.instance
          .collection('clubs')
          .doc(chatId)
          .collection('polls')
          .doc(pollId)
          .snapshots();
    }
  }

  @override
  void didUpdateWidget(covariant _PollMessageBubble old) {
    super.didUpdateWidget(old);
    if (widget.initialData['id'] != old.initialData['id'] ||
        widget.chatId != old.chatId)
      _initStream();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_pollStream == null)
      return _buildContent(context, widget.initialData, null);
    return StreamBuilder<DocumentSnapshot>(
      stream: _pollStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.active &&
            snap.hasData &&
            !snap.data!.exists) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Bu anket silindi.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          );
        }
        final liveData = (snap.hasData && snap.data!.exists)
            ? snap.data!.data() as Map<String, dynamic>
            : widget.initialData;
        return _buildContent(context, liveData, widget.initialData['id']);
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    Map<String, dynamic> data,
    String? pollId,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? Colors.white10 : Colors.black12;
    final primaryTextColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;
    final optionBg = isDark
        ? Colors.grey.withOpacity(0.1)
        : Colors.grey.withOpacity(0.05);

    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final options = List<dynamic>.from(data['options'] ?? []);
    final voters = Map<String, dynamic>.from(data['voters'] ?? {});
    final totalVotes = voters.length;
    final myVoteIndex = voters[myUid];

    return Container(
      width: 280,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.poll, color: Colors.lightBlueAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    data['question'] ?? 'Anket',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: List.generate(options.length, (index) {
                final opt = options[index];
                final count = opt['voteCount'] ?? 0;
                final percent = totalVotes == 0 ? 0.0 : (count / totalVotes);
                final isSelected = (myVoteIndex == index);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      if (widget.chatId != null &&
                          pollId != null &&
                          myUid != null) {
                        ClubService.instance.votePoll(
                          widget.chatId!,
                          pollId,
                          myUid,
                          index,
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      children: [
                        Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: optionBg,
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected
                                ? Border.all(color: Colors.green)
                                : null,
                          ),
                          child: FractionallySizedBox(
                            widthFactor: percent > 0 ? percent : 0.01,
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.green.withOpacity(0.3)
                                    : Colors.lightBlueAccent.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                opt['text'],
                                style: TextStyle(
                                  fontSize: 13,
                                  color: primaryTextColor,
                                ),
                              ),
                              Text(
                                '${(percent * 100).toInt()}% ($count)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: subTextColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(
              '$totalVotes Toplam Oy',
              style: TextStyle(
                fontSize: 11,
                color: subTextColor.withOpacity(0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
