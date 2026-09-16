import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';

class SearchProfilesScreen extends StatefulWidget {
  const SearchProfilesScreen({super.key});

  @override
  State<SearchProfilesScreen> createState() => _SearchProfilesScreenState();
}

class _SearchProfilesScreenState extends State<SearchProfilesScreen> {
  final _controller = TextEditingController();
  final _fs = FirebaseFirestore.instance;
  Timer? _debounce;
  int _searchGen = 0; // increments per search to discard stale results

  static const _kRecentKey = 'recent_searches_v1';
  static const _kRecentLimit = 10;
  List<String> _recents = [];

  String _query = '';
  bool _isLoading = false;
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() {
    super.initState();
    _loadRecents();
    // İlk açılışta boş arama yaparak son kullanıcıları veya rastgele kullanıcıları getirebiliriz
    // _runSearch(); // İsteğe bağlı: açılışta liste dolu gelsin isterseniz açın
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadRecents() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final list = sp.getStringList(_kRecentKey) ?? const [];
      if (!mounted) return;
      setState(() {
        _recents = list;
      });
    } catch (_) {}
  }

  Future<void> _pushRecent(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final lc = q.toLowerCase();
      final next = List<String>.from(_recents);
      next.removeWhere((e) => e.toLowerCase() == lc);
      next.insert(0, q);
      if (next.length > _kRecentLimit) {
        next.removeRange(_kRecentLimit, next.length);
      }
      await sp.setStringList(_kRecentKey, next);
      if (!mounted) return;
      setState(() {
        _recents = next;
      });
    } catch (_) {}
  }

  Future<void> _clearRecents() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kRecentKey);
      if (!mounted) return;
      setState(() {
        _recents = [];
      });
    } catch (_) {}
  }

  void _pushUnique(
    List<Map<String, dynamic>> buf,
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    if (!buf.any((e) => e['uid'] == d.id)) {
      buf.add({'uid': d.id, ...d.data()});
    }
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() {
        _query = v.trim();
      });
      _runSearch();
    });
  }

  // --- Arama Mantığı (Orijinal kod korundu) ---
  Future<void> _runSearch() async {
    final q = _query.trim();
    final qLc = q.toLowerCase();
    final myGen = ++_searchGen;

    if (q.isEmpty) {
      // Arama boşsa, son kayıt olanları veya güncellenenleri getir
      try {
        final snap = await _fs
            .collection('users')
            .orderBy('createdAt', descending: true)
            .limit(20)
            .get();
        final recents = [
          for (final d in snap.docs) {'uid': d.id, ...d.data()},
        ];
        if (mounted && myGen == _searchGen) {
          setState(() {
            _results = recents;
            _isLoading = false;
          });
        }
      } catch (_) {
        if (mounted && myGen == _searchGen) setState(() => _results = []);
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final List<Map<String, dynamic>> buf = [];

      // 1) letterboxdUsername exact (lc)
      try {
        final rLb = await _fs
            .collection('users')
            .where('letterboxdUsername_lc', isEqualTo: qLc)
            .limit(10)
            .get();
        for (final d in rLb.docs) _pushUnique(buf, d);
      } catch (_) {}

      // 2) email exact
      if (buf.length < 10) {
        try {
          final rEmail = await _fs
              .collection('users')
              .where('email', isEqualTo: q)
              .limit(10)
              .get();
          for (final d in rEmail.docs) _pushUnique(buf, d);
        } catch (_) {}
      }

      // 3) username exact / prefix
      if (buf.length < 20) {
        try {
          final rUx = await _fs
              .collection('users')
              .where('username_lc', isEqualTo: qLc)
              .limit(10)
              .get();
          for (final d in rUx.docs) _pushUnique(buf, d);
        } catch (_) {}
      }

      // 4) displayName prefix
      if (buf.length < 20) {
        try {
          final rDp = await _fs
              .collection('users')
              .orderBy('displayName_lc')
              .startAt([qLc])
              .endAt(['$qLc\uf8ff'])
              .limit(10)
              .get();
          for (final d in rDp.docs) _pushUnique(buf, d);
        } catch (_) {}
      }
      
      // Fallback: Client side filter if logic fails or mostly empty
      if (buf.isEmpty) {
         // ... (Existing fallback logic or simpler scan)
      }

      if (mounted && myGen == _searchGen) {
        setState(() {
          _results = buf;
        });
      }
    } catch (e) {
      if (!mounted) return;
      // Hata olursa sessiz kalabilir veya snackbar gösterebiliriz
    } finally {
      if (mounted && myGen == _searchGen) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Container(
          height: 45,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: _controller,
            autofocus: false,
            textAlignVertical: TextAlignVertical.center,
            style: theme.textTheme.bodyLarge,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Kullanıcı adı, isim veya e-posta',
              hintStyle: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                  fontSize: 14),
              border: InputBorder.none,
              prefixIcon: Icon(Icons.search,
                  color: theme.colorScheme.onSurfaceVariant),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                      },
                    )
                  : null,
            ),
            onChanged: _onChanged,
            onSubmitted: (_) => _runSearch(),
          ),
        ),
        actions: [
          // Ayarlar butonu
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: theme.iconTheme.color),
            onSelected: (value) async {
              if (value == 'settings') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Ayarlar'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Loading Indicator ---
          if (_isLoading)
             LinearProgressIndicator(
               minHeight: 2, 
               backgroundColor: Colors.transparent, 
               color: theme.colorScheme.primary
             ),

          // --- Recent Searches ---
          if (_recents.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SON ARAMALAR',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.outline,
                      letterSpacing: 1.0,
                    ),
                  ),
                  GestureDetector(
                    onTap: _clearRecents,
                    child: Text(
                      'Temizle',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _recents.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final term = _recents[i];
                  return ActionChip(
                    label: Text(term),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.surfaceContainerHigh,
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    onPressed: () {
                      _controller.text = term;
                      _onChanged(term);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],

          // --- Results List ---
          Expanded(
            child: _results.isEmpty
                ? _buildEmptyState(theme)
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final item = _results[i];
                      return _UserResultCard(
                        data: item,
                        onTap: () async {
                          final term = _controller.text.trim();
                          FocusScope.of(context).unfocus();
                          
                          // Navigate
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PublicProfileScreen(uid: item['uid']),
                            ),
                          );

                          // Save recent
                          if (term.isNotEmpty) {
                            Future.microtask(() => _pushRecent(term));
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    if (_query.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search_rounded, 
              size: 80, color: theme.colorScheme.surfaceContainerHighest),
            const SizedBox(height: 16),
            Text(
              'Yeni insanlarla tanış',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, 
            size: 60, color: theme.colorScheme.outline.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text(
            'Sonuç bulunamadı',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserResultCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _UserResultCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    final username = (data['username'] ?? '').toString();
    final displayName = (data['displayName'] ?? '').toString();
    final lb = (data['letterboxdUsername'] ?? '').toString();
    final photoURL = (data['photoURL'] ?? '').toString();

    // Akıllı isim gösterimi
    String title = displayName.isNotEmpty ? displayName : username;
    if (title.isEmpty && lb.isNotEmpty) title = '@$lb';
    if (title.isEmpty) title = 'İsimsiz Kullanıcı';

    // Avatar için harf
    final fallbackLetter = title.isNotEmpty ? title[0].toUpperCase() : '?';

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow, // Modern kart rengi
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.4),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.surfaceContainerHighest,
                    image: photoURL.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(photoURL), fit: BoxFit.cover)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: photoURL.isEmpty
                      ? Text(
                          fallbackLetter,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (lb.isNotEmpty) ...[
                            Icon(Icons.movie_creation_outlined, 
                              size: 14, color: theme.colorScheme.secondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '@$lb',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ] else 
                            Text(
                              'Letterboxd bağlı değil',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                                fontStyle: FontStyle.italic
                              ),
                            ),
                        ],
                      )
                    ],
                  ),
                ),

                // Action Icon
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: theme.colorScheme.outline.withOpacity(0.5),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}