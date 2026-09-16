import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fluttergirdi/models/diary_entry.dart';

class DiaryPage {
  final List<DiaryEntry> entries;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;
  final bool hasMore;

  const DiaryPage({
    required this.entries,
    required this.lastDocument,
    required this.hasMore,
  });
}

/// Read-efficient access to a user's denormalized diary.
///
/// The first page is kept in memory, pagination uses one-shot queries, and no
/// live listener is opened. This keeps repeated profile/diary visits from
/// generating unnecessary reads.
class DiaryService {
  DiaryService._();

  static final DiaryService instance = DiaryService._();
  static const int defaultPageSize = 30;
  static const Duration _firstPageTtl = Duration(minutes: 5);
  static const int _maxCachedProfiles = 40;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Map<String, _CachedFirstPage> _firstPageCache = {};
  final Map<String, Future<DiaryPage>> _pendingFirstPages = {};
  final Map<String, int> _cacheGenerations = {};

  DocumentReference<Map<String, dynamic>> _entryReference(
    String uid,
    String eventId,
  ) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('diary')
        .doc(eventId);
  }

  /// Adds the diary write to the caller's existing batch, keeping this event
  /// atomic with the associated shelf/profile update.
  void addToBatch(WriteBatch batch, String uid, DiaryEntry entry) {
    if (uid.trim().isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'uid cannot be empty.');
    }
    batch.set(_entryReference(uid, entry.id), {
      ...entry.toMap(),
      'recordedAt': FieldValue.serverTimestamp(),
    });
    invalidate(uid);
  }

  /// Transaction kullanan seyrek senkron akışları için aynı denormalize olayı
  /// ekler. Transaction'ın tüm okumaları tamamlandıktan sonra çağrılmalıdır.
  void addToTransaction(Transaction transaction, String uid, DiaryEntry entry) {
    if (uid.trim().isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'uid cannot be empty.');
    }
    transaction.set(_entryReference(uid, entry.id), {
      ...entry.toMap(),
      'recordedAt': FieldValue.serverTimestamp(),
    });
    invalidate(uid);
  }

  /// Prepends [entry] to the denormalized profile preview and caps it at five.
  /// This method performs no read; callers should pass the user data they
  /// already have in memory and write the returned value in the same batch.
  List<Map<String, dynamic>> mergeRecent(Object? current, DiaryEntry entry) {
    final merged = <Map<String, dynamic>>[entry.toMap()];
    final seenIds = <String>{entry.id};

    if (current is Iterable) {
      for (final raw in current) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final id = item['id']?.toString() ?? '';
        if (id.isNotEmpty && !seenIds.add(id)) continue;
        merged.add(item);
        if (merged.length == 5) break;
      }
    }

    return merged;
  }

  /// Fetches one page. Only the first page is memoized; later pages are read
  /// exactly once per explicit pagination request from the screen.
  Future<DiaryPage> fetchPage({
    required String uid,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = defaultPageSize,
    bool forceRefresh = false,
  }) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      return const DiaryPage(entries: [], lastDocument: null, hasMore: false);
    }
    final normalizedLimit = limit.clamp(1, 100);
    final isFirstPage = startAfter == null;

    if (isFirstPage && forceRefresh) invalidate(normalizedUid);
    if (isFirstPage && !forceRefresh) {
      final cached = _firstPageCache[normalizedUid];
      if (cached != null &&
          cached.limit == normalizedLimit &&
          DateTime.now().difference(cached.cachedAt) < _firstPageTtl) {
        return cached.page;
      }
      if (cached != null) _firstPageCache.remove(normalizedUid);
      final pending = _pendingFirstPages[normalizedUid];
      if (pending != null) return pending;
    }

    final generation = _cacheGenerations[normalizedUid] ?? 0;
    final future = _queryPage(
      uid: normalizedUid,
      startAfter: startAfter,
      limit: normalizedLimit,
    );
    if (!isFirstPage) return future;

    _pendingFirstPages[normalizedUid] = future;
    try {
      final page = await future;
      if ((_cacheGenerations[normalizedUid] ?? 0) == generation) {
        _firstPageCache[normalizedUid] = _CachedFirstPage(
          limit: normalizedLimit,
          page: page,
          cachedAt: DateTime.now(),
        );
        while (_firstPageCache.length > _maxCachedProfiles) {
          _firstPageCache.remove(_firstPageCache.keys.first);
        }
      }
      return page;
    } finally {
      if (identical(_pendingFirstPages[normalizedUid], future)) {
        _pendingFirstPages.remove(normalizedUid);
      }
    }
  }

  Future<DiaryPage> getPage({
    required String uid,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = defaultPageSize,
    bool forceRefresh = false,
  }) {
    return fetchPage(
      uid: uid,
      startAfter: startAfter,
      limit: limit,
      forceRefresh: forceRefresh,
    );
  }

  Future<DiaryPage> _queryPage({
    required String uid,
    required DocumentSnapshot<Map<String, dynamic>>? startAfter,
    required int limit,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .doc(uid)
        .collection('diary')
        .orderBy('watchedAt', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get(
      const GetOptions(source: Source.serverAndCache),
    );
    final documents = snapshot.docs;
    return DiaryPage(
      entries: documents.map(DiaryEntry.fromDocument).toList(growable: false),
      lastDocument: documents.isEmpty ? null : documents.last,
      hasMore: documents.length == limit,
    );
  }

  void invalidate(String uid) {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) return;
    _firstPageCache.remove(normalizedUid);
    _pendingFirstPages.remove(normalizedUid);
    _cacheGenerations[normalizedUid] =
        (_cacheGenerations[normalizedUid] ?? 0) + 1;
  }
}

class _CachedFirstPage {
  final int limit;
  final DiaryPage page;
  final DateTime cachedAt;

  const _CachedFirstPage({
    required this.limit,
    required this.page,
    required this.cachedAt,
  });
}
