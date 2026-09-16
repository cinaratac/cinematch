import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/services/user_profile_service.dart';
import 'package:fluttergirdi/services/letterboxd_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart'; // TMDB araması için eklendi
import 'package:cached_network_image/cached_network_image.dart'; // TMDB resimleri için eklendi
import '../services/text_filter_service.dart';

class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic>? initialUserData;
  const EditProfilePage({super.key, this.initialUserData});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _letterboxdCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  String? _selectedBannerColor;

  // Kullanıcılara sunacağımız banner renk seçenekleri (Hex formatında)
  final List<String> _bannerColorOptions = [
    '#2E7D32', // Klasik Yeşil
    '#1565C0', // Mavi
    '#C62828', // Kırmızı
    '#6A1B9A', // Mor
    '#EF6C00', // Turuncu
    '#00695C', // Turkuaz
    '#37474F', // Mavi Gri
    '#D81B60', // Pembe
    '#000000', // Siyah
  ];
  // Listeleri dynamic yapıyoruz ki içine hem String (eski) hem de Map (yeni TMDB verisi) alabilsin
  final List<dynamic> _favDirectors = [];
  final List<dynamic> _favActors = [];
  final Set<String> _selectedGenres = {}; // Seçilen türler

  // Tür Listesinin Açık/Kapalı Durumu
  bool _isGenresExpanded = false;

  final List<String> _genreOptions = const [
    'Aksiyon',
    'Aksiyon-Gerilim',
    'Casus',
    'Dövüş',
    'Felaket',
    'Macera',
    "Klasikler",
    'Bilimkurgu',
    'Kıyamet Sonrası',
    'Steampunk',
    'Dram',
    'Melodram',
    'Politik Dram',
    'Tarihi Dram',
    'Trajedi',
    'Gerilim',
    'Psikolojik Gerilim',
    'Politik Gerilim',
    'Erotik Gerilim',
    'Komedi',
    'Aksiyon Komedisi',
    'Kara Mizah',
    'Komedi-Drama',
    'Romantik Komedi',
    'Parodi',
    'Korku',
    'Gotik',
    'Doğaüstü',
    'Vampir',
    'Zombi',
    'Slasher',
    'Fantastik',
    'Mitolojik',
    'K-drama',
    'Süper Kahraman',
    'Romantik',
    'Romantik Dram',
    'Romantik Gerilim',
    'Savaş',
    'Tarih',
    'Biyografi',
    'Müzikal',
    'Belgesel',
    'Doğa',
    'Gezi',
    'Spor',
    'Suç',
    'Polisiye',
    'Mafya',
    'Gizem',
    'Kara Film (Noir)',
    'Western',
    'Fantastik Komedi',
    'Aile',
    'Çocuk',
    'Gençlik',
    'LGBTQ+',
    'Animasyon',
    'Anime',
  ];

  String? _origUsername;
  String? _origBio;
  String? _origLb;
  int? _origAge;

  bool _loading = true;
  bool _saving = false;
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() {
          _selectedImage = File(picked.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Resim seçilemedi.')));
    }
  }

  void _applyInitial(Map<String, dynamic> data) {
    String val = (data['username'] ?? '').toString();
    if (val.isEmpty) {
      final user = FirebaseAuth.instance.currentUser;
      if (user?.displayName != null && user!.displayName!.isNotEmpty) {
        val = user.displayName!;
      }
    }
    _usernameCtrl.text = val;
    _bioCtrl.text = (data['bio'] ?? '').toString();
    _selectedBannerColor = (data['bannerColor'] ?? '').toString();
    if (_selectedBannerColor!.isEmpty) _selectedBannerColor = null;
    _origUsername = (_usernameCtrl.text).trim().isEmpty
        ? null
        : _usernameCtrl.text.trim();

    _letterboxdCtrl.text = (data['letterboxdUsername'] ?? '').toString();

    // Yönetmenler
    _favDirectors.clear();
    final dArr = data['favDirectors'];
    if (dArr is List) {
      _favDirectors.addAll(dArr);
    }

    // Oyuncular
    _favActors.clear();
    final aArr = data['favActors'];
    if (aArr is List) {
      _favActors.addAll(aArr);
    }

    // Türler
    _selectedGenres.clear();
    final gArr = data['favGenres'];
    if (gArr is List) {
      _selectedGenres.addAll(gArr.whereType<String>());
    }

    final age = data['age'];
    if (age is int && age > 15) {
      _ageCtrl.text = age.toString();
    } else if (age is num && age.toInt() > 0) {
      _ageCtrl.text = age.toInt().toString();
    } else {
      _ageCtrl.text = '';
    }

    _origUsername = (_usernameCtrl.text).trim().isEmpty
        ? null
        : _usernameCtrl.text.trim();
    final lbStr = (_letterboxdCtrl.text).trim();
    _origLb = lbStr.isEmpty ? null : lbStr.toLowerCase();

    if (_ageCtrl.text.trim().isNotEmpty) {
      _origAge = int.tryParse(_ageCtrl.text.trim());
    } else {
      _origAge = null;
    }
    _origBio = (_bioCtrl.text).trim().isEmpty ? null : _bioCtrl.text.trim();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialUserData != null) {
      _applyInitial(widget.initialUserData!);
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.initialUserData != null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      var doc = await ref.get(const GetOptions(source: Source.cache));
      if (!doc.exists) {
        doc = await ref.get(const GetOptions(source: Source.server));
      }
      final data = doc.data() ?? <String, dynamic>{};
      _applyInitial(data);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestLbRefresh() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final currLb = _letterboxdCtrl.text.trim();
    if (currLb.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce Letterboxd kullanıcı adını gir.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Letterboxd verileri çekiliyor...'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );

      await LetterboxdService.fullSyncOnboarding(
        uid: user.uid,
        lbUsername: currLb,
        source: 'manual_edit_profile',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Letterboxd verileri başarıyla güncellendi!'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('Letterboxd yenileme hatası: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      final message = e is LetterboxdSyncException
          ? e.message
          : 'Letterboxd verileri güncellenemedi. Lütfen tekrar dene.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _removeDirector(dynamic item) {
    setState(() {
      _favDirectors.remove(item);
    });
  }

  void _removeActor(dynamic item) {
    setState(() {
      _favActors.remove(item);
    });
  }

  // Listeden öğenin ismini çeken yardımcı fonksiyon
  String _getItemName(dynamic item) {
    if (item is Map) return item['name'] ?? '';
    return item.toString();
  }

  // TMDB Arama Menüsünü Açan Fonksiyon
  // TMDB Arama Menüsünü Açan Fonksiyon
  void _showTMDBPersonSearch(String title, bool isActor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return _TMDBPersonSearchSheet(
          title: title,
          isActorSearch:
              isActor, // <-- YENİ: Arama ekranına ne aradığımızı söylüyoruz
          onPersonSelected: (personData) {
            setState(() {
              if (isActor) {
                if (!_favActors.any(
                  (item) => (item is Map ? item['id'] : 0) == personData['id'],
                )) {
                  _favActors.add(personData);
                }
              } else {
                if (!_favDirectors.any(
                  (item) => (item is Map ? item['id'] : 0) == personData['id'],
                )) {
                  _favDirectors.add(personData);
                }
              }
            });
            Navigator.pop(context); // Seçimden sonra pencereyi kapat
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    _letterboxdCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      String? uploadedPhotoUrl;
      if (_selectedImage != null) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('user_avatars')
            .child('${user.uid}_$timestamp.jpg');

        await storageRef.putFile(_selectedImage!);
        uploadedPhotoUrl = await storageRef.getDownloadURL();
        await user.updatePhotoURL(uploadedPhotoUrl);
      }

      final username = _usernameCtrl.text.trim();
      final bio = _bioCtrl.text.trim();
      final ageStr = _ageCtrl.text.trim();
      final age = int.tryParse(ageStr);
      final currLb = _letterboxdCtrl.text.trim().toLowerCase();

      if (TextFilterService.hasProfanity(username)) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kullanıcı adı uygunsuz.')),
          );
        setState(() => _saving = false);
        return;
      }
      if (TextFilterService.hasProfanity(bio)) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Biyografi uygunsuz.')));
        setState(() => _saving = false);
        return;
      }
      if (_origUsername != null &&
          username.toLowerCase() != _origUsername!.toLowerCase()) {
        final existingUser = await FirebaseFirestore.instance
            .collection('users')
            .where('displayName_lc', isEqualTo: username.toLowerCase())
            .get();

        if (existingUser.docs.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Bu kullanıcı adı zaten başka biri tarafından kullanılıyor.',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          setState(() => _saving = false);
          return;
        }
      }

      if (username.isNotEmpty) {
        await user.updateDisplayName(username);
      }

      Map<String, dynamic> payload = {};
      if (uploadedPhotoUrl != null) {
        payload['photoURL'] = uploadedPhotoUrl;
        payload['photoUrl'] = FieldValue.delete();
      }

      if (username.isNotEmpty) {
        payload['username'] = username;
        payload['username_lc'] = username.toLowerCase();
        payload['displayName'] = username;
        payload['displayName_lc'] = username.toLowerCase();
        payload['handle'] = username;
      }
      if (_selectedBannerColor != null) {
        payload['bannerColor'] = _selectedBannerColor;
      } else {
        payload['bannerColor'] = FieldValue.delete();
      }

      payload['bio'] = bio.isNotEmpty ? bio : FieldValue.delete();
      payload['age'] = (age != null && age > 0) ? age : FieldValue.delete();
      payload['favDirectors'] = _favDirectors;
      payload['favActors'] = _favActors;
      payload['favGenres'] = _selectedGenres.toList();

      bool lbChanged = _origLb != currLb;
      if (lbChanged) {
        payload['letterboxdUsername'] = currLb.isNotEmpty
            ? currLb
            : FieldValue.delete();
        payload['letterboxdUsername_lc'] = currLb.isNotEmpty
            ? currLb
            : FieldValue.delete();
        payload['lbUsername'] = currLb.isNotEmpty
            ? currLb
            : FieldValue.delete();
        await UserProfileService.instance.clearTasteProfile(user.uid);
      }

      payload['updatedAt'] = FieldValue.serverTimestamp();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(payload, SetOptions(merge: true));

      final sp = await SharedPreferences.getInstance();
      if (currLb.isNotEmpty) {
        await sp.setString('lb_username_${user.uid}', currLb);
      } else {
        await sp.remove('lb_username_${user.uid}');
      }

      if (lbChanged && currLb.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profil ve Letterboxd güncelleniyor...'),
              backgroundColor: Color(0xFF2E7D32),
            ),
          );
        }
        try {
          await LetterboxdService.fullSyncOnboarding(
            uid: user.uid,
            lbUsername: currLb,
            source: 'profile_username_change',
          );
        } catch (_) {}
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profil güncellendi.'),
              backgroundColor: Color(0xFF2E7D32),
            ),
          );
        }
      }

      _origUsername = username.isNotEmpty ? username : null;
      _origBio = bio.isNotEmpty ? bio : null;
      _origAge = age;
      _origLb = currLb.isNotEmpty ? currLb : null;

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
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
    final sectionTitleColor = isDark ? const Color(0xFF81C784) : primaryGreen;
    final buttonTextColor = Colors.white;
    final containerColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark
        ? Colors.grey[800]!
        : Colors.grey.withOpacity(0.3);
    final textColor = isDark ? Colors.white : Colors.black87;

    if (_loading) {
      return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [bgGradientStart, bgGradientEnd],
            ),
          ),
          child: Center(child: CircularProgressIndicator(color: primaryGreen)),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Profili Düzenle',
          style: TextStyle(
            color: sectionTitleColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: sectionTitleColor),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: TextButton(
              onPressed: _saving ? null : _save,
              style: TextButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: buttonTextColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Kaydet',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
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
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // --- PROFİL RESMİ ---
                Center(
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: primaryGreen, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: primaryGreen.withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: isDark
                                ? Colors.grey[800]
                                : Colors.grey[200],
                            backgroundImage: _selectedImage != null
                                ? FileImage(_selectedImage!)
                                : (FirebaseAuth
                                                  .instance
                                                  .currentUser
                                                  ?.photoURL !=
                                              null
                                          ? NetworkImage(
                                              FirebaseAuth
                                                  .instance
                                                  .currentUser!
                                                  .photoURL!,
                                            )
                                          : null)
                                      as ImageProvider?,
                            child:
                                (_selectedImage == null &&
                                    FirebaseAuth
                                            .instance
                                            .currentUser
                                            ?.photoURL ==
                                        null)
                                ? Icon(
                                    Icons.person,
                                    size: 50,
                                    color: isDark
                                        ? Colors.grey[500]
                                        : Colors.grey[400],
                                  )
                                : null,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: primaryGreen,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark ? Colors.black : Colors.white,
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // --- KULLANICI BİLGİLERİ ---
                _SectionTitle(
                  title: 'Temel Bilgiler',
                  color: sectionTitleColor,
                ),
                const SizedBox(height: 16),

                _buildStyledTextField(
                  context,
                  controller: _usernameCtrl,
                  labelText: 'Kullanıcı Adı',
                  hintText: _origUsername ?? 'Kullanıcı adı girin',
                  icon: Icons.alternate_email,
                  isDark: isDark,
                  primaryColor: primaryGreen,
                  validator: (v) {
                    if (v == null || v.isEmpty) return null;
                    final rx = RegExp(r'^[a-zA-Z0-9_.\-]{3,20}$');
                    if (!rx.hasMatch(v))
                      return '3-20 karakter, harf/rakam/_ . -';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                _buildStyledTextField(
                  context,
                  controller: _bioCtrl,
                  labelText: 'Biyografi',
                  hintText: 'Kendinden veya film zevkinden bahset...',
                  icon: Icons.edit_note,
                  maxLines: 3,
                  maxLength: 150,
                  isDark: isDark,
                  primaryColor: primaryGreen,
                ),
                const SizedBox(height: 16),

                _buildStyledTextField(
                  context,
                  controller: _ageCtrl,
                  labelText: 'Yaş',
                  hintText: 'Örn: 24',
                  icon: Icons.cake_outlined,
                  keyboardType: TextInputType.number,
                  isDark: isDark,
                  primaryColor: primaryGreen,
                  validator: (v) {
                    if (v == null || v.isEmpty) return null;
                    final n = int.tryParse(v);
                    if (n == null || n <= 15 || n > 120) return 'Geçersiz yaş';
                    return null;
                  },
                ),

                const SizedBox(height: 32),

                // --- LETTERBOXD ---
                _SectionTitle(
                  title: 'Letterboxd Bağlantısı',
                  color: sectionTitleColor,
                ),
                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildStyledTextField(
                        context,
                        controller: _letterboxdCtrl,
                        labelText: 'Letterboxd Kullanıcı Adı',
                        hintText: 'username',
                        icon: Icons.link,
                        isDark: isDark,
                        primaryColor: primaryGreen,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final ok = RegExp(
                            r'^[A-Za-z0-9_\-.]+$',
                          ).hasMatch(v.trim());
                          return ok ? null : 'Geçersiz karakter';
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: IconButton.filled(
                        onPressed: _saving ? null : _requestLbRefresh,
                        style: IconButton.styleFrom(
                          backgroundColor: primaryGreen,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(12),
                        ),
                        icon: const Icon(Icons.sync, color: Colors.white),
                        tooltip: 'Verileri Yenile',
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 4),
                  child: Text(
                    'İsteğe bağlı — girersen eşitleme yapılır',
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ),

                const SizedBox(height: 32),
                // --- BANNER RENGİ ---
                _SectionTitle(
                  title: 'Profil Kapak Rengi',
                  color: sectionTitleColor,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 50,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _bannerColorOptions.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final colorHex = _bannerColorOptions[index];
                      final color = Color(
                        int.parse(
                          'FF${colorHex.replaceAll('#', '')}',
                          radix: 16,
                        ),
                      );
                      final isSelected = _selectedBannerColor == colorHex;
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedBannerColor = colorHex),
                        child: Container(
                          width: 50,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: Colors.white, width: 3)
                                : null,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: color.withOpacity(0.5),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 32),
                // --- SEVDİĞİN TÜRLER ---
                _SectionTitle(
                  title: 'Sevdiğin Türler',
                  color: sectionTitleColor,
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: containerColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        onTap: () {
                          setState(() {
                            _isGenresExpanded = !_isGenresExpanded;
                          });
                        },
                        borderRadius: BorderRadius.vertical(
                          top: const Radius.circular(16),
                          bottom: Radius.circular(_isGenresExpanded ? 0 : 16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _isGenresExpanded
                                    ? 'Türleri Gizle'
                                    : 'Türleri Düzenle (${_selectedGenres.length} Seçili)',
                                style: TextStyle(
                                  color: textColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              Icon(
                                _isGenresExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_isGenresExpanded)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _genreOptions.map((g) {
                              final isSelected = _selectedGenres.contains(g);
                              return FilterChip(
                                label: Text(g),
                                labelStyle: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : (isDark
                                            ? Colors.grey[300]
                                            : Colors.black87),
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 13,
                                ),
                                selected: isSelected,
                                selectedColor: primaryGreen,
                                backgroundColor: isDark
                                    ? Colors.grey[800]
                                    : Colors.grey[100],
                                checkmarkColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  side: BorderSide(
                                    color: isSelected
                                        ? primaryGreen
                                        : Colors.transparent,
                                  ),
                                ),
                                onSelected: (v) {
                                  if (_saving) return;
                                  setState(() {
                                    if (v) {
                                      _selectedGenres.add(g);
                                    } else {
                                      _selectedGenres.remove(g);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // --- FAVORİ YÖNETMENLER (GÜNCELLENDİ) ---
                _SectionTitle(
                  title: 'Favori Yönetmenler',
                  color: sectionTitleColor,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._favDirectors.map((item) {
                      return _buildChip(
                        _getItemName(item),
                        () => _removeDirector(item),
                        primaryGreen,
                      );
                    }).toList(),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: const Text("Yönetmen Ekle"),
                      onPressed: () =>
                          _showTMDBPersonSearch("Yönetmen Ara", false),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // --- FAVORİ OYUNCULAR (GÜNCELLENDİ) ---
                _SectionTitle(
                  title: 'Favori Oyuncular',
                  color: sectionTitleColor,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._favActors.map((item) {
                      return _buildChip(
                        _getItemName(item),
                        () => _removeActor(item),
                        primaryGreen,
                      );
                    }).toList(),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: const Text("Oyuncu Ekle"),
                      onPressed: () =>
                          _showTMDBPersonSearch("Oyuncu Ara", true),
                    ),
                  ],
                ),

                const SizedBox(height: 40),

                // --- ALT KAYDET BUTONU ---
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGreen,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: primaryGreen.withOpacity(0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _saving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Değişiklikleri Kaydet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- HELPER WIDGETS ---
  Widget _buildStyledTextField(
    BuildContext context, {
    required TextEditingController controller,
    required String labelText,
    String? hintText,
    required IconData icon,
    required bool isDark,
    required Color primaryColor,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    final fillColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.grey[500] : Colors.grey[400];
    final iconColor = isDark ? Colors.grey[400] : Colors.grey[400];
    final labelColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Container(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        maxLength: maxLength,
        validator: validator,
        style: TextStyle(fontSize: 16, color: textColor),
        decoration: InputDecoration(
          labelText: labelText,
          hintText: hintText,
          prefixIcon: Icon(icon, color: iconColor),
          labelStyle: TextStyle(color: labelColor),
          hintStyle: TextStyle(color: hintColor),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: primaryColor, width: 1.5),
          ),
          filled: true,
          fillColor: fillColor,
          counterText: "",
        ),
      ),
    );
  }

  Widget _buildChip(String label, VoidCallback onDelete, Color primaryColor) {
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: primaryColor.withOpacity(0.8),
      deleteIcon: const Icon(Icons.close, size: 18, color: Colors.white),
      onDeleted: _saving ? null : onDelete,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide.none,
      ),
      elevation: 2,
      shadowColor: Colors.black26,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionTitle({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: color,
        letterSpacing: -0.5,
      ),
    );
  }
}

// --- YENİ TMDB ARAMA WIDGET'I (GÜNCELLENDİ) ---
class _TMDBPersonSearchSheet extends StatefulWidget {
  final String title;
  final bool isActorSearch; // <-- YENİ: Ne aradığımızı bilelim
  final Function(Map<String, dynamic>) onPersonSelected;

  const _TMDBPersonSearchSheet({
    required this.title,
    required this.isActorSearch, // <-- YENİ EKLENDİ
    required this.onPersonSelected,
  });

  @override
  State<_TMDBPersonSearchSheet> createState() => _TMDBPersonSearchSheetState();
}

class _TMDBPersonSearchSheetState extends State<_TMDBPersonSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  int _searchRequestId = 0;
  List<dynamic> _searchResults = [];
  bool _isLoading = false;

  Future<void> _searchTMDB(String query) async {
    final normalizedQuery = query.trim();
    if (!mounted) return;
    if (normalizedQuery.isEmpty) {
      _searchRequestId++;
      setState(() {
        _searchResults = [];
        _isLoading = false;
      });
      return;
    }

    final requestId = ++_searchRequestId;
    setState(() => _isLoading = true);

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('callTMDB')
          .call({
            'endpoint': '/3/search/person',
            'params': {'query': normalizedQuery, 'language': 'tr-TR'},
          });

      if (mounted && requestId == _searchRequestId) {
        setState(() {
          // Gelen tüm sonuçları al
          List<dynamic> allResults = result.data['results'] ?? [];

          // YENİ: Sadece aradığımız mesleğe göre filtrele
          _searchResults = allResults.where((person) {
            final dept = person['known_for_department'];
            if (widget.isActorSearch) {
              return dept == 'Acting'; // Oyuncu arıyorsak sadece oyuncular
            } else {
              return dept ==
                  'Directing'; // Yönetmen arıyorsak sadece yönetmenler
            }
          }).toList();

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && requestId == _searchRequestId) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Arama hatası: $e')));
      }
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      _searchTMDB(value);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted && _searchController.text == value) {
        _searchTMDB(value);
      }
    });
  }

  void _onSearchSubmitted(String value) {
    _searchDebounce?.cancel();
    _searchTMDB(value);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchRequestId++;
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final primaryGreen = const Color(0xFF2E7D32);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            autofocus: true,
            style: TextStyle(color: textColor),
            decoration: InputDecoration(
              hintText: widget.isActorSearch
                  ? 'Oyuncu adı yazın...'
                  : 'Yönetmen adı yazın...',
              hintStyle: TextStyle(
                color: isDark ? Colors.grey[500] : Colors.grey[400],
              ),
              prefixIcon: Icon(Icons.search, color: primaryGreen),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: primaryGreen, width: 2),
              ),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E1E1E) : Colors.grey[100],
            ),
            onChanged: _onSearchChanged,
            onSubmitted: _onSearchSubmitted,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: primaryGreen))
                : _searchResults.isEmpty
                ? Center(
                    child: Text(
                      'Sonuç bulunamadı.',
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final person = _searchResults[index];
                      final profilePath = person['profile_path'];
                      final knownFor = person['known_for_department'] ?? '';

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isDark
                              ? Colors.grey[800]
                              : Colors.grey[200],
                          backgroundImage: profilePath != null
                              ? CachedNetworkImageProvider(
                                  'https://image.tmdb.org/t/p/w200$profilePath',
                                )
                              : null,
                          child: profilePath == null
                              ? Icon(
                                  Icons.person,
                                  color: isDark
                                      ? Colors.grey[500]
                                      : Colors.grey[400],
                                )
                              : null,
                        ),
                        title: Text(
                          person['name'] ?? '',
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          knownFor == 'Acting'
                              ? 'Oyuncu'
                              : (knownFor == 'Directing'
                                    ? 'Yönetmen'
                                    : knownFor),
                          style: TextStyle(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        onTap: () {
                          widget.onPersonSelected({
                            'name': person['name'],
                            'id': person['id'],
                            'profile_path': profilePath,
                          });
                        },
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
