import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';
import '../screens/search_movie.dart';
import '../services/text_filter_service.dart';

class ComposePostPage extends StatefulWidget {
  final int maxChars;
  final Map<String, dynamic>? initialMovie;

  final Future<void> Function({
    required String text,
    Map<String, dynamic>? movie,
    // DİKKAT: Artık tek bir File yerine List<File> alıyor.
    // Eğer mevcut onSend fonksiyonunuz tek resim destekliyorsa
    // bunu images.isNotEmpty ? images.first : null şeklinde dönüştürebilirsiniz.
    // Ancak tam destek için FeedService'in de güncellenmesi gerekir.
    // Şimdilik burada UI tarafını çoklu hale getiriyoruz.
    List<File>? images,
    double? rating,
    required bool isSpoiler,
    List<String>? tags,
    String? reviewTitle,
  })
  onSend;

  const ComposePostPage({
    super.key,
    required this.maxChars,
    this.initialMovie,
    required this.onSend,
  });

  @override
  State<ComposePostPage> createState() => _ComposePostPageState();
}

class _ComposePostPageState extends State<ComposePostPage> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _tagsCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();

  Map<String, dynamic>? _selectedMovie;

  // ÇOKLU RESİM LİSTESİ
  final List<File> _selectedImages = [];

  double _rating = 0.0;
  bool _isSpoiler = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialMovie != null) {
      _selectedMovie = widget.initialMovie;
    }
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> picked = await _picker.pickMultiImage(
        maxWidth: 1080,
        imageQuality: 85,
      );
      if (picked.isNotEmpty) {
        setState(() {
          // Var olanlara ekle (Limit koymak isterseniz burada kontrol edin)
          _selectedImages.addAll(picked.map((e) => File(e.path)));
        });
      }
    } catch (e) {
      debugPrint('');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _titleCtrl.dispose();
    _tagsCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pickMovie() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SearchMoviePage(isSelectionMode: true),
      ),
    );

    if (result != null && result is Map && mounted) {
      setState(() {
        _selectedMovie = {
          'title': result['title'],
          'poster': result['poster'],
          'tmdbId': result['id'],
          'releaseDate': result['releaseDate'],
        };
        _rating = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryGreen = const Color(0xFF2E7D32);
    final bgGradientStart = isDark
        ? const Color(0xFF0D2410)
        : const Color(0xFFE8F5E9);
    final bgGradientEnd = isDark ? const Color(0xFF000000) : Colors.white;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Yeni Gönderi',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgGradientStart, bgGradientEnd],
          ),
        ),
        child: SafeArea(
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              final text = value.text;
              final remaining = widget.maxChars - text.characters.length;
              final hasContent =
                  text.trim().isNotEmpty ||
                  _selectedImages.isNotEmpty ||
                  _selectedMovie != null;

              return ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                children: [
                  // Kullanıcı Bilgisi
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.grey.shade300,
                        backgroundImage:
                            FirebaseAuth.instance.currentUser?.photoURL != null
                            ? NetworkImage(
                                FirebaseAuth.instance.currentUser!.photoURL!,
                              )
                            : null,
                        child:
                            FirebaseAuth.instance.currentUser?.photoURL == null
                            ? const Icon(Icons.person, color: Colors.grey)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        FirebaseAuth.instance.currentUser?.displayName ??
                            'Kullanıcı',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Başlık (Opsiyonel)
                  if (_selectedMovie != null)
                    TextField(
                      controller: _titleCtrl,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: textColor,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Başlık (İsteğe bağlı)',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.grey[500] : Colors.grey[400],
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),

                  // Ana Metin
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    maxLines: null,
                    minLines: 3,
                    style: TextStyle(fontSize: 16, color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Neler düşünüyorsun?',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.grey[500] : Colors.grey[400],
                      ),
                      border: InputBorder.none,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // SEÇİLEN RESİMLER (YATAY KAYDIRMALI)
                  if (_selectedImages.isNotEmpty)
                    SizedBox(
                      height: 150,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _selectedImages.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  _selectedImages[index],
                                  height: 150,
                                  width: 120,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => setState(
                                    () => _selectedImages.removeAt(index),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                  if (_selectedImages.isNotEmpty) const SizedBox(height: 16),

                  // FİLM KARTI
                  if (_selectedMovie != null) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          if ((_selectedMovie!['poster'] ?? '').isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: PosterImage(
                                posterUrl: _selectedMovie!['poster'],
                                title: _selectedMovie!['title'],
                                width: 40,
                                height: 60,
                                fit: BoxFit.cover,
                              ),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _selectedMovie!['title'] ?? '',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() {
                              _selectedMovie = null;
                              _rating = 0;
                            }),
                            icon: const Icon(Icons.close, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // AYARLAR PANELI (Puan, Etiket, Spoiler)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: primaryGreen.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        if (_selectedMovie != null) ...[
                          Row(
                            children: [
                              Text(
                                "Puan:",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Row(
                                children: List.generate(5, (index) {
                                  return GestureDetector(
                                    onTap: () =>
                                        setState(() => _rating = index + 1.0),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2.0,
                                      ),
                                      child: Icon(
                                        index < _rating
                                            ? Icons.star_rounded
                                            : Icons.star_border_rounded,
                                        color: Colors.amber,
                                        size: 28,
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                        ],
                        TextField(
                          controller: _tagsCtrl,
                          style: TextStyle(color: textColor),
                          decoration: InputDecoration(
                            labelText: 'Etiketler',
                            hintText: 'korku, 90lar...',
                            prefixIcon: Icon(Icons.tag, color: primaryGreen),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.visibility_off_outlined,
                                  color: _isSpoiler ? Colors.red : Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "Spoiler içerir",
                                  style: TextStyle(
                                    color: textColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            Switch(
                              value: _isSpoiler,
                              onChanged: (val) =>
                                  setState(() => _isSpoiler = val),
                              activeColor: Colors.red,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ALT BAR (Butonlar)
                  Row(
                    children: [
                      IconButton(
                        onPressed: _pickImages,
                        icon: Icon(
                          Icons.photo_library_outlined,
                          color: primaryGreen,
                        ),
                        tooltip: 'Fotoğraf Ekle',
                      ),
                      IconButton(
                        onPressed: _pickMovie,
                        icon: Icon(
                          Icons.movie_creation_outlined,
                          color: primaryGreen,
                        ),
                        tooltip: 'Film Ekle',
                      ),
                      const Spacer(),
                      Text(
                        '$remaining',
                        style: TextStyle(
                          color: remaining < 0 ? Colors.red : Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _isSubmitting || !hasContent || remaining < 0
                            ? null
                            : () async {
                                if (TextFilterService.hasProfanity(text) ||
                                    TextFilterService.hasProfanity(
                                      _titleCtrl.text,
                                    )) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Uygunsuz içerik.'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }
                                List<String> tagsList = [];
                                if (_tagsCtrl.text.isNotEmpty) {
                                  tagsList = _tagsCtrl.text
                                      .split(',')
                                      .map((e) => e.trim())
                                      .where((e) => e.isNotEmpty)
                                      .toList();
                                }
                                setState(() => _isSubmitting = true);
                                try {
                                  await widget.onSend(
                                    text: text,
                                    movie: _selectedMovie,
                                    images:
                                        _selectedImages, // LİSTE GÖNDERİLİYOR
                                    rating: _rating > 0 ? _rating : null,
                                    isSpoiler: _isSpoiler,
                                    tags: tagsList,
                                    reviewTitle: _titleCtrl.text,
                                  );
                                } catch (_) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Hata oluştu.'),
                                      ),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _isSubmitting = false);
                                  }
                                }
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryGreen,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        child: const Text(
                          'Paylaş',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
