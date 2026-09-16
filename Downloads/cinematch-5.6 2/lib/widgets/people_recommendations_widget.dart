import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/screens/actors_screen.dart';
import 'package:fluttergirdi/screens/director_screen.dart';
import 'package:fluttergirdi/services/people_recommendation_service.dart';
import 'package:fluttergirdi/widgets/ui_polish.dart';

class PeopleRecommendationsWidget extends StatefulWidget {
  const PeopleRecommendationsWidget({super.key});

  @override
  State<PeopleRecommendationsWidget> createState() =>
      _PeopleRecommendationsWidgetState();
}

class _PeopleRecommendationsWidgetState
    extends State<PeopleRecommendationsWidget>
    with AutomaticKeepAliveClientMixin {
  PeopleRecommendations? _recommendations;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final result = await PeopleRecommendationService.instance.loadForUser(uid);
    if (!mounted) return;
    setState(() {
      _recommendations = result;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const _PeopleRecommendationsSkeleton();

    final recommendations = _recommendations;
    if (recommendations == null || recommendations.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PeopleRow(
            title: 'Sana Özel Oyuncular',
            icon: Icons.theater_comedy_outlined,
            people: recommendations.actors,
          ),
          if (recommendations.actors.isNotEmpty &&
              recommendations.directors.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: HairlineDivider(indent: 16, endIndent: 16),
            ),
          _PeopleRow(
            title: 'Sana Özel Yönetmenler',
            icon: Icons.video_camera_front_outlined,
            people: recommendations.directors,
          ),
        ],
      ),
    );
  }
}

class _PeopleRow extends StatelessWidget {
  const _PeopleRow({
    required this.title,
    required this.icon,
    required this.people,
  });

  final String title;
  final IconData icon;
  final List<RecommendedPerson> people;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, size: 19, color: colors.primary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 202,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: people.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) => _PersonCard(
              person: people[index],
              onTap: () => _openPerson(context, people[index]),
            ),
          ),
        ),
      ],
    );
  }

  void _openPerson(BuildContext context, RecommendedPerson person) {
    final destination = person.kind == RecommendedPersonKind.actor
        ? ActorScreen(actorId: person.id, actorName: person.name)
        : DirectorScreen(directorId: person.id, directorName: person.name);
    Navigator.push(context, MaterialPageRoute(builder: (_) => destination));
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.onTap});

  final RecommendedPerson person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reason = person.matchedMovieTitles.isEmpty
        ? person.kind == RecommendedPersonKind.actor
              ? 'Oyuncu'
              : 'Yönetmen'
        : person.matchedMovieTitles.first;

    return SizedBox(
      width: 112,
      child: Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 142,
                width: double.infinity,
                child: person.profileUrl.isEmpty
                    ? _PortraitFallback(name: person.name)
                    : CachedNetworkImage(
                        imageUrl: person.profileUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 336,
                        placeholder: (_, _) => const _PortraitPlaceholder(),
                        errorWidget: (_, _, _) =>
                            _PortraitFallback(name: person.name),
                      ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      AccentMetadata(text: reason),
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
}

class _PortraitFallback extends StatelessWidget {
  const _PortraitFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Text(
          initial,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _PortraitPlaceholder extends StatelessWidget {
  const _PortraitPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}

class _PeopleRecommendationsSkeleton extends StatelessWidget {
  const _PeopleRecommendationsSkeleton();

  @override
  Widget build(BuildContext context) {
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var row = 0; row < 2; row++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(width: 154, height: 16, color: fill),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 202,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 4,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, _) => Container(
                  width: 112,
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
            if (row == 0) const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}
