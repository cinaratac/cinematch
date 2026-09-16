import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttergirdi/auth/auth_gate.dart';
import 'package:fluttergirdi/services/password_reset_service.dart';

class PasswordResetPage extends StatefulWidget {
  const PasswordResetPage({
    super.key,
    required this.email,
    this.initialResendSeconds = 60,
  });

  final String email;
  final int initialResendSeconds;

  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  static const _primaryGreen = Color(0xFF2E7D32);

  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  Timer? _resendTimer;
  int _resendSeconds = 60;
  bool _busy = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  String? _resetToken;

  bool get _isPasswordStep => _resetToken != null;

  @override
  void initState() {
    super.initState();
    _startResendTimer(widget.initialResendSeconds);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startResendTimer(int seconds) {
    _resendTimer?.cancel();
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

  String get _maskedEmail {
    final email = widget.email.trim();
    final at = email.indexOf('@');
    if (at <= 1) return email;
    final visible = email.substring(0, at.clamp(1, 2));
    final hidden = List.filled(at - visible.length, '•').join();
    return '$visible$hidden${email.substring(at)}';
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.redAccent : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _verifyCode() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final token = await PasswordResetService.instance.verifyCode(
        email: widget.email,
        code: _codeController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _resetToken = token);
    } on PasswordResetException catch (error) {
      _showMessage(error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendCode() async {
    if (_busy || _resendSeconds > 0) return;
    setState(() => _busy = true);
    try {
      final retryAfter = await PasswordResetService.instance.request(
        widget.email,
      );
      if (!mounted) return;
      _codeController.clear();
      _startResendTimer(retryAfter);
      _showMessage(PasswordResetService.codeSentMessage);
    } on PasswordResetException catch (error) {
      _showMessage(error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePassword() async {
    if (_busy) return;
    final password = _passwordController.text;
    if (password.length < 8) {
      _showMessage('Yeni şifre en az 8 karakter olmalı.', error: true);
      return;
    }
    if (password != _confirmPasswordController.text) {
      _showMessage('Şifreler birbiriyle uyuşmuyor.', error: true);
      return;
    }

    setState(() => _busy = true);
    try {
      await PasswordResetService.instance.completeAndSignIn(
        email: widget.email,
        resetToken: _resetToken!,
        newPassword: password,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (_) => false,
      );
    } on PasswordResetException catch (error) {
      _showMessage(error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFE8F5E9),
        foregroundColor: _primaryGreen,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE8F5E9), Colors.white],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.04, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _isPasswordStep
                      ? _buildPasswordStep()
                      : _buildCodeStep(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCodeStep() {
    return Column(
      key: const ValueKey('code'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          '$_maskedEmail adresine gönderilen 6 haneli kodu gir.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[700], fontSize: 15, height: 1.4),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _codeController,
          enabled: !_busy,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.oneTimeCode],
          textAlign: TextAlign.center,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _verifyCode(),
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 30,
            fontWeight: FontWeight.bold,
            letterSpacing: 0,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            hintStyle: TextStyle(color: Colors.grey[400]),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _primaryGreen, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy || _codeController.text.trim().length != 6
              ? null
              : _verifyCode,
          style: FilledButton.styleFrom(
            backgroundColor: _primaryGreen,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _busy
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
        ),
        const SizedBox(height: 18),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: _primaryGreen),
          onPressed: _busy || _resendSeconds > 0 ? null : _resendCode,
          child: Text(
            _resendSeconds > 0
                ? 'Yeni kod gönder ($_resendSeconds sn)'
                : 'Yeni kod gönder',
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      key: const ValueKey('password'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock_reset_rounded, size: 78, color: _primaryGreen),
        const SizedBox(height: 24),
        const Text(
          'Yeni şifreni belirle',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _primaryGreen,
            fontSize: 27,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'En az 8 karakterden oluşan yeni bir şifre kullan.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[700], height: 1.45),
        ),
        const SizedBox(height: 32),
        _passwordField(
          controller: _passwordController,
          label: 'Yeni şifre',
          visible: _showPassword,
          onToggle: () => setState(() => _showPassword = !_showPassword),
        ),
        const SizedBox(height: 16),
        _passwordField(
          controller: _confirmPasswordController,
          label: 'Yeni şifre tekrar',
          visible: _showConfirmPassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _savePassword(),
          onToggle: () =>
              setState(() => _showConfirmPassword = !_showConfirmPassword),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _primaryGreen,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _busy ? null : _savePassword,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: const Text('Şifreyi Kaydet'),
          ),
        ),
      ],
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool visible,
    required VoidCallback onToggle,
    TextInputAction textInputAction = TextInputAction.next,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      enabled: !_busy,
      obscureText: !visible,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[700]),
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          tooltip: visible ? 'Şifreyi gizle' : 'Şifreyi göster',
          onPressed: onToggle,
          icon: Icon(
            visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          ),
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _primaryGreen, width: 2),
        ),
      ),
      style: const TextStyle(color: Colors.black87),
    );
  }
}
