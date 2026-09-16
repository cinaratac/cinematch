import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_cached_pdfview/flutter_cached_pdfview.dart';
import 'package:fluttergirdi/onboarding/letterboxd_onboarding.dart';
import 'package:fluttergirdi/auth/login_page.dart';
import 'package:fluttergirdi/auth/email_verification_page.dart';
import '../services/text_filter_service.dart';

class GoogleRegisterPage extends StatefulWidget {
  final User user; // Firebase Auth'tan gelen kullanıcı nesnesi

  const GoogleRegisterPage({super.key, required this.user});

  @override
  State<GoogleRegisterPage> createState() => _GoogleRegisterPageState();
}

class _GoogleRegisterPageState extends State<GoogleRegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();

  bool _isLoading = false;
  bool _agreedToTerms = false;
  bool _allowMail = false;

  // --- YENİ: Sağlayıcıyı (Google, Apple veya E-posta) Dinamik Tespit Etme ---
  String get _providerName {
    if (widget.user.providerData.any((p) => p.providerId == 'apple.com'))
      return 'Apple';
    if (widget.user.providerData.any((p) => p.providerId == 'google.com'))
      return 'Google';
    return 'E-posta'; // İnterneti kopup kaydı yarım kalanlar için
  }

  String get _providerId {
    if (widget.user.providerData.any((p) => p.providerId == 'apple.com'))
      return 'apple';
    if (widget.user.providerData.any((p) => p.providerId == 'google.com'))
      return 'google';
    return 'email';
  }

  @override
  Widget build(BuildContext context) {
    final primaryGreen = const Color(0xFF2E7D32);
    final bgGradientStart = const Color(0xFFE8F5E9);
    final bgGradientEnd = Colors.white;

    // --- YENİ: E-posta null gelme ihtimaline karşı (Apple "E-postamı Gizle" özelliği için) ---
    final displayEmail = widget.user.email ?? "Gizli E-posta";

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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // İptal / Çıkış Butonu
                    Align(
                      alignment: Alignment.topLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          // Kullanıcı kaydı tamamlamazsa çıkış yap
                          await FirebaseAuth.instance.signOut();
                          if (mounted) {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (_) => const LoginPage(),
                              ),
                              (_) => false,
                            );
                          }
                        },
                        icon: const Icon(Icons.arrow_back, color: Colors.grey),
                        label: const Text(
                          "Vazgeç",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Google/Apple Avatarı veya İkon
                    Center(
                      child: CircleAvatar(
                        radius: 50,
                        backgroundColor: primaryGreen.withOpacity(0.1),
                        backgroundImage: widget.user.photoURL != null
                            ? NetworkImage(widget.user.photoURL!)
                            : null,
                        child: widget.user.photoURL == null
                            ? Icon(Icons.person, size: 50, color: primaryGreen)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 24),

                    Text(
                      'Kaydı Tamamla',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: primaryGreen,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // --- YENİ: Dinamik Karşılama Metni ---
                    Text(
                      '$_providerName hesabınız ($displayEmail) ile bağlandınız.\nLütfen bir kullanıcı adı seçin ve sözleşmeyi onaylayın.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 32),

                    // --- KULLANICI ADI ALANI ---
                    Container(
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
                        controller: _usernameController,
                        style: const TextStyle(color: Colors.black),
                        decoration: InputDecoration(
                          prefixIcon: Icon(
                            Icons.alternate_email,
                            color: Colors.grey[400],
                          ),
                          hintText: 'Kullanıcı Adı Seçin',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: primaryGreen,
                              width: 1.5,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        validator: (v) {
                          final value = (v ?? '').trim();
                          if (value.isEmpty) return 'Kullanıcı adı zorunlu';
                          final re = RegExp(r'^[a-zA-Z0-9._-]{3,20}$');
                          if (!re.hasMatch(value))
                            return 'Geçersiz karakter veya uzunluk (3-20)';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- SÖZLEŞME ONAYI ---
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
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              text: 'Kaydı tamamla butonuna basarak ',
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

                    // --- MAIL İZNİ ---
                    const SizedBox(height: 12),
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

                    // --- KAYDI TAMAMLA BUTONU ---
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _completeRegistration,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGreen,
                          foregroundColor: Colors.white,
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text(
                                'Kaydı Tamamla',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _completeRegistration() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lütfen kullanıcı sözleşmesini onaylayın.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uname = _usernameController.text.trim();

      // Uygunsuz dil kontrolü
      if (TextFilterService.hasProfanity(uname)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu kullanıcı adı uygunsuz ifadeler içeriyor.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      // Kullanıcı Adı Benzersizlik Kontrolü
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
        setState(() => _isLoading = false);
        return;
      }

      // Kullanıcı adını Auth profiline de kaydet
      await widget.user.updateDisplayName(uname);

      // Onboarding bitene kadar herkese açık users profili oluşturma.
      final uid = widget.user.uid;
      final email = widget.user.email ?? "";

      await FirebaseFirestore.instance
          .collection('registration_drafts')
          .doc(uid)
          .set({
            'displayName': uname,
            'displayName_lc': uname.toLowerCase(),
            'email': email,
            'photoURL': widget.user.photoURL,
            'termsAccepted': true,
            'marketingConsent': _allowMail,
            'termsAcceptedAt': FieldValue.serverTimestamp(),
            'authProvider': _providerId,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      // Özellikle Apple ile ilk oturum açılışında native Functions SDK'sının
      // güncel Firebase Auth belirtecini görmesini garanti et.
      await widget.user.getIdToken(true);

      // Başarılı -> Onboarding'e yönlendir
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => _providerId == 'email'
                ? const EmailVerificationPage()
                : const OnboardingLetterboxd(),
          ),
          (_) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showTermsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.9,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
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
                child: const PDF(enableSwipe: true, swipeHorizontal: false)
                    .fromAsset(
                      'assets/docs/sozlesme.pdf',
                      errorWidget: (e) => Center(child: Text("Hata: $e")),
                    ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      setState(() => _agreedToTerms = true);
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
}
