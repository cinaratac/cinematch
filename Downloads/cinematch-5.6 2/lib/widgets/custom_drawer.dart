import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttergirdi/services/tab_service.dart';
// --- SAYFA IMPORTLARI ---
import 'package:fluttergirdi/screens/leaderboard_screen.dart';
import 'package:fluttergirdi/screens/badges_progress_screen.dart';
import 'package:fluttergirdi/screens/settings_page.dart';
import 'package:fluttergirdi/screens/clubs_tab.dart';
import '../screens/trivia_welcome_screen.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:fluttergirdi/auth/login_page.dart';
import 'package:fluttergirdi/widgets/ui_polish.dart';
import 'package:fluttergirdi/widgets/viewport_fitted_content.dart';

class CustomDrawer extends StatefulWidget {
  const CustomDrawer({super.key});

  @override
  State<CustomDrawer> createState() => _CustomDrawerState();
}

class _CustomDrawerState extends State<CustomDrawer> {
  String? _lastSeenAnnouncementId;
  String? _currentUid;

  @override
  void initState() {
    super.initState();
    _initializeDrawerData();
  }

  // Tüm ağır yükleme işlemlerini burada tek seferde yapıyoruz
  Future<void> _initializeDrawerData() async {
    // 1. Kullanıcı ve Admin Kontrolü
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUid = user.uid;
    }

    // 2. Shared Preferences (Asenkron olduğu için UI'ı bloklamaz)
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _lastSeenAnnouncementId = prefs.getString('last_seen_announcement_id');
      });
    }
  }

  Future<void> _markAnnouncementAsSeen(String currentId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_seen_announcement_id', currentId);
    if (mounted) {
      setState(() {
        _lastSeenAnnouncementId = currentId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final drawerWidth = (MediaQuery.sizeOf(context).width * 0.82)
        .clamp(280.0, 350.0)
        .toDouble();

    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      width: drawerWidth,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(28),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(8, 0),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildProfileHeader(_currentUid),

              const HairlineDivider(),

              Expanded(
                child: ViewportFittedContent(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  alignment: Alignment.topCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSectionTitle("KEŞFET"),
                      _buildMenuItem(
                        context,
                        title: 'Liderlik Tablosu',
                        onTap: () =>
                            _openPage(context, const LeaderboardScreen()),
                      ),
                      _buildMenuItem(
                        context,
                        title: 'Odalar',
                        onTap: () => _openPage(context, const ClubsScreen()),
                      ),
                      _buildMenuItem(
                        context,
                        title: 'Rozetler',
                        onTap: () =>
                            _openPage(context, const BadgesProgressScreen()),
                      ),
                      _buildMenuItem(
                        context,
                        title: 'Sinema Yarışması',
                        onTap: () =>
                            _openPage(context, const TriviaWelcomeScreen()),
                      ),

                      const SizedBox(height: 24),
                      _buildSectionTitle("YAYINLAR"),

                      StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('system')
                            .doc('announcement')
                            .snapshots(),
                        builder: (context, snapshot) {
                          bool hasNew = false;
                          String? currentId;
                          if (snapshot.hasData && snapshot.data!.exists) {
                            final data =
                                snapshot.data!.data() as Map<String, dynamic>;
                            if (data['isActive'] == true) {
                              currentId = data['id'];
                              if (currentId != null &&
                                  currentId != _lastSeenAnnouncementId) {
                                hasNew = true;
                              }
                            }
                          }
                          return _buildMenuItem(
                            context,
                            title: 'Yenilikler',
                            hasBadge: hasNew,
                            onTap: () {
                              if (currentId != null) {
                                _markAnnouncementAsSeen(currentId);
                              }
                              _openPage(context, const AnnouncementsScreen());
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 24),

                      _buildSectionTitle("UYGULAMA"),
                      _buildMenuItem(
                        context,
                        title: 'Ayarlar',
                        onTap: () => _openPage(context, const SettingsPage()),
                      ),
                      _buildMenuItem(
                        context,
                        title: 'Davet Et',
                        onTap: () => SharePlus.instance.share(
                          ShareParams(
                            text:
                                'CineMatch ile film zevkini keşfet! https://play.google.com/store/apps/details?id=com.kozmosoft.cinematch',
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          onPressed: () async {
                            // 1. Önbellek temizliği
                            await DefaultCacheManager().emptyCache();
                            // 2. Shared Preferences temizliği
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.clear();

                            // 3. KRİTİK ADIM: Önce tüm sayfaları (ve Stream'leri) yok edip Login'e git!
                            if (context.mounted) {
                              Navigator.of(
                                context,
                                rootNavigator: true,
                              ).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => const LoginPage(),
                                ),
                                (route) =>
                                    false, // Arkada açık kalan ne kadar sayfa varsa hepsini siler
                              );
                            }

                            // 4. Navigasyondan hemen sonra çıkış yap (Böylece permission-denied hatası asla olmaz)
                            await FirebaseAuth.instance.signOut();
                          },
                          child: const Text(
                            "Çıkış yap",
                            style: TextStyle(
                              color: CupertinoColors.destructiveRed,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPage(BuildContext context, Widget page) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Widget _buildProfileHeader(String? uid) {
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 126);

        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final name = data?['displayName'] ?? data?['username'] ?? 'Kullanıcı';
        final email = FirebaseAuth.instance.currentUser?.email ?? '';
        final photoUrl = (data?['photoURL'] ?? '').toString().trim();
        final colors = Theme.of(context).colorScheme;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Navigator.pop(context);
              TabService.instance.changeTab(4);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 29,
                        backgroundColor: colors.surfaceContainerHighest,
                        backgroundImage: photoUrl.isEmpty
                            ? null
                            : NetworkImage(photoUrl),
                        child: photoUrl.isEmpty
                            ? Text(
                                name.toString().trim().isEmpty
                                    ? 'C'
                                    : name
                                          .toString()
                                          .trim()
                                          .characters
                                          .first
                                          .toUpperCase(),
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: colors.onSurfaceVariant,
                                      fontWeight: FontWeight.w900,
                                    ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: colors.onSurface,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (email.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                email,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 7),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 7),
          const HairlineDivider(),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required String title,
    required VoidCallback onTap,
    bool hasBadge = false,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        splashColor: colors.primary.withValues(alpha: 0.08),
        highlightColor: colors.primary.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (hasBadge)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'YENİ',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ... AnnouncementsScreen sınıfı aynı kalabilir ...
class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Yenilikler'),
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('system')
            .doc('announcement')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data == null) return const Center(child: Text("Duyuru yok"));

          final items = data['items'] as List? ?? [];
          if (items.isEmpty) {
            final title = data['title'] as String?;
            final message = data['message'] as String?;
            if (title != null) {
              items.add({
                'title': title,
                'message': message,
                'date': Timestamp.now(),
              });
            }
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final item = items[index];
              final date = (item['date'] as Timestamp?)?.toDate();

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          CupertinoIcons.sparkles,
                          color: Colors.orange,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item['title'] ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        if (date != null)
                          Text(
                            "${date.day}.${date.month}",
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item['message'] ?? '',
                      style: TextStyle(
                        color: isDark ? Colors.grey[300] : Colors.black87,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
