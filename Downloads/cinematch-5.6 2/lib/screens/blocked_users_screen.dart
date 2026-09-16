import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/services/blocking_service.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final String? _currentUid = FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_currentUid == null) {
      return const Scaffold(
        body: Center(child: Text('Giriş yapılmış bir kullanıcı bulunamadı.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Engellenen Kullanıcılar'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUid)
            .collection('blocked')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Text(
                'Engellenen kullanıcı bulunmuyor.',
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
              ),
            );
          }

          return ListView.separated(
            itemCount: docs.length,
            padding: const EdgeInsets.symmetric(vertical: 12),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final targetUid = docs[index].id;

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(targetUid)
                    .get(),
                builder: (context, userSnap) {
                  if (!userSnap.hasData) {
                    return const ListTile(
                      title: Text('Yükleniyor...'),
                    );
                  }

                  final data = userSnap.data!.data() as Map<String, dynamic>?;
                  if (data == null) {
                    return const SizedBox.shrink();
                  }

                  // Profil bilgilerini güvenli bir şekilde çekiyoruz
                  final name = data['displayName'] ?? data['username'] ?? 'Kullanıcı';
                  final photo = data['photoURL'];

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.grey.shade800,
                      backgroundImage: (photo != null && photo.toString().isNotEmpty)
                          ? NetworkImage(photo.toString())
                          : null,
                      child: (photo == null || photo.toString().isEmpty)
                          ? const Icon(Icons.person, color: Colors.white)
                          : null,
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    trailing: OutlinedButton(
                      onPressed: () async {
                        // Engeli kaldır aksiyonu (BlockingService kullanılıyor)
                        await BlockingService.instance.unblockUser(
                          currentUserId: _currentUid,
                          targetUserId: targetUid,
                        );

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('$name adlı kullanıcının engeli kaldırıldı.'),
                            ),
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      ),
                      child: const Text('Engeli Kaldır', style: TextStyle(fontSize: 12)),
                    ),
                    onTap: () {
                      // Kullanıcının profiline gitme aksiyonu
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PublicProfileScreen(uid: targetUid),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}