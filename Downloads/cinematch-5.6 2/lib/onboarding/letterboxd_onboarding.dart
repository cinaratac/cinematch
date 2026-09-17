import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttergirdi/auth/google_register_page.dart';
import 'package:fluttergirdi/auth/email_verification_page.dart';
import 'package:fluttergirdi/auth/login_page.dart';
import 'package:fluttergirdi/screens/initial_loading_screen.dart';
import 'package:fluttergirdi/screens/search_movie.dart';
import 'package:fluttergirdi/services/catalog_service.dart';
import 'package:fluttergirdi/services/letterboxd_service.dart';
import 'package:fluttergirdi/services/onboarding_draft_service.dart';
import 'package:fluttergirdi/services/registration_state.dart';
import 'package:cloud_functions/cloud_functions.dart'; // TMDB araması için
import 'package:cached_network_image/cached_network_image.dart'; // Resimler için
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class OnboardingLetterboxd extends StatefulWidget {
  const OnboardingLetterboxd({super.key});

  @override
  State<OnboardingLetterboxd> createState() => _OnboardingLetterboxdState();
}

class _OnboardingLetterboxdState extends State<OnboardingLetterboxd>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController(); // Letterboxd Username

  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _draftUid;
  Timer? _draftDebounce;
  Future<void> _draftWriteQueue = Future<void>.value();
  bool _restoringDraft = true;
  String? _profileImagePath;
  String? _uploadedPhotoPath;
  String? _uploadedPhotoUrl;
  String? _googleProfilePhotoUrl;
  Map<String, dynamic>? _favoriteMovie;

  final _ageController = TextEditingController();

  // Tema Renkleri
  final primaryGreen = const Color(0xFF2E7D32);
  final bgGradientStart = const Color(0xFFE8F5E9);
  final bgGradientEnd = Colors.white;

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
  final Set<String> _selectedGenres = {};

  // Eskiden List<String> idi, TMDB verisini tutabilmek için List<dynamic> yapıldı.
  final List<dynamic> _favDirectors = [];
  final List<dynamic> _favActors = [];

  static const int _totalSteps = 7;
  int _step = 0;
  int _maxStepReached = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_scheduleDraftSave);
    _ageController.addListener(_scheduleDraftSave);
    _checkAlreadySet();
  }

  Future<void> _checkAlreadySet() async {
    final authUser = FirebaseAuth.instance.currentUser;
    final uid = authUser?.uid;
    if (uid == null) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
      return;
    }

    _googleProfilePhotoUrl = _googleProviderPhotoUrl(authUser!);

    try {
      final db = FirebaseFirestore.instance;
      final snapshots = await Future.wait([
        db
            .collection('users')
            .doc(uid)
            .get(const GetOptions(source: Source.server)),
        db
            .collection('registration_drafts')
            .doc(uid)
            .get(const GetOptions(source: Source.server)),
      ]);
      if (!mounted) return;

      final stage = RegistrationState.resolve(
        userData: snapshots[0].data(),
        draftData: snapshots[1].data(),
      );
      final registrationDraft = snapshots[1].data();
      final draftProvider = (registrationDraft?['authProvider'] ?? '')
          .toString();
      final draftPhotoUrl = (registrationDraft?['photoURL'] ?? '')
          .toString()
          .trim();
      if (_googleProfilePhotoUrl == null &&
          draftProvider == 'google' &&
          _isValidHttpsUrl(draftPhotoUrl)) {
        _googleProfilePhotoUrl = draftPhotoUrl;
      }
      if (stage == RegistrationStage.complete) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const InitialLoadingScreen()),
          (_) => false,
        );
        return;
      }
      if (stage == RegistrationStage.emailVerification) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const EmailVerificationPage()),
          (_) => false,
        );
        return;
      }
      if (stage == RegistrationStage.profile) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => GoogleRegisterPage(user: user)),
            (_) => false,
          );
        }
        return;
      }

      _draftUid = uid;
      await _restoreLocalDraft(uid);
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _restoreLocalDraft(String uid) async {
    final draft = await OnboardingDraftService.load(uid);
    if (draft != null) {
      _controller.text = (draft['letterboxdUsername'] ?? '').toString();
      _ageController.text = (draft['age'] ?? '').toString();
      _selectedGenres
        ..clear()
        ..addAll((draft['genres'] as List? ?? const []).map((item) => '$item'));
      _favDirectors
        ..clear()
        ..addAll(
          (draft['directors'] as List? ?? const []).whereType<Map>().map(
            (item) => Map<String, dynamic>.from(item),
          ),
        );
      _favActors
        ..clear()
        ..addAll(
          (draft['actors'] as List? ?? const []).whereType<Map>().map(
            (item) => Map<String, dynamic>.from(item),
          ),
        );
      final savedProfileImagePath = (draft['profileImagePath'] ?? '')
          .toString()
          .trim();
      if (savedProfileImagePath.isNotEmpty &&
          await File(savedProfileImagePath).exists()) {
        _profileImagePath = savedProfileImagePath;
      }
      final uploadedPhotoPath = (draft['uploadedPhotoPath'] ?? '')
          .toString()
          .trim();
      final uploadedPhotoUrl = (draft['uploadedPhotoUrl'] ?? '')
          .toString()
          .trim();
      if (uploadedPhotoPath.isNotEmpty &&
          uploadedPhotoUrl.startsWith('https://')) {
        _uploadedPhotoPath = uploadedPhotoPath;
        _uploadedPhotoUrl = uploadedPhotoUrl;
      }
      final rawFavoriteMovie = draft['favoriteMovie'];
      if (rawFavoriteMovie is Map) {
        _favoriteMovie = Map<String, dynamic>.from(rawFavoriteMovie);
      }
      final savedStep = (draft['step'] as num?)?.toInt() ?? 0;
      _step = savedStep.clamp(0, _totalSteps - 1);
      _maxStepReached = _step;
    }
    _restoringDraft = false;
  }

  void _scheduleDraftSave() {
    if (_restoringDraft || _draftUid == null) return;
    _draftDebounce?.cancel();
    _draftDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_saveDraftNow()),
    );
  }

  Future<void> _saveDraftNow() {
    final uid = _draftUid;
    if (uid == null || _restoringDraft) return Future<void>.value();
    final data = <String, dynamic>{
      'letterboxdUsername': _controller.text.trim(),
      'age': _ageController.text.trim(),
      'genres': _selectedGenres.toList(),
      'directors': _favDirectors,
      'actors': _favActors,
      'profileImagePath': _profileImagePath,
      'uploadedPhotoPath': _uploadedPhotoPath,
      'uploadedPhotoUrl': _uploadedPhotoUrl,
      'favoriteMovie': _favoriteMovie,
      'step': _step,
    };
    _draftWriteQueue = _draftWriteQueue.then((_) async {
      if (_draftUid != uid) return;
      await OnboardingDraftService.save(uid, data);
    });
    return _draftWriteQueue;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveDraftNow());
    }
  }

  String? _validator(String? v) {
    final val = (v ?? '').trim();
    if (val.isEmpty) return null;
    final ok = RegExp(r'^[a-zA-Z0-9_\-\.]+$').hasMatch(val);
    if (!ok) return 'Geçersiz karakter var';
    if (val.length < 2) return 'En az 2 karakter';
    return null;
  }

  int? _parseAge(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null) return null;
    if (v < 13 || v > 120) return null;
    return v;
  }

  // --- İLERLEME ÇUBUĞU ---
  Widget _buildStepBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: List.generate(_totalSteps, (i) {
          final bool done = i < _step;
          final bool current = i == _step;
          final Color color = done
              ? primaryGreen
              : current
              ? const Color(0xFF81C784)
              : Colors.grey.withValues(alpha: 0.3);

          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (i <= _maxStepReached || i <= _step) {
                  setState(() => _step = i);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 8,
                margin: EdgeInsets.symmetric(
                  horizontal: i == _totalSteps - 1 ? 0 : 4,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: current
                      ? [
                          BoxShadow(
                            color: primaryGreen.withValues(alpha: 0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // --- ADIM İÇERİKLERİ ---
  Widget _buildStepContent(BuildContext context) {
    switch (_step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderTitle('Letterboxd Bağlantısı'),
            const SizedBox(height: 8),
            Text(
              'Letterboxd kullanıcı adını girersen, izlediğin ve beğendiğin filmleri otomatik çekip senin için harika eşleşmeler bulabiliriz.',
              style: TextStyle(color: Colors.grey[700], fontSize: 15),
            ),
            const SizedBox(height: 24),
            _buildStyledTextField(
              controller: _controller,
              hintText: 'Letterboxd Kullanıcı Adı (İsteğe bağlı)',
              icon: Icons.alternate_email,
              validator: _validator,
            ),
          ],
        );
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderTitle('Yaşın Kaç?'),
            const SizedBox(height: 8),
            Text(
              'Sana uygun yaş grubundaki kişilerle eşleşmen için gerekli.',
              style: TextStyle(color: Colors.grey[700], fontSize: 15),
            ),
            const SizedBox(height: 24),
            _buildStyledTextField(
              controller: _ageController,
              hintText: 'Yaş',
              icon: Icons.cake_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              validator: (v) {
                if (v == null || v.isEmpty) return 'Yaş zorunlu';
                final val = int.tryParse(v);
                if (val == null) return 'Geçersiz değer';
                if (val < 13) {
                  return 'Uygulamayı kullanmak için 13+ olmalısınız';
                }
                if (val > 120) return 'Geçersiz yaş';
                return null;
              },
            ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderTitle('Profil Fotoğrafın'),
            const SizedBox(height: 8),
            Text(
              'Seni diğer kullanıcılara gösterecek bir fotoğraf seç. Fotoğrafı seçtikten sonra kırpabilir ve ölçeklendirebilirsin.',
              style: TextStyle(color: Colors.grey[700], fontSize: 15),
            ),
            const SizedBox(height: 28),
            Center(child: _buildProfilePhotoPicker()),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _showPhotoSourceSheet,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(
                _hasRequiredPhoto ? 'Fotoğrafı Değiştir' : 'Fotoğraf Seç',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: primaryGreen,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Profil fotoğrafı zorunludur.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderTitle('Sevdiğin Türler'),
            const SizedBox(height: 8),
            Text(
              'Hangi tür filmleri izlemekten keyif alırsın? (Birden fazla seçebilirsin)',
              style: TextStyle(color: Colors.grey[700], fontSize: 15),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _genreOptions.map((g) {
                  final sel = _selectedGenres.contains(g);
                  return FilterChip(
                    label: Text(g),
                    labelStyle: TextStyle(
                      color: sel ? Colors.white : Colors.black87,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    ),
                    selected: sel,
                    selectedColor: primaryGreen,
                    backgroundColor: Colors.grey[100],
                    checkmarkColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: sel ? primaryGreen : Colors.transparent,
                      ),
                    ),
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _selectedGenres.add(g);
                        } else {
                          _selectedGenres.remove(g);
                        }
                      });
                      _scheduleDraftSave();
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        );
      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderTitle('Favori Filmin'),
            const SizedBox(height: 8),
            Text(
              'En az bir favori film seç. Seçtiğin film hem Favoriler hem de İzlenenler listene eklenecek.',
              style: TextStyle(color: Colors.grey[700], fontSize: 15),
            ),
            const SizedBox(height: 24),
            if (_favoriteMovie == null)
              OutlinedButton.icon(
                onPressed: _saving ? null : _selectFavoriteMovie,
                icon: Icon(Icons.movie_filter_outlined, color: primaryGreen),
                label: Text(
                  'Favori Film Ara ve Seç',
                  style: TextStyle(color: primaryGreen, fontSize: 16),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  side: BorderSide(color: primaryGreen, width: 2),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              )
            else
              _buildSelectedMovieCard(),
          ],
        );
      case 5:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderTitle('Favori Yönetmenler'),
            const SizedBox(height: 8),
            Text(
              'En az bir favori yönetmen ekle.',
              style: TextStyle(color: Colors.grey[700], fontSize: 15),
            ),
            const SizedBox(height: 24),
            // YENİ: Arama Butonu
            OutlinedButton.icon(
              onPressed: () => _showTMDBPersonSearch("Yönetmen Ara", false),
              icon: Icon(Icons.search, color: primaryGreen),
              label: Text(
                "Yönetmen Ara ve Ekle",
                style: TextStyle(color: primaryGreen, fontSize: 16),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: BorderSide(color: primaryGreen, width: 2),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildChipList(_favDirectors, (item) {
              setState(() => _favDirectors.remove(item));
              _scheduleDraftSave();
            }),
          ],
        );
      case 6:
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderTitle('Favori Oyuncular'),
            const SizedBox(height: 8),
            Text(
              'En az bir favori oyuncu ekle.',
              style: TextStyle(color: Colors.grey[700], fontSize: 15),
            ),
            const SizedBox(height: 24),
            // YENİ: Arama Butonu
            OutlinedButton.icon(
              onPressed: () => _showTMDBPersonSearch("Oyuncu Ara", true),
              icon: Icon(Icons.search, color: primaryGreen),
              label: Text(
                "Oyuncu Ara ve Ekle",
                style: TextStyle(color: primaryGreen, fontSize: 16),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: BorderSide(color: primaryGreen, width: 2),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildChipList(_favActors, (item) {
              setState(() => _favActors.remove(item));
              _scheduleDraftSave();
            }),
          ],
        );
    }
  }

  bool get _hasRequiredPhoto =>
      (_profileImagePath != null && _profileImagePath!.isNotEmpty) ||
      (_uploadedPhotoUrl != null && _uploadedPhotoUrl!.isNotEmpty) ||
      (_googleProfilePhotoUrl != null && _googleProfilePhotoUrl!.isNotEmpty);

  static String? _googleProviderPhotoUrl(User user) {
    for (final provider in user.providerData) {
      if (provider.providerId != 'google.com') continue;
      final photoUrl = provider.photoURL?.trim() ?? '';
      if (_isValidHttpsUrl(photoUrl)) return photoUrl;
    }
    return null;
  }

  static bool _isValidHttpsUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  ImageProvider<Object>? get _profileImageProvider {
    final localPath = _profileImagePath;
    if (localPath != null && localPath.isNotEmpty) {
      return FileImage(File(localPath));
    }
    final remoteUrl = _uploadedPhotoUrl;
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      return CachedNetworkImageProvider(remoteUrl);
    }
    final googleUrl = _googleProfilePhotoUrl;
    if (googleUrl != null && googleUrl.isNotEmpty) {
      return CachedNetworkImageProvider(googleUrl);
    }
    return null;
  }

  Widget _buildProfilePhotoPicker() {
    final imageProvider = _profileImageProvider;
    return GestureDetector(
      onTap: _saving ? null : _showPhotoSourceSheet,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 156,
            height: 156,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: primaryGreen, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
              image: imageProvider == null
                  ? null
                  : DecorationImage(image: imageProvider, fit: BoxFit.cover),
            ),
            child: imageProvider == null
                ? Icon(
                    Icons.person_add_alt_1_outlined,
                    size: 64,
                    color: primaryGreen.withValues(alpha: 0.75),
                  )
                : null,
          ),
          Positioned(
            right: 2,
            bottom: 2,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: primaryGreen,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: const Icon(Icons.edit, color: Colors.white, size: 21),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPhotoSourceSheet() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Galeriden Seç'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Fotoğraf Çek'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
    if (source != null) await _pickAndCropProfilePhoto(source);
  }

  Future<void> _pickAndCropProfilePhoto(ImageSource source) async {
    try {
      final selected = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 95,
      );
      if (selected == null) return;

      final cropped = await ImageCropper().cropImage(
        sourcePath: selected.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 88,
        maxWidth: 1024,
        maxHeight: 1024,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Profil Fotoğrafını Düzenle',
            toolbarColor: primaryGreen,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: primaryGreen,
            lockAspectRatio: true,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'Profil Fotoğrafını Düzenle',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            aspectRatioPickerButtonHidden: true,
          ),
        ],
      );
      if (cropped == null || !mounted) return;

      setState(() {
        _profileImagePath = cropped.path;
        _uploadedPhotoPath = null;
        _uploadedPhotoUrl = null;
      });
      _scheduleDraftSave();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Fotoğraf hazırlanamadı: $error')));
    }
  }

  Future<void> _selectFavoriteMovie() async {
    final selected = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => const SearchMoviePage(
          isSelectionMode: true,
          selectionHint: 'Favori filmini ara...',
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _favoriteMovie = selected);
    _scheduleDraftSave();
  }

  Widget _buildSelectedMovieCard() {
    final movie = _favoriteMovie!;
    final title = (movie['title'] ?? 'Film').toString();
    final posterUrl = (movie['poster'] ?? '').toString();
    final release = (movie['release_date'] ?? movie['releaseDate'] ?? '')
        .toString();
    final year = release.length >= 4 ? release.substring(0, 4) : '';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryGreen.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: posterUrl.isEmpty
                ? Container(
                    width: 76,
                    height: 114,
                    color: Colors.grey[200],
                    child: const Icon(Icons.movie_outlined),
                  )
                : CachedNetworkImage(
                    imageUrl: posterUrl,
                    width: 76,
                    height: 114,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      width: 76,
                      height: 114,
                      color: Colors.grey[200],
                    ),
                    errorWidget: (_, _, _) => Container(
                      width: 76,
                      height: 114,
                      color: Colors.grey[200],
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (year.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(year, style: TextStyle(color: Colors.grey[600])),
                ],
                const SizedBox(height: 14),
                TextButton.icon(
                  onPressed: _saving ? null : _selectFavoriteMovie,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Başka Film Seç'),
                  style: TextButton.styleFrom(foregroundColor: primaryGreen),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper Widget: Chip Listesi (Dynamic tip desteği eklendi)
  Widget _buildChipList(List<dynamic> items, Function(dynamic) onDelete) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((item) {
          final name = item is Map ? item['name'] : item.toString();
          return Chip(
            label: Text(name, style: const TextStyle(color: Colors.white)),
            backgroundColor: primaryGreen.withValues(alpha: 0.8),
            deleteIcon: const Icon(Icons.close, size: 18, color: Colors.white),
            onDeleted: () => onDelete(item),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide.none,
            ),
          );
        }).toList(),
      ),
    );
  }

  // Helper Widget: Başlık
  Widget _buildHeaderTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: primaryGreen,
        letterSpacing: -0.5,
      ),
    );
  }

  // Helper Widget: Stil Verilmiş Text Field
  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    void Function(String)? onSubmitted,
    TextInputAction textInputAction = TextInputAction.done,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        textInputAction: textInputAction,
        onFieldSubmitted: onSubmitted,
        validator: validator,
        style: const TextStyle(fontSize: 16, color: Colors.black),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.grey[400]),
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.grey[400]),
          contentPadding: const EdgeInsets.symmetric(vertical: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: primaryGreen, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  // --- TMDB Arama Menüsünü Açan Fonksiyon ---
  void _showTMDBPersonSearch(String title, bool isActor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: _TMDBPersonSearchSheet(
            title: title,
            isActorSearch: isActor,
            onPersonSelected: (personData) {
              if (!mounted) return;
              setState(() {
                if (isActor) {
                  if (!_favActors.any(
                    (item) =>
                        (item is Map ? item['id'] : 0) == personData['id'],
                  )) {
                    _favActors.add(personData);
                  }
                } else {
                  if (!_favDirectors.any(
                    (item) =>
                        (item is Map ? item['id'] : 0) == personData['id'],
                  )) {
                    _favDirectors.add(personData);
                  }
                }
              });
              _scheduleDraftSave();
              Navigator.pop(context); // Seçimden sonra pencereyi kapat
            },
          ),
        );
      },
    );
  }

  void _showRequirementError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _validateCurrentStep() {
    if (!(_formKey.currentState?.validate() ?? true)) return false;
    switch (_step) {
      case 1:
        if (_parseAge(_ageController.text) == null) {
          _showRequirementError('Lütfen geçerli bir yaş gir.');
          return false;
        }
        break;
      case 2:
        if (!_hasRequiredPhoto) {
          _showRequirementError('Devam etmek için bir profil fotoğrafı seç.');
          return false;
        }
        break;
      case 4:
        if (_favoriteMovie == null) {
          _showRequirementError('Devam etmek için en az bir favori film seç.');
          return false;
        }
        break;
      case 5:
        if (_favDirectors.isEmpty) {
          _showRequirementError(
            'Devam etmek için en az bir favori yönetmen seç.',
          );
          return false;
        }
        break;
      case 6:
        if (_favActors.isEmpty) {
          _showRequirementError(
            'Kaydı tamamlamak için en az bir favori oyuncu seç.',
          );
          return false;
        }
        break;
    }
    return true;
  }

  bool _validateAllRequiredFields() {
    final letterboxdError = _validator(_controller.text);
    if (letterboxdError != null) {
      setState(() => _step = 0);
      _showRequirementError(letterboxdError);
      return false;
    }
    if (_parseAge(_ageController.text) == null) {
      setState(() => _step = 1);
      _showRequirementError('Lütfen geçerli bir yaş gir.');
      return false;
    }
    if (!_hasRequiredPhoto) {
      setState(() => _step = 2);
      _showRequirementError('Bir profil fotoğrafı seçmen gerekiyor.');
      return false;
    }
    final movieId = int.tryParse('${_favoriteMovie?['id'] ?? ''}');
    if (_favoriteMovie == null || movieId == null || movieId <= 0) {
      setState(() => _step = 4);
      _showRequirementError('En az bir geçerli favori film seçmen gerekiyor.');
      return false;
    }
    if (_favDirectors.isEmpty) {
      setState(() => _step = 5);
      _showRequirementError('En az bir favori yönetmen seçmen gerekiyor.');
      return false;
    }
    if (_favActors.isEmpty) {
      setState(() => _step = 6);
      _showRequirementError('En az bir favori oyuncu seçmen gerekiyor.');
      return false;
    }
    return true;
  }

  Future<({String path, String url})> _uploadRequiredProfilePhoto(
    String uid,
  ) async {
    final existingPath = _uploadedPhotoPath;
    final existingUrl = _uploadedPhotoUrl;
    if (existingPath != null &&
        existingPath.isNotEmpty &&
        existingUrl != null &&
        existingUrl.isNotEmpty) {
      return (path: existingPath, url: existingUrl);
    }

    final storagePath = 'profile_images/$uid/avatar.jpg';
    final storageRef = FirebaseStorage.instance.ref(storagePath);
    final metadata = SettableMetadata(
      contentType: 'image/jpeg',
      customMetadata: {'ownerUid': uid, 'purpose': 'onboarding_profile'},
    );

    final localPath = _profileImagePath;
    final localFile = localPath == null || localPath.isEmpty
        ? null
        : File(localPath);
    if (localFile != null && await localFile.exists()) {
      await storageRef.putFile(localFile, metadata);
    } else {
      final googlePhotoUrl = _googleProfilePhotoUrl;
      if (googlePhotoUrl == null || googlePhotoUrl.isEmpty) {
        if (localFile != null) {
          throw StateError(
            'Seçilen fotoğraf artık cihazda yok. Lütfen yeniden seç.',
          );
        }
        throw StateError('Profil fotoğrafı bulunamadı. Lütfen yeniden seç.');
      }

      final response = await http
          .get(Uri.parse(googlePhotoUrl))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw StateError(
          'Google profil fotoğrafı alınamadı. Lütfen bir fotoğraf seç.',
        );
      }
      if (response.bodyBytes.length >= 5 * 1024 * 1024) {
        throw StateError(
          'Google profil fotoğrafı çok büyük. Lütfen başka bir fotoğraf seç.',
        );
      }
      await storageRef.putData(response.bodyBytes, metadata);
    }

    final downloadUrl = await storageRef.getDownloadURL();
    _uploadedPhotoPath = storagePath;
    _uploadedPhotoUrl = downloadUrl;
    await _saveDraftNow();
    return (path: storagePath, url: downloadUrl);
  }

  Future<String> _resolveFavoriteMovieKey() async {
    final movie = _favoriteMovie!;
    final tmdbId = int.tryParse('${movie['id'] ?? ''}');
    if (tmdbId == null || tmdbId <= 0) {
      throw StateError('Seçilen film doğrulanamadı. Lütfen yeniden seç.');
    }
    final releaseDate = (movie['release_date'] ?? movie['releaseDate'] ?? '')
        .toString();
    final year = releaseDate.length >= 4
        ? int.tryParse(releaseDate.substring(0, 4))
        : null;
    final result = await CatalogService().resolveAndUpsert(
      tmdbId: tmdbId,
      title: (movie['title'] ?? '').toString(),
      year: year,
    );
    final key = (result?['docId'] ?? '').toString();
    if (key.isEmpty) {
      throw StateError('Film güvenli kataloğa kaydedilemedi. Tekrar dene.');
    }
    return key;
  }

  Future<void> _completeOnboardingWithFreshAuth(
    User user,
    Map<String, dynamic> payload,
  ) async {
    final callable = FirebaseFunctions.instance.httpsCallable(
      'completeOnboarding',
    );

    // Uzun onboarding akışında veya Apple ile ilk girişten hemen sonra native
    // Functions SDK'sı eski bir token kullanabiliyor. Çağrıdan önce yenile ve
    // olası bir yarış durumunda yalnızca bir kez daha dene. Sunucu işlemi
    // idempotent olduğu için bu retry güvenlidir.
    await user.getIdToken(true);
    try {
      await callable.call(payload);
    } on FirebaseFunctionsException catch (error) {
      if (error.code != 'unauthenticated') rethrow;
      await user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser;
      if (refreshedUser == null || refreshedUser.uid != user.uid) rethrow;
      await refreshedUser.getIdToken(true);
      await callable.call(payload);
    }
  }

  Future<void> _saveAndBuild() async {
    if (!_validateAllRequiredFields()) return;
    final ageVal = _parseAge(_ageController.text);
    if (ageVal == null) return;

    setState(() => _saving = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: primaryGreen),
                const SizedBox(height: 20),
                Text(
                  "Profilin oluşturuluyor...",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: primaryGreen,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Fotoğrafın ve film tercihlerin güvenle kaydediliyor. Letterboxd hesabı bağladıysan verilerin de eşitlenecek.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final lbUsernameRaw = _controller.text.trim();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw 'Oturum bulunamadı';
      final uid = user.uid;
      final profilePhoto = await _uploadRequiredProfilePhoto(uid);
      final favoriteMovieKey = await _resolveFavoriteMovieKey();

      await _completeOnboardingWithFreshAuth(user, {
        'letterboxdUsername': lbUsernameRaw,
        'age': ageVal,
        'favGenres': _selectedGenres.toList(),
        'favDirectors': _favDirectors,
        'favActors': _favActors,
        'profilePhotoPath': profilePhoto.path,
        'photoURL': profilePhoto.url,
        'favoriteMovieKey': favoriteMovieKey,
      });

      try {
        await user.updatePhotoURL(profilePhoto.url);
      } catch (error) {
        debugPrint('Firebase Auth profil fotoğrafı güncellenemedi: $error');
      }

      // Letterboxd, veri merkezi isteklerine challenge sayfası döndürebildiği
      // için aktarım kullanıcının cihaz bağlantısından tamamlanır. Bu await,
      // profil açılmadan önce Firestore yazımının gerçekten bitmesini sağlar.
      if (lbUsernameRaw.isNotEmpty) {
        await LetterboxdService.requestFullSync(
          uid: uid,
          lbUsername: lbUsernameRaw,
          source: 'onboarding',
        );
      }

      _draftUid = null;
      _draftDebounce?.cancel();
      await _draftWriteQueue;
      await OnboardingDraftService.clear(uid);

      if (!mounted) return;
      Navigator.of(context).pop();

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const InitialLoadingScreen()),
        (_) => false,
      );
    } catch (e, stackTrace) {
      debugPrint('Onboarding tamamlanamadı: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      Navigator.of(context).pop();

      String msg = 'Profil oluşturulamadı. Lütfen tekrar dene.';
      if (e is FirebaseFunctionsException && e.code == 'already-exists') {
        msg =
            'Bu kullanıcı adı başka biri tarafından alınmış. Lütfen geri dönüp farklı bir kullanıcı adı seç.';
      } else if (e is FirebaseFunctionsException &&
          (e.code == 'failed-precondition' || e.code == 'invalid-argument')) {
        msg = e.message ?? msg;
      } else if (e is FirebaseFunctionsException &&
          e.code == 'unauthenticated') {
        msg = FirebaseAuth.instance.currentUser == null
            ? 'Oturumun sona ermiş. Lütfen yeniden giriş yap.'
            : 'Oturumun doğrulanamadı. Kayıt bilgilerin korundu; internet bağlantını kontrol edip tekrar dene.';
      } else if (e is FirebaseFunctionsException && e.code == 'internal') {
        msg = 'Film bilgileri kaydedilirken sunucu hatası oluştu. Tekrar dene.';
      } else if (e is LetterboxdSyncException) {
        msg =
            'Profilin oluşturuldu ancak Letterboxd aktarımı tamamlanamadı: ${e.message} Tekrar deneyebilirsin.';
      } else if (e.toString().contains('Letterboxd kullanıcısı bulunamadı')) {
        msg =
            'Girdiğin Letterboxd kullanıcı adı bulunamadı. Lütfen kontrol et.';
      } else if (e is FirebaseFunctionsException &&
          (e.code == 'unavailable' || e.code == 'deadline-exceeded')) {
        msg = 'Sunucuya erişilemiyor. İnternet bağlantını kontrol et.';
      } else if (e is StateError) {
        msg = e.message.toString();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (e is FirebaseFunctionsException && e.code == 'already-exists') {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => GoogleRegisterPage(user: user)),
            (_) => false,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelRegistration() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kaydı iptal et?'),
        content: const Text(
          'Hesap taslağın ve girdiğin onboarding bilgileri kalıcı olarak silinecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Devam Et'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Kaydı Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Oturum bulunamadı.');
      await FirebaseFunctions.instance
          .httpsCallable('cancelRegistration')
          .call();
      _draftUid = null;
      _draftDebounce?.cancel();
      await _draftWriteQueue;
      await OnboardingDraftService.clear(uid);
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kayıt iptal edilemedi: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftDebounce?.cancel();
    unawaited(_saveDraftNow());
    _controller.dispose();
    _ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

    if (_loadError != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Kayıt durumu doğrulanamadı. İnternet bağlantını kontrol et.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _loadError = null;
                        _loading = true;
                      });
                      _checkAlreadySet();
                    },
                    child: const Text('Tekrar Dene'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgGradientStart, bgGradientEnd],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bottomInset = MediaQuery.of(context).viewInsets.bottom;
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 50,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _saving ? null : _cancelRegistration,
                            child: const Text('Kaydı iptal et'),
                          ),
                        ),
                        // Üst İlerleme Çubuğu
                        _buildStepBar(context),

                        const SizedBox(height: 32),

                        // İçerik (Animasyonlu geçiş)
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder:
                              (Widget child, Animation<double> animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.05, 0),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                          child: KeyedSubtree(
                            key: ValueKey<int>(_step),
                            child: _buildStepContent(context),
                          ),
                        ),

                        const SizedBox(height: 40),

                        // Alt Butonlar
                        Row(
                          children: [
                            // GERİ BUTONU
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: OutlinedButton(
                                  onPressed: (_step == 0 || _saving)
                                      ? null
                                      : () {
                                          setState(() => _step = _step - 1);
                                          _scheduleDraftSave();
                                        },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: primaryGreen,
                                    side: BorderSide(
                                      color: primaryGreen.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Geri',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            // İLERİ / KAYDET BUTONU
                            Expanded(
                              flex: 2,
                              child: SizedBox(
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _saving
                                      ? null
                                      : () async {
                                          if (!_validateCurrentStep()) return;

                                          if (_step < _totalSteps - 1) {
                                            setState(() {
                                              _step += 1;
                                              if (_maxStepReached < _step) {
                                                _maxStepReached = _step;
                                              }
                                            });
                                            _scheduleDraftSave();
                                          } else {
                                            await _saveAndBuild();
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryGreen,
                                    foregroundColor: Colors.white,
                                    elevation: 4,
                                    shadowColor: primaryGreen.withValues(
                                      alpha: 0.4,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _saving
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              _step == _totalSteps - 1
                                                  ? 'Tamamla'
                                                  : 'Devam Et',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Icon(
                                              _step == _totalSteps - 1
                                                  ? Icons.check_circle
                                                  : Icons.arrow_forward,
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// --- YENİ TMDB ARAMA WIDGET'I ---
class _TMDBPersonSearchSheet extends StatefulWidget {
  final String title;
  final bool isActorSearch;
  final Function(Map<String, dynamic>) onPersonSelected;

  const _TMDBPersonSearchSheet({
    required this.title,
    required this.isActorSearch,
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
          List<dynamic> allResults = result.data['results'] ?? [];

          _searchResults = allResults.where((person) {
            final dept = person['known_for_department'];
            if (widget.isActorSearch) {
              return dept == 'Acting';
            } else {
              return dept == 'Directing';
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
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            autofocus: true,
            style: const TextStyle(color: Colors.black87),
            decoration: InputDecoration(
              hintText: widget.isActorSearch
                  ? 'Oyuncu adı yazın...'
                  : 'Yönetmen adı yazın...',
              hintStyle: Colors.grey[400] != null
                  ? TextStyle(color: Colors.grey[400])
                  : null,
              prefixIcon: Icon(Icons.search, color: primaryGreen),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: primaryGreen, width: 2),
              ),
              filled: true,
              fillColor: Colors.grey[100],
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
                      style: TextStyle(color: Colors.grey[600]),
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
                          backgroundColor: Colors.grey[200],
                          backgroundImage: profilePath != null
                              ? CachedNetworkImageProvider(
                                  'https://image.tmdb.org/t/p/w200$profilePath',
                                )
                              : null,
                          child: profilePath == null
                              ? Icon(Icons.person, color: Colors.grey[400])
                              : null,
                        ),
                        title: Text(
                          person['name'] ?? '',
                          style: const TextStyle(
                            color: Colors.black87,
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
                            color: Colors.grey[600],
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
