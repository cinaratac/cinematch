import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/date_helper.dart';
import 'public_profile_screen.dart'; // <--- BU IMPORT ÖNEMLİ (Profil Sayfası İçin)

class TriviaLeaderboardScreen extends StatelessWidget {
  const TriviaLeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final weekId = DateHelper.getCurrentWeekId();
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E), // Koyu Lacivert Tema
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Haftanın Liderleri", style: TextStyle(color: Colors.white)),
        centerTitle: true,
        leading: const BackButton(color: Colors.white),
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance
            .collection('weekly_leaderboard')
            .doc(weekId)
            .collection('scores')
            .orderBy('score', descending: true)
            .orderBy('timestamp', descending: false)
            .limit(50)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("Hata oluştu", style: TextStyle(color: Colors.white)));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.amber));
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.leaderboard, size: 60, color: Colors.white24),
                  SizedBox(height: 16),
                  Text("Henüz kimse yarışmadı.\nİlk sen ol!", 
                    textAlign: TextAlign.center, 
                    style: TextStyle(color: Colors.white54)
                  ),
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
              
              final uid = data['uid'] ?? '';
              final displayName = data['displayName'] ?? 'Kullanıcı';
              final score = data['score'] ?? 0;
              final photoURL = data['photoURL'] as String?;
              
              final isMe = uid == myUid;
              
              // Sıralama renkleri (Altın, Gümüş, Bronz)
              Color rankColor = Colors.white70;
              if (index == 0) rankColor = const Color(0xFFFFD700); 
              else if (index == 1) rankColor = const Color(0xFFC0C0C0); 
              else if (index == 2) rankColor = const Color(0xFFCD7F32); 

              return Container(
                decoration: BoxDecoration(
                  // Ben isem arkaplanı belirginleştir
                  color: isMe 
                      ? Colors.indigo.withOpacity(0.6) 
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: isMe ? Border.all(color: Colors.indigoAccent, width: 1.5) : null,
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  
                  // --- SOL TARAFTA (Rank + Avatar) ---
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. Sıralama Numarası (#1, #2...)
                      SizedBox(
                        width: 30,
                        child: Text(
                          "${index + 1}",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: rankColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 2. Profil Resmi (Varsa Göster)
                      GestureDetector(
                        onTap: () {
                          if (uid.isNotEmpty) {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: uid)));
                          }
                        },
                        child: CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.grey.shade800,
                          backgroundImage: (photoURL != null && photoURL.isNotEmpty) 
                              ? NetworkImage(photoURL) 
                              : null,
                          child: (photoURL == null || photoURL.isEmpty)
                              ? const Icon(Icons.person, color: Colors.white70)
                              : null,
                        ),
                      ),
                    ],
                  ),

                  // --- ORTA (İsim) ---
                  title: Text(
                    displayName,
                    style: TextStyle(
                      color: Colors.white, 
                      fontWeight: isMe ? FontWeight.bold : FontWeight.w500,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  // --- SAĞ (Puan) ---
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.amber.withOpacity(0.4), blurRadius: 8, spreadRadius: 0)
                      ]
                    ),
                    child: Text(
                      "$score P",
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 14),
                    ),
                  ),

                  // --- TIKLAMA (Profile Git) ---
                  onTap: () {
                    // Kullanıcı satıra tıklarsa profiline git
                    if (uid.isNotEmpty) {
                      Navigator.push(
                        context, 
                        MaterialPageRoute(builder: (_) => PublicProfileScreen(uid: uid))
                      );
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}