import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttergirdi/auth/login_page.dart';
import 'package:fluttergirdi/onboarding/letterboxd_onboarding.dart';
import 'package:fluttergirdi/services/onboarding_draft_service.dart';

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({super.key});

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  static const _primaryGreen = Color(0xFF2E7D32);

  final _codeController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _countdownTimer;
  int _secondsUntilResend = 0;
  bool _sending = false;
  bool _verifying = false;
  bool _cancelling = false;
  String? _statusMessage;

  bool get _busy => _sending || _verifying || _cancelling;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestCode(automatic: true);
    });
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    if (!mounted) return;
    setState(() => _secondsUntilResend = seconds.clamp(0, 600));
    if (_secondsUntilResend == 0) return;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _secondsUntilResend <= 1) {
        timer.cancel();
        if (mounted) setState(() => _secondsUntilResend = 0);
        return;
      }
      setState(() => _secondsUntilResend -= 1);
    });
  }

  Future<void> _requestCode({bool automatic = false}) async {
    if (_sending || (!automatic && _secondsUntilResend > 0)) return;
    setState(() {
      _sending = true;
      _statusMessage = automatic ? 'Doğrulama kodu gönderiliyor...' : null;
    });
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('requestEmailVerificationCode')
          .call();
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['alreadyVerified'] == true) {
        await _continueToOnboarding();
        return;
      }
      final retryAfter = (data['retryAfterSeconds'] as num?)?.toInt() ?? 60;
      _startCountdown(retryAfter);
      if (!mounted) return;
      setState(() {
        _statusMessage = data['sent'] == true
            ? '6 haneli kod e-posta adresine gönderildi.'
            : 'Daha önce gönderilen kodu kullanabilirsin.';
      });
      _focusNode.requestFocus();
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() => _statusMessage = _messageForFunctionError(error));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Kod gönderilemedi. Bağlantını kontrol edip tekrar dene.';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _statusMessage = 'Lütfen 6 haneli kodu eksiksiz gir.');
      return;
    }
    if (_verifying) return;
    setState(() {
      _verifying = true;
      _statusMessage = 'Kod doğrulanıyor...';
    });
    try {
      await FirebaseFunctions.instance
          .httpsCallable('verifyEmailVerificationCode')
          .call({'code': code});
      await _continueToOnboarding();
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = _messageForFunctionError(error);
        _codeController.clear();
      });
      _focusNode.requestFocus();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Kod doğrulanamadı. Bağlantını kontrol edip tekrar dene.';
      });
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _continueToOnboarding() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Oturum bulunamadı.');
    await user.reload();
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const OnboardingLetterboxd()),
      (_) => false,
    );
  }

  Future<void> _cancelRegistration() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kaydı iptal et?'),
        content: const Text(
          'Doğrulanmamış hesabın ve kayıt taslağın kalıcı olarak silinecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
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

    setState(() => _cancelling = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Oturum bulunamadı.');
      await FirebaseFunctions.instance
          .httpsCallable('cancelRegistration')
          .call();
      await OnboardingDraftService.clear(uid);
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _statusMessage = 'Kayıt iptal edilemedi: $error');
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  String _messageForFunctionError(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'invalid-argument':
        return error.message ?? 'Kod geçersiz.';
      case 'deadline-exceeded':
        return 'Kodun süresi dolmuş. Lütfen yeni kod iste.';
      case 'resource-exhausted':
        return error.message ?? 'Çok fazla deneme yapıldı. Bir süre bekle.';
      case 'failed-precondition':
        return error.message ?? 'Doğrulama işlemi başlatılamadı.';
      case 'permission-denied':
        return 'Bu hesap için e-posta doğrulaması kullanılamıyor.';
      case 'unauthenticated':
        return 'Oturumun sona ermiş. Lütfen yeniden kayıt ol.';
      default:
        return error.message ?? 'İşlem tamamlanamadı. Tekrar dene.';
    }
  }

  String _maskedEmail(String? email) {
    final value = (email ?? '').trim();
    final at = value.indexOf('@');
    if (at <= 1) return value;
    final visible = value.substring(0, 2);
    final hidden = List.filled((at - 2).clamp(2, 8), '•').join();
    return '$visible$hidden${value.substring(at)}';
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _codeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = _maskedEmail(FirebaseAuth.instance.currentUser?.email);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFE8F5E9), Colors.white],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy ? null : _cancelRegistration,
                          child: const Text('Kaydı iptal et'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Icon(
                        Icons.mark_email_read_outlined,
                        size: 76,
                        color: _primaryGreen,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'E-posta Adresini Doğrula',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.bold,
                          color: _primaryGreen,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '$email adresine gönderdiğimiz 6 haneli kodu gir.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[700], fontSize: 15),
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: _codeController,
                        focusNode: _focusNode,
                        enabled: !_busy,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 12,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '000000',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: _primaryGreen,
                              width: 2,
                            ),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _verifyCode(),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed:
                            _busy || _codeController.text.trim().length != 6
                            ? null
                            : _verifyCode,
                        style: FilledButton.styleFrom(
                          backgroundColor: _primaryGreen,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _verifying
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Doğrula ve Devam Et',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: _busy || _secondsUntilResend > 0
                            ? null
                            : _requestCode,
                        child: Text(
                          _secondsUntilResend > 0
                              ? 'Yeni kod gönder ($_secondsUntilResend sn)'
                              : 'Yeni kod gönder',
                        ),
                      ),
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _statusMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _statusMessage!.contains('gönderildi')
                                ? _primaryGreen
                                : Colors.grey[700],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Kod 10 dakika geçerlidir. Spam klasörünü de kontrol etmeyi unutma.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
