import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/blog_post.dart';
import 'package:fluttergirdi/screens/movie_detail_screen.dart';
import 'package:fluttergirdi/screens/public_profile_screen.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

class BlogDetailPage extends StatelessWidget {
  final BlogPost post;

  const BlogDetailPage({super.key, required this.post});

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  void _openAuthor(BuildContext context) {
    if (post.authorId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PublicProfileScreen(uid: post.authorId),
      ),
    );
  }

  void _openMovie(BuildContext context, BlogMovie movie) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MovieDetailScreen(
          tmdbId: movie.tmdbId,
          title: movie.title,
          posterUrl: _posterUrl(movie),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final dateText = _formatDate(post.publishedAt);
    final hasCover = post.coverImageUrl.isNotEmpty;
    final content = post.contentHtml.isNotEmpty
        ? post.contentHtml
        : '<p>${post.contentText}</p>';
    final extraImages = post.images
        .where(
          (image) =>
              image.url != post.coverImageUrl && !content.contains(image.url),
        )
        .toList(growable: false);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: hasCover ? 278 : 88,
            title: Text(
              'Blog',
              style: TextStyle(
                color: hasCover ? Colors.white : colors.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            iconTheme: IconThemeData(
              color: hasCover ? Colors.white : colors.onSurface,
            ),
            backgroundColor: colors.surface,
            flexibleSpace: hasCover
                ? FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        Hero(
                          tag: 'blog-cover-${post.id}',
                          child: CachedNetworkImage(
                            imageUrl: post.coverImageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 1000,
                            placeholder: (_, _) => ColoredBox(
                              color: colors.surfaceContainerHighest,
                            ),
                            errorWidget: (_, _, _) => ColoredBox(
                              color: colors.surfaceContainerHighest,
                            ),
                          ),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x99000000),
                                Color(0x11000000),
                                Color(0xB8000000),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 24, 20, 64 + bottomInset),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.category.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        post.title,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: colors.onSurface,
                          height: 1.08,
                          fontWeight: FontWeight.w900,
                          fontSize: 34,
                        ),
                      ),
                      if (post.excerpt.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          post.excerpt,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.48,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      _AuthorRow(
                        post: post,
                        dateText: dateText,
                        onTap: post.authorId.isEmpty
                            ? null
                            : () => _openAuthor(context),
                      ),
                      const SizedBox(height: 22),
                      Divider(color: colors.outlineVariant),
                      const SizedBox(height: 14),
                      _BlogHtmlBody(html: content),
                      if (extraImages.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text(
                          'Görseller',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 180,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: extraImages.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final image = extraImages[index];
                              return SizedBox(
                                width: 260,
                                child: _ArticleImage(
                                  url: image.url,
                                  alt: image.alt,
                                  compact: true,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      if (post.movies.isNotEmpty) ...[
                        const SizedBox(height: 30),
                        Divider(color: colors.outlineVariant),
                        const SizedBox(height: 20),
                        Text(
                          post.movies.length == 1
                              ? 'Yazıdaki Film'
                              : 'Yazıdaki Filmler',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 205,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: post.movies.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              final movie = post.movies[index];
                              return _MovieCard(
                                movie: movie,
                                onTap: () => _openMovie(context, movie),
                              );
                            },
                          ),
                        ),
                      ],
                      if (post.tags.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: post.tags
                              .map(
                                (tag) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    '#$tag',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: colors.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthorRow extends StatelessWidget {
  final BlogPost post;
  final String dateText;
  final VoidCallback? onTap;

  const _AuthorRow({
    required this.post,
    required this.dateText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final username = post.authorUsername.isEmpty
        ? ''
        : '@${post.authorUsername.replaceFirst('@', '')}';
    final meta = [
      if (dateText.isNotEmpty) dateText,
      if (post.readingMinutes > 0) '${post.readingMinutes} dk okuma',
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: colors.surfaceContainerHighest,
                backgroundImage: post.authorPhotoUrl.isEmpty
                    ? null
                    : CachedNetworkImageProvider(post.authorPhotoUrl),
                child: post.authorPhotoUrl.isEmpty
                    ? Icon(Icons.person_rounded, color: colors.onSurfaceVariant)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (username.isNotEmpty) username,
                        if (meta.isNotEmpty) meta,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlogHtmlBody extends StatelessWidget {
  final String html;

  const _BlogHtmlBody({required this.html});

  @override
  Widget build(BuildContext context) {
    final fragment = html_parser.parseFragment(html);
    final widgets = <Widget>[];
    for (final node in fragment.nodes) {
      widgets.addAll(_widgetsForNode(context, node));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  List<Widget> _widgetsForNode(BuildContext context, dom.Node node) {
    if (node is dom.Text) {
      final text = node.data.trim();
      if (text.isEmpty) return const [];
      return [_TextBlock(element: null, fallbackText: text)];
    }
    if (node is! dom.Element) return const [];

    final tag = node.localName;
    if (tag == 'img') {
      final url = node.attributes['src']?.trim() ?? '';
      if (url.isEmpty) return const [];
      return [
        _ArticleImage(url: url, alt: node.attributes['alt'] ?? ''),
        const SizedBox(height: 20),
      ];
    }
    if (tag == 'figure') {
      final image = node.querySelector('img');
      final caption = node.querySelector('figcaption')?.text.trim() ?? '';
      final url = image?.attributes['src']?.trim() ?? '';
      if (url.isEmpty) return const [];
      return [
        _ArticleImage(
          url: url,
          alt: caption.isEmpty ? image?.attributes['alt'] ?? '' : caption,
        ),
        const SizedBox(height: 20),
      ];
    }
    if (tag == 'hr') {
      return const [
        Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
      ];
    }
    if (tag == 'ul' || tag == 'ol') {
      final items = node.children
          .where((child) => child.localName == 'li')
          .toList();
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < items.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 25,
                        child: Text(tag == 'ol' ? '${index + 1}.' : '•'),
                      ),
                      Expanded(child: _TextBlock(element: items[index])),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ];
    }
    if (tag == 'blockquote') {
      final colors = Theme.of(context).colorScheme;
      return [
        Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: colors.primary, width: 4)),
            color: colors.primaryContainer.withValues(alpha: 0.28),
          ),
          child: _TextBlock(element: node, italic: true),
        ),
      ];
    }

    final nestedImages = node.querySelectorAll('img');
    final children = <Widget>[];
    if (node.text.trim().isNotEmpty) {
      children.add(
        _TextBlock(
          element: node,
          headingLevel: tag == 'h2' ? 2 : (tag == 'h3' ? 3 : null),
        ),
      );
      children.add(SizedBox(height: tag == 'h2' || tag == 'h3' ? 12 : 18));
    }
    for (final image in nestedImages) {
      final url = image.attributes['src']?.trim() ?? '';
      if (url.isEmpty) continue;
      children.add(_ArticleImage(url: url, alt: image.attributes['alt'] ?? ''));
      children.add(const SizedBox(height: 20));
    }
    return children;
  }
}

class _TextBlock extends StatelessWidget {
  final dom.Element? element;
  final String fallbackText;
  final int? headingLevel;
  final bool italic;

  const _TextBlock({
    required this.element,
    this.fallbackText = '',
    this.headingLevel,
    this.italic = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final baseStyle = headingLevel == 2
        ? theme.textTheme.headlineSmall?.copyWith(
            height: 1.22,
            fontWeight: FontWeight.w900,
          )
        : headingLevel == 3
        ? theme.textTheme.titleLarge?.copyWith(
            height: 1.3,
            fontWeight: FontWeight.w900,
          )
        : theme.textTheme.bodyLarge?.copyWith(
            color: colors.onSurface,
            fontSize: 17,
            height: 1.66,
            fontStyle: italic ? FontStyle.italic : null,
          );

    final span = element == null
        ? TextSpan(text: fallbackText, style: baseStyle)
        : TextSpan(
            style: baseStyle,
            children: element!.nodes
                .map((node) => _inlineSpan(context, node, baseStyle))
                .toList(growable: false),
          );
    return SelectableText.rich(span);
  }

  InlineSpan _inlineSpan(
    BuildContext context,
    dom.Node node,
    TextStyle? style,
  ) {
    if (node is dom.Text) return TextSpan(text: node.data, style: style);
    if (node is! dom.Element) return const TextSpan();
    if (node.localName == 'br') return const TextSpan(text: '\n');
    if (node.localName == 'img') return const TextSpan();

    var childStyle = style;
    switch (node.localName) {
      case 'strong':
      case 'b':
        childStyle = childStyle?.copyWith(fontWeight: FontWeight.w800);
      case 'em':
      case 'i':
        childStyle = childStyle?.copyWith(fontStyle: FontStyle.italic);
      case 'u':
        childStyle = childStyle?.copyWith(decoration: TextDecoration.underline);
      case 's':
        childStyle = childStyle?.copyWith(
          decoration: TextDecoration.lineThrough,
        );
      case 'a':
        childStyle = childStyle?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: Theme.of(context).colorScheme.primary,
        );
    }
    return TextSpan(
      style: childStyle,
      children: node.nodes
          .map((child) => _inlineSpan(context, child, childStyle))
          .toList(growable: false),
    );
  }
}

class _ArticleImage extends StatelessWidget {
  final String url;
  final String alt;
  final bool compact;

  const _ArticleImage({
    required this.url,
    required this.alt,
    this.compact = false,
  });

  void _showFullScreen(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.94),
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (_, _) => const CircularProgressIndicator(),
                  errorWidget: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white70,
                    size: 46,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 8,
            child: IconButton.filledTonal(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(compact ? 12 : 10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _showFullScreen(context),
            child: AspectRatio(
              aspectRatio: compact ? 1.45 : 16 / 10,
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: compact ? 600 : 1100,
                placeholder: (_, _) => ColoredBox(
                  color: colors.surfaceContainerHighest,
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, _, _) => Icon(
                  Icons.broken_image_outlined,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        if (!compact && alt.trim().isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            alt.trim(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }
}

class _MovieCard extends StatelessWidget {
  final BlogMovie movie;
  final VoidCallback onTap;

  const _MovieCard({required this.movie, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final poster = _posterUrl(movie);
    return SizedBox(
      width: 104,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: poster.isEmpty
                      ? ColoredBox(
                          color: colors.surfaceContainerHighest,
                          child: Icon(
                            Icons.movie_outlined,
                            color: colors.onSurfaceVariant,
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: poster,
                          fit: BoxFit.cover,
                          memCacheWidth: 260,
                          errorWidget: (_, _, _) => ColoredBox(
                            color: colors.surfaceContainerHighest,
                            child: const Icon(Icons.movie_outlined),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                movie.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _posterUrl(BlogMovie movie) {
  if (movie.posterUrl.isNotEmpty) return movie.posterUrl;
  if (movie.posterPath.isEmpty) return '';
  return 'https://image.tmdb.org/t/p/w342${movie.posterPath}';
}
