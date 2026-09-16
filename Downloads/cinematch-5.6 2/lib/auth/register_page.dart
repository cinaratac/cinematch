import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_cached_pdfview/flutter_cached_pdfview.dart';
import 'package:fluttergirdi/auth/email_verification_page.dart';
import 'package:fluttergirdi/services/text_filter_service.dart';
// Yeni arka plan widget'ını import ediyoruz (Paket adınız fluttergirdi varsayılmıştır)
import 'package:fluttergirdi/widgets/background_3d_posters.dart';
import 'package:fluttergirdi/widgets/viewport_fitted_content.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _form = GlobalKey<FormState>();

  // Controller'lar
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  // Şifre gizlilik durumları
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _loading = false;

  // İzin değişkenleri
  bool _agreedToTerms = false;
  bool _allowMail = false;

  // Karakter göz takibi için offset
  double _eyeOffsetX = 0;
  double _eyeOffsetY = 0;

  // --- KAYIT FONKSİYONU ---
  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;

    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Kayıt olmak için Kullanıcı Sözleşmesini okuyup onaylamanız gerekmektedir.',
          ),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    User? createdUser;
    try {
      final email = _email.text.trim();
      final pass = _password.text.trim();
      final uname = _username.text.trim();

      // Küfür filtresi kontrolü
      if (TextFilterService.hasProfanity(uname)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bu kullanıcı adı uygunsuz ifadeler içerdiği için kullanılamaz.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      final existingUser = await FirebaseFirestore.instance
          .collection('users')
          .where('displayName_lc', isEqualTo: uname.toLowerCase())
          .get();

      if (existingUser.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Bu kullanıcı adı zaten alınmış. Lütfen başka bir tane seçin.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _loading = false);
        return;
      }

      // 1) Firebase Auth ile kullanıcı oluşturma
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pass);
      createdUser = credential.user;

      // 2) Kullanıcı adını güncelleme
      try {
        await createdUser?.updateDisplayName(uname);
      } catch (_) {}

      final uid = createdUser?.uid;
      if (uid == null) throw StateError('Kullanıcı hesabı oluşturulamadı.');

      // Profil herkese açık users koleksiyonuna ancak onboarding tamamlanınca
      // yazılır. Bu taslak yalnızca hesap sahibince okunabilir.
      await FirebaseFirestore.instance
          .collection('registration_drafts')
          .doc(uid)
          .set({
            'displayName': uname,
            'displayName_lc': uname.toLowerCase(),
            'email': email,
            'termsAccepted': true,
            'marketingConsent': _allowMail,
            'termsAcceptedAt': FieldValue.serverTimestamp(),
            'authProvider': 'email',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      // E-posta/şifre kaydında onboarding'den önce 6 haneli kod doğrulanır.
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const EmailVerificationPage()),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      String msg;
      switch (e.code) {
        case 'email-already-in-use':
          msg = 'Bu e-posta ile zaten bir hesap var';
          break;
        case 'invalid-email':
          msg = 'Geçersiz e-posta adresi';
          break;
        case 'weak-password':
          msg = 'Şifre çok zayıf (en az 6 karakter)';
          break;
        default:
          msg = 'Hata: ${e.message ?? e.code}';
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      // Auth oluşturulup taslak kaydedilemediyse yarım/orphan hesap bırakma.
      try {
        await createdUser?.delete();
      } catch (_) {
        await FirebaseAuth.instance.signOut();
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Kayıt başlatılamadı: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- SÖZLEŞME MODAL ---
  void _showTermsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.9,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Kullanıcı Sözleşmesi",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child:
                    const PDF(
                      enableSwipe: true,
                      swipeHorizontal: false,
                      autoSpacing: false,
                      pageFling: false,
                    ).fromAsset(
                      'assets/docs/sozlesme.pdf',
                      errorWidget: (dynamic error) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 40,
                                color: Colors.red,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "Sözleşme görüntülenemedi.\nHata: $error",
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        _agreedToTerms = true;
                      });
                      Navigator.pop(context);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                    ),
                    child: const Text("Okudum ve Onaylıyorum"),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Tema Renkleri
    final primaryGreen = const Color(0xFF2E7D32); // Koyu Yeşil

    // Arka plan gradyanı (yarı saydam yaparak posterlerin görünmesini sağlıyoruz)
    // 0.90 ve 0.95 opacity, yazıların okunabilirliği ile arka plan görünürlüğü arasında iyi bir denge kurar.
    final bgGradientStart = const Color(0xFFE8F5E9).withOpacity(0.75);
    final bgGradientEnd = Colors.white.withOpacity(0.85);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // 1. KATMAN: Netflix Tarzı Akan Poster Duvarı (En Arkada)
          const Positioned.fill(child: Background3DPosters()),

          // 2. KATMAN: Yarı Saydam Gradyan Perde
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [bgGradientStart, bgGradientEnd],
                ),
              ),
            ),
          ),

          // 3. KATMAN: Form İçeriği (En Önde)
          SafeArea(
            child: GestureDetector(
              onTap: () {
                FocusScope.of(context).unfocus();
                setState(() {
                  _eyeOffsetX = 0;
                  _eyeOffsetY = 0;
                });
              },
              behavior: HitTestBehavior.translucent,
              child: Center(
                child: ViewportFittedContent(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Form(
                    key: _form,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Geri Butonu (Sol Üst)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            icon: Icon(Icons.arrow_back, color: primaryGreen),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),

                        // --- YEŞİL KARAKTER (ForestFace) ---
                        Center(
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: primaryGreen.withOpacity(0.15),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: _ForestFace(
                              offsetX: _eyeOffsetX,
                              offsetY: _eyeOffsetY,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // --- BAŞLIKLAR ---
                        Text(
                          'Hesap Oluştur',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: primaryGreen,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Profilini filmlerle doldur, kişisel listelerini oluştur, kulüplere katıl ve insanlarla tanış.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // --- KULLANICI ADI ---
                        _buildStyledTextFormField(
                          controller: _username,
                          hintText: 'Kullanıcı Adı',
                          icon: Icons.alternate_email,
                          primaryColor: primaryGreen,
                          onTap: () => setState(() {
                            _eyeOffsetX = -6;
                            _eyeOffsetY = 4;
                          }),
                          validator: (v) {
                            final value = (v ?? '').trim();
                            if (value.isEmpty) return 'Kullanıcı adı zorunlu';
                            final re = RegExp(r'^[a-zA-Z0-9._-]{3,20}$');
                            if (!re.hasMatch(value)) {
                              return 'Geçersiz karakter veya uzunluk';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // --- E-POSTA ---
                        _buildStyledTextFormField(
                          controller: _email,
                          hintText: 'E-posta Adresi',
                          icon: Icons.email_outlined,
                          primaryColor: primaryGreen,
                          keyboardType: TextInputType.emailAddress,
                          onTap: () => setState(() {
                            _eyeOffsetX = -8;
                            _eyeOffsetY = 6;
                          }),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Zorunlu alan';
                            if (!v.contains('@'))
                              return 'Geçerli bir e-posta gir';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // --- ŞİFRE ---
                        _buildStyledTextFormField(
                          controller: _password,
                          hintText: 'Şifre',
                          icon: Icons.lock_outline,
                          primaryColor: primaryGreen,
                          isPassword: true,
                          isVisible: !_obscure1,
                          onVisibilityToggle: () =>
                              setState(() => _obscure1 = !_obscure1),
                          onTap: () => setState(() {
                            _eyeOffsetX = 0;
                            _eyeOffsetY = 10;
                          }),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Zorunlu alan';
                            if (v.length < 6) return 'En az 6 karakter olmalı';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // --- ŞİFRE TEKRAR ---
                        _buildStyledTextFormField(
                          controller: _confirm,
                          hintText: 'Şifre (Tekrar)',
                          icon: Icons.lock_reset_outlined,
                          primaryColor: primaryGreen,
                          isPassword: true,
                          isVisible: !_obscure2,
                          onVisibilityToggle: () =>
                              setState(() => _obscure2 = !_obscure2),
                          onTap: () => setState(() {
                            _eyeOffsetX = 0;
                            _eyeOffsetY = 10;
                          }),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Zorunlu alan';
                            if (v != _password.text)
                              return 'Şifreler uyuşmuyor';
                            return null;
                          },
                        ),

                        const SizedBox(height: 24),

                        // --- 1. KULLANICI SÖZLEŞMESİ ---
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 24,
                              width: 24,
                              child: Checkbox(
                                value: _agreedToTerms,
                                activeColor: primaryGreen,
                                onChanged: (v) =>
                                    setState(() => _agreedToTerms = v ?? false),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  text: 'Kaydol butonuna basarak ',
                                  style: const TextStyle(
                                    color: Colors.black87,
                                    fontSize: 13,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: 'Kullanıcı Sözleşmesini',
                                      style: TextStyle(
                                        color: primaryGreen,
                                        fontWeight: FontWeight.bold,
                                        decoration: TextDecoration.underline,
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = _showTermsDialog,
                                    ),
                                    const TextSpan(
                                      text:
                                          ' okuduğumu ve kabul ettiğimi onaylıyorum.',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // --- 2. E-POSTA İZNİ ---
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 24,
                              width: 24,
                              child: Checkbox(
                                value: _allowMail,
                                activeColor: primaryGreen,
                                onChanged: (v) =>
                                    setState(() => _allowMail = v ?? false),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _allowMail = !_allowMail),
                                child: Text(
                                  'Cinematch hakkındaki yeniliklerden e-posta yoluyla haberdar olmak istiyorum.',
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        // --- KAYDOL BUTONU ---
                        SizedBox(
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryGreen,
                              foregroundColor: Colors.white,
                              elevation: 4,
                              shadowColor: primaryGreen.withOpacity(0.4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Kaydol',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // --- ZATEN HESABIN VAR MI? ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Zaten hesabın var mı?',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                'Giriş Yap',
                                style: TextStyle(
                                  color: primaryGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- STİL VERİLMİŞ TEXT FIELD WIDGET ---
  Widget _buildStyledTextFormField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required Color primaryColor,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
    bool isVisible = false,
    VoidCallback? onVisibilityToggle,
    VoidCallback? onTap,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword && !isVisible,
        keyboardType: keyboardType,
        onTap: onTap,
        validator: validator,
        style: const TextStyle(fontSize: 16, color: Colors.black),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.grey[400]),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    isVisible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.grey[400],
                  ),
                  onPressed: onVisibilityToggle,
                )
              : null,
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.grey[400]),
          contentPadding: const EdgeInsets.symmetric(vertical: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: primaryColor, width: 1.5),
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
}

// --- KARAKTER (ForestFace) ---
class _ForestFace extends StatelessWidget {
  final double offsetX;
  final double offsetY;
  const _ForestFace({this.offsetX = 0, this.offsetY = 0});

  @override
  Widget build(BuildContext context) {
    const base = Color(0xFF1B5E20); // forest green
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ring(160, base.withOpacity(0.90)),
          _ring(130, base.withOpacity(0.75)),
          _ring(100, base.withOpacity(0.55)),
          _ring(72, base.withOpacity(0.35)),
          _ring(48, base.withOpacity(0.20)),

          Positioned(left: 46, top: 62, child: _eye(offsetX, offsetY)),
          Positioned(right: 46, top: 62, child: _eye(offsetX, offsetY)),
        ],
      ),
    );
  }

  static Widget _ring(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  static Widget _eye(double offsetX, double offsetY) {
    return Container(
      width: 30,
      height: 30,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment(offsetX / 10, offsetY / 10),
        child: Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: Colors.black87,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
