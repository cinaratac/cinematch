import 'dart:async';
import 'dart:math' as math;
import 'package:fluttergirdi/screens/search_movie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/services/notification_service.dart';
import '../services/text_filter_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:fluttergirdi/widgets/green_characters.dart';
import 'package:fluttergirdi/widgets/chat_ui_components.dart';
import 'package:fluttergirdi/widgets/chat_sheets.dart';
import 'package:fluttergirdi/services/blocking_service.dart';

// --- YENİ EKLENEN: Merkezi Önbellek Servisi ---
import '../services/user_cache_service.dart';

class ChatRoomScreen extends StatefulWidget {
  final String chatId;
  final String otherUid;
  final String? otherTitle;
  final bool isGroup;
  final String? groupName;

  const ChatRoomScreen({
    super.key,
    required this.chatId,
    required this.otherUid,
    this.otherTitle,
    this.isGroup = false,
    this.groupName,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _SwipeToReply extends StatefulWidget {
  final bool isMine;
  final VoidCallback onReply;
  final Widget child;

  const _SwipeToReply({
    super.key,
    required this.isMine,
    required this.onReply,
    required this.child,
  });

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  static const double _triggerDistance = 18;
  static const double _maximumDistance = 36;

  double _offset = 0;
  bool _dragging = false;
  bool _didHaptic = false;

  void _handleDragStart(DragStartDetails details) {
    setState(() {
      _dragging = true;
      _didHaptic = false;
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final rawDelta = details.primaryDelta ?? 0;
    final towardCenterDelta = widget.isMine ? -rawDelta : rawDelta;
    final nextMagnitude = (_offset.abs() + towardCenterDelta)
        .clamp(0.0, _maximumDistance)
        .toDouble();

    if (!_didHaptic && nextMagnitude >= _triggerDistance) {
      _didHaptic = true;
      HapticFeedback.selectionClick();
    }

    setState(() {
      _offset = widget.isMine ? -nextMagnitude : nextMagnitude;
    });
  }

  void _finishDrag() {
    final shouldReply = _offset.abs() >= _triggerDistance;
    setState(() {
      _dragging = false;
      _offset = 0;
    });
    if (shouldReply) widget.onReply();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_offset.abs() / _maximumDistance).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: (_) => _finishDrag(),
      onHorizontalDragCancel: _finishDrag,
      child: Stack(
        alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: widget.isMine ? 0 : 7,
              right: widget.isMine ? 7 : 0,
            ),
            child: Opacity(
              opacity: progress,
              child: Icon(
                Icons.reply_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          AnimatedContainer(
            duration: _dragging
                ? Duration.zero
                : const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_offset, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  static const int _messagePageSize = 30;
  static final Map<String, bool> _blockedCache = {};
  bool _initialMuteStatus = false; // Ekran açıldığındaki orjinal durum
  late final ValueNotifier<bool> _isMutedNotifier;

  static final Map<String, bool> _blockedMeCache = {};
  static final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _messageCache = {};

  Timer? _muteDebounceTimer;
  final ValueNotifier<bool> _showGuideNotifier = ValueNotifier<bool>(false);
  final _svc = ChatService.instance;
  final _ctrl = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _messages = [];
  QueryDocumentSnapshot<Map<String, dynamic>>? _oldestMessage;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _messagesSub;
  bool _initialMessagesLoading = true;
  bool _loadingOlderMessages = false;
  bool _hasMoreOlderMessages = true;
  bool _receivedFirstMessagePage = false;
  Map<String, dynamic>? _replyingTo;
  final Set<String> _requestedAuthorIds = {};
  final Map<String, Map<String, List<String>>> _localReactionOverrides = {};
  Timer? _typingStopTimer;
  bool _isTyping = false;
  DateTime? _lastTypingWriteAt;
  bool _isBlocked = false;
  bool _hasBlockedMe = false;
  bool _isLoadingBlock = true;

  // --- YENİ EKLENEN: Teslim edildi / Görüldü tik sistemi ---
  DateTime? _otherReadAt;
  DateTime? _otherDeliveredAt;
  StreamSubscription? _otherReadSub;
  StreamSubscription? _otherDeliveredSub;

  Future<void> _loadBlockStatus() async {
    if (widget.isGroup) {
      if (mounted) setState(() => _isLoadingBlock = false);
      return;
    }

    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    try {
      final status = await BlockingService.instance.checkBlockStatus(
        currentUserId: myUid,
        targetUserId: widget.otherUid,
      );

      // KİLİT BURADA: Eğer veritabanından cevap gelene kadar kullanıcı sayfadan çıktıysa işlemi iptal et!
      if (!mounted) return;

      _blockedCache[widget.otherUid] = status['iBlockedThem'] ?? false;
      _blockedMeCache[widget.otherUid] = status['theyBlockedMe'] ?? false;

      setState(() {
        _isBlocked = status['iBlockedThem'] ?? false;
        _hasBlockedMe = status['theyBlockedMe'] ?? false;
        _isLoadingBlock = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingBlock = false);
    }
  }

  @override
  void initState() {
    super.initState();
    NotificationService.I.enterChat(widget.chatId);

    // 1. EKRAN AÇILDIĞI AN İKONU "AÇIK" OLARAK GÖSTER
    _isMutedNotifier = ValueNotifier<bool>(false);
    _ctrl.addListener(_handleTypingChanged);

    final myUid = FirebaseAuth.instance.currentUser!.uid;

    // Son mesajlar canlı dinlenir; eski mesajlar yalnızca yukarı kaydırıldıkça
    // sayfalı okunur. Böylece uzun sohbetler ilk açılışı pahalılaştırmaz.
    final cachedMessages = _messageCache[widget.chatId];
    if (cachedMessages != null && cachedMessages.isNotEmpty) {
      _messages = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
        cachedMessages,
      );
      _oldestMessage = _messages.last;
      _initialMessagesLoading = false;
    }
    _scrollController.addListener(_handleMessageScroll);
    _startMessageStream(myUid);

    // 3. Cache üzerinden engelleme durumunu kontrol et
    if (_blockedCache.containsKey(widget.otherUid)) {
      _isBlocked = _blockedCache[widget.otherUid]!;
      _hasBlockedMe = _blockedMeCache[widget.otherUid] ?? false;
      _isLoadingBlock = false;
    }

    _svc.markAsRead(widget.chatId, myUid);
    // Oda açıldığı an, o ana kadarki tüm mesajlar bu cihaza teslim edilmiş
    // sayılır (görüldü zaten markAsRead ile ayrıca işaretleniyor).
    _svc.markDelivered(widget.chatId, myUid);

    // --- YENİ EKLENEN: Karşı tarafın "teslim edildi" / "görüldü" bilgisini dinle ---
    if (!widget.isGroup) {
      _otherReadSub = _svc
          .otherReadAtStream(widget.chatId, widget.otherUid)
          .listen((dt) {
            if (mounted) setState(() => _otherReadAt = dt);
          });
      _otherDeliveredSub = _svc
          .otherDeliveredAtStream(widget.chatId, widget.otherUid)
          .listen((dt) {
            if (mounted) setState(() => _otherDeliveredAt = dt);
          });
    }

    // 4. Ağır işlemleri sayfa açılış animasyonu bitene kadar ertele.
    Future.delayed(Duration.zero, () {
      if (!mounted) return;
      _checkAndShowGuide();
      _loadBlockStatus();
      _loadInitialMuteStatus();
    });
  }

  Query<Map<String, dynamic>> get _messagesQuery => FirebaseFirestore.instance
      .collection('chats')
      .doc(widget.chatId)
      .collection('messages')
      .orderBy('createdAt', descending: true);

  void _startMessageStream(String myUid) {
    _messagesSub = _messagesQuery
        .limit(_messagePageSize)
        .snapshots()
        .listen(
          (snapshot) {
            final hasIncomingMessage = snapshot.docChanges.any((change) {
              if (change.type == DocumentChangeType.removed) return false;
              final data = change.doc.data();
              if (data == null) return false;
              final author = (data['authorId'] ?? data['from'] ?? '')
                  .toString();
              return author.isNotEmpty && author != myUid;
            });

            _mergeMessages(snapshot.docs);

            if (!_receivedFirstMessagePage) {
              _receivedFirstMessagePage = true;
              _hasMoreOlderMessages = snapshot.docs.length == _messagePageSize;
            }

            if (hasIncomingMessage) {
              unawaited(_svc.markAsRead(widget.chatId, myUid));
              unawaited(_svc.markDelivered(widget.chatId, myUid));
            }

            if (!mounted) return;
            setState(() => _initialMessagesLoading = false);
          },
          onError: (Object error) {
            debugPrint('Mesajlar dinlenemedi: $error');
            if (mounted) setState(() => _initialMessagesLoading = false);
          },
        );
  }

  void _mergeMessages(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> incoming,
  ) {
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
      for (final message in _messages) message.id: message,
    };
    for (final message in incoming) {
      byId[message.id] = message;
      final localOverride = _localReactionOverrides[message.id];
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (localOverride != null && currentUid != null) {
        final snapshotReactions = _readReactions(message.data()['reactions']);
        if (_selectedReaction(snapshotReactions, currentUid) ==
            _selectedReaction(localOverride, currentUid)) {
          _localReactionOverrides.remove(message.id);
        }
      }
    }

    final merged = byId.values.toList()..sort(_compareMessagesNewestFirst);
    _messages = merged;
    _oldestMessage = merged.isEmpty ? null : merged.last;

    // RAM önbelleğini sınırlı tut; yeniden açılışta son mesajlar anında görünür.
    _messageCache[widget.chatId] = merged.take(200).toList(growable: false);
  }

  int _compareMessagesNewestFirst(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final aTimestamp = a.data()['createdAt'] as Timestamp?;
    final bTimestamp = b.data()['createdAt'] as Timestamp?;
    if (aTimestamp == null && bTimestamp == null) {
      return b.id.compareTo(a.id);
    }
    if (aTimestamp == null) return -1;
    if (bTimestamp == null) return 1;
    return bTimestamp.compareTo(aTimestamp);
  }

  void _handleMessageScroll() {
    if (!_scrollController.hasClients ||
        _loadingOlderMessages ||
        !_hasMoreOlderMessages) {
      return;
    }

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      unawaited(_loadOlderMessages());
    }
  }

  Future<void> _loadOlderMessages() async {
    final oldestMessage = _oldestMessage;
    if (_loadingOlderMessages ||
        !_hasMoreOlderMessages ||
        oldestMessage == null) {
      return;
    }

    setState(() => _loadingOlderMessages = true);
    try {
      final snapshot = await _messagesQuery
          .startAfterDocument(oldestMessage)
          .limit(_messagePageSize)
          .get();
      _mergeMessages(snapshot.docs);
      _hasMoreOlderMessages = snapshot.docs.length == _messagePageSize;
    } catch (error) {
      debugPrint('Eski mesajlar yüklenemedi: $error');
      if (mounted) _showError('Eski mesajlar yüklenemedi.');
    } finally {
      if (mounted) setState(() => _loadingOlderMessages = false);
    }
  }

  Future<void> _loadInitialMuteStatus() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      // Çok daha hızlı olması için önce yerel önbellekten (cache) okumayı dener:
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.cache))
          .catchError(
            (_) =>
                FirebaseFirestore.instance.collection('users').doc(uid).get(),
          );

      // KİLİT BURADA: Eğer sayfadan çıkıldıysa notifer'a dokunma, çöker!
      if (!mounted) return;

      final mutedChats = List<String>.from(doc.data()?['mutedChats'] ?? []);

      _initialMuteStatus = mutedChats.contains(widget.chatId);
      // Arka planda gerçek durumu sessizce güncelle (Ekranda loading vs dönmez)
      _isMutedNotifier.value = _initialMuteStatus;
    } catch (e) {
      debugPrint('Bildirim ayarı yüklenemedi: $e');
    }
  }

  Future<void> _checkAndShowGuide() async {
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final bool seen = sp.getBool('seen_watchlist_guide') ?? false;
      if (!seen) {
        _showGuideNotifier.value = true;
        await sp.setBool('seen_watchlist_guide', true);
      }
    } catch (e) {
      debugPrint('');
    }
  }

  void _handleTypingChanged() {
    if (widget.isGroup || _isBlocked || _hasBlockedMe) return;

    final hasText = _ctrl.text.trim().isNotEmpty;
    if (!hasText) {
      _typingStopTimer?.cancel();
      _setTyping(false, force: true);
      return;
    }

    final now = DateTime.now();
    final shouldRefresh =
        _lastTypingWriteAt == null ||
        now.difference(_lastTypingWriteAt!) > const Duration(seconds: 4);

    if (!_isTyping || shouldRefresh) {
      _setTyping(true, force: shouldRefresh);
    }

    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(milliseconds: 2800), () {
      _setTyping(false, force: true);
    });
  }

  void _setTyping(bool value, {bool force = false}) {
    if (widget.isGroup) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;
    if (!force && _isTyping == value) return;

    _isTyping = value;
    _lastTypingWriteAt = DateTime.now();
    unawaited(_svc.setTyping(widget.chatId, myUid, value));
  }

  @override
  void dispose() {
    NotificationService.I.leaveChat(widget.chatId);
    // 1. Önce sunucuya kaydedilecek bir şey varsa onu hallet
    if (_isMutedNotifier.value != _initialMuteStatus) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final isMutedNow = _isMutedNotifier.value;

        if (isMutedNow) {
          FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .update({
                'mutedChats': FieldValue.arrayUnion([widget.chatId]),
              })
              .catchError((_) {});
        } else {
          FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .update({
                'mutedChats': FieldValue.arrayRemove([widget.chatId]),
              })
              .catchError((_) {});
        }
      }
    }

    // 2. Kapatma, iptal etme ve temizleme işlemleri (Sadece BİR KERE)
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid != null) _svc.markAsRead(widget.chatId, myUid);
    if (myUid != null && _isTyping) {
      unawaited(_svc.setTyping(widget.chatId, myUid, false));
    }

    _messagesSub?.cancel();
    _otherReadSub?.cancel();
    _otherDeliveredSub?.cancel();
    _muteDebounceTimer?.cancel();
    _typingStopTimer?.cancel();
    _ctrl.removeListener(_handleTypingChanged);
    _scrollController.removeListener(_handleMessageScroll);

    _ctrl.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    _showGuideNotifier.dispose();
    _isMutedNotifier.dispose();

    // 3. super.dispose() HER ZAMAN EN SONDA OLMALIDIR!
    super.dispose();
  }

  String _messagePreview(Map<String, dynamic> data) {
    final text = (data['text'] ?? '').toString().trim();
    if (text.isNotEmpty) return _truncatePreview(text);

    final movie = data['movie'];
    if (movie is Map) {
      final title = (movie['title'] ?? movie['name'] ?? '').toString().trim();
      return title.isEmpty ? 'Film' : '🎬 $title';
    }

    final event = data['event'];
    if (event is Map) {
      final title = (event['title'] ?? '').toString().trim();
      return title.isEmpty ? 'Etkinlik' : '📅 $title';
    }

    final poll = data['poll'];
    if (poll is Map) {
      final question = (poll['question'] ?? '').toString().trim();
      return question.isEmpty ? 'Anket' : '📊 $question';
    }

    return 'Mesaj';
  }

  String _truncatePreview(String value) {
    final codePoints = value.runes.toList(growable: false);
    if (codePoints.length <= 100) return value;
    return '${String.fromCharCodes(codePoints.take(99))}…';
  }

  void _startReply(
    QueryDocumentSnapshot<Map<String, dynamic>> message,
    String myUid,
  ) {
    final data = message.data();
    final authorId = (data['authorId'] ?? data['from'] ?? '').toString();
    final cachedUser = UserCacheService.instance.getFromCache(authorId);
    final authorName = authorId == myUid
        ? 'Sen'
        : (cachedUser?.displayName ?? widget.otherTitle ?? 'Kullanıcı');

    setState(() {
      _replyingTo = {
        'messageId': message.id,
        'authorId': authorId,
        'authorName': authorName,
        'text': _messagePreview(data),
        'type': (data['type'] ?? 'text').toString(),
      };
    });
    _inputFocusNode.requestFocus();
  }

  Map<String, List<String>> _readReactions(dynamic rawReactions) {
    if (rawReactions is! Map) return const {};
    final reactions = <String, List<String>>{};
    for (final entry in rawReactions.entries) {
      final emoji = entry.key.toString();
      if (!ChatService.supportedReactions.contains(emoji)) continue;
      final users = entry.value;
      if (users is List) {
        reactions[emoji] = users.map((uid) => uid.toString()).toList();
      }
    }
    return reactions;
  }

  Map<String, List<String>> _reactionsForMessage(
    QueryDocumentSnapshot<Map<String, dynamic>> message,
  ) {
    return _localReactionOverrides[message.id] ??
        _readReactions(message.data()['reactions']);
  }

  String? _selectedReaction(Map<String, List<String>> reactions, String myUid) {
    for (final entry in reactions.entries) {
      if (entry.value.contains(myUid)) return entry.key;
    }
    return null;
  }

  Future<void> _showReactionPicker(
    QueryDocumentSnapshot<Map<String, dynamic>> message,
    String myUid,
    BuildContext anchorContext,
    bool isMine,
  ) async {
    final anchorObject = anchorContext.findRenderObject();
    final overlayObject = Overlay.of(context).context.findRenderObject();
    if (anchorObject is! RenderBox || overlayObject is! RenderBox) return;

    final anchorOrigin = anchorObject.localToGlobal(
      Offset.zero,
      ancestor: overlayObject,
    );
    final anchorSize = anchorObject.size;
    final overlaySize = overlayObject.size;
    final bubbleWidth = math.min(304.0, overlaySize.width - 24);
    const bubbleHeight = 62.0;
    final anchorCenterX = isMine
        ? anchorOrigin.dx + (anchorSize.width * 0.72)
        : anchorOrigin.dx + (anchorSize.width * 0.28);
    final bubbleLeft = (anchorCenterX - bubbleWidth / 2)
        .clamp(12.0, overlaySize.width - bubbleWidth - 12.0)
        .toDouble();
    final bubbleTop = math.max(
      MediaQuery.paddingOf(context).top + 8,
      anchorOrigin.dy - bubbleHeight - 8,
    );

    HapticFeedback.mediumImpact();
    final reactions = _reactionsForMessage(message);
    final currentReaction = _selectedReaction(reactions, myUid);

    final emoji = await showGeneralDialog<String>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: true,
      barrierLabel: 'Tepkileri kapat',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final colors = Theme.of(dialogContext).colorScheme;
        return Stack(
          children: [
            Positioned(
              left: bubbleLeft,
              top: bubbleTop,
              width: bubbleWidth,
              height: bubbleHeight,
              child: Material(
                color: colors.surface,
                elevation: 12,
                shadowColor: Colors.black.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(28),
                clipBehavior: Clip.antiAlias,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ChatService.supportedReactions
                        .map((reaction) {
                          final selected = reaction == currentReaction;
                          return Material(
                            color: selected
                                ? colors.primaryContainer
                                : Colors.transparent,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () =>
                                  Navigator.pop(dialogContext, reaction),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  reaction,
                                  style: const TextStyle(fontSize: 25),
                                ),
                              ),
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
    );

    if (!mounted || emoji == null) return;
    await _toggleReaction(
      message: message,
      myUid: myUid,
      emoji: emoji,
      remove: emoji == currentReaction,
    );
  }

  Future<void> _toggleReaction({
    required QueryDocumentSnapshot<Map<String, dynamic>> message,
    required String myUid,
    required String emoji,
    bool? remove,
  }) async {
    final reactions = _reactionsForMessage(message);
    final shouldRemove = remove ?? reactions[emoji]?.contains(myUid) == true;

    final optimisticReactions = <String, List<String>>{
      for (final entry in reactions.entries)
        entry.key: List<String>.from(entry.value),
    };
    for (final supportedEmoji in ChatService.supportedReactions) {
      optimisticReactions.putIfAbsent(supportedEmoji, () => <String>[]);
      optimisticReactions[supportedEmoji]!.remove(myUid);
    }
    if (!shouldRemove) optimisticReactions[emoji]!.add(myUid);
    setState(() => _localReactionOverrides[message.id] = optimisticReactions);

    try {
      HapticFeedback.selectionClick();
      await _svc.toggleReaction(
        chatId: widget.chatId,
        messageId: message.id,
        userId: myUid,
        emoji: emoji,
        remove: shouldRemove,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _localReactionOverrides.remove(message.id));
      }
      if (mounted) _showError('Tepki kaydedilemedi.');
    }
  }

  Future<void> _sendMessage() async {
    final txt = _ctrl.text.trim();
    if (txt.isEmpty) return;

    if (TextFilterService.hasProfanity(txt)) {
      _showError('Mesajınız uygunsuz ifadeler içeriyor.');
      return;
    }

    try {
      final myUid = FirebaseAuth.instance.currentUser!.uid;
      final replyTo = _replyingTo == null
          ? null
          : Map<String, dynamic>.from(_replyingTo!);
      _typingStopTimer?.cancel();
      _setTyping(false, force: true);
      _ctrl.clear();
      setState(() => _replyingTo = null);

      // 1. Kendi mesajımızı Firebase'e gönderiyoruz
      await _svc.send(
        widget.chatId,
        myUid,
        txt,
        otherUid: widget.otherUid,
        replyTo: replyTo,
      );

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }

      // --- YENİ EKLENEN: Bot AI Entegrasyonu ---
      if (widget.otherUid == "cinematch_bot_ai") {
        try {
          // Kendi Render API url'ini buraya yazmalısın
          final url = Uri.parse(
            "https://SENIN-RENDER-ADRESIN.onrender.com/api/chat",
          );
          final response = await http.post(
            url,
            headers: {"Content-Type": "application/json; charset=utf-8"},
            body: jsonEncode({
              "uid":
                  myUid, // Python tarafında Firebase'den veriyi çekmek için UID yolluyoruz
              "message": txt,
            }),
          );

          if (response.statusCode == 200) {
            // Türkçe karakter sorunu yaşamamak için utf8.decode kullanıyoruz
            final data = jsonDecode(utf8.decode(response.bodyBytes));
            final botReply = data['reply'] ?? "Anlayamadım, tekrar eder misin?";

            // Botun cevabını sohbete ekle (Gönderen: Bot, Alıcı: Sen)
            await _svc.send(
              widget.chatId,
              "cinematch_bot_ai", // Mesajın yazarı Bot
              botReply,
              otherUid: myUid, // Alıcı benim
            );
          } else {
            debugPrint("Bot API Hatası: ${response.statusCode}");
          }
        } catch (e) {
          debugPrint("Bot İstek Hatası: $e");
        }
      }
      // -----------------------------------------
    } catch (e) {
      if (!mounted) return;
      _showError('Gönderilemedi: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  Future<void> _openFilmPicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => const SearchMoviePage(isSelectionMode: true),
      ),
    );

    if (!mounted || result == null) return;

    final myUid = FirebaseAuth.instance.currentUser!.uid;
    try {
      final replyTo = _replyingTo == null
          ? null
          : Map<String, dynamic>.from(_replyingTo!);
      await _svc.send(
        widget.chatId,
        myUid,
        "",
        otherUid: widget.otherUid,
        movie: {
          'title': result['title'],
          'poster': result['poster'],
          'id': result['id'].toString(),
        },
        replyTo: replyTo,
      );

      if (mounted && replyTo != null) {
        setState(() => _replyingTo = null);
      }

      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) _showError('Film gönderilemedi: $e');
    }
  }

  void _openWatchlistWheel() {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WatchlistWheelSheet(
        chatId: widget.chatId,
        myUid: myUid,
        otherUid: widget.otherUid,
      ),
    );
  }

  Widget _buildFeaturedMovieBanner() {
    if (!widget.isGroup) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.chatId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) return const SizedBox.shrink();
        final data = snap.data!.data() as Map<String, dynamic>;
        final movie = data['featuredMovie'] as Map<String, dynamic>?;

        if (movie == null) return const SizedBox.shrink();

        return FeaturedMovieBannerWidget(movie: movie);
      },
    );
  }

  Widget _buildInputArea() {
    if (_isLoadingBlock) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_isBlocked || _hasBlockedMe) {
      return SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.black26
              : Colors.grey.shade200,
          child: const Text(
            'Bu kullanıcıyla mesajlaşamazsınız.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inputBg = isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade200;
    final hintColor = isDark ? Colors.white38 : Colors.black38;
    final iconColor = isDark ? Colors.white54 : Colors.black54;
    final textColor = isDark ? Colors.white : Colors.black;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyingTo != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                decoration: BoxDecoration(
                  color: inputBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border(
                    left: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (_replyingTo!['authorName'] ?? 'Mesaj').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            (_replyingTo!['text'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: hintColor, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Yanıtı iptal et',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _replyingTo = null),
                      icon: Icon(
                        Icons.close_rounded,
                        color: iconColor,
                        size: 19,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: inputBg,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            focusNode: _inputFocusNode,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendMessage(),
                            style: TextStyle(color: textColor),
                            decoration: InputDecoration(
                              hintText: _replyingTo == null
                                  ? 'Mesaj...'
                                  : 'Yanıt yaz...',
                              hintStyle: TextStyle(color: hintColor),
                              isCollapsed: true,
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: 'Film paylaş',
                              onPressed: _openFilmPicker,
                              icon: Icon(
                                Icons.movie_filter_outlined,
                                color: iconColor,
                              ),
                            ),
                            if (!widget.isGroup) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'Watchlist Çarkı',
                                onPressed: _openWatchlistWheel,
                                icon: Icon(Icons.donut_large, color: iconColor),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesList(String myUid) {
    final docs = _messages;

    final authorIds = <String>{};
    if (widget.otherUid.isNotEmpty) authorIds.add(widget.otherUid);
    for (final doc in docs) {
      final data = doc.data();
      final authorId = (data['authorId'] ?? data['from'] ?? '').toString();
      if (authorId.isNotEmpty) authorIds.add(authorId);
    }

    final missingIds = authorIds
        .where((id) {
          if (UserCacheService.instance.getFromCache(id) != null) return false;
          return _requestedAuthorIds.add(id);
        })
        .toList(growable: false);
    if (missingIds.isNotEmpty) {
      Future.microtask(() async {
        try {
          await UserCacheService.instance.fetchUsers(missingIds);
          if (mounted) setState(() {});
        } catch (_) {
          _requestedAuthorIds.removeAll(missingIds);
        }
      });
    }

    if (_initialMessagesLoading && docs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (docs.isEmpty) return const EmptyChatView();

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: docs.length + (_hasMoreOlderMessages ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == docs.length) {
          return SizedBox(
            height: 48,
            child: Center(
              child: _loadingOlderMessages
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: _loadOlderMessages,
                      child: const Text('Daha eski mesajlar'),
                    ),
            ),
          );
        }

        final doc = docs[i];
        final data = doc.data();
        final author = (data['authorId'] ?? data['from'] ?? '').toString();
        final mine = author == myUid;
        final text = (data['text'] ?? '').toString();
        final timestamp = data['createdAt'] as Timestamp?;
        final date = timestamp?.toDate();
        final type = data['type'] as String?;
        final eventData = data['event'] is Map
            ? Map<String, dynamic>.from(data['event'] as Map)
            : null;
        final pollData = data['poll'] is Map
            ? Map<String, dynamic>.from(data['poll'] as Map)
            : null;
        final replyTo = data['replyTo'] is Map
            ? Map<String, dynamic>.from(data['replyTo'] as Map)
            : null;
        final reactions = _reactionsForMessage(doc);

        MessageDeliveryStatus? deliveryStatus;
        if (mine && date != null && !widget.isGroup) {
          if (_otherReadAt != null && !date.isAfter(_otherReadAt!)) {
            deliveryStatus = MessageDeliveryStatus.read;
          } else if (_otherDeliveredAt != null &&
              !date.isAfter(_otherDeliveredAt!)) {
            deliveryStatus = MessageDeliveryStatus.delivered;
          } else {
            deliveryStatus = MessageDeliveryStatus.sent;
          }
        }

        final messageRow = MessageRow(
          text: text,
          movie: data['movie'],
          isMine: mine,
          timestamp: date,
          authorId: author,
          type: type,
          eventData: eventData,
          pollData: pollData,
          chatId: widget.chatId,
          deliveryStatus: deliveryStatus,
          replyTo: replyTo,
          reactions: reactions,
          currentUserId: myUid,
          onReactionTap: (emoji) =>
              _toggleReaction(message: doc, myUid: myUid, emoji: emoji),
        );

        final interactiveRow = _SwipeToReply(
          key: ValueKey('reply_${doc.id}'),
          isMine: mine,
          onReply: () => _startReply(doc, myUid),
          child: Builder(
            builder: (anchorContext) => GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPressStart: (_) =>
                  _showReactionPicker(doc, myUid, anchorContext, mine),
              child: messageRow,
            ),
          ),
        );

        bool isFirstOfDay = false;
        if (date != null) {
          if (i == docs.length - 1) {
            isFirstOfDay = true;
          } else {
            final olderTimestamp =
                docs[i + 1].data()['createdAt'] as Timestamp?;
            final olderDate = olderTimestamp?.toDate();
            if (olderDate == null ||
                olderDate.year != date.year ||
                olderDate.month != date.month ||
                olderDate.day != date.day) {
              isFirstOfDay = true;
            }
          }
        }

        if (!isFirstOfDay) return interactiveRow;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DateSeparator(date: date!),
            interactiveRow,
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: ChatAppBarTitle(
          chatId: widget.chatId,
          otherUid: widget.otherUid,
          initialTitle: widget.otherTitle,
          isGroup: widget.isGroup,
          groupName: widget.groupName,
        ),
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _isMutedNotifier,
            builder: (context, isMuted, child) {
              return IconButton(
                icon: Icon(
                  isMuted ? Icons.notifications_off : Icons.notifications,
                  color: isMuted
                      ? Colors.grey
                      : Theme.of(context).iconTheme.color,
                ),
                onPressed: () {
                  _isMutedNotifier.value = !isMuted;
                },
              );
            },
          ),
        ],
      ),
      body: _isLoadingBlock
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
            )
          : (_isBlocked || _hasBlockedMe)
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.block, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Bu kullanıcıyla mesajlaşamazsınız.',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                Column(
                  children: [
                    _buildFeaturedMovieBanner(),
                    Expanded(
                      child: Container(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: _buildMessagesList(myUid),
                      ),
                    ),
                    _buildInputArea(),
                  ],
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _showGuideNotifier,
                  builder: (context, isVisible, child) {
                    if (!isVisible) return const SizedBox.shrink();
                    return GuideCharacterOverlay(
                      message:
                          "Beraber film izlemek için watchlist çarkını deneyebilirsin",
                      isVisible: isVisible,
                      onClose: () => _showGuideNotifier.value = false,
                    );
                  },
                ),
              ],
            ),
    );
  }
}
