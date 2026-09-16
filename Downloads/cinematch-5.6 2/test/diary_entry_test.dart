import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttergirdi/models/diary_entry.dart';

void main() {
  test('Diary girdisi ek katalog okuması gerektirmeyen film özeti üretir', () {
    final watchedAt = DateTime(2026, 8, 3, 21, 15);
    final entry = DiaryEntry.fromMovie(
      movieData: {
        'id': 550,
        'title': 'Fight Club',
        'poster_path': '/poster.jpg',
        'release_date': '1999-10-15',
      },
      movieKey: 'tmdb:550',
      source: 'watched',
      watchedAt: watchedAt,
    );

    expect(entry.movieKey, 'tmdb:550');
    expect(entry.tmdbId, 550);
    expect(entry.title, 'Fight Club');
    expect(entry.posterUrl, 'https://image.tmdb.org/t/p/w500/poster.jpg');
    expect(entry.releaseYear, 1999);
    expect(entry.watchedAt, watchedAt);
    expect(entry.id, startsWith('550_'));
    expect(entry.toMap()['watchedAt'], isA<Timestamp>());
  });

  test('Letterboxd Diary girdisi TMDB kimliği olmadan da saklanabilir', () {
    final entry = DiaryEntry.fromMovie(
      movieData: {'title': 'A Matter of Life and Death', 'year': 1946},
      movieKey: 'film:a-matter-of-life-and-death',
      source: 'letterboxd_sync',
      watchedAt: DateTime(2026, 8, 3),
    );

    expect(entry.tmdbId, isNull);
    expect(entry.movieKey, 'film:a-matter-of-life-and-death');
    expect(entry.releaseYear, 1946);
    expect(entry.id, contains('film-a-matter-of-life-and-death'));
  });

  test('Senkron Diary girdisi kararlı olay kimliğini korur', () {
    final entry = DiaryEntry.fromMovie(
      movieData: const {'title': 'Past Lives'},
      movieKey: 'film:past-lives-2023',
      source: 'letterboxd_sync',
      eventId: 'letterboxd_ZmlsbTpwYXN0LWxpdmVzLTIwMjM',
    );

    expect(entry.id, 'letterboxd_ZmlsbTpwYXN0LWxpdmVzLTIwMjM');
  });

  test('Diary özeti güvenlik kuralı alan sınırlarına uyar', () {
    String repeated(String value, int count) =>
        List.filled(count, value).join();

    final entry = DiaryEntry.fromMovie(
      movieData: {'title': repeated('A', 220)},
      posterUrl: 'https://example.com/${repeated('p', 1300)}',
      movieKey: 'film:${repeated('k', 340)}',
      source: repeated('s', 80),
      eventId: repeated('e', 600),
    );

    expect(entry.id.runes.length, 500);
    expect(entry.movieKey.runes.length, 300);
    expect(entry.title.runes.length, 180);
    expect(entry.posterUrl.runes.length, 1200);
    expect(entry.source.runes.length, 64);
  });
}
