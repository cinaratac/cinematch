import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/gamification.dart';
import 'package:fluttergirdi/services/follow_system_service.dart';
import 'package:share_plus/share_plus.dart';

class BadgesProgressScreen extends StatefulWidget {
  const BadgesProgressScreen({super.key});

  @override
  State<BadgesProgressScreen> createState() => _BadgesProgressScreenState();
}
// --- RAM ÖNBELLEK SİSTEMİ (GİR-ÇIK YAPINCA YENİDEN YÜKLEMEYİ ÖNLER) ---
class _BadgeProgressCache {
  static Map<String, double>? progress;
  static Map<String, String>? labels;
  static DateTime? lastFetch;

  // Veriler son 5 dakika içinde yüklendiyse geçerli sayılır
  static bool get isValid =>
      progress != null &&
      labels != null &&
      lastFetch != null &&
      DateTime.now().difference(lastFetch!) < const Duration(minutes: 5);

  static void update(Map<String, double> p, Map<String, String> l) {
    progress = p;
    labels = l;
    lastFetch = DateTime.now();
  }
}
class _BadgesProgressScreenState extends State<BadgesProgressScreen> {
  bool _loading = true;
  final Map<String, double> _progress = {}; // BadgeID -> Yüzde (0.0 - 1.0)
  final Map<String, String> _labels = {};   // BadgeID -> "85/100"

  @override
  void initState() {
    super.initState();
    _calculateProgress();
  }

  Future<void> _calculateProgress() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    // 1. ÖNBELLEK KONTROLÜ: Eğer veriler yakın zamanda çekildiyse hiç beklemeden anında göster!
    if (_BadgeProgressCache.isValid) {
      setState(() {
        _progress.addAll(_BadgeProgressCache.progress!);
        _labels.addAll(_BadgeProgressCache.labels!);
        _loading = false;
      });
      return;
    }

    final db = FirebaseFirestore.instance;
    
    try {
      // 2. PARALEL SORGULAR: Tüm verileri arka arkaya değil, "Aynı Anda" çek (Yüklemeyi 4 Kat Hızlandırır)
      final results = await Future.wait([
        db.collection('users').doc(uid).get(const GetOptions(source: Source.serverAndCache)),
        db.collection('posts').where('authorId', isEqualTo: uid).where('isReview', isEqualTo: true).count().get(),
        db.collection('custom_lists').where('ownerId', isEqualTo: uid).count().get(),
        FollowSystemService.I.fetchFollowerCountOnce(uid),
      ]);

      // Sonuçları değişkenlere dağıt
      final userDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final postsSnap = results[1] as AggregateQuerySnapshot;
      final listSnap = results[2] as AggregateQuerySnapshot;
      final followersCount = results[3] as int;

      final userData = userDoc.data() ?? {};
      final List<String> ownedBadges = List<String>.from(userData['badges'] ?? []);

      // Film Kurdu Verisi (Bir önceki düzeltmemiz olan "watchedKeys" de burada duruyor)
      final uniqueMovies = {
        ...List.from(userData['favoritesKeys'] ?? []),
        ...List.from(userData['fiveStarKeys'] ?? []),
        ...List.from(userData['watchlistKeys'] ?? []),
        ...List.from(userData['dislikedKeys'] ?? []),
        ...List.from(userData['watchedKeys'] ?? []) // <-- İZLEDİM LİSTESİ BURADA!
      }.length;

      final reviewCount = postsSnap.count ?? 0;
      final listCount = listSnap.count ?? 0;

      if (!mounted) return;

      final Map<String, double> tempProgress = {};
      final Map<String, String> tempLabels = {};

      for (var badge in AppBadge.allBadges) {
        int current = 0;
        switch (badge.type) {
          case BadgeType.filmBuff: current = uniqueMovies; break;
          case BadgeType.critic: current = reviewCount; break;
          case BadgeType.archivist: current = listCount; break;
          case BadgeType.socialite: current = followersCount; break;
          default: current = 0;
        }

        double pct = (current / badge.threshold).clamp(0.0, 1.0);
        if (ownedBadges.contains(badge.id)) {
          pct = 1.0;
        }
        
        tempProgress[badge.id] = pct;
        tempLabels[badge.id] = '$current / ${badge.threshold}';
      }

      // 3. Çekilen ve hesaplanan bu yeni veriyi RAM'e (Önbelleğe) yaz
      _BadgeProgressCache.update(tempProgress, tempLabels);

      setState(() {
        _progress.addAll(tempProgress);
        _labels.addAll(tempLabels);
        _loading = false;
      });

    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }
  int get _earnedCount => _progress.values.where((p) => p >= 1.0).length;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: cs.surface,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 260,
                  pinned: true,
                  stretch: true,
                  backgroundColor: cs.surface,
                  surfaceTintColor: Colors.transparent,
                  flexibleSpace: FlexibleSpaceBar(
                    background: _HeaderSection(
                      earned: _earnedCount,
                      total: AppBadge.allBadges.length,
                    ),
                  ),
                  title: _earnedCount > -1 ? null : const Text("Başarılar"), 
                ),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final badge = AppBadge.allBadges[index];
                        return _BadgeCard(
                          badge: badge,
                          progress: _progress[badge.id] ?? 0.0,
                          label: _labels[badge.id] ?? '',
                          onTap: () => _showBadgeDetails(context, badge, _progress[badge.id] ?? 0.0, _labels[badge.id] ?? ''),
                        );
                      },
                      childCount: AppBadge.allBadges.length,
                    ),
                  ),
                ),
                
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
    );
  }

  void _showBadgeDetails(BuildContext context, AppBadge badge, double progress, String label) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BadgeDetailSheet(badge: badge, progress: progress, label: label),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  final int earned;
  final int total;
  const _HeaderSection({required this.earned, required this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = (total == 0) ? 0.0 : (earned / total);

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                cs.primary.withOpacity(0.15),
                cs.surface,
              ],
            ),
          ),
        ),
        Positioned(
          top: -50, right: -50,
          child: Container(
            width: 200, height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withOpacity(0.05),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'BAŞARI SEVİYESİ',
                style: TextStyle(letterSpacing: 2, fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: 1.0,
                        color: cs.surfaceContainerHighest,
                        strokeWidth: 10,
                      ),
                    ),
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: pct,
                        color: cs.primary,
                        strokeCap: StrokeCap.round,
                        strokeWidth: 10,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(pct * 100).toInt()}%',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: cs.primary),
                        ),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '$earned / $total Rozet Kazanıldı',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BadgeCard extends StatelessWidget {
  final AppBadge badge;
  final double progress;
  final String label;
  final VoidCallback onTap;

  const _BadgeCard({required this.badge, required this.progress, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isCompleted = progress >= 1.0;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              badge.color.withOpacity(0.15),
              Theme.of(context).colorScheme.surfaceContainer,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: isCompleted ? badge.color.withOpacity(0.6) : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: badge.color.withOpacity(isCompleted ? 0.25 : 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 80,
              decoration: BoxDecoration(
                color: badge.color.withOpacity(0.2),
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
              ),
              child: Center(
                child: Hero(
                  tag: 'badge_${badge.id}',
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                         BoxShadow(
                           color: badge.color.withOpacity(0.4),
                           blurRadius: 15,
                           spreadRadius: -2,
                         )
                      ]
                    ),
                    child: Icon(badge.icon, size: 36, color: badge.color),
                  ),
                ),
              ),
            ),
            
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      badge.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      badge.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: Colors.black12,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  return Container(
                                    height: 6,
                                    width: constraints.maxWidth * progress,
                                    decoration: BoxDecoration(
                                      color: badge.color,
                                      borderRadius: BorderRadius.circular(4),
                                      boxShadow: [
                                        BoxShadow(color: badge.color.withOpacity(0.6), blurRadius: 4)
                                      ]
                                    ),
                                  );
                                }
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label, 
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badge.color),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Icon(
                isCompleted ? Icons.workspace_premium : Icons.lock_outline,
                color: isCompleted ? Colors.amber : Colors.grey.withOpacity(0.4),
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeDetailSheet extends StatelessWidget {
  final AppBadge badge;
  final double progress;
  final String label;

  const _BadgeDetailSheet({required this.badge, required this.progress, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // İlerleme tamamlandı mı kontrolü
    final isCompleted = progress >= 1.0;

    return Container(
      // ... (Dekorasyon kodları aynı kalacak)
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ... (Üst kısımdaki ikon, başlık, açıklama ve ilerleme çubuğu kodları aynı kalacak)
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 32),

          Hero(
            tag: 'badge_${badge.id}',
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: badge.color.withOpacity(0.15),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: badge.color.withOpacity(0.5), blurRadius: 40, spreadRadius: 5)
                ]
              ),
              child: Icon(badge.icon, size: 64, color: badge.color),
            ),
          ),
          const SizedBox(height: 24),

          Text(badge.name, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(badge.description, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
          
          const SizedBox(height: 32),
          
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isCompleted ? Colors.green.withOpacity(0.3) : Colors.transparent),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isCompleted ? Icons.check_circle : Icons.timelapse, color: isCompleted ? Colors.green : Colors.orange),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isCompleted ? 'ROZET KAZANILDI' : 'DEVAM EDİYOR', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
                    Text(isCompleted ? 'Tebrikler!' : 'İlerleme: $label', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: BorderSide(color: theme.colorScheme.outline),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Kapat'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    // --- PAYLAŞILACAK METNİ DE GÜNCELLEDİK ---
                    // Eğer kazanıldıysa "Kazandım", kazanılmadıysa "Kazanmak Üzereyim" yazsın.
                    final text = isCompleted 
                        ? "CineMatch uygulamasında '${badge.name}' rozetini kazandım! 🎬✨ https://play.google.com/store/apps/details?id=com.kozmosoft.cinematch&hl=tr"
                        : "CineMatch uygulamasında '${badge.name}' rozetini kazanmak üzereyim! 🚀 https://play.google.com/store/apps/details?id=com.kozmosoft.cinematch&hl=tr ";
                    
                    try {
                        Share.share(text); 
                    } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Paylaşım özelliği şu an kullanılamıyor.')),
                        );
                    }
                  },
                  icon: const Icon(Icons.share),
                  // --- BUTON METNİ BURADA GÜNCELLENDİ ---
                  label: Text(
                    'Rozeti Paylaş',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), // Sığması için fontu biraz küçültebiliriz
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8), // Padding'i ayarladık
                    backgroundColor: badge.color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    shadowColor: badge.color.withOpacity(0.4),
                    elevation: 8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}