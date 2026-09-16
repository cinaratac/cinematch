import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class VersionCheckService {
  static final VersionCheckService instance = VersionCheckService._();
  VersionCheckService._();

  Future<void> checkVersion(BuildContext context) async {
    try {
      // 1. Cihazdaki mevcut sürüm bilgisini al
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      int currentBuildNumber = int.parse(packageInfo.buildNumber);

      // 2. Firestore'dan güncel ayarları çek
      final doc = await FirebaseFirestore.instance
          .collection('system')
          .doc('config')
          .get();

      if (!doc.exists) return;

      int minVersion = doc.data()?['min_version_code'] ?? 0;
      String updateUrl = doc.data()?['update_url'] ?? "";

      // 3. Karşılaştır: Mevcut sürüm, minimum sürümden küçükse engelle
      if (currentBuildNumber < minVersion) {
        if (context.mounted) {
          _showUpdateDialog(context, updateUrl);
        }
      }
    } catch (e) {
      debugPrint("Versiyon kontrol hatası: $e");
    }
  }

  void _showUpdateDialog(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierDismissible: false, // Diyalog dışına tıklayarak kapatılamaz
      builder: (context) {
        return PopScope(
          canPop: false, // Geri tuşuyla kapatılmasını engeller
          child: AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text("Güncelleme Gerekli", style: TextStyle(color: Colors.white)),
            content: const Text(
              "Uygulamaya devam edebilmek için lütfen yeni sürümü indirin. Bu sürüm artık desteklenmiyor.",
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text("ŞİMDİ GÜNCELLE", style: TextStyle(color: Color(0xFF29CA2C))),
              ),
            ],
          ),
        );
      },
    );
  }
}