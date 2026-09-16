import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/date_helper.dart';
import 'trivia_quiz_screen.dart';
import 'trivia_leaderboard_screen.dart';

class TriviaWelcomeScreen extends StatefulWidget {
  const TriviaWelcomeScreen({super.key});

  @override
  State<TriviaWelcomeScreen> createState() => _TriviaWelcomeScreenState();
}

class _TriviaWelcomeScreenState extends State<TriviaWelcomeScreen> {
  bool _checkingStatus = true;
  bool _alreadyPlayed = false;
  bool _isQuizReady = false;
  int _myScore = 0;

  @override
  void initState() {
    super.initState();
    _checkPlayStatus();
  }

  Future<void> _checkPlayStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final weekId = DateHelper.getCurrentWeekId();
    final db = FirebaseFirestore.instance;

    try {
      final scoreFuture = db
          .collection('weekly_leaderboard')
          .doc(weekId)
          .collection('scores')
          .doc(user.uid)
          .get();

      final countFuture = db
          .collection('trivia_questions')
          .where('weekId', isEqualTo: weekId)
          .where('isActive', isEqualTo: true)
          .count()
          .get();

      final results = await Future.wait([scoreFuture, countFuture]);

      final scoreDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final countSnapshot = results[1] as AggregateQuerySnapshot;

      if (mounted) {
        setState(() {
          _alreadyPlayed = scoreDoc.exists;
          if (scoreDoc.exists) {
            _myScore = scoreDoc.data()?['score'] ?? 0;
          }

          final questionCount = countSnapshot.count;
          _isQuizReady = questionCount == 10; 
          
          _checkingStatus = false;
        });
      }
    } catch (e) {
      debugPrint("Hata: $e");
      if (mounted) setState(() => _checkingStatus = false);
    }
  }

  void _startQuiz() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const TriviaQuizScreen()),
    );
  }

  void _openLeaderboard() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TriviaLeaderboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E), // Koyu tema
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
      ),
      body: _checkingStatus
          ? const Center(child: CircularProgressIndicator())
          : SizedBox( // DÜZELTME 1: Ekranın tam genişliğini alması için SizedBox eklendi
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center, // DÜZELTME 2: İçerikleri yatayda ortala
                  children: [
                    // --- ORTAK İKON ---
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: (_isQuizReady || _alreadyPlayed) 
                            ? Colors.amber.withOpacity(0.2) 
                            : Colors.grey.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        (_isQuizReady || _alreadyPlayed) ? Icons.emoji_events_rounded : Icons.construction, 
                        size: 80, 
                        color: (_isQuizReady || _alreadyPlayed) ? Colors.amber : Colors.grey
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // --- İÇERİK KONTROLÜ ---
                    if (_alreadyPlayed) ...[
                      // DURUM 1: ZATEN OYNADI
                      const Text(
                        "Haftalık Yarışma",
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        "Bu haftaki hakkını kullandın!\nPuanın: $_myScore",
                        style: const TextStyle(fontSize: 18, color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        ),
                        onPressed: _openLeaderboard,
                        icon: const Icon(Icons.leaderboard),
                        label: const Text("Liderlik Tablosu"),
                      ),

                    ] else if (!_isQuizReady) ...[
                      // DURUM 2: SORULAR HAZIR DEĞİL
                      const Text(
                        "Hazırlıklar Sürüyor!",
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        "Bu haftanın sinema soruları editörlerimiz tarafından hazırlanıyor.\n\nLütfen daha sonra tekrar kontrol et.",
                        style: TextStyle(fontSize: 16, color: Colors.white70, height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Geri Dön", style: TextStyle(color: Colors.white)),
                      ),

                    ] else ...[
                      // DURUM 3: OYNAMADI VE HAZIR
                      const Text(
                        "Haftalık Sinema Yarışması",
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      _buildRuleRow(Icons.refresh, "Yarışma her hafta yenilenir."),
                      _buildRuleRow(Icons.timer, "Her soru için 30 saniyen var."),
                      _buildRuleRow(Icons.quiz, "Toplam 10 soru."),
                      _buildRuleRow(Icons.star, "Her soru 10 puan değerinde."),
                      _buildRuleRow(Icons.block, "Sadece 1 kez katılabilirsin!"),
                      
                      const Spacer(),
                      
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _startQuiz,
                          child: const Text("YARIŞMAYA BAŞLA", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildRuleRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.amber, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 16))),
        ],
      ),
    );
  }
}