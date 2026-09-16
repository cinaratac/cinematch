import 'package:cloud_firestore/cloud_firestore.dart';

class CustomList {
  final String id;
  final String ownerId;
  final String title;
  final String description;
  final int movieCount;
  final int likeCount;
  final String? coverImageUrl; // Listenin kapağı (son eklenen filmden)
  final bool isPublic;
  final String ownerName;
  final DateTime createdAt;

  CustomList({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.description,
    this.movieCount = 0,
    this.likeCount = 0,
    this.coverImageUrl,
    required this.ownerName,
    this.isPublic = true,
    required this.createdAt,
  });

  factory CustomList.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CustomList(
      id: doc.id,
      ownerName: data['ownerName'] ?? 'Sinema Sever',
      ownerId: data['ownerId'] ?? '',
      title: data['title'] ?? 'İsimsiz Liste',
      description: data['description'] ?? '',
      movieCount: data['movieCount'] ?? 0,
      likeCount: data['likeCount'] ?? 0,
      coverImageUrl: data['coverImageUrl'],
      isPublic: data['isPublic'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}