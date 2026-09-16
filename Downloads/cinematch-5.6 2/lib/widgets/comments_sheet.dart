import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/services/text_filter_service.dart';
import 'package:fluttergirdi/services/feed_service.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/services/follow_system_service.dart';
// Film arama ve detay sayfaları
import '../screens/search_movie.dart';
import '../screens/movie_detail_screen.dart';
import 'poster_image.dart';
import 'package:fluttergirdi/services/blocking_service.dart';

class CommentsSheet extends StatefulWidget {
  final String postId;
  final String postAuthorId;

  const CommentsSheet({
    super.key,
    required this.postId,
    required this.postAuthorId,
  });

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final TextEditingController _commentCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Set<String> _blockedUsers = {};
  bool _isLoadingBlocks = true;
  late final Stream<QuerySnapshot> _mainRepliesStream;

  String? _replyingToDocId;
  String? _replyingToReplyId;
  String? _replyingToUserName;
  String? _replyingToUid;

  // Seçilen filmi tutmak için
  Map<String, dynamic>? _selectedMovie;

  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadBlocks();
    _mainRepliesStream = FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('replies')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> _loadBlocks() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final blocks = await BlockingService.instance.getBlockedAndBlockerIds(
        uid,
      );
      if (mounted) {
        setState(() {
          _blockedUsers = blocks;
          _isLoadingBlocks = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoadingBlocks = false);
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Film seçme fonksiyonu
  Future<void> _pickMovie() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SearchMoviePage(isSelectionMode: true),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _selectedMovie = result;
      });
    }
  }

  void _removeSelectedMovie() {
    setState(() {
      _selectedMovie = null;
    });
  }

  Future<void> _send() async {
    final text = _commentCtrl.text.trim();
    // Metin boş olsa bile film seçiliyse gönderilebilir
    if (text.isEmpty && _selectedMovie == null) return;

    if (text.isNotEmpty && TextFilterService.hasProfanity(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Uygunsuz içerik tespit edildi.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Gönderim sürerken kullanıcı yanıt seçimini kapatsa bile kayıt ve bildirim
    // aynı hedefe gitmeli.
    final replyingToDocId = _replyingToDocId;
    final replyingToReplyId = _replyingToReplyId;
    final replyingToUserName = _replyingToUserName;
    final replyingToUid = _replyingToUid;

    setState(() => _isSending = true);

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final now = FieldValue.serverTimestamp();

      final Map<String, dynamic> data = {
        'text': text,
        'authorId': user.uid,
        'createdAt': now,
        'likeCount': 0,
      };

      if (_selectedMovie != null) {
        data['movie'] = _selectedMovie;
      }

      if (replyingToDocId == null) {
        // --- ANA YORUM ---
        data['replyCount'] = 0;
        final ref = db
            .collection('posts')
            .doc(widget.postId)
            .collection('replies')
            .doc();
        batch.set(ref, data);

        final postRef = db.collection('posts').doc(widget.postId);
        batch.update(postRef, {'replyCount': FieldValue.increment(1)});
      } else {
        // --- ALT YANIT (REPLY) ---
        data.addAll({
          'replyToUid': replyingToUid,
          'replyToUserName': replyingToUserName,
          'replyToReplyId': replyingToReplyId,
        });
        final parentRef = db
            .collection('posts')
            .doc(widget.postId)
            .collection('replies')
            .doc(replyingToDocId);
        final subRef = parentRef.collection('subReplies').doc();

        batch.set(subRef, data);

        batch.update(parentRef, {'replyCount': FieldValue.increment(1)});

        final postRef = db.collection('posts').doc(widget.postId);
        batch.update(postRef, {'replyCount': FieldValue.increment(1)});
      }

      await batch.commit();

      // Bildirim Gönderme
      String previewText = text.isNotEmpty ? text : 'Bir film paylaştı 🎬';
      if (replyingToDocId == null) {
        await FeedService.instance.notifyComment(
          postId: widget.postId,
          postAuthorUid: widget.postAuthorId,
          preview: previewText,
        );
      } else if (replyingToUid != null && replyingToReplyId != null) {
        await FeedService.instance.notifyCommentReply(
          postId: widget.postId,
          targetUid: replyingToUid,
          parentReplyId: replyingToDocId,
          replyToReplyId: replyingToReplyId,
          preview: previewText,
        );
      }

      // --- TEMİZLİK ---
      _commentCtrl.clear();
      _removeSelectedMovie();
      _cancelReply();
      if (!mounted) return;
      FocusScope.of(context).unfocus();
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _initiateReply(
    String parentDocId,
    String userName,
    String uid,
    String replyId,
  ) {
    setState(() {
      _replyingToDocId = parentDocId;
      _replyingToReplyId = replyId;
      _replyingToUserName = userName;
      _replyingToUid = uid;
    });
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingToDocId = null;
      _replyingToReplyId = null;
      _replyingToUserName = null;
      _replyingToUid = null;
    });
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Yorumlar',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Liste
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _mainRepliesStream,
              builder: (context, snapshot) {
                // EKLENDİ: Engeller yüklenene kadar bekle
                if (_isLoadingBlocks ||
                    snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var docs = snapshot.data?.docs ?? [];

                // YENİ: Engellenen kişilerin yorumlarını ÇIKAR
                if (_blockedUsers.isNotEmpty) {
                  docs = docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return !_blockedUsers.contains(data['authorId']);
                  }).toList();
                }
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      "Henüz yorum yok.",
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    return _CommentTile(
                      key: ValueKey(docs[index].id),
                      postId: widget.postId,
                      doc: docs[index],
                      onReply: _initiateReply,
                      blockedUsers:
                          _blockedUsers, // YENİ: Listeyi aşağıya iletiyoruz
                    );
                  },
                );
              },
            ),
          ),

          // Input Alanı
          Container(
            // --- GÜNCELLEME BURADA YAPILDI ---
            // Eğer klavye açıksa (bottomInset > 0) normal boşluk bırak.
            // Eğer klavye kapalıysa alt tarafa 24 birim (veya dilediğiniz kadar) ekstra boşluk ver.
            padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset > 0 ? 8 : 40),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 5,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_replyingToUserName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0, left: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.reply,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_mentionLabel(_replyingToUserName!)} adlı kişiye yanıt veriliyor',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        InkWell(
                          onTap: _cancelReply,
                          child: const Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Seçilen Film Önizlemesi
                if (_selectedMovie != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: PosterImage(
                            posterUrl: _selectedMovie!['poster'] ?? '',
                            title: _selectedMovie!['title'] ?? '',
                            width: 30,
                            height: 45,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedMovie!['title'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _selectedMovie!['releaseDate']
                                        ?.toString()
                                        .split('-')
                                        .first ??
                                    '',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: _removeSelectedMovie,
                        ),
                      ],
                    ),
                  ),

                Row(
                  children: [
                    // Film Ekleme Butonu
                    IconButton(
                      onPressed: _pickMovie,
                      icon: Icon(
                        Icons.movie_creation_outlined,
                        color: _selectedMovie != null
                            ? theme.colorScheme.primary
                            : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TextField(
                        controller: _commentCtrl,
                        focusNode: _focusNode,
                        decoration: InputDecoration(
                          hintText: _replyingToUserName != null
                              ? 'Yanıtını yaz...'
                              : 'Yorum yap...',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withOpacity(0.3),
                        ),
                        minLines: 1,
                        maxLines: 4,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _isSending ? null : _send,
                      icon: _isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.send_rounded,
                              color: theme.colorScheme.primary,
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: bottomInset),
        ],
      ),
    );
  }
}

// ... Dosyanın geri kalanı aynı şekilde devam eder (_AttachedMovieWidget, _CommentTile vb.) ...
class _AttachedMovieWidget extends StatelessWidget {
  final Map<String, dynamic> movie;
  const _AttachedMovieWidget({required this.movie});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Film ID'si varsa detay sayfasına yönlendir
        final movieId = movie['id'];
        if (movieId != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MovieDetailScreen(tmdbId: movieId),
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: PosterImage(
                posterUrl: movie['poster'] ?? '',
                title: movie['title'] ?? '',
                width: 24,
                height: 36,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie['title'] ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Text(
                        movie['releaseDate']?.toString().split('-').first ?? '',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 8,
                        color: Colors.grey.shade600,
                      ),
                    ],
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

// --- TEKİL YORUM SATIRI ---
void _openCommentAuthorProfile(BuildContext context, String uid) {
  if (uid.isEmpty) return;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: uid)),
  );
}

class _CommentActionsButton extends StatefulWidget {
  final String postId;
  final String commentId;
  final String? subReplyId;
  final String authorId;
  final String authorName;

  const _CommentActionsButton({
    required this.postId,
    required this.commentId,
    this.subReplyId,
    required this.authorId,
    required this.authorName,
  });

  @override
  State<_CommentActionsButton> createState() => _CommentActionsButtonState();
}

class _CommentActionsButtonState extends State<_CommentActionsButton> {
  bool? _isFollowing;
  bool _busy = false;

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;
  bool get _isMe => _myUid == widget.authorId;

  @override
  void initState() {
    super.initState();
    _loadFollowState();
  }

  Future<void> _loadFollowState() async {
    final myUid = _myUid;
    if (myUid == null || _isMe || widget.authorId.isEmpty) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(myUid)
          .collection('following')
          .doc(widget.authorId)
          .get(const GetOptions(source: Source.serverAndCache));
      if (mounted) setState(() => _isFollowing = snap.exists);
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    if (_busy || _isMe || widget.authorId.isEmpty) return;
    final wasFollowing = _isFollowing == true;

    setState(() {
      _busy = true;
      _isFollowing = !wasFollowing;
    });

    try {
      if (wasFollowing) {
        await FollowSystemService.I.unfollowUser(widget.authorId);
      } else {
        await FollowSystemService.I.followUser(widget.authorId);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isFollowing = wasFollowing);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('İşlem tamamlanamadı.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openChat() async {
    final myUid = _myUid;
    if (myUid == null || _isMe || widget.authorId.isEmpty) return;

    final chatId = ChatService.instance.chatIdFor(myUid, widget.authorId);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChatRoomScreen(chatId: chatId, otherUid: widget.authorId),
      ),
    );
  }

  Future<void> _reportComment() async {
    final myUid = _myUid;
    if (myUid == null || widget.authorId.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('reports').add({
        'type': 'comment',
        'reporterId': myUid,
        'reportedUserId': widget.authorId,
        'reportedUserName': widget.authorName,
        'postId': widget.postId,
        'commentId': widget.commentId,
        if (widget.subReplyId != null) 'subReplyId': widget.subReplyId,
        'reason': 'comment_report',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Yorum raporlandı.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rapor gönderilemedi.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final followLabel = _isFollowing == true ? 'Takipten Çık' : 'Takip Et';
    return PopupMenuButton<String>(
      tooltip: 'Yorum seçenekleri',
      icon: const Icon(Icons.more_horiz_rounded, size: 20),
      onSelected: (value) async {
        switch (value) {
          case 'profile':
            _openCommentAuthorProfile(context, widget.authorId);
            break;
          case 'follow':
            await _toggleFollow();
            break;
          case 'message':
            await _openChat();
            break;
          case 'report':
            await _reportComment();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'profile',
          child: Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 20),
              SizedBox(width: 10),
              Text('Profili Gör'),
            ],
          ),
        ),
        if (!_isMe) ...[
          PopupMenuItem(
            value: 'follow',
            enabled: !_busy,
            child: Row(
              children: [
                Icon(
                  _isFollowing == true
                      ? Icons.person_remove_outlined
                      : Icons.person_add_outlined,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(followLabel),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'message',
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 20),
                SizedBox(width: 10),
                Text('Mesaj Gönder'),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'report',
            child: Row(
              children: [
                Icon(Icons.flag_outlined, size: 20, color: Colors.red),
                SizedBox(width: 10),
                Text('Bu yorumu raporla', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final String postId;
  final QueryDocumentSnapshot doc;
  final _ReplyCallback onReply;
  final Set<String> blockedUsers; // YENİ PARAMETRE

  const _CommentTile({
    super.key,
    required this.postId,
    required this.doc,
    required this.onReply,
    required this.blockedUsers, // YENİ PARAMETRE
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final authorId = data['authorId'] as String? ?? '';
    final text = data['text'] as String? ?? '';
    final likeCount = (data['likeCount'] ?? 0) as int;
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final movieData = data['movie'] as Map<String, dynamic>?;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(authorId)
          .get(),
      builder: (context, userSnap) {
        String name = "Kullanıcı";
        String replyName = "Kullanıcı";
        String? photo;
        if (userSnap.hasData && userSnap.data!.exists) {
          final uData = userSnap.data!.data() as Map<String, dynamic>;
          name = uData['displayName'] ?? uData['username'] ?? "Kullanıcı";
          replyName = (uData['username'] ?? name).toString();
          photo = uData['photoURL'];
        } else {
          replyName = name;
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _openCommentAuthorProfile(context, authorId),
                child: CircleAvatar(
                  radius: 18,
                  backgroundImage: photo != null ? NetworkImage(photo) : null,
                  child: photo == null
                      ? const Icon(Icons.person, size: 20)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: GestureDetector(
                            onTap: () =>
                                _openCommentAuthorProfile(context, authorId),
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (createdAt != null)
                          Text(
                            _formatTime(createdAt),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (text.isNotEmpty)
                      Text(text, style: const TextStyle(fontSize: 14)),

                    if (movieData != null)
                      _AttachedMovieWidget(movie: movieData),

                    const SizedBox(height: 6),

                    Row(
                      children: [
                        _CommentLikeButton(
                          postId: postId,
                          commentId: doc.id,
                          initialCount: likeCount,
                          isSubReply: false,
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () =>
                              onReply(doc.id, replyName, authorId, doc.id),
                          child: Text(
                            'Yanıtla',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Alt yanıt listesine blockedUsers gönderiliyor
                    _SubRepliesList(
                      key: ValueKey(doc.id),
                      postId: postId,
                      parentId: doc.id,
                      onReply: onReply,
                      blockedUsers: blockedUsers, // YENİ EKLENDİ
                    ),
                  ],
                ),
              ),
              _CommentActionsButton(
                postId: postId,
                commentId: doc.id,
                authorId: authorId,
                authorName: name,
              ),
            ],
          ),
        );
      },
    );
  }
}

String _formatTime(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'şimdi';
  if (diff.inMinutes < 60) return '${diff.inMinutes}dk';
  if (diff.inHours < 24) return '${diff.inHours}s';
  if (diff.inDays < 7) return '${diff.inDays}g';
  if (diff.inDays < 30) return '${diff.inDays ~/ 7}hf';
  if (diff.inDays < 365) return '${diff.inDays ~/ 30}ay';
  return '${diff.inDays ~/ 365}y';
}

class _SubRepliesList extends StatefulWidget {
  final String postId;
  final String parentId;
  final _ReplyCallback onReply;
  final Set<String> blockedUsers; // YENİ PARAMETRE

  const _SubRepliesList({
    super.key,
    required this.postId,
    required this.parentId,
    required this.onReply,
    required this.blockedUsers, // YENİ PARAMETRE
  });

  @override
  State<_SubRepliesList> createState() => _SubRepliesListState();
}

class _SubRepliesListState extends State<_SubRepliesList> {
  late final Stream<QuerySnapshot> _subStream;

  @override
  void initState() {
    super.initState();
    _subStream = FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('replies')
        .doc(widget.parentId)
        .collection('subReplies')
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _subStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        // --- İŞTE SENİN SORDUĞUN FİLTRELEME KISMI BURADA ---
        var subs = snapshot.data!.docs;

        if (widget.blockedUsers.isNotEmpty) {
          subs = subs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final authorId = data['authorId'] as String?;
            return !widget.blockedUsers.contains(authorId);
          }).toList();
        }

        if (subs.isEmpty) return const SizedBox.shrink();
        // ---------------------------------------------------

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            children: subs.map((subDoc) {
              final sData = subDoc.data() as Map<String, dynamic>;
              return _SubReplyTile(
                postId: widget.postId,
                parentId: widget.parentId,
                subDoc: subDoc,
                data: sData,
                onReply: widget.onReply,
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _SubReplyTile extends StatelessWidget {
  final String postId;
  final String parentId;
  final QueryDocumentSnapshot subDoc;
  final Map<String, dynamic> data;
  final _ReplyCallback onReply;

  const _SubReplyTile({
    required this.postId,
    required this.parentId,
    required this.subDoc,
    required this.data,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final authorId = (data['authorId'] ?? '').toString();
    final text = (data['text'] ?? '').toString();
    final likeCount = (data['likeCount'] ?? 0) as int;
    final movieData = data['movie'] as Map<String, dynamic>?;
    final replyToUid = (data['replyToUid'] ?? '').toString();
    final replyToUserName = (data['replyToUserName'] ?? '').toString();
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate(); // ← YENİ

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(authorId)
          .get(),
      builder: (context, snap) {
        String name = "";
        String replyName = "Kullanıcı";
        String? photo;
        if (snap.hasData) {
          final u = snap.data!.data() as Map<String, dynamic>?;
          name = u?['displayName'] ?? u?['username'] ?? '';
          replyName = (u?['username'] ?? name).toString();
          photo = u?['photoURL'];
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => _openCommentAuthorProfile(context, authorId),
                child: CircleAvatar(
                  radius: 12,
                  backgroundImage: photo != null ? NetworkImage(photo) : null,
                  child: photo == null
                      ? const Icon(Icons.person, size: 14)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: GestureDetector(
                            onTap: () =>
                                _openCommentAuthorProfile(context, authorId),
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        if (createdAt != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            _formatTime(createdAt),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (text.isNotEmpty)
                      _ReplyText(
                        text: text,
                        replyToUid: replyToUid,
                        replyToUserName: replyToUserName,
                      ),

                    if (movieData != null)
                      _AttachedMovieWidget(movie: movieData),

                    const SizedBox(height: 4),

                    Row(
                      children: [
                        _CommentLikeButton(
                          postId: postId,
                          commentId: parentId,
                          subReplyId: subDoc.id,
                          initialCount: likeCount,
                          isSubReply: true,
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () =>
                              onReply(parentId, replyName, authorId, subDoc.id),
                          child: Text(
                            'Yanıtla',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _CommentActionsButton(
                postId: postId,
                commentId: parentId,
                subReplyId: subDoc.id,
                authorId: authorId,
                authorName: name,
              ),
            ],
          ),
        );
      },
    );
  }
}

typedef _ReplyCallback =
    void Function(
      String parentDocId,
      String userName,
      String uid,
      String replyId,
    );

String _mentionLabel(String userName) {
  final trimmed = userName.trim();
  if (trimmed.isEmpty) return '@kullanıcı';
  return trimmed.startsWith('@') ? trimmed : '@$trimmed';
}

class _ReplyText extends StatelessWidget {
  const _ReplyText({
    required this.text,
    required this.replyToUid,
    required this.replyToUserName,
  });

  final String text;
  final String replyToUid;
  final String replyToUserName;

  @override
  Widget build(BuildContext context) {
    if (replyToUserName.isEmpty) {
      return Text(text, style: const TextStyle(fontSize: 13));
    }

    final mentionStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );

    return Text.rich(
      TextSpan(
        style: DefaultTextStyle.of(context).style.copyWith(fontSize: 13),
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: replyToUid.isEmpty
                  ? null
                  : () => _openCommentAuthorProfile(context, replyToUid),
              child: Text(_mentionLabel(replyToUserName), style: mentionStyle),
            ),
          ),
          TextSpan(text: ' $text'),
        ],
      ),
    );
  }
}

class _CommentLikeButton extends StatefulWidget {
  final String postId;
  final String commentId;
  final String? subReplyId;
  final int initialCount;
  final bool isSubReply;

  const _CommentLikeButton({
    required this.postId,
    required this.commentId,
    this.subReplyId,
    required this.initialCount,
    required this.isSubReply,
  });

  @override
  State<_CommentLikeButton> createState() => _CommentLikeButtonState();
}

class _CommentLikeButtonState extends State<_CommentLikeButton> {
  bool _isLiked = false;
  int _count = 0;
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _count = widget.initialCount;
    _checkIfLiked();
  }

  DocumentReference get _docRef {
    final db = FirebaseFirestore.instance;
    final parent = db
        .collection('posts')
        .doc(widget.postId)
        .collection('replies')
        .doc(widget.commentId);

    if (widget.isSubReply && widget.subReplyId != null) {
      return parent.collection('subReplies').doc(widget.subReplyId);
    }
    return parent;
  }

  Future<void> _checkIfLiked() async {
    if (_uid.isEmpty) return;
    try {
      final likeDoc = await _docRef.collection('likes').doc(_uid).get();
      if (mounted && likeDoc.exists) {
        setState(() => _isLiked = true);
      }
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    if (_uid.isEmpty) return;

    setState(() {
      _isLiked = !_isLiked;
      _count += _isLiked ? 1 : -1;
    });

    final likeRef = _docRef.collection('likes').doc(_uid);
    final batch = FirebaseFirestore.instance.batch();

    if (_isLiked) {
      batch.set(likeRef, {'createdAt': FieldValue.serverTimestamp()});
      batch.update(_docRef, {'likeCount': FieldValue.increment(1)});
    } else {
      batch.delete(likeRef);
      batch.update(_docRef, {'likeCount': FieldValue.increment(-1)});
    }

    try {
      await batch.commit();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLiked = !_isLiked;
          _count += _isLiked ? 1 : -1;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleLike,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isLiked ? Icons.favorite : Icons.favorite_border,
            size: widget.isSubReply ? 14 : 16,
            color: _isLiked ? Colors.red : Colors.grey.shade600,
          ),
          if (_count > 0) ...[
            const SizedBox(width: 4),
            Text(
              '$_count',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
          if (!widget.isSubReply && _count == 0) ...[
            const SizedBox(width: 4),
            Text(
              'Beğen',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
