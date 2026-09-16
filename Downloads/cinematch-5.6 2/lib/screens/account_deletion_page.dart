import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:fluttergirdi/auth/login_page.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

enum _DeletionStep { identity, code, reason }

class AccountDeletionPage extends StatefulWidget {
  const AccountDeletionPage({super.key});

  @override
  State<AccountDeletionPage> createState() => _AccountDeletionPageState();
}

class _AccountDeletionPageState extends State<AccountDeletionPage> {
  static const _danger = Color(0xFFC62828);
  static const _reasons = <String, String>{
    'privacy': 'Gizlilik konusunda endişelerim var',
    'too_many_notifications': 'Çok fazla bildirim alıyorum',
    'not_useful': 'Uygulamayı yeterince faydalı bulmadım',
    'technical_problems': 'Teknik sorunlar yaşadım',
    'found_alternative': 'Başka bir uygulama kullanıyorum',
    'taking_break': 'Sadece bir süre ara vermek istiyorum',
    'other': 'Başka bir neden',
  };

  final _codeController = TextEditingController();
  final _noteController = TextEditingController();
  final _codeFocusNode = FocusNode();
  Timer? _resendTimer;
  _DeletionStep _step = _DeletionStep.identity;
  bool _busy = false;
  int _resendSeconds = 0;
  String? _statusMessage;
  String? _authorizationToken;
  String? _selectedReason;
  String? _maskedDestination;

  User? get _user => FirebaseAuth.instance.currentUser;

  bool get _hasGoogle =>
      _user?.providerData.any((item) => item.providerId == 'google.com') ==
      true;

  bool get _hasApple =>
      _user?.providerData.any((item) => item.providerId == 'apple.com') == true;

  String get _verificationButtonLabel {
    if (_hasGoogle) return 'Google ile doğrula ve kod gönder';
    if (_hasApple) return 'Apple ile doğrula ve kod gönder';
    return 'E-postama kod gönder';
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _codeController.dispose();
    _noteController.dispose();
    _codeFocusNode.dispose();
    super.dispose();
  }

  String _maskedEmail(String? rawEmail) {
    final email = (rawEmail ?? '').trim();
    final at = email.indexOf('@');
    if (at <= 1) return email;
    final visible = email.substring(0, at.clamp(1, 2));
    final hidden = List.filled((at - visible.length).clamp(2, 8), '•').join();
    return '$visible$hidden${email.substring(at)}';
  }

  void _startResendTimer(int seconds) {
    _resendTimer?.cancel();
    if (!mounted) return;
    setState(() => _resendSeconds = seconds.clamp(0, 600));
    if (_resendSeconds == 0) return;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _resendSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendSeconds = 0);
        return;
      }
      setState(() => _resendSeconds -= 1);
    });
  }

  Future<void> _reauthenticateFederated(User user) async {
    if (_hasGoogle) {
      final googleSignIn = GoogleSignIn();
      try {
        await googleSignIn.signOut();
      } catch (_) {}
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) throw const _VerificationCancelled();
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await user.reauthenticateWithCredential(credential);
      return;
    }

    if (_hasApple) {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final credential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      await user.reauthenticateWithCredential(credential);
    }
  }

  Future<void> _requestCode() async {
    if (_busy || _resendSeconds > 0) return;
    final user = _user;
    if (user == null) {
      setState(() => _statusMessage = 'Oturumun sona ermiş. Tekrar giriş yap.');
      return;
    }

    setState(() {
      _busy = true;
      _statusMessage = (_hasGoogle || _hasApple)
          ? 'Kimliğin doğrulanıyor...'
          : 'Doğrulama kodu hazırlanıyor...';
    });
    try {
      await _reauthenticateFederated(user);
      await user.getIdToken(true);
      final response = await FirebaseFunctions.instance
          .httpsCallable('requestAccountDeletionCode')
          .call();
      final data = Map<String, dynamic>.from(response.data as Map);
      if (!mounted) return;
      final retryAfter = (data['retryAfterSeconds'] as num?)?.toInt() ?? 60;
      setState(() {
        _maskedDestination = _maskedEmail(data['email']?.toString());
        _step = _DeletionStep.code;
        _statusMessage = data['sent'] == true
            ? '6 haneli kod e-posta adresine gönderildi.'
            : 'Daha önce gönderilen kodu kullanabilirsin.';
      });
      _startResendTimer(retryAfter);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _codeFocusNode.requestFocus();
      });
    } on _VerificationCancelled {
      if (mounted) setState(() => _statusMessage = 'Doğrulama iptal edildi.');
    } on SignInWithAppleAuthorizationException catch (error) {
      if (!mounted) return;
      setState(() {
        _statusMessage = error.code == AuthorizationErrorCode.canceled
            ? 'Apple doğrulaması iptal edildi.'
            : 'Apple doğrulaması tamamlanamadı. Tekrar dene.';
      });
    } on FirebaseAuthException catch (error, stack) {
      if (kDebugMode) {
        debugPrint('Hesap silme yeniden doğrulama: $error\n$stack');
      }
      if (!mounted) return;
      setState(() => _statusMessage = _authErrorMessage(error));
    } on FirebaseFunctionsException catch (error, stack) {
      if (kDebugMode) debugPrint('Hesap silme kod isteği: $error\n$stack');
      if (!mounted) return;
      setState(() => _statusMessage = _functionErrorMessage(error));
    } catch (error, stack) {
      if (kDebugMode) debugPrint('Hesap silme kod isteği: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Kod gönderilemedi. Bağlantını kontrol edip tekrar dene.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_busy) return;
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _statusMessage = '6 haneli kodu eksiksiz gir.');
      return;
    }
    setState(() {
      _busy = true;
      _statusMessage = 'Kod doğrulanıyor...';
    });
    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('verifyAccountDeletionCode')
          .call({'code': code});
      final data = Map<String, dynamic>.from(response.data as Map);
      final token = data['authorizationToken']?.toString() ?? '';
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) {
        throw StateError('Silme yetkisi alınamadı.');
      }
      if (!mounted) return;
      _resendTimer?.cancel();
      setState(() {
        _authorizationToken = token;
        _step = _DeletionStep.reason;
        _statusMessage = null;
      });
    } on FirebaseFunctionsException catch (error, stack) {
      if (kDebugMode) debugPrint('Hesap silme kod doğrulama: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _statusMessage = _functionErrorMessage(error);
        _codeController.clear();
      });
      _codeFocusNode.requestFocus();
    } catch (error, stack) {
      if (kDebugMode) debugPrint('Hesap silme kod doğrulama: $error\n$stack');
      if (!mounted) return;
      setState(() => _statusMessage = 'Kod doğrulanamadı. Tekrar dene.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeDeletion() async {
    if (_busy) return;
    final reason = _selectedReason;
    final token = _authorizationToken;
    final note = _noteController.text.trim();
    if (reason == null) {
      setState(() => _statusMessage = 'Lütfen bir ayrılma nedeni seç.');
      return;
    }
    if (reason == 'other' && note.length < 3) {
      setState(() {
        _statusMessage = 'Başka bir neden seçtiysen kısa bir açıklama yaz.';
      });
      return;
    }
    if (token == null) {
      setState(
        () => _statusMessage = 'Doğrulamanın süresi doldu. Baştan dene.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: _danger, size: 34),
        title: const Text('Hesabın kalıcı olarak silinsin mi?'),
        content: const Text(
          'Profilin, film listelerin, paylaşımların ve hesabına bağlı veriler silinecek. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Kalıcı Olarak Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _statusMessage = 'Hesabın ve verilerin güvenli şekilde siliniyor...';
    });
    try {
      await FirebaseFunctions.instance
          .httpsCallable(
            'completeAccountDeletion',
            options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
          )
          .call({
            'authorizationToken': token,
            'reasonCode': reason,
            'note': note,
          });

      await DefaultCacheManager().emptyCache();
      final preferences = await SharedPreferences.getInstance();
      await preferences.clear();
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    } on FirebaseFunctionsException catch (error, stack) {
      if (kDebugMode) debugPrint('Hesap silme tamamlama: $error\n$stack');
      if (!mounted) return;
      setState(() => _statusMessage = _functionErrorMessage(error));
    } catch (error, stack) {
      if (kDebugMode) debugPrint('Hesap silme tamamlama: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Hesap silinemedi. Bağlantını kontrol edip tekrar dene.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'user-mismatch':
        return 'Lütfen bu CineMatch hesabına bağlı Google/Apple hesabını seç.';
      case 'invalid-credential':
      case 'wrong-password':
        return 'Kimliğin doğrulanamadı. Bilgilerini kontrol edip tekrar dene.';
      case 'too-many-requests':
        return 'Çok fazla deneme yapıldı. Bir süre sonra tekrar dene.';
      default:
        return 'Kimlik doğrulaması tamamlanamadı. Tekrar dene.';
    }
  }

  String _functionErrorMessage(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'invalid-argument':
        return error.message ?? 'Girilen bilgi geçersiz.';
      case 'deadline-exceeded':
        return 'Kodun süresi dolmuş. Yeni kod iste.';
      case 'resource-exhausted':
        return error.message ?? 'Çok fazla deneme yapıldı. Bir süre bekle.';
      case 'permission-denied':
      case 'unauthenticated':
        return error.message ?? 'Kimliğini yeniden doğrulaman gerekiyor.';
      case 'failed-precondition':
        return error.message ?? 'İşlem şu anda başlatılamıyor.';
      default:
        return error.message ?? 'İşlem tamamlanamadı. Tekrar dene.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF202124) : Colors.white;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Hesabı Sil'), centerTitle: true),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _StepHeader(step: _step),
              const SizedBox(height: 22),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Container(
                  key: ValueKey(_step),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                    boxShadow: isDark
                        ? null
                        : const [
                            BoxShadow(
                              color: Color(0x12000000),
                              blurRadius: 20,
                              offset: Offset(0, 8),
                            ),
                          ],
                  ),
                  child: switch (_step) {
                    _DeletionStep.identity => _buildIdentityStep(),
                    _DeletionStep.code => _buildCodeStep(),
                    _DeletionStep.reason => _buildReasonStep(),
                  },
                ),
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: _danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _statusMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _danger, height: 1.3),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdentityStep() {
    final email = _maskedEmail(_user?.email);
    final providerText = _hasGoogle
        ? 'Önce bağlı Google hesabınla yeniden doğrulanacaksın.'
        : _hasApple
        ? 'Önce bağlı Apple hesabınla yeniden doğrulanacaksın.'
        : 'E-posta adresine 6 haneli bir güvenlik kodu göndereceğiz.';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.shield_outlined, color: _danger, size: 48),
        const SizedBox(height: 14),
        const Text(
          'Kimliğini doğrula',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          '$providerText Ardından $email adresine gönderilen kodu gireceksin.',
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.45),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _danger,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _busy ? null : _requestCode,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_hasApple ? Icons.apple : Icons.verified_user_outlined),
            label: Text(_verificationButtonLabel),
          ),
        ),
      ],
    );
  }

  Widget _buildCodeStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.mark_email_read_outlined, color: _danger, size: 46),
        const SizedBox(height: 12),
        const Text(
          'E-postandaki kodu gir',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          '${_maskedDestination ?? _maskedEmail(_user?.email)} adresine gönderilen kod 10 dakika geçerlidir.',
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.4),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _codeController,
          focusNode: _codeFocusNode,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            fontSize: 25,
            letterSpacing: 10,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onSubmitted: (_) => _verifyCode(),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _danger,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _busy ? null : _verifyCode,
            child: _busy
                ? const SizedBox.square(
                    dimension: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Kodu Doğrula'),
          ),
        ),
        TextButton(
          onPressed: _busy || _resendSeconds > 0 ? null : _requestCode,
          child: Text(
            _resendSeconds > 0
                ? 'Yeni kod için $_resendSeconds sn bekle'
                : 'Kodu yeniden gönder',
          ),
        ),
      ],
    );
  }

  Widget _buildReasonStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Neden gitmek istiyorsun?',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 7),
        const Text(
          'Geri bildirimin yalnızca ürünü geliştirmek için, hesabından ayrı olarak saklanır.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.4),
        ),
        const SizedBox(height: 16),
        RadioGroup<String>(
          groupValue: _selectedReason,
          onChanged: (value) {
            if (_busy) return;
            setState(() {
              _selectedReason = value;
              _statusMessage = null;
            });
          },
          child: Column(
            children: [
              for (final entry in _reasons.entries)
                Card(
                  margin: const EdgeInsets.only(bottom: 7),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: _selectedReason == entry.key
                          ? _danger
                          : Theme.of(context).dividerColor,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: RadioListTile<String>(
                    value: entry.key,
                    enabled: !_busy,
                    activeColor: _danger,
                    title: Text(entry.value),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _noteController,
          enabled: !_busy,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: _selectedReason == 'other'
                ? 'Kısa açıklama (zorunlu)'
                : 'Eklemek istediğin bir şey var mı? (isteğe bağlı)',
            alignLabelWithHint: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _danger,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          onPressed: _busy ? null : _completeDeletion,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_forever_rounded),
          label: Text(
            _busy ? 'Hesap siliniyor...' : 'Hesabımı Kalıcı Olarak Sil',
          ),
        ),
      ],
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});

  final _DeletionStep step;

  @override
  Widget build(BuildContext context) {
    final activeIndex = step.index;
    const labels = ['Kimlik', 'Kod', 'Neden'];
    return Row(
      children: [
        for (var index = 0; index < labels.length; index++) ...[
          Expanded(
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: index <= activeIndex
                        ? _AccountDeletionPageState._danger
                        : Theme.of(
                            context,
                          ).disabledColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: index < activeIndex
                      ? const Icon(Icons.check, size: 17, color: Colors.white)
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: index <= activeIndex
                                ? Colors.white
                                : Theme.of(context).disabledColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                const SizedBox(height: 5),
                Text(labels[index], style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          if (index < labels.length - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 20),
                color: index < activeIndex
                    ? _AccountDeletionPageState._danger
                    : Theme.of(context).disabledColor.withValues(alpha: 0.15),
              ),
            ),
        ],
      ],
    );
  }
}

class _VerificationCancelled implements Exception {
  const _VerificationCancelled();
}
