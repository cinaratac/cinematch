import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/login_page.dart';
import 'package:fluttergirdi/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:fluttergirdi/screens/account_deletion_page.dart';
import 'package:fluttergirdi/screens/blocked_users_screen.dart';
import 'package:fluttergirdi/auth/password_reset_page.dart';
import 'package:flutter_cached_pdfview/flutter_cached_pdfview.dart';
import 'package:fluttergirdi/services/password_reset_service.dart';
import 'package:fluttergirdi/utils/app_contact.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;
  bool _notificationsEnabled = true;

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _loadNotificationPreferences();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<T?> _showSettingsDialog<T>({
    required String title,
    required Widget child,
    List<Widget> actions = const [],
    IconData? icon,
    Color? iconColor,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        backgroundColor: Colors.transparent,
        child: _SettingsPopupSurface(
          title: title,
          icon: icon,
          iconColor: iconColor,
          actions: actions,
          child: child,
        ),
      ),
    );
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmText,
    IconData? icon,
    Color? iconColor,
    bool destructive = false,
  }) {
    final color = destructive
        ? Colors.red
        : (iconColor ?? Theme.of(context).primaryColor);

    return _showSettingsDialog<bool>(
      title: title,
      icon: icon,
      iconColor: color,
      child: Text(
        message,
        style: TextStyle(
          fontSize: 14,
          height: 1.35,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white70
              : Colors.black87,
        ),
      ),
      actions: [
        _SettingsPopupButton(
          label: 'Vazgeç',
          onPressed: () => Navigator.pop(context, false),
        ),
        _SettingsPopupButton(
          label: confirmText,
          color: color,
          filled: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }

  Future<void> _copySupportEmail() async {
    await Clipboard.setData(const ClipboardData(text: AppContact.supportEmail));
    if (!mounted) return;
    Navigator.pop(context);
    _toast('E-posta adresi kopyalandı.');
  }

  Future<void> _loadNotificationPreferences() async {
    final user = _user;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final local = prefs.getBool('notifications_enabled');
    if (local != null) {
      if (mounted) setState(() => _notificationsEnabled = local);
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data();
        final serverEnabled = data?['notificationsEnabled'];
        if (serverEnabled is bool) {
          if (mounted) setState(() => _notificationsEnabled = serverEnabled);
          await prefs.setBool('notifications_enabled', serverEnabled);
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleNotifications(bool value) async {
    final user = _user;
    if (user == null) return;

    setState(() => _notificationsEnabled = value);

    if (value) {
      try {
        var settings = await FirebaseMessaging.instance
            .getNotificationSettings();

        if (settings.authorizationStatus != AuthorizationStatus.authorized &&
            settings.authorizationStatus != AuthorizationStatus.provisional) {
          settings = await FirebaseMessaging.instance.requestPermission();
        }

        if (settings.authorizationStatus != AuthorizationStatus.authorized &&
            settings.authorizationStatus != AuthorizationStatus.provisional) {
          setState(() => _notificationsEnabled = false);
          _toast(
            'Bildirim izni verilmedi. Cihaz ayarlarından açmanız gerekebilir.',
          );
          return;
        }
      } catch (e) {
        if (e.toString().contains('already running')) {
          _toast('Bildirim izinleri kontrol ediliyor...');
        } else {
          setState(() => _notificationsEnabled = false);
          _toast('İzin hatası: $e');
          return;
        }
      }
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'notificationsEnabled': value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_enabled', value);
    } catch (e) {
      setState(() => _notificationsEnabled = !value);
      _toast('Firebase Hatası: $e');
    }
  }

  Future<void> _resetPassword() async {
    final user = _user;
    if (user == null || user.email == null) {
      _toast('E-posta bulunamadı.');
      return;
    }
    final hasPasswordProvider = user.providerData.any(
      (provider) => provider.providerId == 'password',
    );
    if (!hasPasswordProvider) {
      _toast(
        'Bu hesap Google veya Apple ile giriş yapıyor; ayrı bir şifresi yok.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final retryAfter = await PasswordResetService.instance.request(
        user.email!,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PasswordResetPage(
            email: user.email!,
            initialResendSeconds: retryAfter,
          ),
        ),
      );
    } on PasswordResetException catch (error) {
      _toast(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearLetterboxdSync() async {
    final user = _user;
    if (user == null) return;

    final ok = await _showConfirmDialog(
      title: 'Bağlantıyı Kaldır',
      message: 'Letterboxd verileri silinecek. Devam edilsin mi?',
      confirmText: 'Kaldır',
      icon: Icons.link_off_rounded,
      destructive: true,
    );
    if (ok != true) return;

    setState(() => _busy = true);
    final fs = FirebaseFirestore.instance;
    final uid = user.uid;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('lb_username_$uid');

      await fs.collection('userTasteProfiles').doc(uid).set({
        'letterboxdUsername': FieldValue.delete(),
        'loved': <String>[],
        'disliked': <String>[],
        'watchlist': <String>[],
        'posters': <String, String>{},
        'vector': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await fs.collection('users').doc(uid).set({
        'lbUsername': FieldValue.delete(),
        'letterboxdUsername': FieldValue.delete(),
        'favorites': FieldValue.delete(),
        'favoritesKeys': FieldValue.delete(),
        'watchlist': FieldValue.delete(),
        'watchlistKeys': FieldValue.delete(),
        'fiveStar': FieldValue.delete(),
        'fiveStarKeys': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _toast('Eşleşme kaldırıldı.');
    } catch (e) {
      _toast('Hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickTheme() async {
    String current = 'system';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .get();
      if (snap.data()?['themeMode'] is String) {
        current = snap.data()!['themeMode'];
      }
    } catch (_) {}

    if (!mounted) return;
    String selected = current;

    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: _SettingsPopupSurface(
              title: 'Görünüm',
              icon: Icons.palette_rounded,
              iconColor: Colors.blueAccent,
              showHandle: true,
              // ignore: sort_child_properties_last
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ThemeOption(
                    label: 'Aydınlık',
                    val: 'light',
                    group: selected,
                    icon: Icons.light_mode_rounded,
                    onTap: (v) => setSheetState(() => selected = v),
                  ),
                  _ThemeOption(
                    label: 'Karanlık',
                    val: 'dark',
                    group: selected,
                    icon: Icons.dark_mode_rounded,
                    onTap: (v) => setSheetState(() => selected = v),
                  ),
                  _ThemeOption(
                    label: 'Sistem',
                    val: 'system',
                    group: selected,
                    icon: Icons.settings_suggest_rounded,
                    onTap: (v) => setSheetState(() => selected = v),
                  ),
                ],
              ),
              actions: [
                _SettingsPopupButton(
                  label: 'Vazgeç',
                  onPressed: () => Navigator.pop(context),
                ),
                _SettingsPopupButton(
                  label: 'Uygula',
                  filled: true,
                  onPressed: () => Navigator.pop(context, selected),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != null) await _applyThemeMode(result);
  }

  Future<void> _applyThemeMode(String mode) async {
    final user = _user;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'themeMode': mode,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      ThemeMode tm = ThemeMode.system;
      if (mode == 'light') tm = ThemeMode.light;
      if (mode == 'dark') tm = ThemeMode.dark;

      ThemeBridge.themeMode.value = tm;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('themeMode', mode);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    final ok = await _showConfirmDialog(
      title: 'Çıkış Yap',
      message: 'Hesabınızdan çıkış yapmak istediğinize emin misiniz?',
      confirmText: 'Çıkış',
      icon: Icons.logout_rounded,
      destructive: true,
    );
    if (ok != true) return;

    await DefaultCacheManager().emptyCache();

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }

    await FirebaseAuth.instance.signOut();
  }

  Future<void> _deleteAccount() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AccountDeletionPage()));
  }

  void _showAboutApp() {
    _showSettingsDialog<void>(
      title: 'CineMatch',
      icon: Icons.movie_filter_rounded,
      iconColor: Colors.teal,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Text(
            'Sürüm 1.0.0\n\nFilm zevklerini eşleştiren sosyal platform.\n© 2024 Kozmosoft',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.35),
          ),
        ],
      ),
      actions: [
        _SettingsPopupButton(
          label: 'Lisanslar',
          onPressed: () {
            Navigator.pop(context);
            showLicensePage(
              context: context,
              applicationName: 'CineMatch',
              applicationVersion: '1.0.0',
              applicationLegalese: '© 2024 Kozmosoft',
              applicationIcon: const Icon(Icons.movie_filter_rounded, size: 48),
            );
          },
        ),
        _SettingsPopupButton(
          label: 'Tamam',
          color: Colors.black,
          filled: true,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  void _showSupportDialog() {
    const email = AppContact.supportEmail;

    _showSettingsDialog<void>(
      title: 'Destek',
      icon: Icons.mail_rounded,
      iconColor: Colors.green,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Görüş ve önerileriniz için:',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Material(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _copySupportEmail,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.copy_rounded, size: 18),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        email,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        _SettingsPopupButton(
          label: 'Tamam',
          color: Colors.black,
          filled: true,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  void _showPdfDialog(String title, String assetPath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
          ),
          body:
              PDF(
                enableSwipe: true,
                swipeHorizontal: false,
                autoSpacing: true,
                pageFling: true,
                pageSnap: false,
                fitPolicy: FitPolicy.WIDTH,
                fitEachPage: true,
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
              ).fromAsset(
                assetPath,
                errorWidget: (dynamic error) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 40,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Belge görüntülenemedi.\nHata: $error",
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFF2F2F7);
    final sectionColor = isDark
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFFFFFFF);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Ayarlar',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        backgroundColor: backgroundColor,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 20),
              children: [
                _SettingsSection(
                  title: "TERCİHLER",
                  sectionColor: sectionColor,
                  children: [
                    _SettingsTile(
                      icon: Icons.notifications_rounded,
                      iconColor: Colors.redAccent,
                      title: "Bildirimler",
                      isSwitch: true,
                      switchValue: _notificationsEnabled,
                      onSwitchChanged: (v) => _toggleNotifications(v),
                    ),
                    _SettingsTile(
                      icon: Icons.palette_rounded,
                      iconColor: Colors.blueAccent,
                      title: "Görünüm",
                      trailingText:
                          ThemeBridge.themeMode.value == ThemeMode.light
                          ? "Aydınlık"
                          : (ThemeBridge.themeMode.value == ThemeMode.dark
                                ? "Karanlık"
                                : "Sistem"),
                      onTap: _pickTheme,
                    ),
                  ],
                ),
                _SettingsSection(
                  title: "HESAP",
                  sectionColor: sectionColor,
                  children: [
                    _SettingsTile(
                      icon: Icons.lock_rounded,
                      iconColor: Colors.grey,
                      title: "Şifre Sıfırla",
                      onTap: _resetPassword,
                    ),
                    _SettingsTile(
                      icon: Icons.link_off_rounded,
                      iconColor: Colors.orange,
                      title: "Letterboxd Bağlantısını Kes",
                      onTap: _clearLetterboxdSync,
                    ),
                    _SettingsTile(
                      icon: Icons.block_outlined,
                      iconColor: Colors.red,
                      title: "Engellenen Kullanıcılar",
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BlockedUsersScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                _SettingsSection(
                  title: "UYGULAMA",
                  sectionColor: sectionColor,
                  children: [
                    _SettingsTile(
                      icon: Icons.article_rounded,
                      iconColor: Colors.blueGrey,
                      title: "Kullanım Koşulları",
                      onTap: () {
                        _showPdfDialog(
                          "Kullanım Koşulları",
                          "assets/docs/sozlesme.pdf",
                        );
                      },
                    ),
                    _SettingsTile(
                      icon: Icons.privacy_tip_rounded,
                      iconColor: Colors.blueGrey,
                      title: "Gizlilik Politikası",
                      onTap: () {
                        _showPdfDialog(
                          "Gizlilik Politikası",
                          "assets/docs/sozlesme.pdf",
                        );
                      },
                    ),
                    _SettingsTile(
                      icon: Icons.mail_rounded,
                      iconColor: Colors.green,
                      title: "Destek Al",
                      onTap: _showSupportDialog,
                    ),
                    _SettingsTile(
                      icon: Icons.info_rounded,
                      iconColor: Colors.teal,
                      title: "Hakkında",
                      onTap: _showAboutApp,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _SettingsSection(
                  sectionColor: sectionColor,
                  children: [
                    _SettingsTile(
                      title: "Çıkış Yap",
                      textColor: Colors.blue,
                      centerText: true,
                      onTap: _logout,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                _SettingsSection(
                  footer: "Hesabınızı silmek geri alınamaz bir işlemdir.",
                  sectionColor: sectionColor,
                  children: [
                    _SettingsTile(
                      title: "Hesabı Sil",
                      textColor: Colors.red,
                      centerText: true,
                      onTap: _deleteAccount,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildTmdbAttribution(),
                const SizedBox(height: 40),
              ],
            ),
    );
  }
}

class _SettingsPopupSurface extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget> actions;
  final IconData? icon;
  final Color? iconColor;
  final bool showHandle;

  const _SettingsPopupSurface({
    required this.title,
    required this.child,
    this.actions = const [],
    this.icon,
    this.iconColor,
    this.showHandle = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final border = isDark ? Colors.white12 : Colors.black12;
    final accent = iconColor ?? Theme.of(context).primaryColor;

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showHandle) ...[
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon, color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              child,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 18),
                Row(
                  children: [
                    for (int i = 0; i < actions.length; i++) ...[
                      Expanded(child: actions[i]),
                      if (i != actions.length - 1) const SizedBox(width: 10),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsPopupButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool filled;
  final Color? color;

  const _SettingsPopupButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveColor =
        color ?? (isDark ? Colors.white : Theme.of(context).primaryColor);

    if (filled) {
      return SizedBox(
        height: 46,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: effectiveColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: onPressed,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    }

    return SizedBox(
      height: 46,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: effectiveColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String? title;
  final String? footer;
  final List<Widget> children;
  final Color sectionColor;

  const _SettingsSection({
    this.title,
    required this.sectionColor,
    this.children = const [],
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 16, 16, 8),
            child: Text(
              title!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: sectionColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 56),
                    child: Divider(
                      height: 1,
                      color: isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade200,
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
            child: Text(
              footer!,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
              ),
            ),
          ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? trailingText;
  final bool isSwitch;
  final bool switchValue;
  final Function(bool)? onSwitchChanged;
  final VoidCallback? onTap;
  final Color? textColor;
  final bool centerText;

  const _SettingsTile({
    this.icon,
    this.iconColor,
    required this.title,
    this.trailingText,
    this.isSwitch = false,
    this.switchValue = false,
    this.onSwitchChanged,
    this.onTap,
    this.textColor,
    this.centerText = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : Colors.black;

    return InkWell(
      onTap: isSwitch ? () => onSwitchChanged?.call(!switchValue) : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (iconColor ?? Colors.blue).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: iconColor ?? Colors.blue),
              ),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Text(
                title,
                textAlign: centerText ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: textColor ?? primaryTextColor,
                ),
              ),
            ),
            if (isSwitch)
              Transform.scale(
                scale: 0.8,
                child: CupertinoSwitch(
                  value: switchValue,
                  activeTrackColor: Theme.of(context).primaryColor,
                  onChanged: onSwitchChanged,
                ),
              )
            else if (trailingText != null)
              Row(
                children: [
                  Text(
                    trailingText!,
                    style: const TextStyle(fontSize: 15, color: Colors.grey),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Colors.grey,
                  ),
                ],
              )
            else if (!centerText)
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Colors.grey,
              ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final String val;
  final String group;
  final IconData icon;
  final Function(String) onTap;

  const _ThemeOption({
    required this.label,
    required this.val,
    required this.group,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSelected = val == group;
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected
            ? theme.primaryColor.withValues(alpha: 0.13)
            : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04)),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onTap(val),
          child: ListTile(
            leading: Icon(
              icon,
              color: isSelected ? theme.primaryColor : Colors.grey,
            ),
            title: Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: isSelected
                ? Icon(Icons.check_circle, color: theme.primaryColor)
                : const Icon(Icons.circle_outlined, color: Colors.grey),
          ),
        ),
      ),
    );
  }
}

Widget _buildTmdbAttribution() {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Divider(),
      const SizedBox(height: 20),
      Opacity(
        opacity: 0.8,
        child: Image.asset(
          'assets/images/tmdb_logo.png',
          width: 60,
          height: 60,
        ),
      ),
      const SizedBox(height: 10),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30.0),
        child: Text(
          "This product uses the TMDB API but is not endorsed or certified by TMDB.",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 10,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
      const SizedBox(height: 30),
    ],
  );
}
