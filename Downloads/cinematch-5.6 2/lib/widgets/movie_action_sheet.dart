import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluttergirdi/models/shelf_target.dart';
import 'package:fluttergirdi/models/custom_list.dart';
import 'package:fluttergirdi/services/user_profile_service.dart';
import 'package:fluttergirdi/services/custom_list_service.dart';
import 'package:fluttergirdi/services/streak_service.dart';
import 'package:fluttergirdi/services/shelf_state_cache.dart';

class MovieActionSheet extends StatefulWidget {
  final int tmdbId;
  final Map<String, dynamic> movieData;
  final String? posterUrl;
  final String? catalogDocId;

  const MovieActionSheet({
    super.key,
    required this.tmdbId,
    required this.movieData,
    this.posterUrl,
    this.catalogDocId,
  });

  @override
  State<MovieActionSheet> createState() => _MovieActionSheetState();
}

class _MovieActionSheetState extends State<MovieActionSheet> {
  bool _dataReady = false;
  bool _syncing = false;

  late String _uid;
  late String _tmdbStr;
  late String? _catalogId;

  StreamSubscription<DocumentSnapshot>? _userSub;
  StreamSubscription<List<CustomList>>? _listsSub;

  ShelfStateCache get _cache => ShelfStateCache.instance;

  Set<String> get _watchedSet => _cache.get(_uid, 'watchedKeys');
  Set<String> get _watchlistSet => _cache.get(_uid, 'watchlistKeys');
  Set<String> get _favoritesSet => _cache.get(_uid, 'favoritesKeys');
  Set<String> get _fiveStarSet => _cache.get(_uid, 'fiveStarKeys');
  Set<String> get _dislikedSet => _cache.get(_uid, 'dislikedKeys');
  List<CustomList> get _customLists => _cache.getLists(_uid);

  bool _isIn(Set<String> set) =>
      set.contains(_tmdbStr) ||
      (_catalogId != null && set.contains(_catalogId!));

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _uid = user?.uid ?? '';
    _tmdbStr = widget.tmdbId.toString();
    _catalogId = widget.catalogDocId?.toLowerCase();

    if (_cache.hasData(_uid)) {
      _dataReady = true;
    }
    _startListeners();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _listsSub?.cancel();
    super.dispose();
  }

  void _startListeners() {
    if (_uid.isEmpty) return;

    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .snapshots()
        .listen(
          (doc) {
            if (!mounted) return;
            _cache.applyDoc(_uid, doc);
            setState(() {
              _dataReady = true;
              _syncing = false;
            });
          },
          onError: (_) {
            if (mounted) {
              setState(() {
                _dataReady = true;
                _syncing = false;
              });
            }
          },
        );

    _listsSub = CustomListService.instance.getUserLists(_uid).listen((lists) {
      _cache.setLists(_uid, lists);
      if (mounted) setState(() {});
    });

    if (!_dataReady) setState(() => _syncing = true);
  }

  // --------------------------------------------------------------------------
  // Toggle: İzledim
  // --------------------------------------------------------------------------
  void _toggleWatched() {
    final isWatched =
        _isIn(_watchedSet) ||
        _isIn(_favoritesSet) ||
        _isIn(_fiveStarSet) ||
        _isIn(_dislikedSet);
    final isFiveStar = _isIn(_fiveStarSet);
    final isDisliked = _isIn(_dislikedSet);
    final isWatchlist = _isIn(_watchlistSet);

    if (isWatched) {
      for (final f in [
        'watchedKeys',
        'favoritesKeys',
        'fiveStarKeys',
        'dislikedKeys',
      ]) {
        _cache.optimisticRemove(_uid, f, _tmdbStr);
        if (_catalogId != null) _cache.optimisticRemove(_uid, f, _catalogId!);
      }
      Navigator.pop(context);
      _fireAndForget(() async {
        await UserProfileService.instance.fastToggleWatched(
          uid: _uid,
          movieData: widget.movieData,
          tmdbId: widget.tmdbId,
          catalogDocId: widget.catalogDocId,
          isCurrentlyAdded: true,
          removeFromLoved: isFiveStar,
          removeFromDisliked: isDisliked,
        );
      });
      _showSnack("'$_title' listelerden çıkarıldı.", Colors.redAccent);
    } else {
      _cache.optimisticAdd(_uid, 'watchedKeys', _tmdbStr);
      if (isWatchlist) {
        _cache.optimisticRemove(_uid, 'watchlistKeys', _tmdbStr);
        if (_catalogId != null) {
          _cache.optimisticRemove(_uid, 'watchlistKeys', _catalogId!);
        }
      }
      final streakContext = Navigator.of(context, rootNavigator: true).context;
      Navigator.pop(context);
      StreakService.instance.triggerAction(streakContext);
      _fireAndForget(
        () => UserProfileService.instance.fastToggleWatched(
          uid: _uid,
          movieData: widget.movieData,
          tmdbId: widget.tmdbId,
          catalogDocId: widget.catalogDocId,
          isCurrentlyAdded: false,
        ),
      );
      _showSnack("'$_title' izlendi olarak işaretlendi.", Colors.teal);
    }
    if (mounted) setState(() {});
  }

  // --------------------------------------------------------------------------
  // Toggle: Standart liste
  // --------------------------------------------------------------------------
  void _toggleList(ShelfTarget target) {
    final fieldName = _fieldFor(target);
    final isAdded = _isIn(_setFor(target));
    final wasWatched =
        _isIn(_watchedSet) ||
        _isIn(_favoritesSet) ||
        _isIn(_fiveStarSet) ||
        _isIn(_dislikedSet);

    if (isAdded) {
      _cache.optimisticRemove(_uid, fieldName, _tmdbStr);
      if (_catalogId != null) {
        _cache.optimisticRemove(_uid, fieldName, _catalogId!);
      }
      Navigator.pop(context);
      _fireAndForget(
        () => UserProfileService.instance.fastToggleStandardList(
          uid: _uid,
          movieData: widget.movieData,
          tmdbId: widget.tmdbId,
          catalogDocId: widget.catalogDocId,
          target: target,
          isCurrentlyAdded: true,
          posterUrl: widget.posterUrl,
        ),
      );
      _showSnack("'$_title' listeden çıkarıldı.", Colors.redAccent);
    } else {
      _cache.optimisticAdd(_uid, fieldName, _tmdbStr);
      if (target != ShelfTarget.watchlist) {
        _cache.optimisticAdd(_uid, 'watchedKeys', _tmdbStr);
        _cache.optimisticRemove(_uid, 'watchlistKeys', _tmdbStr);
        if (_catalogId != null) {
          _cache.optimisticRemove(_uid, 'watchlistKeys', _catalogId!);
        }
      }
      final streakContext = Navigator.of(context, rootNavigator: true).context;
      Navigator.pop(context);
      if (target != ShelfTarget.watchlist) {
        StreakService.instance.triggerAction(streakContext);
      }
      _fireAndForget(() async {
        await UserProfileService.instance.fastToggleStandardList(
          uid: _uid,
          movieData: widget.movieData,
          tmdbId: widget.tmdbId,
          catalogDocId: widget.catalogDocId,
          target: target,
          isCurrentlyAdded: false,
          posterUrl: widget.posterUrl,
          logToDiary: target != ShelfTarget.watchlist && !wasWatched,
        );
      });
      _showSnack("'$_title' listeye eklendi.", Colors.green.shade700);
    }
    if (mounted) setState(() {});
  }

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------
  String get _title => (widget.movieData['title'] ?? '').toString();

  String _fieldFor(ShelfTarget t) => switch (t) {
    ShelfTarget.fiveStar => 'fiveStarKeys',
    ShelfTarget.disliked => 'dislikedKeys',
    ShelfTarget.favorites => 'favoritesKeys',
    ShelfTarget.watchlist => 'watchlistKeys',
  };

  Set<String> _setFor(ShelfTarget t) => switch (t) {
    ShelfTarget.fiveStar => _fiveStarSet,
    ShelfTarget.disliked => _dislikedSet,
    ShelfTarget.favorites => _favoritesSet,
    ShelfTarget.watchlist => _watchlistSet,
  };

  void _fireAndForget(Future<void> Function() fn) {
    fn().catchError((e) => debugPrint('Firestore write error: $e'));
  }

  void _showSnack(String msg, Color color) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: color,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: _syncing && !_dataReady
            ? _buildSkeleton()
            : _buildContent(context),
      ),
    );
  }

  Widget _buildSkeleton() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          _skeletonBox(160, 22),
          const SizedBox(height: 20),
          _skeletonBox(80, 14),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: List.generate(5, (_) => _skeletonCircle()),
          ),
          const Divider(height: 40),
          _skeletonBox(100, 14),
          const SizedBox(height: 12),
          _skeletonBox(double.infinity, 56),
          const SizedBox(height: 10),
          _skeletonBox(double.infinity, 56),
        ],
      ),
    );
  }

  Widget _skeletonBox(double w, double h) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: Colors.grey.withOpacity(0.2),
      borderRadius: BorderRadius.circular(8),
    ),
  );

  Widget _skeletonCircle() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey.withOpacity(0.2),
        ),
      ),
      const SizedBox(height: 8),
      _skeletonBox(50, 12),
    ],
  );

  Widget _buildContent(BuildContext context) {
    final isWatched =
        _isIn(_watchedSet) ||
        _isIn(_favoritesSet) ||
        _isIn(_fiveStarSet) ||
        _isIn(_dislikedSet);
    final isWatchlist = _isIn(_watchlistSet);
    final isFavorite = _isIn(_favoritesSet);
    final isFiveStar = _isIn(_fiveStarSet);
    final isDisliked = _isIn(_dislikedSet);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Listelere Ekle',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              if (_syncing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Profil Listeleri',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              _buildAction(
                Icons.visibility_rounded,
                'İzledim',
                Colors.teal,
                isWatched,
                _toggleWatched,
              ),
              _buildAction(
                Icons.bookmark_add_rounded,
                'İzlenecekler',
                Colors.blue,
                isWatchlist,
                () => _toggleList(ShelfTarget.watchlist),
              ),
              _buildAction(
                Icons.favorite_rounded,
                'Favoriler',
                Colors.pink,
                isFavorite,
                () => _toggleList(ShelfTarget.favorites),
              ),
              _buildAction(
                Icons.star_rounded,
                'Sevdiklerim',
                Colors.amber,
                isFiveStar,
                () => _toggleList(ShelfTarget.fiveStar),
              ),
              _buildAction(
                Icons.thumb_down_rounded,
                'Sevmedim',
                Colors.redAccent,
                isDisliked,
                () => _toggleList(ShelfTarget.disliked),
              ),
            ],
          ),
          const Divider(height: 40),
          const Text(
            'Özel Listelerim',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_customLists.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Henüz özel bir listen yok.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _customLists.length,
              itemBuilder: (context, i) {
                final list = _customLists[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(8),
                      image: list.coverImageUrl != null
                          ? DecorationImage(
                              image: NetworkImage(list.coverImageUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: list.coverImageUrl == null
                        ? const Icon(Icons.list, color: Colors.white54)
                        : null,
                  ),
                  title: Text(
                    list.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${list.movieCount} film',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  trailing: const Icon(Icons.add_circle_outline),
                  onTap: () => _addToCustomList(context, list.id, list.title),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAction(
    IconData icon,
    String label,
    Color color,
    bool isAdded,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isAdded ? color : color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isAdded ? Icons.check_rounded : icon,
              color: isAdded ? Colors.white : color,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isAdded ? FontWeight.bold : FontWeight.w600,
              color: isAdded ? color : Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Future<void> _addToCustomList(
    BuildContext context,
    String listId,
    String listTitle,
  ) async {
    final query = await FirebaseFirestore.instance
        .collection('custom_lists')
        .doc(listId)
        .collection('items')
        .where('id', isEqualTo: widget.tmdbId)
        .get();
    if (!mounted) return;
    if (query.docs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bu film zaten "$listTitle" listesinde!'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context);
    final poster =
        widget.posterUrl ??
        (widget.movieData['poster_path'] != null
            ? 'https://image.tmdb.org/t/p/w500${widget.movieData['poster_path']}'
            : null);
    _fireAndForget(
      () => CustomListService.instance.addMovieToList(listId, {
        'id': widget.tmdbId,
        'title': widget.movieData['title'],
        'poster': poster,
      }),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${widget.movieData['title']}, "$listTitle" listesine eklendi.',
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
