import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';

// --- PROJE İÇİ IMPORTLAR ---
import 'package:fluttergirdi/widgets/comments_sheet.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import 'package:fluttergirdi/widgets/app_confirm_dialog.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/screens/post_detail_screen.dart';
import 'package:fluttergirdi/screens/chat_room_screen.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/services/chat_service.dart';
import 'package:fluttergirdi/services/follow_system_service.dart';
import 'package:fluttergirdi/widgets/ui_polish.dart';

class PostTile extends StatefulWidget {
  final String postId;
  final String authorId;

  // Görsel Alanları
  final String? postImage; // Eski tekli yapı (Geriye dönük uyumluluk)
  final List<String>? postImages; // Yeni çoklu yapı

  // Kullanıcı Bilgileri
  final String displayName;
  final String handle;
  final String photoURL;

  // İçerik
  final String timeLabel;
  final String text;
  final String? reviewTitle;
  final double? rating;
  final bool isSpoiler;
  final List<String> tags;

  // Film Bilgileri
  final String? movieTitle;
  final String? moviePoster;
  final int? movieTmdbId;

  // Sayaçlar ve Durumlar
  final int likeCount;
  final int replyCount;
  final bool initialIsLiked;
  final bool initialIsFollowing;

  // Navigasyon Kontrolü
  final bool isDetail;

  // Aksiyonlar
  final Function(String postId, bool isLiked) onToggleLike;
  final Function(String userId) onStartChat;
  final Function(String userId) onFollow;
  final Function(String postId) onReport;
  final VoidCallback? onDelete;

  const PostTile({
    super.key,
    required this.postId,
    required this.authorId,
    this.postImage,
    this.postImages,
    required this.displayName,
    required this.handle,
    required this.photoURL,
    required this.timeLabel,
    required this.text,
    this.reviewTitle,
    this.rating,
    this.isSpoiler = false,
    this.tags = const [],
    this.movieTitle,
    this.moviePoster,
    this.movieTmdbId,
    required this.likeCount,
    required this.replyCount,
    required this.initialIsLiked,
    required this.initialIsFollowing,
    this.isDetail = false,
    required this.onToggleLike,
    required this.onStartChat,
    required this.onFollow,
    required this.onReport,
    this.onDelete,
  });

  @override
  State<PostTile> createState() => _PostTileState();
}

class _PostTileState extends State<PostTile> {
  late bool _isLiked;
  late bool _isFollowing;
  int _currentLikeCount = 0;
  bool _revealSpoiler = false;

  // Galeri Kontrolcüsü
  int _currentImageIndex = 0;
  final PageController _pageController = PageController();
  bool _isResolvingMovie = false;

  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _currentLikeCount = widget.likeCount;
    _isLiked = widget.initialIsLiked;
    _isFollowing = widget.initialIsFollowing;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // --- AKSİYON FONKSİYONLARI ---

  // --- MEVCUT _handleLike FONKSİYONU ---
  void _handleLike() {
    setState(() {
      _isLiked = !_isLiked;
      if (_isLiked) {
        _currentLikeCount++;
      } else {
        _currentLikeCount--;
      }
    });
    widget.onToggleLike(widget.postId, _isLiked);
  }

  // --- YENİ EKLENECEK FONKSİYON ---
  void _showLikers() {
    // Eğer beğeni sayısı 0 ise listeyi açma
    if (_currentLikeCount == 0) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _PostLikersSheet(postId: widget.postId),
    );
  }

  void _navigateToProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(uid: widget.authorId),
      ),
    );
  }

  void _navigateToDetail() {
    // Eğer zaten detay sayfasındaysak tekrar açma
    if (widget.isDetail) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: widget.postId),
      ),
    );
  }

  Future<void> _openMovieDetail() async {
    final title = widget.movieTitle?.trim() ?? '';
    final poster = widget.moviePoster;
    int? tmdbId = widget.movieTmdbId;

    if (tmdbId == null && title.isNotEmpty) {
      if (_isResolvingMovie) return;
      setState(() => _isResolvingMovie = true);
      tmdbId = await _resolveTmdbIdByTitle(title);
      if (mounted) setState(() => _isResolvingMovie = false);
    }

    if (!mounted) return;
    if (tmdbId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Film detaylari bulunamadi.')),
      );
      return;
    }

    unawaited(_cacheResolvedMovieId(tmdbId));
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MovieDetailScreen(
          tmdbId: tmdbId!,
          title: title.isEmpty ? null : title,
          posterUrl: poster,
        ),
      ),
    );
  }

  Future<int?> _resolveTmdbIdByTitle(String title) async {
    final db = FirebaseFirestore.instance;

    try {
      final catalogByTitle = await db
          .collection('catalog_films')
          .where('title', isEqualTo: title)
          .limit(1)
          .get();
      if (catalogByTitle.docs.isNotEmpty) {
        final id = _coerceTmdbId(catalogByTitle.docs.first.data()['tmdbId']);
        if (id != null) return id;
      }
    } catch (_) {}

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('callTMDB')
          .call({
            'endpoint': '/3/search/movie',
            'params': {'query': title, 'include_adult': 'false'},
          });
      final data = Map<String, dynamic>.from(result.data as Map);
      final results = data['results'] as List?;
      if (results != null && results.isNotEmpty) {
        return _coerceTmdbId((results.first as Map)['id']);
      }
    } catch (e) {
      debugPrint('Film detay cozumleme hatasi: $e');
    }

    return null;
  }

  int? _coerceTmdbId(dynamic raw) {
    if (raw is int && raw > 0) return raw;
    if (raw is num && raw > 0) return raw.toInt();
    if (raw is String) {
      final parsed = int.tryParse(raw.trim());
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  Future<void> _cacheResolvedMovieId(int tmdbId) async {
    if (widget.movieTmdbId != null) return;
    try {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .set({
            'tmdbId': tmdbId,
            'movie.tmdbId': tmdbId,
            'movie.id': tmdbId,
          }, SetOptions(merge: true));
    } catch (_) {}
  }

  void _openFullScreenImage(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(
          child: CachedNetworkImage(
            imageUrl: url,
            placeholder: (context, url) =>
                const Center(child: CircularProgressIndicator()),
            errorWidget: (context, url, error) =>
                const Icon(Icons.error, color: Colors.white),
          ),
        ),
      ),
    );
  }

  void _showCommentsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          CommentsSheet(postId: widget.postId, postAuthorId: widget.authorId),
    );
  }

  Future<void> _startMessage() async {
    try {
      final chatId = ChatService.instance.chatIdFor(
        _currentUserId,
        widget.authorId,
      );
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ChatRoomScreen(chatId: chatId, otherUid: widget.authorId),
          ),
        );
      }
    } catch (e) {
      debugPrint('Sohbet hatası: $e');
    }
  }

  // --- UI OLUŞTURUCULAR ---

  Widget _buildImageCarousel(List<String> images) {
    if (images.isEmpty) return const SizedBox.shrink();
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (MediaQuery.sizeOf(context).width * devicePixelRatio)
        .round()
        .clamp(360, 1440)
        .toInt();

    // Tek resim varsa direkt göster (PageView overhead'i olmasın)
    if (images.length == 1) {
      return GestureDetector(
        onTap: widget.isDetail
            ? () => _openFullScreenImage(images.first)
            : _navigateToDetail,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 500),
          width: double.infinity,
          color: Colors.black12,
          child: CachedNetworkImage(
            imageUrl: images.first,
            memCacheWidth: cacheWidth,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(color: Colors.grey[200]),
            errorWidget: (context, url, error) => const SizedBox(
              height: 200,
              child: Center(
                child: Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          ),
        ),
      );
    }

    // Çoklu resim (Carousel)
    return Column(
      children: [
        SizedBox(
          height: 400, // Instagram standardı kare/dikey oran
          child: PageView.builder(
            controller: _pageController,
            itemCount: images.length,
            onPageChanged: (index) {
              setState(() => _currentImageIndex = index);
            },
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: widget.isDetail
                    ? () => _openFullScreenImage(images[index])
                    : _navigateToDetail,
                child: CachedNetworkImage(
                  imageUrl: images[index],
                  memCacheWidth: cacheWidth,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  placeholder: (context, url) =>
                      Container(color: Colors.grey[200]),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                ),
              );
            },
          ),
        ),
        // Nokta Göstergesi (Dots Indicator)
        if (images.length > 1)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(images.length, (index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: _currentImageIndex == index ? 8 : 6,
                  height: _currentImageIndex == index ? 8 : 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // RENK DEĞİŞİKLİĞİ: MAVİ -> YEŞİL
                    color: _currentImageIndex == index
                        ? const Color(0xFF2E7D32) // Temanın yeşili
                        : Colors.grey.withOpacity(0.5),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildRatingStars(double rating) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(5, (index) {
          IconData icon = Icons.star_border_rounded;
          if (index < rating) {
            icon = Icons.star_rounded;
          }
          return Icon(icon, color: Colors.amber, size: 20);
        }),
      ),
    );
  }

  void _showMoreOptions() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.authorId != _currentUserId) ...[
                ListTile(
                  leading: Icon(
                    _isFollowing
                        ? Icons.person_remove_outlined
                        : Icons.person_add_outlined,
                    color: _isFollowing ? Colors.red : null,
                  ),
                  title: Text(
                    _isFollowing
                        ? '@${widget.handle.replaceAll('@', '')} takipten çık'
                        : '@${widget.handle.replaceAll('@', '')} takip et',
                    style: TextStyle(color: _isFollowing ? Colors.red : null),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    if (_isFollowing) {
                      await FollowSystemService.I.unfollowUser(widget.authorId);
                      if (mounted) setState(() => _isFollowing = false);
                    } else {
                      await FollowSystemService.I.followUser(widget.authorId);
                      widget.onFollow(widget.authorId);
                      if (mounted) setState(() => _isFollowing = true);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: const Text('Mesaj Gönder'),
                  onTap: () {
                    Navigator.pop(context);
                    _startMessage();
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.flag_outlined, color: Colors.red),
                  title: const Text(
                    'Bildir / Şikayet Et',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onReport(widget.postId);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Bildiriminiz alındı.')),
                    );
                  },
                ),
              ] else
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Gönderiyi Sil',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    if (!mounted) return;
                    final confirm = await showAppConfirmDialog(
                      context: this.context,
                      title: 'Gönderiyi Sil',
                      message:
                          'Bu gönderi kalıcı olarak silinecek. Bu işlem geri alınamaz.',
                      confirmText: 'Sil',
                      icon: Icons.delete_forever_rounded,
                      destructive: true,
                    );

                    if (confirm == true) {
                      try {
                        await FirebaseFirestore.instance
                            .collection('posts')
                            .doc(widget.postId)
                            .delete();
                        if (widget.onDelete != null) widget.onDelete!();
                      } catch (e) {
                        debugPrint('Silme hatası: $e');
                      }
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Görselleri Birleştir (Geriye dönük uyumluluk + Yeni Liste)
    final List<String> displayImages = [];
    if (widget.postImages != null && widget.postImages!.isNotEmpty) {
      displayImages.addAll(widget.postImages!);
    } else if (widget.postImage != null && widget.postImage!.isNotEmpty) {
      displayImages.add(widget.postImage!);
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.32),
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. HEADER (Profil, İsim, Tarih)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _navigateToProfile,
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: cs.surfaceContainerHighest,
                    backgroundImage: widget.photoURL.isNotEmpty
                        ? ResizeImage(
                            CachedNetworkImageProvider(widget.photoURL),
                            width: (40 * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                          )
                        : null,
                    child: widget.photoURL.isEmpty
                        ? Icon(Icons.person, color: cs.onSurfaceVariant)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _navigateToProfile,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.handle.replaceAll(
                            '@',
                            '',
                          ), // @ işaretini varsa temizler
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.timeLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.more_horiz, color: cs.onSurfaceVariant),
                  onPressed: _showMoreOptions,
                ),
              ],
            ),
          ),

          // 2. FOTOĞRAF ALANI (EN YUKARIDA)
          if (displayImages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _buildImageCarousel(displayImages),
            ),

          // 3. İNCELEME BAŞLIĞI (Varsa)
          if (widget.reviewTitle != null && widget.reviewTitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                widget.reviewTitle!,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),

          // 4. METİN İÇERİĞİ (Spoiler Korumalı)
          if (widget.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                if (widget.isSpoiler && !_revealSpoiler) {
                  setState(() => _revealSpoiler = true);
                } else {
                  _navigateToDetail();
                }
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: widget.isSpoiler && !_revealSpoiler
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.errorContainer.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.error.withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: cs.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Spoiler içerir! Okumak için dokun.",
                                style: TextStyle(
                                  color: cs.error,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Text(
                        widget.text,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),

          // 5. YILDIZLAR (Filmin Hemen Üstünde)
          if (widget.rating != null) _buildRatingStars(widget.rating!),

          // 6. FİLM KARTI (Varsa)
          if (widget.movieTitle != null)
            GestureDetector(
              onTap: _openMovieDetail,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.outlineVariant.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.zero,
                        child: PosterImage(
                          posterUrl: widget.moviePoster,
                          title: widget.movieTitle,
                          fit: BoxFit.cover,
                          width: 54,
                          cacheWidth:
                              (54 * MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF2E7D32,
                                ).withOpacity(0.1), // Yeşil tema
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'İZLİYOR',
                                style: TextStyle(
                                  color: Color(0xFF2E7D32),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.movieTitle!,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: _isResolvingMovie
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.chevron_right,
                                color: Colors.grey,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 7. ETİKETLER
          if (widget.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: widget.tags.map((tag) {
                  return TintedTag(
                    label: '#$tag',
                    color: const Color(0xFF2E7D32),
                    compact: true,
                  );
                }).toList(),
              ),
            ),

          // 8. ALT AKSİYONLAR (Like, Comment, Share)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 16, right: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    // YENİ KOD (İkon ve Sayı ayrı tıklanabilir)
                    Row(
                      children: [
                        // 1. KALP İKONU (Sadece Beğenme İşlemi)
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _handleLike,
                          child: Padding(
                            padding: const EdgeInsets.all(6.0),
                            child: Icon(
                              _isLiked ? Icons.favorite : Icons.favorite_border,
                              color: _isLiked
                                  ? Colors.red
                                  : cs.onSurfaceVariant,
                              size: 26,
                            ),
                          ),
                        ),

                        // 2. BEĞENİ SAYISI (Listeyi Açma İşlemi)
                        if (_currentLikeCount > 0)
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: _showLikers, // Sayıya basınca listeyi aç
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 6,
                              ),
                              child: Text(
                                '$_currentLikeCount',
                                style: TextStyle(
                                  color: _isLiked
                                      ? Colors.red
                                      : cs.onSurfaceVariant,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    _ActionButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      color: cs.onSurfaceVariant,
                      count: widget.replyCount,
                      onTap: _showCommentsSheet,
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(
                    Icons.share_outlined,
                    size: 22,
                    color: cs.onSurfaceVariant,
                  ),
                  onPressed: () {
                    final String appLink =
                        'https://cinematchsocial.web.app/post?id=${widget.postId}';

                    // Gönderi metni boşsa film adını, ikisi de boşsa varsayılan metni al
                    String contentPreview = widget.text;
                    if (contentPreview.isEmpty) {
                      contentPreview =
                          widget.movieTitle ??
                          'Cinematch\'te bir gönderi paylaştı!';
                    }

                    // Metin çok uzunsa kırp
                    if (contentPreview.length > 100) {
                      contentPreview = '${contentPreview.substring(0, 100)}...';
                    }

                    Share.share(
                      '${widget.displayName} (@${widget.handle.replaceAll('@', '')}):\n\n'
                      '"$contentPreview"\n\n'
                      'Tümünü görmek için tıkla:\n$appLink',
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Yardımcı Buton Widget'ı
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 24, color: color),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
// --- BEĞENENLER LİSTESİ PENCERESİ ---

class _PostLikersSheet extends StatelessWidget {
  final String postId;
  const _PostLikersSheet({required this.postId});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (_, controller) {
        return Column(
          children: [
            // Başlık ve Tutamaç
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                "Beğenenler",
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),

            // Liste
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                // 'posts' -> 'postId' -> 'likes' koleksiyonunu dinliyoruz
                stream: FirebaseFirestore.instance
                    .collection('posts')
                    .doc(postId)
                    .collection('likes')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return const Center(child: Text("Henüz kimse beğenmemiş."));
                  }

                  return ListView.builder(
                    controller: controller,
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final uid =
                          data['by'] as String; // 'by' alanı user ID'yi tutuyor
                      return _LikerUserTile(uid: uid);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// Tekil Kullanıcı Satırı (Veriyi çeker ve gösterir)

class _LikerUserTile extends StatelessWidget {
  final String uid;
  const _LikerUserTile({required this.uid});

  // lib/widgets/post_tile.dart içindeki _LikerUserTile build metodu

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) return const SizedBox.shrink();

        // "Tek isim" kuralımız için username alanını alıyoruz
        final username =
            (data['username'] ?? data['displayName'] ?? 'Kullanıcı').toString();
        final photoURL = data['photoURL'] as String?;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: uid)),
            ),
            child: CircleAvatar(
              radius: 24,
              backgroundColor: Colors.grey[200],
              backgroundImage: (photoURL != null && photoURL.isNotEmpty)
                  ? NetworkImage(photoURL)
                  : null,
              child: (photoURL == null || photoURL.isEmpty)
                  ? const Icon(Icons.person, color: Colors.grey)
                  : null,
            ),
          ),
          // Sadece kullanıcı adı görünecek ve @ işareti temizlenecek
          title: Text(
            username.replaceAll('@', ''),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          // Alt başlığı (Letterboxd vb.) tamamen kaldırıyoruz
          subtitle: null,
          trailing: const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: Colors.grey,
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: uid)),
            );
          },
        );
      },
    );
  }
}
