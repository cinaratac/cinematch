import 'package:flutter_test/flutter_test.dart';
import 'package:fluttergirdi/models/blog_post.dart';

void main() {
  test(
    'Blog yazısı yayınlanan yazar, film ve görselleri güvenle ayrıştırır',
    () {
      final publishedAt = DateTime(2026, 8, 3, 12, 30);
      final post = BlogPost.fromMap('post-1', {
        'title': 'Bir Film Yazısı',
        'contentHtml': '<p>İçerik</p>',
        'category': 'İnceleme',
        'authorId': 'author-1',
        'authorName': 'Yazar',
        'readingMinutes': 4,
        'publishedAt': publishedAt,
        'tags': ['sinema', 'dram'],
        'movies': [
          {
            'tmdbId': 550,
            'title': 'Fight Club',
            'year': 1999,
            'posterPath': '/poster.jpg',
          },
          {'tmdbId': 0, 'title': 'Geçersiz'},
        ],
        'images': [
          {'url': 'https://example.com/image.jpg', 'alt': 'Sahne'},
          {'url': ''},
        ],
      });

      expect(post.id, 'post-1');
      expect(post.authorId, 'author-1');
      expect(post.readingMinutes, 4);
      expect(post.publishedAt, publishedAt);
      expect(post.tags, ['sinema', 'dram']);
      expect(post.movies, hasLength(1));
      expect(post.movies.single.tmdbId, 550);
      expect(post.movies.single.year, 1999);
      expect(post.images, hasLength(1));
      expect(post.images.single.alt, 'Sahne');
    },
  );
}
