import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/blog_post.dart';
import 'package:fluttergirdi/models/news_article.dart';
import 'package:fluttergirdi/screens/blog_detail_page.dart';
import 'package:fluttergirdi/screens/news_detail_page.dart';
import 'package:fluttergirdi/services/blog_service.dart';
import 'package:fluttergirdi/services/news_service.dart';

enum _PublicationKind { news, blog }

class _FeedPublication {
  final _PublicationKind kind;
  final NewsArticle? news;
  final BlogPost? blog;

  const _FeedPublication.news(NewsArticle article)
    : kind = _PublicationKind.news,
      news = article,
      blog = null;

  const _FeedPublication.blog(BlogPost post)
    : kind = _PublicationKind.blog,
      news = null,
      blog = post;

  String get title => news?.title ?? blog?.title ?? '';
  String get imageUrl => news?.imageUrl ?? blog?.coverImageUrl ?? '';
  String get category => news?.category ?? blog?.category ?? '';
}

class FeedPublicationTeaser extends StatefulWidget {
  const FeedPublicationTeaser({super.key});

  @override
  State<FeedPublicationTeaser> createState() => _FeedPublicationTeaserState();
}

class _FeedPublicationTeaserState extends State<FeedPublicationTeaser> {
  static final Random _random = Random();
  static Future<_FeedPublication?>? _sharedFuture;

  late final Future<_FeedPublication?> _future;

  @override
  void initState() {
    super.initState();
    _future = _sharedFuture ??= _loadPublication();
  }

  static Future<_FeedPublication?> _loadPublication() async {
    final preferBlog = _random.nextBool();
    final first = await _loadKind(
      preferBlog ? _PublicationKind.blog : _PublicationKind.news,
    );
    if (first != null) return first;
    return _loadKind(
      preferBlog ? _PublicationKind.news : _PublicationKind.blog,
    );
  }

  static Future<_FeedPublication?> _loadKind(_PublicationKind kind) async {
    try {
      if (kind == _PublicationKind.blog) {
        final posts = await BlogService.instance.fetchTeaserCandidates();
        if (posts.isEmpty) return null;
        return _FeedPublication.blog(posts[_random.nextInt(posts.length)]);
      }

      final articles = await NewsService.instance.fetchTeaserCandidates();
      if (articles.isEmpty) return null;
      return _FeedPublication.news(articles[_random.nextInt(articles.length)]);
    } catch (_) {
      return null;
    }
  }

  void _open(BuildContext context, _FeedPublication publication) {
    if (publication.kind == _PublicationKind.blog) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BlogDetailPage(post: publication.blog!),
        ),
      );
      return;
    }

    final article = publication.news!;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            NewsDetailPage(articleId: article.id, initialArticle: article),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_FeedPublication?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _TeaserLoading();
        }
        final publication = snapshot.data;
        if (publication == null) return const SizedBox.shrink();
        return _TeaserCard(
          publication: publication,
          onTap: () => _open(context, publication),
        );
      },
    );
  }
}

class _TeaserCard extends StatelessWidget {
  final _FeedPublication publication;
  final VoidCallback onTap;

  const _TeaserCard({required this.publication, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isBlog = publication.kind == _PublicationKind.blog;
    final imageUrl = publication.imageUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 112,
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 11, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isBlog
                                  ? Icons.auto_stories_rounded
                                  : Icons.newspaper_rounded,
                              size: 14,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                isBlog ? 'BLOGDAN BİR YAZI' : 'GÜNDEMDEN',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.primary,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.7,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Text(
                            publication.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              height: 1.15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                publication.category,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Text(
                              '  ·  Okumaya devam et',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 13,
                              color: colors.onSurface,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 112,
                  height: double.infinity,
                  child: imageUrl.isEmpty
                      ? _TeaserImageFallback(isBlog: isBlog)
                      : CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 320,
                          placeholder: (_, _) =>
                              _TeaserImageFallback(isBlog: isBlog),
                          errorWidget: (_, _, _) =>
                              _TeaserImageFallback(isBlog: isBlog),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeaserImageFallback extends StatelessWidget {
  final bool isBlog;

  const _TeaserImageFallback({required this.isBlog});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.surfaceContainerHighest],
        ),
      ),
      child: Icon(
        isBlog ? Icons.auto_stories_rounded : Icons.newspaper_rounded,
        color: colors.onPrimaryContainer.withValues(alpha: 0.65),
        size: 34,
      ),
    );
  }
}

class _TeaserLoading extends StatelessWidget {
  const _TeaserLoading();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainer;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        height: 112,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
