import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/search_movie.dart';
import 'package:fluttergirdi/services/ai_chat_service.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/services/notification_service.dart';
import 'package:fluttergirdi/widgets/chat_ui_components.dart'
    show MessageBubble;
import 'package:fluttergirdi/widgets/cinematch_bot_avatar.dart';

/// cinematchbotai (Python/Flask) ile canlı konuşulan sohbet odası.
///
/// Mevcut ChatRoomScreen'deki (insan-insan sohbet) engelleme, sessize alma,
/// okundu/teslim tiki gibi mantıklar bilerek burada yok; bu oda kavramsal
/// olarak farklı (karşı taraf bir insan değil), o yüzden basit ve bağımsız
/// bir ekran olarak kuruldu. Aynı Firestore chat/message şemasını kullanıyor,
/// film kartları için de diğer sohbetlerdeki MessageBubble'ı paylaşıyor.
class AiChatRoomScreen extends StatefulWidget {
  const AiChatRoomScreen({super.key});

  @override
  State<AiChatRoomScreen> createState() => _AiChatRoomScreenState();
}

class _AiChatRoomScreenState extends State<AiChatRoomScreen> {
  final _ai = AiChatService.instance;
  final _chatService = ChatService.instance;
  final _ctrl = TextEditingController();
  final _scrollController = ScrollController();

  String? _chatId;
  bool _botTyping = false;
  late final String _myUid;
  Map<String, dynamic> _tasteProfile = const {};

  // Kullanıcı bir film seçtiğinde, film tıklar tıklamaz GÖNDERİLMİYOR;
  // gönder tuşuna basılana kadar burada "eklenti" olarak bekliyor, bu
  // sırada kullanıcı isterse üstüne yazı da yazabiliyor.
  Map<String, dynamic>? _attachedMovie;

  @override
  void initState() {
    super.initState();
    NotificationService.I.enterChat(AiChatService.aiUid);
    _myUid = FirebaseAuth.instance.currentUser!.uid;
    _init();
  }

  Future<void> _init() async {
    // Oda oluşturma ve zevk profilini çekme paralel yapılabilir.
    final results = await Future.wait([
      _ai.getOrCreateAiChat(_myUid),
      _ai.fetchTasteProfile(_myUid),
    ]);
    if (!mounted) return;
    setState(() {
      _chatId = results[0] as String;
      _tasteProfile = results[1] as Map<String, dynamic>;
    });
  }

  Future<void> _pickMovie() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => const SearchMoviePage(isSelectionMode: true),
      ),
    );
    if (!mounted || result == null) return;

    // Sadece mesaj kutusuna "eklenti" olarak koyuyoruz, HENÜZ göndermiyoruz.
    setState(() {
      _attachedMovie = {
        'title': result['title'],
        'poster': result['poster'],
        'id': result['id'].toString(),
      };
    });
  }

  void _removeAttachedMovie() {
    setState(() => _attachedMovie = null);
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    final movie = _attachedMovie;
    if ((text.isEmpty && movie == null) || _chatId == null || _botTyping) {
      return;
    }

    _ctrl.clear();
    setState(() {
      _botTyping = true;
      _attachedMovie = null;
    });
    _scrollToBottom();

    try {
      // 1) Kullanıcının mesajını (varsa film eklentisiyle birlikte) Firestore'a yaz.
      await _chatService.send(
        _chatId!,
        _myUid,
        text,
        otherUid: AiChatService.aiUid,
        movie: movie,
      );

      // AI'ya gönderilecek metni hazırla: kullanıcı bir film eklediyse,
      // bunu modelin anlayacağı doğal bir cümleye çeviriyoruz.
      String effectiveMessage = text;
      if (movie != null) {
        final title = movie['title'] ?? '';
        effectiveMessage = text.isEmpty
            ? '$title filmini gönderdim, bu film hakkında ne düşünüyorsun?'
            : '$text (Paylaştığım film: $title)';
      }

      // 2) Python backend'inden (OpenRouter destekli AI) cevabı al.
      // Kullanıcının favori tür/oyuncu/yönetmen/film bilgisi de gönderiliyor
      // ki AI kişiye özel öneriler yapabilsin.
      final answer = await _ai.askAi(
        effectiveMessage,
        userId: _myUid,
        username: FirebaseAuth.instance.currentUser?.displayName ?? '',
        tasteProfile: _tasteProfile,
      );

      // 3) Botun metin cevabını aynı odaya yaz.
      await _ai.sendBotMessage(_chatId!, answer.text);

      // 4) AI bir ya da birkaç film önerdiyse, her birini TMDB'de arayıp
      // (bulunanları) diğer sohbetlerdeki gibi tıklanabilir film kartı
      // olarak ayrı birer mesaj şeklinde gönder.
      for (final title in answer.recommendedMovies) {
        final tmdbMovie = await _ai.searchMovieOnTmdb(title);
        if (tmdbMovie != null) {
          await _ai.sendBotMessage(_chatId!, '', movie: tmdbMovie);
        }
      }
    } finally {
      if (mounted) setState(() => _botTyping = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    NotificationService.I.leaveChat(AiChatService.aiUid);
    _ctrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(
          children: [
            const CinematchBotAvatar(),
            const SizedBox(width: 10),
            const Text('CineBot AI', style: TextStyle(fontSize: 17)),
          ],
        ),
      ),
      body: _chatId == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('chats')
                        .doc(_chatId)
                        .collection('messages')
                        .orderBy('createdAt', descending: true)
                        .limit(100)
                        .snapshots(),
                    builder: (context, snap) {
                      final docs = snap.data?.docs ?? [];

                      if (snap.connectionState == ConnectionState.waiting &&
                          docs.isEmpty) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (docs.isEmpty && !_botTyping) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Merhaba! Ben CineBot 🎬\n'
                              'Film önerisi isteyebilir, bana bir film '
                              'gönderip hakkında konuşabilir ya da '
                              '"neler yapabilirsin?" diye sorabilirsin.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ),
                        );
                      }

                      final typingOffset = _botTyping ? 1 : 0;

                      return ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        itemCount: docs.length + typingOffset,
                        itemBuilder: (context, i) {
                          if (_botTyping && i == 0) {
                            return _buildTypingBubble(cs);
                          }
                          final doc = docs[i - typingOffset];
                          final m = doc.data();
                          final author =
                              (m['authorId'] ?? m['from']) as String?;
                          final mine = author == _myUid;
                          final text = (m['text'] ?? '') as String;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: mine
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (!mine) ...[
                                  const CinematchBotAvatar(size: 24),
                                  const SizedBox(width: 8),
                                ],
                                Flexible(
                                  child: MessageBubble(
                                    text: text,
                                    movie: m['movie'],
                                    isMine: mine,
                                    timestamp: (m['createdAt'] as Timestamp?)
                                        ?.toDate(),
                                  ),
                                ),
                                if (mine) const SizedBox(width: 8),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                if (_attachedMovie != null) _buildAttachedMoviePreview(cs),
                _buildInputBar(cs),
              ],
            ),
    );
  }

  Widget _buildAttachedMoviePreview(ColorScheme cs) {
    final movie = _attachedMovie!;
    final poster = (movie['poster'] ?? '') as String;
    final title = (movie['title'] ?? '') as String;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: poster.isNotEmpty
                ? Image.network(
                    poster,
                    width: 34,
                    height: 48,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 34,
                    height: 48,
                    color: Colors.black26,
                    child: const Icon(
                      Icons.movie,
                      size: 18,
                      color: Colors.white54,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: _removeAttachedMovie,
            tooltip: 'Filmi kaldır',
          ),
        ],
      ),
    );
  }

  Widget _buildTypingBubble(ColorScheme cs) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SizedBox(
          width: 24,
          height: 12,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar(ColorScheme cs) {
    final canSend =
        !_botTyping && (_ctrl.text.trim().isNotEmpty || _attachedMovie != null);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 10, 10),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.movie_creation_outlined),
              tooltip: 'Film gönder',
              onPressed: _botTyping ? null : _pickMovie,
            ),
            Expanded(
              child: TextField(
                controller: _ctrl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: _attachedMovie != null
                      ? 'İstersen bir şeyler yaz...'
                      : "CineBot'a bir şey sor...",
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withOpacity(0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: canSend ? _send : null,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
