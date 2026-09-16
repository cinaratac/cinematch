import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:fluttergirdi/services/user_cache_service.dart';

class _MessageAvatarCacheManager extends CacheManager with ImageCacheManager {
  _MessageAvatarCacheManager()
    : super(
        Config(
          'messageAvatarCache',
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 500,
          repo: JsonCacheInfoRepository(databaseName: 'messageAvatarCache_db'),
        ),
      );
}

class MessageAvatarCacheService {
  MessageAvatarCacheService._();

  static final MessageAvatarCacheService instance =
      MessageAvatarCacheService._();

  static const int cacheSize = 128;

  final _MessageAvatarCacheManager cacheManager = _MessageAvatarCacheManager();
  final Map<String, Future<void>> _pending = {};

  Future<void> ensureCached(String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) return Future.value();

    final existing = _pending[url];
    if (existing != null) return existing;

    final operation = _load(url);
    _pending[url] = operation;
    return operation;
  }

  Future<void> _load(String url) async {
    try {
      await for (final response in cacheManager.getImageFile(
        url,
        maxWidth: cacheSize,
        maxHeight: cacheSize,
      )) {
        if (response is FileInfo) return;
      }
      throw StateError('Avatar indirilemedi.');
    } catch (_) {
      _pending.remove(url);
      rethrow;
    }
  }

  Future<void> preloadChats(
    String currentUid,
    Iterable<Map<String, dynamic>> chats, {
    int limit = 20,
  }) async {
    final urls = <String>{};
    final orderedChats = chats.toList()
      ..sort((a, b) {
        final aTime = a['updatedAt'] is Timestamp
            ? (a['updatedAt'] as Timestamp).toDate()
            : DateTime(2000);
        final bTime = b['updatedAt'] is Timestamp
            ? (b['updatedAt'] as Timestamp).toDate()
            : DateTime(2000);
        return bTime.compareTo(aTime);
      });

    for (final data in orderedChats) {
      if (data['isGroup'] == true || data['isClub'] == true) continue;

      final photos = data['photos'];
      final denormalized = photos is Map
          ? (photos[currentUid] ?? '').toString().trim()
          : '';
      if (denormalized.isNotEmpty) {
        urls.add(denormalized);
      } else {
        final participants = List<String>.from(data['participants'] ?? []);
        final otherUid = participants.firstWhere(
          (uid) => uid != currentUid,
          orElse: () => '',
        );
        final cachedUrl = UserCacheService.instance
            .getFromCache(otherUid)
            ?.photoURL
            .trim();
        if (cachedUrl != null && cachedUrl.isNotEmpty) urls.add(cachedUrl);
      }

      if (urls.length >= limit) break;
    }

    await Future.wait(urls.map((url) => ensureCached(url).catchError((_) {})));
  }
}
