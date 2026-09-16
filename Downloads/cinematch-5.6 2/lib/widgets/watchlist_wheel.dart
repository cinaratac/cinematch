import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Watchlist filmi için basit veri modeli
class WatchlistMovie {
  final String title;
  final String? posterUrl;
  final String? id;
  const WatchlistMovie({required this.title, this.posterUrl, this.id});
}

/// Watchlist'ten rastgele film seçmek için kullanılan Çark (Wheel) Widget'ı
class WatchlistWheel extends StatefulWidget {
  final List<WatchlistMovie> items;
  final void Function(WatchlistMovie chosen)? onChosen;
  final double size;
  final int? randomSeed;
  final bool showCenterPreview;

  const WatchlistWheel({
    super.key,
    required this.items,
    this.onChosen,
    this.size = 320,
    this.randomSeed,
    this.showCenterPreview = true,
  });

  @override
  State<WatchlistWheel> createState() => _WatchlistWheelState();
}

class _WatchlistWheelState extends State<WatchlistWheel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  double _angle = 0.0; // Mevcut dönüş açısı (radyan)
  bool _spinning = false;
  late math.Random _rng;

  @override
  void initState() {
    super.initState();
    _rng = math.Random(widget.randomSeed);
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutQuart);
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _spinning = false);
        _emitResult();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _emitResult() {
    if (widget.items.isEmpty) return;
    final idx = _indexForCurrentAngle(widget.items.length, _angle);
    widget.onChosen?.call(widget.items[idx]);
  }

  /// Çarkı rastgelelik ekleyerek çevirir
  void spin() {
    if (widget.items.length <= 1 || _spinning) return;
    setState(() => _spinning = true);

    final start = _angle;
    // Hedef: 5 ile 8 arası tam tur ve rastgele bir dilim seçimi
    final fullTurns = 5 + _rng.nextInt(4);
    final slice = (2 * math.pi) / widget.items.length;
    final offsetWithinSlice =
        _rng.nextDouble() * (slice * 0.9) + slice * 0.05; // Kenarlardan kaçın

    final currentIdx = _indexForCurrentAngle(widget.items.length, start);
    int targetIdx = _rng.nextInt(widget.items.length);
    if (widget.items.length > 1 && targetIdx == currentIdx) {
      targetIdx = (targetIdx + 1) % widget.items.length; // Aynı film gelmesin
    }

    final pointerAngle = -math.pi / 2; // Tepe noktası (12 yönü)
    final targetAngleCenter = targetIdx * slice + slice / 2.0;
    final delta = _normalizeAngle(targetAngleCenter - pointerAngle);

    final end = start + fullTurns * 2 * math.pi + delta + offsetWithinSlice;

    final tween = Tween<double>(begin: start, end: end);
    _ctrl.reset();
    _ctrl.addListener(() {
      setState(() {
        _angle = tween.evaluate(_anim);
      });
    });
    _ctrl.forward();
  }

  static double _normalizeAngle(double a) {
    final twoPi = 2 * math.pi;
    a = a % twoPi;
    if (a < 0) a += twoPi;
    return a;
  }

  static int _indexForCurrentAngle(int itemCount, double angle) {
    if (itemCount == 0) return 0;
    final twoPi = 2 * math.pi;
    final slice = twoPi / itemCount;
    final normalized = _normalize(angle);
    final pointer = _normalize(-normalized - math.pi / 2);
    int idx = (pointer / slice).floor();
    if (idx < 0) idx = 0;
    if (idx >= itemCount) idx = itemCount - 1;
    return idx;
  }

  static double _normalize(double a) {
    final twoPi = 2 * math.pi;
    a = a % twoPi;
    if (a < 0) a += twoPi;
    return a;
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final size = widget.size;
    final selectedIdx = items.isNotEmpty
        ? _indexForCurrentAngle(items.length, _angle)
        : -1;
    final selected = (selectedIdx >= 0) ? items[selectedIdx] : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            // Dönen Çark
            SizedBox(
              width: size,
              height: size,
              child: Transform.rotate(
                angle: _angle,
                child: CustomPaint(painter: _WheelPainter(items: items)),
              ),
            ),

            // Seçili Filmin Ortadaki Önizlemesi
            if (widget.showCenterPreview && selected != null)
              _CenterBadge(movie: selected),

            // Tepe Noktasındaki İşaretçi
            Positioned(top: 0, child: _Pointer()),
          ],
        ),

        const SizedBox(height: 24),

        // 1. Eğer birden fazla film varsa, çark dönerken seçili olanı şık bir şekilde yazdırır
        if (selected != null && items.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0, left: 16, right: 16),
            child: Text(
              selected.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),

        // 2. Aksiyon Butonu (Modernleştirilmiş)
        SizedBox(
          width: 220,
          height: 52,
          child: FilledButton.icon(
            // Sadece 1 film varsa tıklandığında popup göster (onChosen), çok varsa çarkı çevir (spin)
            onPressed: items.length == 1
                ? () => widget.onChosen?.call(items.first)
                : (items.length > 1 && !_spinning)
                ? spin
                : null,
            icon: Icon(
              items.length == 1 ? Icons.send_rounded : Icons.casino,
              size: 22,
            ),
            label: Text(
              items.length == 1 ? 'Direkt Gönder' : 'Çarkı Çevir',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(
                0xFF2E7D32,
              ), // Uygulamanızın Tema Yeşili
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  final List<WatchlistMovie> items;
  _WheelPainter({required this.items});

  @override
  void paint(Canvas canvas, Size size) {
    final n = items.isNotEmpty ? items.length : 1;
    final sliceAngle = (2 * math.pi) / n;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2.0;

    final bg = Paint()..color = Colors.grey.withOpacity(0.08);
    canvas.drawCircle(center, radius, bg);

    final paint = Paint()..style = PaintingStyle.fill;
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );

    for (int i = 0; i < n; i++) {
      final start = i * sliceAngle;
      // Dilim renklerini sırayla değiştir (Yeşil tonları)
      final c = i.isEven
          ? const Color(0xFF4CAF50).withOpacity(0.85) // Açık Yeşil
          : const Color(0xFF2E7D32).withOpacity(0.85); // Koyu Yeşil
      paint.color = c;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sliceAngle,
        true,
        paint,
      );

      // Film adını yazdır
      final label = items.isNotEmpty ? items[i].title : '—';
      final tpStyle = const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      );
      textPainter.text = TextSpan(text: label, style: tpStyle);
      textPainter.layout(maxWidth: radius * 0.9);

      // Dilimin orta açısına hizala
      final theta = start + sliceAngle / 2;
      final r = radius * 0.65;
      final offset = center + Offset(math.cos(theta), math.sin(theta)) * r;

      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.rotate(theta + math.pi / 2);
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );
      canvas.restore();
    }

    // Donut efekti vermek için merkeze iç daire çiz
    final inner = Paint()..color = Colors.black.withOpacity(0.08);
    canvas.drawCircle(center, radius * 0.35, inner);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) =>
      oldDelegate.items != items;
}

class _Pointer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(blurRadius: 6, color: Colors.black26, offset: Offset(0, 2)),
        ],
      ),
    );
  }
}

class _CenterBadge extends StatelessWidget {
  final WatchlistMovie movie;
  const _CenterBadge({required this.movie});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            color: Colors.black26,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if ((movie.posterUrl ?? '').isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                movie.posterUrl!,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                // --- ÇÖZÜM BURADA: TARAYICI GİBİ DAVRAN ---
                headers: const {
                  'User-Agent':
                      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  'Accept':
                      'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
                },
                // ----------------------------------------
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 80,
                  height: 80,
                  child: ColoredBox(color: Colors.black12),
                ),
              ),
            )
          else
            const SizedBox(
              width: 80,
              height: 80,
              child: ColoredBox(color: Colors.black12),
            ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              movie.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
        ],
      ),
    );
  }
}