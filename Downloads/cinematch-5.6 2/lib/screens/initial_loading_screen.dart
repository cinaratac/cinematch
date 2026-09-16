import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/shell.dart';
import 'package:fluttergirdi/services/app_popular_movies_service.dart';
import 'package:fluttergirdi/services/global_data_service.dart';
import 'package:fluttergirdi/services/message_avatar_cache_service.dart';
import 'package:fluttergirdi/services/notification_service.dart';
import 'package:fluttergirdi/services/push_token_service.dart';
import 'package:fluttergirdi/services/user_cache_service.dart';
import 'package:fluttergirdi/controllers/feed_controller.dart';
import 'package:fluttergirdi/widgets/branded_splash.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';

class InitialLoadingScreen extends StatefulWidget {
  const InitialLoadingScreen({super.key});

  @override
  State<InitialLoadingScreen> createState() => _InitialLoadingScreenState();
}

class _InitialLoadingScreenState extends State<InitialLoadingScreen> {
  double _progress = 0.06;
  final Completer<void> _progressComplete = Completer<void>();

  @override
  void initState() {
    super.initState();
    _preloadAndGo();
  }

  Future<void> _preloadAndGo() async {
    // Bu ekran yalnızca AuthGate kayıt durumunu sunucudan doğruladıktan sonra
    // açılır. Kullanıcıya özel servisleri yarım kayıtlar için başlatma.
    unawaited(_startNotificationServices());

    // Preloading zaten main.dart'ta başladı ama shell'de de çağrılıyor.
    // Burada tekrar çağırmak zararlı değil — ??= guard var içeride.
    GlobalDataService.instance.startPreloading();
    _setProgress(0.14);

    await _waitForCriticalData();

    if (!mounted) return;
    _setProgress(0.74);
    await _precacheFirstViewportImages();

    if (!mounted) return;
    _setProgress(1);
    await _progressComplete.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {},
    );
    await Future.delayed(const Duration(milliseconds: 80));

    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, _, _) => const HomeShell(),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 350),
        ),
      );
    }
  }

  Future<void> _startNotificationServices() async {
    await NotificationService.I.start();
    await NotificationService.I.requestPermissions();
    await PushTokenService.I.start();
  }

  Future<void> _waitForCriticalData() async {
    unawaited(FeedController.instance.initFollowing());
    var completed = 0;

    Future<void> waitFor(Future<dynamic> operation) async {
      try {
        await operation.timeout(const Duration(seconds: 4));
      } catch (_) {
        // Ağ yavaşsa ekranı kilitleme; servis yüklemeyi arka planda tamamlar.
      } finally {
        completed++;
        _setProgress(0.14 + (completed * 0.15));
      }
    }

    await Future.wait([
      waitFor(FeedController.instance.init()),
      waitFor(AppPopularMoviesService.instance.preload()),
      waitFor(_waitForProfile()),
      waitFor(_waitForChats()),
    ]);
  }

  Future<void> _waitForProfile() async {
    try {
      await GlobalDataService.instance.profileReady.timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {
      debugPrint("Profil yüklemesi zaman aşımına uğradı, devam ediliyor.");
    }
  }

  Future<void> _waitForChats() async {
    try {
      await GlobalDataService.instance.chatsReady.timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {
      debugPrint('Sohbet ön yüklemesi zaman aşımına uğradı, devam ediliyor.');
    }
  }

  Future<void> _precacheFirstViewportImages() async {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final providers = <ImageProvider>[];
    final seenUrls = <String>{};
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final chats = GlobalDataService.instance.myChats ?? const [];
    final avatarPreload = currentUid.isEmpty
        ? Future<void>.value()
        : MessageAvatarCacheService.instance.preloadChats(
            currentUid,
            chats.map((doc) => doc.data()),
          );

    void addImage(
      Object? rawUrl, {
      required int cacheWidth,
      bool isPoster = false,
    }) {
      final url = rawUrl?.toString().trim() ?? '';
      if (url.isEmpty ||
          (!url.startsWith('http://') && !url.startsWith('https://')) ||
          !seenUrls.add(url)) {
        return;
      }
      if (isPoster && url.contains('ltrbxd.com')) return;

      final provider = CachedNetworkImageProvider(
        url,
        cacheKey: isPoster ? url.split('?').first : null,
        cacheManager: isPoster ? customCacheManager : null,
      );
      providers.add(ResizeImage(provider, width: cacheWidth));
    }

    final popularMovies =
        AppPopularMoviesService.instance.cachedMovies ?? const [];
    for (final movie in popularMovies.take(5)) {
      addImage(movie.posterUrl, cacheWidth: 312, isPoster: true);
    }

    final feed = FeedController.instance;
    for (final post in feed.posts.take(3)) {
      final data = post.data() ?? const <String, dynamic>{};
      final authorId = (data['authorId'] ?? '').toString();
      final cachedUser = UserCacheService.instance.getFromCache(authorId);
      addImage(
        cachedUser?.photoURL ?? data['photoURL'],
        cacheWidth: (40 * devicePixelRatio).round(),
      );

      final photoUrls = data['photoURLs'];
      final firstPostImage = photoUrls is List && photoUrls.isNotEmpty
          ? photoUrls.first
          : data['postImage'];
      addImage(
        firstPostImage,
        cacheWidth: (screenWidth * devicePixelRatio).round(),
      );

      final movie = data['movie'] is Map ? data['movie'] as Map : null;
      addImage(
        data['moviePoster'] ?? movie?['poster'] ?? movie?['posterUrl'],
        cacheWidth: (54 * devicePixelRatio).round(),
        isPoster: true,
      );
    }

    try {
      await Future.wait([
        avatarPreload,
        Future.wait(
          providers.map((provider) async {
            try {
              await precacheImage(provider, context, onError: (_, _) {});
            } catch (_) {
              // Bozuk bir görsel uygulamanın açılmasını engellememeli.
            }
          }),
        ),
      ]).timeout(const Duration(milliseconds: 1800));
    } catch (_) {
      // Kalan görseller normal ekran açıldıktan sonra cache'e girebilir.
    }
  }

  void _setProgress(double value) {
    if (!mounted) return;
    final nextProgress = value.clamp(0.0, 1.0);
    if (nextProgress <= _progress) return;
    setState(() => _progress = nextProgress);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: BrandedSplash(
            progress: _progress,
            onProgressComplete: () {
              if (!_progressComplete.isCompleted) {
                _progressComplete.complete();
              }
            },
          ),
        ),
      ),
    );
  }
}
