import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReportUserSheet extends StatefulWidget {
  final String reportedUserId;
  final String reportedUserName;

  const ReportUserSheet({
    super.key,
    required this.reportedUserId,
    required this.reportedUserName,
  });

  // Bu metot sayesinde her yerden kolayca çağırabiliriz
  static void show(BuildContext context, String userId, String userName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // Köşelerin yuvarlak görünmesi için
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom, // Klavye açıldığında yukarı kayması için
        ),
        child: ReportUserSheet(reportedUserId: userId, reportedUserName: userName),
      ),
    );
  }

  @override
  State<ReportUserSheet> createState() => _ReportUserSheetState();
}

class _ReportUserSheetState extends State<ReportUserSheet> {
  final TextEditingController _detailsController = TextEditingController();
  
  // Bildiri sebepleri
  final List<String> _reportReasons = [
    'Spam veya Reklam',
    'Uygunsuz İçerik',
    'Taciz veya Zorbalık',
    'Sahte Hesap',
    'Diğer'
  ];
  
  String? _selectedReason;
  bool _isLoading = false;

  Future<void> _submitReport() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir bildiri sebebi seçin.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      
      if (currentUserId == null) {
        throw Exception("Kullanıcı girişi bulunamadı.");
      }

      // Firestore'a raporu kaydetme
      await FirebaseFirestore.instance.collection('reports').add({
        'reporterId': currentUserId,
        'reportedUserId': widget.reportedUserId,
        'reason': _selectedReason,
        'details': _detailsController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending', // Admin paneli için durum
      });

      if (!mounted) return;
      
      Navigator.pop(context); // Menüyü kapat
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.reportedUserName} başarıyla bildirildi. İnceleyeceğiz.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bir hata oluştu: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Üstteki küçük tutma çubuğu
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Kullanıcıyı Bildir',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Lütfen ${widget.reportedUserName} adlı kullanıcıyı neden bildirdiğinizi seçin. Bu bilgi gizli tutulacaktır.',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          
          // Sebepleri modern çipler (ChoiceChip) olarak gösterme
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: _reportReasons.map((reason) {
              final isSelected = _selectedReason == reason;
              return ChoiceChip(
                label: Text(reason),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedReason = selected ? reason : null;
                  });
                },
                selectedColor: theme.colorScheme.primary.withOpacity(0.2),
                labelStyle: TextStyle(
                  color: isSelected ? theme.colorScheme.primary : theme.textTheme.bodyMedium?.color,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
          
          const SizedBox(height: 20),
          
          // Ek açıklama alanı (Opsiyonel)
          TextField(
            controller: _detailsController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Eklemek istediğiniz başka bir detay var mı? (İsteğe bağlı)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Gönder Butonu
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _isLoading ? null : _submitReport,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Şikayeti Gönder', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}