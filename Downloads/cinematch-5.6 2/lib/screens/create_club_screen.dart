import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:fluttergirdi/services/club_service.dart';

class CreateClubScreen extends StatefulWidget {
  const CreateClubScreen({super.key});

  @override
  State<CreateClubScreen> createState() => _CreateClubScreenState();
}

class _CreateClubScreenState extends State<CreateClubScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  File? _imageFile;
  bool _isPrivate = false;
  bool _isLoading = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _imageFile = File(picked.path);
      });
    }
  }

  Future<String?> _uploadImage(File file) async {
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('club_banners')
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(file);
      return await ref.getDownloadURL();
    } catch (e) {
      return null;
    }
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Oda adı gerekli.')));
      return;
    }
    setState(() => _isLoading = true);

    try {
      String? imageUrl;
      if (_imageFile != null) {
        imageUrl = await _uploadImage(_imageFile!);
      }

      await ClubService.instance.createClub(
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        isPrivate: _isPrivate,
        imageUrl: imageUrl,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Hata: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // 1. ARKA PLAN (Hafif Görsel)
          if (_imageFile != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.15, // Daha soluk
                child: Image.file(_imageFile!, fit: BoxFit.cover),
              ),
            ),

          // Gradiant Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    bgColor.withValues(alpha: 0.4),
                    bgColor.withValues(alpha: 0.95),
                    bgColor,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          // 2. İÇERİK
          SafeArea(
            child: Column(
              children: [
                // Minimal Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(
                          Icons.close_rounded,
                          size: 24,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: isDark
                              ? Colors.white10
                              : Colors.black.withValues(alpha: 0.05),
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(40, 40),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "YENİ ODA",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),

                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      children: [
                        // --- KOMPAKT GÖRSEL ALANI ---
                        GestureDetector(
                          onTap: _pickImage,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            height: 160, // Yükseklik azaltıldı
                            curve: Curves.easeOutExpo,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.03)
                                  : Colors.black.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _imageFile != null
                                    ? Colors.transparent
                                    : (isDark
                                          ? Colors.white12
                                          : Colors.black12),
                                width: 1,
                              ),
                              image: _imageFile != null
                                  ? DecorationImage(
                                      image: FileImage(_imageFile!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: _imageFile == null
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_photo_alternate_outlined,
                                        size: 32,
                                        color: isDark
                                            ? Colors.white38
                                            : Colors.black38,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        "Kapak Görseli",
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? Colors.white38
                                              : Colors.black38,
                                        ),
                                      ),
                                    ],
                                  )
                                : Align(
                                    alignment: Alignment.topRight,
                                    child: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: CircleAvatar(
                                        radius: 16,
                                        backgroundColor: Colors.black45,
                                        child: const Icon(
                                          Icons.edit,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // --- İSİM ALANI (Minimal) ---
                        _buildMinimalInput(
                          context,
                          controller: _nameController,
                          label: "ODA ADI",
                          hint: "Örn: Sinefiller",
                          icon: Icons.title_rounded,
                        ),

                        const SizedBox(height: 24),

                        // --- AÇIKLAMA ALANI (Minimal) ---
                        _buildMinimalInput(
                          context,
                          controller: _descController,
                          label: "AÇIKLAMA",
                          hint: "Amacınız ne?",
                          icon: Icons.short_text_rounded,
                          maxLines: 3,
                        ),

                        const SizedBox(height: 32),

                        // --- GİZLİLİK SEÇİMİ (Minimal) ---
                        GestureDetector(
                          onTap: () => setState(() => _isPrivate = !_isPrivate),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.03)
                                  : Colors.black.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _isPrivate
                                    ? const Color(
                                        0xFFC62828,
                                      ).withValues(alpha: 0.3)
                                    : const Color(
                                        0xFF4CAF50,
                                      ).withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _isPrivate
                                        ? const Color(
                                            0xFFC62828,
                                          ).withValues(alpha: 0.1)
                                        : const Color(
                                            0xFF4CAF50,
                                          ).withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _isPrivate
                                        ? Icons.lock_outline_rounded
                                        : Icons.public_rounded,
                                    color: _isPrivate
                                        ? const Color(0xFFC62828)
                                        : const Color(0xFF4CAF50),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _isPrivate
                                            ? "Özel Oda"
                                            : "Herkese Açık",
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black87,
                                        ),
                                      ),
                                      Text(
                                        _isPrivate
                                            ? "Sadece davetliler"
                                            : "Herkes katılabilir",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? Colors.white38
                                              : Colors.black38,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _isPrivate,
                                  activeThumbColor: const Color(0xFFC62828),
                                  activeTrackColor: const Color(
                                    0xFFC62828,
                                  ).withValues(alpha: 0.3),
                                  inactiveThumbColor: const Color(0xFF4CAF50),
                                  inactiveTrackColor: const Color(
                                    0xFF4CAF50,
                                  ).withValues(alpha: 0.3),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  onChanged: (val) =>
                                      setState(() => _isPrivate = val),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 70),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. ZARİF OLUŞTUR BUTONU
          Positioned(
            bottom: 30,
            left: 24,
            right: 24,
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 0.5),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: _animController,
                      curve: Curves.easeOutBack,
                    ),
                  ),
              child: SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor.withValues(alpha: 1.0),
                    foregroundColor: const Color.fromARGB(255, 33, 94, 15),
                    elevation: 4, // Gölge azaltıldı
                    shadowColor: primaryColor.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              "Oluştur",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalInput(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11, // Çok daha küçük ve şık
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
          ),
          child: Row(
            crossAxisAlignment: maxLines > 1
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(top: maxLines > 1 ? 12 : 0, right: 12),
                child: Icon(
                  icon,
                  size: 18,
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: maxLines,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                  ), // Font küçüldü
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white24 : Colors.black26,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
