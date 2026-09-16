import 'package:cloud_firestore/cloud_firestore.dart';

class NewsArticle {
  final String id;
  final String title;
  final String slug;
  final String summary;
  final String body;
  final String category;
  final String movieTitle;
  final String imageUrl;
  final String sourceUrl;
  final List<String> tags;
  final String authorName;
  final DateTime? publishedAt;

  const NewsArticle({
    required this.id,
    required this.title,
    required this.slug,
    required this.summary,
    required this.body,
    required this.category,
    required this.movieTitle,
    required this.imageUrl,
    required this.sourceUrl,
    required this.tags,
    required this.authorName,
    required this.publishedAt,
  });

  factory NewsArticle.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final published = data['publishedAt'];

    return NewsArticle(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      slug: (data['slug'] ?? '').toString(),
      summary: (data['summary'] ?? '').toString(),
      body: (data['body'] ?? '').toString(),
      category: (data['category'] ?? 'Haber').toString(),
      movieTitle: (data['movieTitle'] ?? '').toString(),
      imageUrl: (data['imageUrl'] ?? '').toString(),
      sourceUrl: (data['sourceUrl'] ?? '').toString(),
      tags: List<String>.from(data['tags'] ?? const []),
      authorName: (data['authorName'] ?? 'CineMatch Editör').toString(),
      publishedAt: published is Timestamp ? published.toDate() : null,
    );
  }
}
