import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';
import 'package:fluttergirdi/screens/post_detail_screen.dart';
import 'package:fluttergirdi/widgets/notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService I = NotificationService._();

  final navigatorKey = GlobalKey<NavigatorState>();
  final _fln = FlutterLocalNotificationsPlugin();
  final Map<String, DateTime> _recentPushes = {};
  final ValueNotifier<_InAppNotification?> _banner = ValueNotifier(null);

  bool _inited = false;
  bool _navigationReady = false;
  bool _messagesScreenActive = false;
  final List<String> _activeChatIds = [];
  Map<String, dynamic>? _pendingNavigation;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  OverlayEntry? _bannerEntry;
  Timer? _bannerTimer;

  static const _chChat = 'cinematch_chat';
  static const _chSocial = 'cinematch_social';

  Future<void> init() async {
    if (_inited || kIsWeb) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _fln.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      ),
      onDidReceiveNotificationResponse: (response) {
        _handlePayload(response.payload);
      },
    );

    if (Platform.isAndroid) {
      final androidPlugin = _fln
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _chChat,
          'Sohbet',
          description: 'Mesaj bildirimleri',
          importance: Importance.high,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _chSocial,
          'Sosyal',
          description: 'Begeni, yorum ve takip bildirimleri',
          importance: Importance.defaultImportance,
        ),
      );
    }

    _foregroundSub = FirebaseMessaging.onMessage.listen(_showForegroundPush);
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleRemoteTap);

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _pendingNavigation = Map<String, dynamic>.from(initialMessage.data);
    }

    _inited = true;
  }

  Future<void> requestPermissions() async {
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      debugPrint('Android bildirim izni: $status');
      return;
    }

    if (Platform.isIOS) {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final dynamic iosPlugin = _fln.resolvePlatformSpecificImplementation();
      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  Future<void> start() async {
    await init();
  }

  void flushPendingNavigation() {
    _navigationReady = true;
    final data = _pendingNavigation;
    if (data == null) return;
    _pendingNavigation = null;
    unawaited(_delayedNavigate(data));
  }

  void setNavigationReady(bool ready) {
    _navigationReady = ready;
    if (ready) flushPendingNavigation();
  }

  void enterChat(String chatId) {
    _activeChatIds
      ..remove(chatId)
      ..add(chatId);
    _dismissVisibleChatBanner();
  }

  void leaveChat(String chatId) {
    _activeChatIds.remove(chatId);
  }

  void setMessagesScreenActive(bool active) {
    _messagesScreenActive = active;
    if (active) _dismissVisibleChatBanner();
  }

  void _dismissVisibleChatBanner() {
    if (_banner.value?.data['type']?.toString() == 'chat') {
      _removeBanner();
    }
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    _foregroundSub = null;
    _openedSub = null;
    _navigationReady = false;
    _messagesScreenActive = false;
    _activeChatIds.clear();
    _removeBanner();
    _inited = false;
  }

  Future<void> _showForegroundPush(RemoteMessage message) async {
    final data = Map<String, dynamic>.from(message.data);
    final isChatNotification = data['type']?.toString() == 'chat';
    if (isChatNotification &&
        (_messagesScreenActive || _activeChatIds.isNotEmpty)) {
      return;
    }
    if (!_shouldShow(_dedupeKey(message))) return;

    final title = message.notification?.title ?? _fallbackTitle(data);
    final body = message.notification?.body ?? _fallbackBody(data);
    _showInAppBanner(
      _InAppNotification(
        id: message.messageId ?? _dedupeKey(message),
        title: title,
        body: body,
        data: data,
      ),
    );
  }

  void _handleRemoteTap(RemoteMessage message) {
    _queueNavigation(message.data);
  }

  void _handlePayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        final data = decoded.map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
        );
        _queueNavigation(data);
      }
    } catch (e) {
      debugPrint('Bildirim payload okunamadi: $e');
    }
  }

  void _queueNavigation(Map<String, dynamic> data) {
    _pendingNavigation = Map<String, dynamic>.from(data);
    unawaited(_markTappedNotificationRead(data));
    if (_navigationReady) unawaited(_delayedNavigate(data));
  }

  Future<void> _markTappedNotificationRead(Map<String, dynamic> data) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final notificationId = data['notificationId']?.toString() ?? '';
    if (uid == null || notificationId.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .doc(notificationId)
          .update({'read': true});
    } catch (_) {}
  }

  Future<void> _delayedNavigate(Map<String, dynamic> data) async {
    for (var i = 0; i < 24; i++) {
      final nav = navigatorKey.currentState;
      if (nav != null) {
        _pendingNavigation = null;
        _navigate(nav, data);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  void _navigate(NavigatorState nav, Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? data['route']?.toString() ?? '';

    if (type == 'chat') {
      final chatId = data['chatId']?.toString() ?? '';
      final otherUid =
          data['otherUid']?.toString() ?? data['actorId']?.toString() ?? '';
      final isGroup = data['isGroup']?.toString() == 'true';
      final groupName = data['groupName']?.toString();
      if (chatId.isEmpty) return;
      nav.push(
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            chatId: chatId,
            otherUid: isGroup ? '' : otherUid,
            otherTitle: isGroup ? groupName : null,
            isGroup: isGroup,
            groupName: isGroup ? groupName : null,
          ),
        ),
      );
      return;
    }

    if (type == 'like' || type == 'comment' || type == 'comment_reply') {
      final postId = data['postId']?.toString() ?? '';
      if (postId.isEmpty) return;
      nav.push(
        MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)),
      );
      return;
    }

    if (type == 'follow') {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      nav.push(
        MaterialPageRoute(builder: (_) => NotificationsScreen(uid: uid)),
      );
      return;
    }

    if (type == 'club_request') {
      final clubId = data['clubId']?.toString() ?? '';
      if (clubId.isEmpty) return;
      final clubName = data['clubName']?.toString();
      nav.push(
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            chatId: clubId,
            otherUid: '',
            otherTitle: clubName,
            isGroup: true,
            groupName: clubName,
          ),
        ),
      );
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      nav.push(
        MaterialPageRoute(builder: (_) => NotificationsScreen(uid: uid)),
      );
    }
  }

  bool _shouldShow(String key) {
    final now = DateTime.now();
    _recentPushes.removeWhere(
      (_, shownAt) => now.difference(shownAt) > const Duration(seconds: 20),
    );
    if (_recentPushes.containsKey(key)) return false;
    _recentPushes[key] = now;
    return true;
  }

  String _dedupeKey(RemoteMessage message) {
    final data = message.data;
    return message.messageId ??
        data['messageId']?.toString() ??
        data['notificationId']?.toString() ??
        '${data['type']}_${data['chatId']}_${data['postId']}_${data['actorId']}';
  }

  String _fallbackTitle(Map<String, dynamic> data) {
    switch (data['type']?.toString()) {
      case 'chat':
        return data['actorName']?.toString() ?? 'Yeni mesaj';
      case 'like':
        return 'Yeni begeni';
      case 'comment':
        return 'Yeni yorum';
      case 'comment_reply':
        return 'Yorumunuz yanıtlandı';
      case 'follow':
        return 'Yeni takipci';
      case 'club_request':
        return 'Kulup istegi';
      default:
        return 'CineMatch';
    }
  }

  String _fallbackBody(Map<String, dynamic> data) {
    final actorName = data['actorName']?.toString() ?? '';
    final preview = data['preview']?.toString() ?? '';
    switch (data['type']?.toString()) {
      case 'chat':
        return preview.isNotEmpty ? preview : 'Yeni mesaj';
      case 'like':
        return actorName.isNotEmpty
            ? '$actorName gonderini begendi'
            : 'Gonderin begenildi';
      case 'comment':
        return preview.isNotEmpty ? '$actorName: $preview' : 'Yeni yorum';
      case 'comment_reply':
        return preview.isNotEmpty
            ? '$actorName: $preview'
            : '$actorName yorumunuzu yanıtladı';
      case 'follow':
        return actorName.isNotEmpty
            ? '$actorName seni takip etmeye basladi'
            : 'Yeni takipcin var';
      case 'club_request':
        return actorName.isNotEmpty
            ? '$actorName kulubune katilmak istiyor'
            : 'Yeni kulup istegi';
      default:
        return 'Yeni bildirimin var';
    }
  }

  void _showInAppBanner(_InAppNotification notification) {
    if (!_navigationReady) return;
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _banner.value = notification;
    _bannerEntry ??= OverlayEntry(
      builder: (_) => _InAppNotificationBanner(
        notification: _banner,
        onDismiss: _removeBanner,
        onTap: (data) {
          _removeBanner();
          _queueNavigation(data);
        },
      ),
    );
    if (!_bannerEntry!.mounted) overlay.insert(_bannerEntry!);
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 5), _removeBanner);
  }

  void _removeBanner() {
    _bannerTimer?.cancel();
    _bannerTimer = null;
    _banner.value = null;
    _bannerEntry?.remove();
    _bannerEntry = null;
  }

  Future<void> markAllAsRead(String userId) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .get();

      if (query.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in query.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Toplu okundu isaretleme hatasi: $e');
    }
  }

  Future<void> deleteOldNotifications(String userId) async {
    try {
      final threeMonthsAgo = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 90)),
      );

      final query = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .where('createdAt', isLessThan: threeMonthsAgo)
          .get();

      if (query.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in query.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      debugPrint('${query.docs.length} eski bildirim silindi.');
    } catch (e) {
      debugPrint('Eski bildirimleri silme hatasi: $e');
    }
  }
}

class _InAppNotification {
  const _InAppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.data,
  });

  final String id;
  final String title;
  final String body;
  final Map<String, dynamic> data;
}

class _InAppNotificationBanner extends StatelessWidget {
  const _InAppNotificationBanner({
    required this.notification,
    required this.onTap,
    required this.onDismiss,
  });

  final ValueListenable<_InAppNotification?> notification;
  final ValueChanged<Map<String, dynamic>> onTap;
  final VoidCallback onDismiss;

  IconData _iconFor(String type) {
    switch (type) {
      case 'chat':
        return Icons.chat_bubble_rounded;
      case 'like':
        return Icons.favorite_rounded;
      case 'comment':
      case 'comment_reply':
        return Icons.mode_comment_rounded;
      case 'follow':
        return Icons.person_add_alt_1_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child: SafeArea(
        bottom: false,
        child: ValueListenableBuilder<_InAppNotification?>(
          valueListenable: notification,
          builder: (context, item, _) {
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: item == null
                  ? const SizedBox.shrink()
                  : TweenAnimationBuilder<double>(
                      key: ValueKey(item.id),
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) => Transform.translate(
                        offset: Offset(0, -24 * (1 - value)),
                        child: Opacity(opacity: value, child: child),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 18,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => onTap(item.data),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: const BoxDecoration(
                                      color: Color(0x1F2E7D32),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _iconFor(
                                        item.data['type']?.toString() ?? '',
                                      ),
                                      color: const Color(0xFF2E7D32),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          item.body,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Kapat',
                                    onPressed: onDismiss,
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }
}
