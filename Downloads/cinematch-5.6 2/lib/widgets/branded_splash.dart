import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/widgets/green_characters.dart';

/// Uygulama genelinde kullanılan marka bilinçli "yükleniyor" görseli.
/// SADECE görsel katmandır — hiçbir preloading/servis başlatma yan etkisi
/// içermez. Bu sayede hem AuthGate'in kayıt durumu kontrolü sırasında
/// (henüz kullanıcıya özel servisler başlamadan) hem de InitialLoadingScreen
/// içinde asıl preloading yapılırken güvenle gösterilebilir.
/// Gerçek yükleme ilerlemesini yumuşatarak karakter ve barı birlikte hareket ettirir.
class BrandedSplash extends StatefulWidget {
  const BrandedSplash({super.key, this.progress, this.onProgressComplete});

  final double? progress;
  final VoidCallback? onProgressComplete;

  @override
  State<BrandedSplash> createState() => _BrandedSplashState();
}

class _BrandedSplashState extends State<BrandedSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _completionReported = false;

  static const List<String> _cinemaFacts = [
    'Matrix serisindeki ikonik yeşil kodlar aslında Japon suşi tariflerinden oluşur.',
    'Yüzüklerin Efendisi filminin bütçesi, gerçek Titanik gemisinin yapım maliyetinden daha yüksekti.',
    'Ucuz Roman (Pulp Fiction) filmindeki bütün saatler 4:20\'yi gösterir.',
    'İlk Star Wars filmi için tasarlanan Millennium Falcon uzay gemisi, bir hamburgerden ilham alınmıştır.',
    'Terminatör\'de Arnold Schwarzenegger, film boyunca sadece 74 kelime konuşmuştur.',
    'Rocky filmindeki ikonik koşu sahnesinde, pazar yerindeki insanların çoğu çekim yapıldığından habersiz gerçek halktı.',
    'Leon (Sevginin Gücü) filmindeki polis baskını sahnesi o kadar gerçekçiydi ki, civardaki bir soyguncu gerçek polis sanıp teslim olmuştur.',
  ];
  static final String _sessionFact =
      _cinemaFacts[Random().nextInt(_cinemaFacts.length)];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    final progress = widget.progress;
    if (progress == null) {
      _controller.animateTo(
        0.86,
        duration: const Duration(milliseconds: 1800),
        curve: Curves.easeOutCubic,
      );
    } else {
      _controller.value = progress.clamp(0.0, 1.0);
      if (_controller.value >= 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _reportCompletion();
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant BrandedSplash oldWidget) {
    super.didUpdateWidget(oldWidget);
    final progress = widget.progress;
    if (progress != null && progress != oldWidget.progress) {
      _animateToProgress(progress);
    }
  }

  void _animateToProgress(double progress) {
    final target = progress.clamp(0.0, 1.0);
    if (target <= _controller.value) {
      if (target >= 1) _reportCompletion();
      return;
    }

    final distance = target - _controller.value;
    final durationMs = (420 + (distance * 1050)).round().clamp(420, 1250);
    _controller
        .animateTo(
          target,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeInOutCubic,
        )
        .then((_) {
          if (mounted && target >= 1 && _controller.value >= 1) {
            _reportCompletion();
          }
        });
  }

  void _reportCompletion() {
    if (_completionReported) return;
    _completionReported = true;
    widget.onProgressComplete?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double barWidth = 260.0;
    const double characterSize = 55.0;
    const double travelDistance = barWidth - characterSize;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final travel = _controller.value * travelDistance;
            return Column(
              children: [
                SizedBox(
                  width: barWidth,
                  height: characterSize,
                  child: Stack(
                    children: [
                      Positioned(
                        left: travel,
                        bottom: 0,
                        child: Transform.rotate(
                          angle: _controller.value * 2 * pi * 3,
                          child: const GreenEyesCharacter(size: characterSize),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),
                SizedBox(
                  width: barWidth,
                  height: 8,
                  child: Stack(
                    children: [
                      Container(
                        width: barWidth,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Container(
                        width: travel + characterSize,
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF2E7D32,
                              ).withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 40),
        Text(
          'Biliyor muydunuz?',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF2E7D32).withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _sessionFact,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            height: 1.4,
            color: Theme.of(
              context,
            ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}
