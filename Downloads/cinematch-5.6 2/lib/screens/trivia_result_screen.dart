import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/date_helper.dart';
import 'trivia_leaderboard_screen.dart';

class TriviaResultScreen extends StatefulWidget {
  final int score;
  final int totalQuestions;

  const TriviaResultScreen({super.key, required this.score, required this.totalQuestions});

  @override
  State<TriviaResultScreen> createState() => _TriviaResultScreenState();
}

class _TriviaResultScreenState extends State<TriviaResultScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _saving = true;

  @override
  void initState() {
    super.initState();
    // Havalı animasyon için
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();
    
    _saveResults();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveResults() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final weekId = DateHelper.getCurrentWeekId();
    final db = FirebaseFirestore.instance;

    // Batch işlemi: Ya hepsi yazılır ya hiçbiri (Güvenlik için)
    final batch = db.batch();

    // 1. Kullanıcının kişisel geçmişine kaydet
    final userHistoryRef = db.collection('users').doc(user.uid).collection('trivia_history').doc(weekId);
    batch.set(userHistoryRef, {
      'score': widget.score,
      'date': FieldValue.serverTimestamp(),
      'weekId': weekId,
    });

    // 2. Haftalık Liderlik Tablosuna Kaydet (Haftalık birincileri seçmek için bu kalabilir)
    final leaderboardRef = db.collection('weekly_leaderboard').doc(weekId).collection('scores').doc(user.uid);
    
    final userDoc = await db.collection('users').doc(user.uid).get();
    final userData = userDoc.data();
    
    batch.set(leaderboardRef, {
      'score': widget.score,
      'uid': user.uid,
      'displayName': userData?['displayName'] ?? userData?['username'] ?? 'Gizli Kullanıcı',
      'photoURL': userData?['photoURL'] ?? '',
      'timestamp': FieldValue.serverTimestamp(),
    });

    // --- YENİ EKLENEN KISIM: TOPLAM PUANI GÜNCELLE ---
    // Kullanıcının ana dökümanındaki 'totalTriviaScore' alanını artırıyoruz.
    final userRef = db.collection('users').doc(user.uid);
    batch.set(userRef, {
      'totalTriviaScore': FieldValue.increment(widget.score),
    }, SetOptions(merge: true));
    // ------------------------------------------------

    await batch.commit();

    if (mounted) {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.amber, width: 4),
                  boxShadow: [
                    BoxShadow(color: Colors.amber.withOpacity(0.5), blurRadius: 30, spreadRadius: 5)
                  ]
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("PUANIN", style: TextStyle(color: Colors.white70, fontSize: 16, letterSpacing: 2)),
                    Text(
                      "${widget.score}",
                      style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            
            if (_saving)
              const Text("Sonucun Kaydediliyor...", style: TextStyle(color: Colors.white54))
            else ...[
              const Text("Tebrikler!", style: TextStyle(color: Colors.amber, fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(
                "Bu haftaki yarışmayı tamamladın.",
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 40),
              
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                    context, 
                    MaterialPageRoute(builder: (_) => const TriviaLeaderboardScreen())
                  );
                },
                icon: const Icon(Icons.leaderboard),
                label: const Text("Liderlik Tablosunu Gör"),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text("Ana Menüye Dön", style: TextStyle(color: Colors.white54)),
              )
            ]
          ],
        ),
      ),
    );
  }
}