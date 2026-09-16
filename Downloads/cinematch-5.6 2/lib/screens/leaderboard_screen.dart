import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/gamification.dart';
import 'package:fluttergirdi/services/gamification_service.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 3, 
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          
          title: const Text(
            'Liderlik Tablosu', 
            style: TextStyle(fontWeight: FontWeight.bold)
          ),

          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Container(
              height: 45,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12), 
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: cs.surface, 
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                labelColor: cs.onSurface,
                unselectedLabelColor: cs.onSurfaceVariant,
                labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                tabs: const [
                  Tab(text: 'En Popüler'),
                  Tab(text: 'En Sinefiller'),
                  Tab(text: 'Yarışma Liderleri'), 
                ],
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            _LeaderboardList(
              fetcher: GamificationService.instance.getWeeklyTopUsers, 
              metricLabel: 'Takipçi'
            ),
            _LeaderboardList(
              fetcher: GamificationService.instance.getTopFilmBuffs,
              metricLabel: 'Film',
            ),
            // 3. YENİ TAB (GENEL PUAN)
            const _TriviaRankingTab(),
          ],
        ),
      ),
    );
  }
}

// --- DİĞER TABLAR İÇİN ORTAK WIDGET (AYNI KALDI) ---
class _LeaderboardList extends StatelessWidget {
  final Future<List<LeaderboardUser>> Function() fetcher;
  final String metricLabel;

  const _LeaderboardList({required this.fetcher, required this.metricLabel});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LeaderboardUser>>(
      future: fetcher(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final users = snap.data ?? [];
        
        if (users.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.emoji_events_outlined, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                const Text("Henüz veri yok.", style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final user = users[index];
            return _buildRankItem(
              context: context,
              index: index,
              rank: user.rank,
              uid: user.uid,
              displayName: user.displayName,
              photoURL: user.photoURL,
              scoreText: '${user.score} $metricLabel',
            );
          },
        );
      },
    );
  }
}

// --- TRIVIA TABI (TOPLAM PUANA GÖRE GÜNCELLENDİ) ---
class _TriviaRankingTab extends StatelessWidget {
  const _TriviaRankingTab();

  @override
  Widget build(BuildContext context) {
    // ARTIK HAFTALIK ID YERİNE GENEL 'users' TABLOSUNA BAKIYORUZ
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
      .orderBy('totalTriviaScore', descending: true)
      .where('totalTriviaScore', isGreaterThan: 0)
      .limit(50)
      .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.quiz_outlined, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                const Text("Henüz kimse puan kazanmamış.", style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final uid = docs[index].id;
            final displayName = data['displayName'] ?? data['username'] ?? 'Gizli';
            final score = data['totalTriviaScore'] ?? 0;
            final photoURL = data['photoURL'] as String?;

            return _buildRankItem(
              context: context,
              index: index,
              rank: index + 1,
              uid: uid,
              displayName: displayName,
              photoURL: photoURL,
              scoreText: '$score Puan', // Toplam Puan
            );
          },
        );
      },
    );
  }
}

// --- ORTAK TASARIM WIDGETI ---
Widget _buildRankItem({
  required BuildContext context,
  required int index,
  required int rank,
  required String uid,
  required String displayName,
  required String? photoURL,
  required String scoreText,
}) {
  Color? bgColor;
  Color? borderColor;
  Color rankBadgeColor;
  bool showCrown = false;

  if (index == 0) {
    bgColor = const Color(0xFFFFD700).withOpacity(0.15);
    borderColor = const Color(0xFFFFD700);
    rankBadgeColor = const Color(0xFFFFD700);
    showCrown = true;
  } else if (index == 1) {
    bgColor = const Color(0xFFC0C0C0).withOpacity(0.15);
    borderColor = const Color(0xFFC0C0C0);
    rankBadgeColor = const Color(0xFFC0C0C0);
  } else if (index == 2) {
    bgColor = const Color(0xFFCD7F32).withOpacity(0.15);
    borderColor = const Color(0xFFCD7F32);
    rankBadgeColor = const Color(0xFFCD7F32);
  } else {
    bgColor = Theme.of(context).colorScheme.surfaceContainerLow;
    borderColor = Colors.transparent;
    rankBadgeColor = Theme.of(context).colorScheme.surfaceContainerHighest;
  }

  return GestureDetector(
    onTap: () {
      if (uid.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: uid)),
        );
      }
    },
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: index < 3 ? 1.5 : 0
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: rankBadgeColor,
              shape: BoxShape.circle,
            ),
            child: Text(
              '#$rank',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: index < 3 ? Colors.black : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.grey.shade800,
                backgroundImage: (photoURL != null && photoURL.isNotEmpty)
                    ? NetworkImage(photoURL)
                    : null,
                child: (photoURL == null || photoURL.isEmpty)
                    ? const Icon(Icons.person, size: 24)
                    : null,
              ),
              if (showCrown)
                Positioned(
                  top: -12,
                  right: -6,
                  child: Transform.rotate(
                    angle: 0.2,
                    child: const Icon(
                      Icons.workspace_premium, 
                      color: Color(0xFFFFD700),
                      size: 28,
                      shadows: [
                        Shadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1))
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              scoreText,
              style: TextStyle(
                fontSize: 12, 
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onPrimaryContainer
              ),
            ),
          ),
        ],
      ),
    ),
  );
}