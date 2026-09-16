import 'package:cloud_firestore/cloud_firestore.dart';

class BlogPost {
  final String id;
  final String title;
  final String slug;
  final String excerpt;
  final String contentHtml;
  final String contentText;
  final String category;
  final List<String> tags;
  final List<BlogMovie> movies;
  final List<BlogImage> images;
  final String coverImageUrl;
  final int readingMinutes;
  final String authorId;
  final String authorName;
  final String authorUsername;
  final String authorPhotoUrl;
  final DateTime? publishedAt;
  final DateTime? updatedAt;

  const BlogPost({
    required this.id,
    required this.title,
    required this.slug,
    required this.excerpt,
    required this.contentHtml,
    required this.contentText,
    required this.category,
    required this.tags,
    required this.movies,
    required this.images,
    required this.coverImageUrl,
    required this.readingMinutes,
    required this.authorId,
    required this.authorName,
    required this.authorUsername,
    required this.authorPhotoUrl,
    required this.publishedAt,
    required this.updatedAt,
  });

  factory BlogPost.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) =>
      BlogPost.fromMap(doc.id, doc.data() ?? const {});

  factory BlogPost.fromMap(String id, Map<String, dynamic> data) {
    final rawMovies = data['movies'];
    final rawImages = data['images'];

    return BlogPost(
      id: id,
      title: _text(data['title']),
      slug: _text(data['slug']),
      excerpt: _text(data['excerpt']),
      contentHtml: _text(data['contentHtml']),
      contentText: _text(data['contentText']),
      category: _text(data['category'], fallback: 'İnceleme'),
      tags: _stringList(data['tags']),
      movies: rawMovies is List
          ? rawMovies
                .whereType<Map>()
                .map(
                  (item) => BlogMovie.fromMap(Map<String, dynamic>.from(item)),
                )
                .where((movie) => movie.tmdbId > 0)
                .toList(growable: false)
          : const [],
      images: rawImages is List
          ? rawImages
                .whereType<Map>()
                .map(
                  (item) => BlogImage.fromMap(Map<String, dynamic>.from(item)),
                )
                .where((image) => image.url.isNotEmpty)
                .toList(growable: false)
          : const [],
      coverImageUrl: _text(data['coverImageUrl']),
      readingMinutes: _positiveInt(data['readingMinutes']),
      authorId: _text(data['authorId']),
      authorName: _text(data['authorName'], fallback: 'CineMatch Blogger'),
      authorUsername: _text(data['authorUsername']),
      authorPhotoUrl: _text(data['authorPhotoUrl']),
      publishedAt: _date(data['publishedAt']),
      updatedAt: _date(data['updatedAt']),
    );
  }
}

class BlogMovie {
  final int tmdbId;
  final String title;
  final String originalTitle;
  final int? year;
  final String posterPath;
  final String posterUrl;

  const BlogMovie({
    required this.tmdbId,
    required this.title,
    required this.originalTitle,
    required this.year,
    required this.posterPath,
    required this.posterUrl,
  });

  factory BlogMovie.fromMap(Map<String, dynamic> data) {
    final rawYear = data['year'];
    return BlogMovie(
      tmdbId: _positiveInt(data['tmdbId']),
      title: _text(data['title']),
      originalTitle: _text(data['originalTitle']),
      year: rawYear is num ? rawYear.toInt() : int.tryParse(_text(rawYear)),
      posterPath: _text(data['posterPath']),
      posterUrl: _text(data['posterUrl']),
    );
  }
}

class BlogImage {
  final String url;
  final String alt;

  const BlogImage({required this.url, required this.alt});

  factory BlogImage.fromMap(Map<String, dynamic> data) =>
      BlogImage(url: _text(data['url']), alt: _text(data['alt']));
}

String _text(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

int _positiveInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse(_text(value));
  return parsed != null && parsed > 0 ? parsed : 0;
}

DateTime? _date(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return DateTime.tryParse(_text(value));
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map(_text)
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
