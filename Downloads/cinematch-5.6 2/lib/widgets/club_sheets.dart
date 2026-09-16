import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fluttergirdi/services/tab_service.dart'; // TabService importu
import 'package:fluttergirdi/services/club_service.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/screens/search_movie.dart';
import 'package:fluttergirdi/widgets/poster_image.dart';

// --- ANA KULÜP DETAY SHEET'İ ---
class ClubDetailSheet extends StatelessWidget {
  final String clubId;
  const ClubDetailSheet({super.key, required this.clubId});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.95,
      minChildSize: 0.6,
      maxChildSize: 1.0,
      builder: (context, scrollController) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('clubs')
              .doc(clubId)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData)
              return const Center(child: CircularProgressIndicator());

            final data = snap.data!.data() as Map<String, dynamic>? ?? {};
            final members = List<String>.from(data['members'] ?? []);
            final admins = List<String>.from(data['admins'] ?? []);
            final imageUrl = data['imageUrl'] as String?;
            final ownerId = data['ownerId'];
            final featuredMovie =
                data['featuredMovie'] as Map<String, dynamic>?;

            final myUid = FirebaseAuth.instance.currentUser?.uid;
            final isOwner = (ownerId == myUid);
            final isAdmin = admins.contains(myUid);
            final canManage = isOwner || isAdmin;

            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  _buildHeader(context, data, imageUrl, canManage),
                  Expanded(
                    child: DefaultTabController(
                      length: 4,
                      child: Column(
                        children: [
                          const TabBar(
                            isScrollable: true,
                            tabs: [
                              Tab(text: "Haftanın Filmi"),
                              Tab(text: "Etkinlikler"),
                              Tab(text: "Anketler"),
                              Tab(text: "Üyeler"),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                FeaturedMovieTab(
                                  clubId: clubId,
                                  canManage: canManage,
                                  movieData: featuredMovie,
                                ),
                                EventsTab(clubId: clubId, canManage: canManage),
                                PollsTab(clubId: clubId, canManage: canManage),
                                MembersTab(
                                  chatId: clubId,
                                  members: members,
                                  admins: admins,
                                  ownerId: ownerId,
                                  canManage: canManage,
                                  myUid: myUid,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    Map<String, dynamic> data,
    String? imageUrl,
    bool canManage,
  ) {
    return Stack(
      children: [
        Container(
          height: 160,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            image: (imageUrl != null && imageUrl.isNotEmpty)
                ? DecorationImage(
                    image: NetworkImage(imageUrl),
                    fit: BoxFit.cover,
                  )
                : null,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: imageUrl == null
              ? const Center(
                  child: Icon(Icons.groups, size: 50, color: Colors.white24),
                )
              : null,
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: Text(
            data['name'] ?? 'Kulüp',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (canManage)
          Positioned(
            top: 10,
            right: 10,
            child: IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              onPressed: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => EditClubSheet(
                    clubId: clubId,
                    currentName: data['name'],
                    currentDesc: data['description'],
                    currentImage: imageUrl,
                    // YENİ: Kurucu bilgisini gönderiyoruz
                    isOwner:
                        data['ownerId'] ==
                        FirebaseAuth.instance.currentUser?.uid,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

// --- TABLAR (SEKMELER) ---

class FeaturedMovieTab extends StatelessWidget {
  final String clubId;
  final bool canManage;
  final Map<String, dynamic>? movieData;

  const FeaturedMovieTab({
    super.key,
    required this.clubId,
    required this.canManage,
    this.movieData,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (movieData != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  const Text(
                    "🏆 HAFTANIN FİLMİ 🏆",
                    style: TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.zero,
                        child: PosterImage(
                          posterUrl: movieData!['poster'] ?? '',
                          title: movieData!['title'] ?? '',
                          width: 100,
                          height: 150,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              movieData!['title'] ?? '',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (movieData!['releaseDate'] != null)
                              Text(
                                "Yıl: ${movieData!['releaseDate'].toString().split('-').first}",
                                style: const TextStyle(color: Colors.grey),
                              ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () {
                                final tmdbId = movieData!['id'];
                                if (tmdbId != null)
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          MovieDetailScreen(tmdbId: tmdbId),
                                    ),
                                  );
                              },
                              icon: const Icon(Icons.info_outline),
                              label: const Text("Detaylar"),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (canManage)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextButton.icon(
                  onPressed: () =>
                      ClubService.instance.removeFeaturedMovie(clubId),
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text(
                    "Filmi Kaldır",
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),
          ] else ...[
            const Icon(Icons.movie_filter, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              "Bu hafta için henüz film seçilmemiş.",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            if (canManage)
              FilledButton.icon(
                onPressed: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const SearchMoviePage(isSelectionMode: true),
                    ),
                  );
                  if (result != null && result is Map<String, dynamic>) {
                    ClubService.instance.setFeaturedMovie(clubId, result);
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text("Film Seç"),
              ),
          ],
        ],
      ),
    );
  }
}

class EventsTab extends StatelessWidget {
  final String clubId;
  final bool canManage;
  const EventsTab({super.key, required this.clubId, required this.canManage});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        if (canManage)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showAddEventDialog(context),
                icon: const Icon(Icons.add),
                label: const Text("Etkinlik Oluştur"),
              ),
            ),
          ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: ClubService.instance.getClubEvents(clubId),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty)
                return const Center(child: Text("Planlanmış etkinlik yok."));

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final date = (data['date'] as Timestamp).toDate();
                  final participants = List<String>.from(
                    data['participants'] ?? [],
                  );
                  final myUid = FirebaseAuth.instance.currentUser?.uid;
                  final isJoined = participants.contains(myUid);
                  final eventId = docs[index].id;

                  // ExpansionTile kullanarak açılır kapanır yapı kuruyoruz
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ExpansionTile(
                      // DÜZELTME: Leading (Tarih Kutusu) Taşma Sorunu Giderildi
                      leading: Container(
                        width:
                            50, // Sabit genişlik vererek hizalamayı düzelttik
                        height: 50, // Yükseklik sınırı
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ), // Padding azaltıldı (8 -> 4)
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min, // İçeriği sıkıştır
                          children: [
                            Text(
                              "${date.day}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                height: 1.0,
                              ), // Font biraz küçüldü (18->16) ve satır yüksekliği sabitlendi
                            ),
                            const SizedBox(height: 2), // Araya minik boşluk
                            Text(
                              [
                                "Oca",
                                "Şub",
                                "Mar",
                                "Nis",
                                "May",
                                "Haz",
                                "Tem",
                                "Ağu",
                                "Eyl",
                                "Eki",
                                "Kas",
                                "Ara",
                              ][date.month - 1],
                              style: const TextStyle(fontSize: 10, height: 1.0),
                            ),
                          ],
                        ),
                      ),
                      // Orta: Başlık ve Katılımcı Sayısı
                      title: Text(
                        data['title'] ?? 'Etkinlik',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} • ${participants.length} Katılımcı",
                        style: TextStyle(
                          color: isDark
                              ? Colors.white.withValues(
                                  alpha: 0.6,
                                ) // Karanlık modda Beyaz (%60 opaklık)
                              : const Color.fromARGB(255, 0, 0, 0).withValues(
                                  alpha: 0.6,
                                ), // Aydınlık modda Siyah (%60 opaklık)
                        ),
                      ),
                      // Sağ Taraf: İkonlar
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Hızlı Katılma Butonu (İkon)
                          IconButton(
                            icon: Icon(
                              isJoined
                                  ? Icons.check_circle
                                  : Icons.add_circle_outline,
                              color: isJoined ? Colors.green : Colors.grey,
                            ),
                            onPressed: () => ClubService.instance.joinEvent(
                              clubId,
                              eventId,
                              myUid!,
                            ),
                          ),
                          // Yönetici ise Silme Butonu (Çöp Kutusu)
                          if (canManage)
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              onPressed: () => _confirmDelete(context, eventId),
                            ),
                          // Açma Kapama Oku (ExpansionTile kendi okunu koyar ama biz custom row kullandığımız için manuel ekleyebiliriz veya ExpansionTile'ın varsayılanını kullanabiliriz.
                          // Burada trailing set ettiğimiz için varsayılan ok kaybolur. Manuel ekliyoruz:)
                          const Icon(Icons.keyboard_arrow_down),
                        ],
                      ),
                      // Açılınca Görünen Kısım: Katılımcı Listesi
                      children: [
                        const Divider(),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(left: 16, bottom: 8),
                                child: Text(
                                  "Katılımcılar",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color.fromARGB(255, 124, 124, 124),
                                  ),
                                ),
                              ),
                              if (participants.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Center(
                                    child: Text("Henüz katılımcı yok."),
                                  ),
                                )
                              else
                                ...participants.map(
                                  (uid) => _ParticipantRow(uid: uid),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context, String eventId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Emin misin?"),
        content: const Text(
          "Bu etkinlik ve ilgili sohbet mesajı kalıcı olarak silinecek.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("İptal"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ClubService.instance.deleteEvent(clubId, eventId);
              Navigator.pop(ctx);
            },
            child: const Text("Sil"),
          ),
        ],
      ),
    );
  }

  void _showAddEventDialog(BuildContext context) {
    // ... (Eski kodunuzdaki dialog içeriği aynen buraya, sadece sendEventMessage eklemeyi unutmayın)
    final titleCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now().add(const Duration(hours: 1));
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Yeni Etkinlik"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: "Etkinlik Adı",
                  hintText: "Örn: Cumartesi Sineması",
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Tarih ve Saat"),
                subtitle: Text(
                  "${selectedDate.day}.${selectedDate.month} - ${selectedDate.hour}:${selectedDate.minute.toString().padLeft(2, '0')}",
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(selectedDate),
                    );
                    if (t != null)
                      setDialogState(
                        () => selectedDate = DateTime(
                          d.year,
                          d.month,
                          d.day,
                          t.hour,
                          t.minute,
                        ),
                      );
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("İptal"),
            ),
            FilledButton(
              onPressed: () async {
                if (titleCtrl.text.isNotEmpty) {
                  // Etkinlik oluşturma ve mesaj gönderme işlemi Servis içinde yapılıyor zaten
                  // Eğer ClubService.createEvent metodunu bir önceki cevaptaki gibi güncellediyseniz burası yeterli:
                  await ClubService.instance.createEvent(
                    clubId,
                    titleCtrl.text.trim(),
                    selectedDate,
                  );
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: const Text("Oluştur"),
            ),
          ],
        ),
      ),
    );
  }
}

// Katılımcı ismini çekmek için yardımcı widget
class _ParticipantRow extends StatelessWidget {
  final String uid;
  const _ParticipantRow({required this.uid});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final data = snap.data!.data() as Map<String, dynamic>?;
        final name = data?['displayName'] ?? data?['username'] ?? 'Kullanıcı';
        final photo = data?['photoURL'];

        return ListTile(
          visualDensity: VisualDensity.compact,
          leading: CircleAvatar(
            radius: 14,
            backgroundImage: (photo != null && photo.isNotEmpty)
                ? NetworkImage(photo)
                : null,
            child: (photo == null || photo.isEmpty)
                ? const Icon(Icons.person, size: 16)
                : null,
          ),
          title: Text(name, style: const TextStyle(fontSize: 14)),
        );
      },
    );
  }
}

class PollsTab extends StatelessWidget {
  final String clubId;
  final bool canManage;
  const PollsTab({super.key, required this.clubId, required this.canManage});

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return Column(
      children: [
        if (canManage)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showAddPollDialog(context),
                icon: const Icon(Icons.poll),
                label: const Text("Anket Oluştur"),
              ),
            ),
          ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: ClubService.instance.getClubPolls(clubId),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty)
                return const Center(child: Text("Aktif anket yok."));
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final options = List<dynamic>.from(data['options']);
                  final voters = Map<String, dynamic>.from(
                    data['voters'] ?? {},
                  );
                  final totalVotes = voters.length;
                  final myVoteIndex = voters[myUid];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  data['question'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              if (canManage)
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () => ClubService.instance
                                      .deletePoll(clubId, docs[index].id),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...List.generate(options.length, (idx) {
                            final count = options[idx]['voteCount'] ?? 0;
                            final percent = totalVotes == 0
                                ? 0.0
                                : (count / totalVotes);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                onTap: () => ClubService.instance.votePoll(
                                  clubId,
                                  docs[index].id,
                                  myUid!,
                                  idx,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  height: 40,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: (myVoteIndex == idx)
                                          ? Colors.green
                                          : Colors.grey.withOpacity(0.3),
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Stack(
                                    children: [
                                      FractionallySizedBox(
                                        widthFactor: percent,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: (myVoteIndex == idx)
                                                ? Colors.green.withOpacity(0.2)
                                                : Colors.grey.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              7,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(options[idx]['text']),
                                            Text(
                                              "$count (${(percent * 100).toInt()}%)",
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                          Text(
                            "$totalVotes oy",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddPollDialog(BuildContext context) {
    final qCtrl = TextEditingController();
    final o1Ctrl = TextEditingController();
    final o2Ctrl = TextEditingController();
    final o3Ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Anket Oluştur"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qCtrl,
                decoration: const InputDecoration(labelText: "Soru"),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: o1Ctrl,
                decoration: const InputDecoration(labelText: "Seçenek 1"),
              ),
              TextField(
                controller: o2Ctrl,
                decoration: const InputDecoration(labelText: "Seçenek 2"),
              ),
              TextField(
                controller: o3Ctrl,
                decoration: const InputDecoration(
                  labelText: "Seçenek 3 (Opsiyonel)",
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("İptal"),
          ),
          FilledButton(
            onPressed: () {
              if (qCtrl.text.isNotEmpty &&
                  o1Ctrl.text.isNotEmpty &&
                  o2Ctrl.text.isNotEmpty) {
                final opts = [o1Ctrl.text.trim(), o2Ctrl.text.trim()];
                if (o3Ctrl.text.isNotEmpty) opts.add(o3Ctrl.text.trim());
                ClubService.instance.createPoll(
                  clubId,
                  qCtrl.text.trim(),
                  opts,
                );
                Navigator.pop(context);
              }
            },
            child: const Text("Paylaş"),
          ),
        ],
      ),
    );
  }
}

class MembersTab extends StatelessWidget {
  final String chatId;
  final List<String> members;
  final List<String> admins;
  final String? ownerId;
  final bool canManage;
  final String? myUid;

  const MembersTab({
    super.key,
    required this.chatId,
    required this.members,
    required this.admins,
    this.ownerId,
    required this.canManage,
    this.myUid,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: members.length,
      itemBuilder: (ctx, i) {
        final uid = members[i];
        final isOwner = (uid == ownerId);
        final isAdmin = admins.contains(uid);

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
          builder: (context, userSnap) {
            if (!userSnap.hasData) return const SizedBox.shrink();
            final userData = userSnap.data!.data() as Map<String, dynamic>?;
            final name =
                userData?['displayName'] ??
                userData?['username'] ??
                'Kullanıcı';
            final photo = userData?['photoURL'];

            return ListTile(
              leading: CircleAvatar(
                backgroundImage: (photo != null) ? NetworkImage(photo) : null,
                child: photo == null ? const Icon(Icons.person) : null,
              ),
              title: Text(name),
              subtitle: isOwner
                  ? const Text(
                      'Kurucu',
                      style: TextStyle(color: Colors.amber, fontSize: 12),
                    )
                  : (isAdmin
                        ? const Text(
                            'Yönetici',
                            style: TextStyle(color: Colors.green, fontSize: 12),
                          )
                        : null),
              trailing: (canManage && uid != myUid && !isOwner)
                  ? PopupMenuButton<String>(
                      onSelected: (val) {
                        if (val == 'kick')
                          ClubService.instance.kickMember(chatId, uid);
                        else if (val == 'promote')
                          ClubService.instance.toggleAdmin(chatId, uid, true);
                        else if (val == 'demote')
                          ClubService.instance.toggleAdmin(chatId, uid, false);
                      },
                      itemBuilder: (_) => [
                        if (!isAdmin)
                          const PopupMenuItem(
                            value: 'promote',
                            child: Text('Yönetici Yap'),
                          )
                        else
                          const PopupMenuItem(
                            value: 'demote',
                            child: Text('Yöneticilikten Al'),
                          ),
                        const PopupMenuItem(
                          value: 'kick',
                          child: Text(
                            'Kulüpten At',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    )
                  : null,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PublicProfileScreen(uid: uid),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// --- KULÜP DÜZENLEME SHEET'İ ---
class EditClubSheet extends StatefulWidget {
  final String clubId;
  final String? currentName;
  final String? currentDesc;
  final String? currentImage;
  final bool isOwner;

  const EditClubSheet({
    super.key,
    required this.clubId,
    this.currentName,
    this.currentDesc,
    this.currentImage,
    required this.isOwner,
  });

  @override
  State<EditClubSheet> createState() => _EditClubSheetState();
}

class _EditClubSheetState extends State<EditClubSheet> {
  late TextEditingController _descCtrl;
  bool _isLoading = false;
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController(text: widget.currentDesc);
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    try {
      String? newImageUrl;
      if (_imageFile != null) {
        final ref = FirebaseStorage.instance.ref().child(
          'club_images/${widget.clubId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await ref.putFile(_imageFile!);
        newImageUrl = await ref.getDownloadURL();
      }
      final Map<String, dynamic> updates = {
        'description': _descCtrl.text.trim(),
      };
      if (newImageUrl != null) updates['imageUrl'] = newImageUrl;
      await FirebaseFirestore.instance
          .collection('clubs')
          .doc(widget.clubId)
          .update(updates);
      if (mounted) Navigator.pop(context);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  // ... (EditClubSheetState sınıfının içi)

  Future<void> _deleteClub() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Kulübü Sil?"),
        content: const Text(
          "Bu işlem geri alınamaz. Kulüp ve tüm verileri kalıcı olarak silinecektir.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("İptal"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Sil"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        // 1. Kulübü veritabanından sil
        await ClubService.instance.deleteClub(widget.clubId);

        if (mounted) {
          // 2. Açık olan pencereleri kapat
          Navigator.pop(context); // Edit Sheet'i kapatır
          Navigator.pop(context); // Alttaki Club Detail Sheet'i kapatır

          // 3. Mesajlar Sekmesine Yönlendir
          // NOT: '3' yerine projenizdeki Mesajlar sekmesinin indeks numarasını yazın.
          // Genellikle: 0=Ana Sayfa, 1=Arama, 2=Kulüpler, 3=Mesajlar, 4=Profil şeklindedir.
          TabService.instance.changeTab(4);
        }
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Hata: $e")));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () async {
              final p = await ImagePicker().pickImage(
                source: ImageSource.gallery,
              );
              if (p != null) setState(() => _imageFile = File(p.path));
            },
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(12),
                image: (_imageFile != null || widget.currentImage != null)
                    ? DecorationImage(
                        image: _imageFile != null
                            ? FileImage(_imageFile!) as ImageProvider
                            : NetworkImage(widget.currentImage!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: const Center(child: Icon(Icons.add_a_photo)),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'Açıklama',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isLoading ? null : _save,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Kaydet'),
            ),
          ),

          // YENİ: SİLME BUTONU (Sadece Kurucuysa Göster)
          if (widget.isOwner) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _isLoading ? null : _deleteClub,
                icon: const Icon(Icons.delete_forever, color: Colors.red),
                label: const Text(
                  "Kulübü Kalıcı Olarak Sil",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
