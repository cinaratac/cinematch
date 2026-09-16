import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationSettingsService {
  static final NotificationSettingsService instance = NotificationSettingsService._();
  NotificationSettingsService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> toggleMuteChat(String chatId, bool isMuted, List<String> currentList) async {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    final userRef = _firestore.collection('users').doc(currentUid);

    // Mevcut listenin bir kopyasını alıyoruz
    List<String> updatedList = List<String>.from(currentList);

    if (isMuted) {
      if (!updatedList.contains(chatId)) {
        updatedList.add(chatId);
      }
    } else {
      updatedList.remove(chatId);
    }

    // arrayUnion veya arrayRemove YERİNE listenin tamamını üzerine yazıyoruz
    await userRef.update({
      'mutedChats': updatedList
    });
  }

  Stream<List<String>> getMutedChatsStream() {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    return _firestore.collection('users').doc(currentUid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data != null && data.containsKey('mutedChats')) {
        return List<String>.from(data['mutedChats'] ?? []);
      }
      return [];
    });
  }
}