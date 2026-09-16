// lib/widgets/discovery_lists_widget.dart

import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/custom_list.dart';
import 'package:fluttergirdi/services/custom_list_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluttergirdi/screens/custom_list_detail_screen.dart';
import 'package:fluttergirdi/screens/lists_screen.dart';
import 'package:fluttergirdi/widgets/ui_polish.dart';

class DiscoveryListsWidget extends StatefulWidget {
  const DiscoveryListsWidget({super.key});

  @override
  State<DiscoveryListsWidget> createState() => _DiscoveryListsWidgetState();
}

class _DiscoveryListsWidgetState extends State<DiscoveryListsWidget>
    with AutomaticKeepAliveClientMixin {
  late final Future<List<CustomList>> _discoveryListsFuture;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _discoveryListsFuture = CustomListService.instance.fetchDiscoveryLists();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // GÜNCELLEME: Başlık kısmı InkWell ile sarıldı ve tıklama özelliği eklendi
        InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ListsScreen()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Keşfet: Listeler",
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                  ],
                ),
              ],
            ),
          ),
        ),

        const HairlineDivider(indent: 16, endIndent: 16),

        // Liste Akışı
        SizedBox(
          height: 220,
          child: FutureBuilder<List<CustomList>>(
            future: _discoveryListsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError ||
                  !snapshot.hasData ||
                  snapshot.data!.isEmpty) {
                return const SizedBox.shrink();
              }

              final lists = snapshot.data!;

              return ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: lists.length,
                itemBuilder: (context, index) {
                  final list = lists[index];
                  return _buildListCard(context, list);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildListCard(BuildContext context, CustomList list) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CustomListDetailScreen(list: list)),
        );
      },
      child: Container(
        width: 140,
        margin: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
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
              // DÜZELTME 2: 'posterUrl' yerine 'coverImageUrl'
              CachedNetworkImage(
                imageUrl:
                    list.coverImageUrl ?? 'https://via.placeholder.com/150',
                memCacheWidth: 420,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Container(color: Colors.grey[800]),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey[900],
                  child: const Icon(Icons.movie, color: Colors.white54),
                ),
              ),

              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                    stops: const [0.5, 1.0],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // DÜZELTME 3: 'name' yerine 'title'
                    Text(
                      list.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${list.movieCount} Film",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 11,
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
