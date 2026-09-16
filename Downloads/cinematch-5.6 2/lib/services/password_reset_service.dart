import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PasswordResetService {
  PasswordResetService._();

  static final PasswordResetService instance = PasswordResetService._();

  static const codeSentMessage =
      'Bu adres bir e-posta/şifre hesabına bağlıysa 6 haneli kod gönderildi. Gelen kutunu ve spam klasörünü kontrol et.';

  Future<int> request(String email) async {
    final normalizedEmail = _normalizedEmail(email);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('requestPasswordReset')
          .call<Map<String, dynamic>>({'email': normalizedEmail});
      return (result.data['retryAfterSeconds'] as num?)?.toInt() ?? 60;
    } on FirebaseFunctionsException catch (error) {
      throw _mapFunctionError(error, action: _PasswordResetAction.request);
    }
  }

  Future<String> verifyCode({
    required String email,
    required String code,
  }) async {
    final normalizedEmail = _normalizedEmail(email);
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const PasswordResetException('6 haneli kodu eksiksiz gir.');
    }
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('verifyPasswordResetCode')
          .call<Map<String, dynamic>>({'email': normalizedEmail, 'code': code});
      final resetToken = (result.data['resetToken'] ?? '').toString();
      if (resetToken.isEmpty) {
        throw const PasswordResetException(
          'Kod doğrulanamadı. Lütfen tekrar dene.',
        );
      }
      return resetToken;
    } on FirebaseFunctionsException catch (error) {
      throw _mapFunctionError(error, action: _PasswordResetAction.verify);
    }
  }

  Future<void> completeAndSignIn({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {
    final normalizedEmail = _normalizedEmail(email);
    if (newPassword.length < 8) {
      throw const PasswordResetException('Yeni şifre en az 8 karakter olmalı.');
    }
    try {
      await FirebaseFunctions.instance
          .httpsCallable('completePasswordReset')
          .call<void>({
            'email': normalizedEmail,
            'resetToken': resetToken,
            'newPassword': newPassword,
          });
    } on FirebaseFunctionsException catch (error) {
      throw _mapFunctionError(error, action: _PasswordResetAction.complete);
    }

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: newPassword,
      );
    } on FirebaseAuthException {
      throw const PasswordResetException(
        'Şifren değiştirildi ancak otomatik giriş yapılamadı. Yeni şifrenle giriş yap.',
      );
    }
  }

  static String _normalizedEmail(String value) {
    final email = value.trim().toLowerCase();
    final at = email.indexOf('@');
    final dot = email.lastIndexOf('.');
    if (at <= 0 || dot <= at + 1 || dot >= email.length - 1) {
      throw const PasswordResetException('Geçerli bir e-posta adresi gir.');
    }
    return email;
  }

  static PasswordResetException _mapFunctionError(
    FirebaseFunctionsException error, {
    required _PasswordResetAction action,
  }) {
    switch (error.code) {
      case 'invalid-argument':
        return PasswordResetException(
          error.message ??
              (action == _PasswordResetAction.complete
                  ? 'Yeni şifre en az 8 karakter olmalı.'
                  : 'Girdiğin bilgileri kontrol et.'),
        );
      case 'permission-denied':
        return PasswordResetException(
          action == _PasswordResetAction.verify
              ? 'Kod geçersiz veya süresi dolmuş.'
              : 'Şifre yenileme oturumu geçersiz veya süresi dolmuş.',
        );
      case 'resource-exhausted':
        return PasswordResetException(
          action == _PasswordResetAction.request
              ? 'Çok fazla kod istendi. Lütfen daha sonra tekrar dene.'
              : 'Çok fazla hatalı kod girildi. Yeni kod iste.',
        );
      case 'unavailable':
      case 'deadline-exceeded':
        return const PasswordResetException(
          'Şifre servisine şu anda ulaşılamıyor. Lütfen tekrar dene.',
        );
      default:
        return const PasswordResetException(
          'İşlem tamamlanamadı. Lütfen tekrar dene.',
        );
    }
  }
}

enum _PasswordResetAction { request, verify, complete }

class PasswordResetException implements Exception {
  const PasswordResetException(this.message);

  final String message;

  @override
  String toString() => message;
}
