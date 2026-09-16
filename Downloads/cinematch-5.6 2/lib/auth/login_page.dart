import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/auth/register_page.dart';
import 'package:fluttergirdi/auth/password_reset_page.dart';
import 'package:fluttergirdi/widgets/green_characters.dart';
import 'package:fluttergirdi/widgets/offline_banner.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:fluttergirdi/widgets/background_3d_posters.dart';
import 'package:fluttergirdi/widgets/viewport_fitted_content.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:fluttergirdi/auth/auth_gate.dart'; // KESİN YÖNLENDİRME İÇİN EKLENDİ
import 'package:fluttergirdi/services/global_data_service.dart';
import 'package:fluttergirdi/services/notification_service.dart';
import 'package:fluttergirdi/services/password_reset_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Controller'lar
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Durum değişkenleri
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;
  bool _isPasswordResetLoading = false;
  bool _isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    NotificationService.I.setNavigationReady(false);
    GlobalDataService.instance.stopPreloading();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Standart E-posta Giriş Fonksiyonu
  Future<void> _login() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen tüm alanları doldurunuz.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // KESİN ÇÖZÜM: Tüm ekran yığınını temizle ve sistemi zorla AuthGate'e yönlendir
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthGate()),
          (route) => false,
        );
      }
      return; // Başarılıysa dur, setState çalıştırma ki ekran kilitlenmesin
    } on FirebaseAuthException catch (e) {
      if (mounted)
        setState(() => _isLoading = false); // Sadece hatada loading'i kapat

      String message = 'Giriş başarısız.';
      if (e.code == 'user-not-found') {
        message = 'Bu e-posta ile kayıtlı kullanıcı bulunamadı.';
      } else if (e.code == 'wrong-password') {
        message = 'Şifre hatalı.';
      } else if (e.code == 'invalid-email') {
        message = 'Geçersiz e-posta formatı.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  // Şifre Sıfırlama Fonksiyonu
  Future<void> _resetPassword() async {
    if (_emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Şifre sıfırlamak için lütfen e-posta adresinizi girin.',
          ),
        ),
      );
      return;
    }
    setState(() => _isPasswordResetLoading = true);
    try {
      final email = _emailController.text.trim();
      final retryAfter = await PasswordResetService.instance.request(email);
      if (mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PasswordResetPage(
              email: email,
              initialResendSeconds: retryAfter,
            ),
          ),
        );
      }
    } on PasswordResetException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPasswordResetLoading = false);
    }
  }

  // Google ile Giriş
  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);

    try {
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        if (mounted) setState(() => _isGoogleLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      // KESİN ÇÖZÜM: Yığınları temizle ve AuthGate'e yönlendir
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthGate()),
          (route) => false,
        );
      }
      return;
    } catch (e) {
      if (mounted) setState(() => _isGoogleLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  // Apple ile Giriş
  Future<void> _signInWithApple() async {
    setState(() => _isAppleLoading = true);

    try {
      final AuthorizationCredentialAppleID appleCredential =
          await SignInWithApple.getAppleIDCredential(
            scopes: [
              AppleIDAuthorizationScopes.email,
              AppleIDAuthorizationScopes.fullName,
            ],
          );

      final OAuthProvider oAuthProvider = OAuthProvider('apple.com');
      final OAuthCredential credential = oAuthProvider.credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      // KESİN ÇÖZÜM: Yığınları temizle ve AuthGate'e yönlendir
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthGate()),
          (route) => false,
        );
      }
      return;
    } catch (e) {
      if (mounted) setState(() => _isAppleLoading = false);
      if (mounted) {
        if (e is SignInWithAppleAuthorizationException &&
            e.code == AuthorizationErrorCode.canceled) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Yeşil Tema Renkleri
    final primaryGreen = const Color(0xFF2E7D32);
    final bgGradientStart = const Color(0xFFE8F5E9).withOpacity(0.75);
    final bgGradientEnd = Colors.white.withOpacity(0.85);

    // Herhangi bir yüklenme durumunu kontrol etme
    final isAnyLoading =
        _isLoading ||
        _isGoogleLoading ||
        _isAppleLoading ||
        _isPasswordResetLoading;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const SafeArea(bottom: false, child: OfflineBanner()),
          Stack(
            children: [
              // 1. KATMAN: Hareketli 3D Posterler
              Positioned.fill(child: const Background3DPosters()),

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

              // 3. KATMAN: Mevcut Login Formu
              SafeArea(
                child: Center(
                  child: ViewportFittedContent(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // --- YEŞİL KARAKTER ALANI ---
                        Hero(
                          tag: 'app_logo',
                          child: Container(
                            height: 140,
                            alignment: Alignment.center,
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
                            child: const GreenEyesCharacter(size: 130),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // --- HOŞ GELDİNİZ METNİ ---
                        Text(
                          'Tekrar Hoş Geldiniz!',
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
                          'Devam etmek için giriş yapın',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 48),

                        // --- E-POSTA ALANI ---
                        _buildTextField(
                          controller: _emailController,
                          hintText: 'E-posta Adresi',
                          icon: Icons.email_outlined,
                          primaryColor: primaryGreen,
                        ),
                        const SizedBox(height: 16),

                        // --- ŞİFRE ALANI ---
                        _buildTextField(
                          controller: _passwordController,
                          hintText: 'Şifre',
                          icon: Icons.lock_outline,
                          isPassword: true,
                          isVisible: _isPasswordVisible,
                          onVisibilityToggle: () => setState(
                            () => _isPasswordVisible = !_isPasswordVisible,
                          ),
                          primaryColor: primaryGreen,
                        ),

                        // --- ŞİFREMİ UNUTTUM ---
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: isAnyLoading ? null : _resetPassword,
                            style: TextButton.styleFrom(
                              foregroundColor: primaryGreen,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 0,
                                vertical: 8,
                              ),
                            ),
                            child: Text(
                              _isPasswordResetLoading
                                  ? 'Gönderiliyor...'
                                  : 'Şifremi Unuttum?',
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // --- GİRİŞ YAP BUTONU ---
                        FractionallySizedBox(
                          widthFactor: 0.9,
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: isAnyLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryGreen,
                                foregroundColor: Colors.white,
                                elevation: 3,
                                shadowColor: primaryGreen.withOpacity(0.3),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Giriş Yap',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // --- GOOGLE İLE BAĞLAN BUTONU ---
                        FractionallySizedBox(
                          widthFactor: 0.9,
                          child: SizedBox(
                            height: 50,
                            child: OutlinedButton.icon(
                              onPressed: isAnyLoading
                                  ? null
                                  : _signInWithGoogle,
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.grey.shade400),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                backgroundColor: Colors.white,
                              ),
                              icon: _isGoogleLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Image.asset(
                                      'assets/images/google_logo.png',
                                      height: 21,
                                      width: 21,
                                      errorBuilder: (c, o, s) =>
                                          const Icon(Icons.login, size: 21),
                                    ),
                              label: Text(
                                _isGoogleLoading
                                    ? 'Bağlanılıyor...'
                                    : 'Google ile Bağlan',
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // --- APPLE İLE GİRİŞ YAP BUTONU ---
                        FractionallySizedBox(
                          widthFactor: 0.9,
                          child: SizedBox(
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: isAnyLoading ? null : _signInWithApple,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              icon: _isAppleLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.apple, size: 24),
                              label: Text(
                                _isAppleLoading
                                    ? 'Bağlanılıyor...'
                                    : 'Apple ile Giriş Yap',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // --- KAYIT OL ALANI ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Hesabın yok mu?',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const RegisterPage(),
                                  ),
                                );
                              },
                              child: Text(
                                'Kayıt Ol',
                                style: TextStyle(
                                  color: primaryGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
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
    );
  }

  // Özel Text Field Widget'ı
  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    required Color primaryColor,
    bool isPassword = false,
    bool isVisible = false,
    VoidCallback? onVisibilityToggle,
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
      child: TextField(
        controller: controller,
        obscureText: isPassword && !isVisible,
        keyboardType: isPassword
            ? TextInputType.visiblePassword
            : TextInputType.emailAddress,
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
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }
}
