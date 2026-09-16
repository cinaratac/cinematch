// lib/screens/lists_screen.dart

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:fluttergirdi/models/custom_list.dart';
import 'package:fluttergirdi/services/custom_list_service.dart';
import 'package:fluttergirdi/screens/custom_list_detail_screen.dart';

class ListsScreen extends StatelessWidget {
  const ListsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Keşfet: Tüm Listeler'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: FutureBuilder<List<CustomList>>(
        future: CustomListService.instance.fetchDiscoveryLists(), 
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Şu an gösterilecek bir liste bulunamadı.'));
          }

          final lists = snapshot.data!;

          return GridView.builder(
            padding: const EdgeInsets.all(16.0),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, // Yan yana 2 liste kartı
              childAspectRatio: 0.75, // Kartların en/boy oranı
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: lists.length,
            itemBuilder: (context, index) {
              final list = lists[index];
              return _buildGridListCard(context, list);
            },
          );
        },
      ),
    );
  }

  Widget _buildGridListCard(BuildContext context, CustomList list) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CustomListDetailScreen(list: list),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: list.coverImageUrl ?? 'https://via.placeholder.com/150', 
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(color: Colors.grey[800]),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[900],
                  child: const Icon(Icons.movie, color: Colors.white54),
                ),
              ),
              
              // Siyah Gradient (Yazıların okunabilmesi için alt kısma doğru koyulaşır)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.85),
                    ],
                    stops: const [0.4, 1.0],
                  ),
                ),
              ),

              // Liste Bilgileri
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      list.title, 
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "${list.movieCount} Film",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
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
  }
}