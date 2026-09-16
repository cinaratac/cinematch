import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/initial_loading_screen.dart';
import 'package:fluttergirdi/services/registration_state.dart';
import 'package:fluttergirdi/widgets/branded_splash.dart';
import '../onboarding/letterboxd_onboarding.dart';
import 'email_verification_page.dart';
import 'google_register_page.dart';
import 'login_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _GateLoading();
        }

        final user = snapshot.data;
        if (user == null) return const LoginPage();
        return _RegistrationGate(key: ValueKey(user.uid), user: user);
      },
    );
  }
}

class _RegistrationGate extends StatefulWidget {
  const _RegistrationGate({super.key, required this.user});

  final User user;

  @override
  State<_RegistrationGate> createState() => _RegistrationGateState();
}

class _RegistrationGateState extends State<_RegistrationGate> {
  late Future<RegistrationStage> _stage;

  @override
  void initState() {
    super.initState();
    _stage = _loadStage();
  }

  Future<RegistrationStage> _loadStage() async {
    final db = FirebaseFirestore.instance;
    final snapshots = await Future.wait([
      db
          .collection('users')
          .doc(widget.user.uid)
          .get(const GetOptions(source: Source.server)),
      db
          .collection('registration_drafts')
          .doc(widget.user.uid)
          .get(const GetOptions(source: Source.server)),
    ]);
    return RegistrationState.resolve(
      userData: snapshots[0].data(),
      draftData: snapshots[1].data(),
    );
  }

  void _retry() {
    setState(() => _stage = _loadStage());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RegistrationStage>(
      future: _stage,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _GateLoading();
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _GateError(onRetry: _retry);
        }

        switch (snapshot.data!) {
          case RegistrationStage.profile:
            return GoogleRegisterPage(user: widget.user);
          case RegistrationStage.emailVerification:
            return const EmailVerificationPage();
          case RegistrationStage.onboarding:
            return const OnboardingLetterboxd();
          case RegistrationStage.complete:
            return const InitialLoadingScreen();
        }
      },
    );
  }
}

// import'lara ekle:

// _GateLoading'i değiştir:
class _GateLoading extends StatelessWidget {
  const _GateLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 40.0),
            child: BrandedSplash(progress: 0.06),
          ),
        ),
      ),
    );
  }
}

class _GateError extends StatelessWidget {
  const _GateError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
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
                  'Kayıt durumu doğrulanamadı. İnternet bağlantını kontrol edip tekrar dene.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Tekrar Dene'),
                ),
                TextButton(
                  onPressed: FirebaseAuth.instance.signOut,
                  child: const Text('Çıkış Yap'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
