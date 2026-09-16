import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:fluttergirdi/models/news_article.dart';
import 'package:fluttergirdi/services/news_service.dart';
import 'package:url_launcher/url_launcher.dart';

class NewsDetailPage extends StatefulWidget {
  final String articleId;
  final NewsArticle? initialArticle;

  const NewsDetailPage({
    super.key,
    required this.articleId,
    this.initialArticle,
  });

  @override
  State<NewsDetailPage> createState() => _NewsDetailPageState();
}

class _NewsDetailPageState extends State<NewsDetailPage> {
  Future<NewsArticle?>? _future;

  @override
  void initState() {
    super.initState();
    if (widget.initialArticle == null) {
      _future = NewsService.instance.fetchArticle(widget.articleId);
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  Future<void> _openSource(String sourceUrl) async {
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<NewsArticle?>(
      future: _future,
      initialData: widget.initialArticle,
      builder: (context, snapshot) {
        final article = snapshot.data;

        return Scaffold(
          appBar: AppBar(
            title: const Text('CineMatch Haber'),
            centerTitle: true,
          ),
          body:
              article == null &&
                  snapshot.connectionState == ConnectionState.waiting
              ? const Center(child: CircularProgressIndicator())
              : article == null
              ? const Center(child: Text('Haber bulunamadı.'))
              : _NewsDetailBody(
                  article: article,
                  dateText: _formatDate(article.publishedAt),
                  onOpenSource: article.sourceUrl.isEmpty
                      ? null
                      : () => _openSource(article.sourceUrl),
                ),
        );
      },
    );
  }
}

class _NewsDetailBody extends StatelessWidget {
  final NewsArticle article;
  final String dateText;
  final VoidCallback? onOpenSource;

  const _NewsDetailBody({
    required this.article,
    required this.dateText,
    required this.onOpenSource,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final textColor = isDark ? Colors.white : const Color(0xFF1B1B1B);
    final mutedColor = isDark ? Colors.white60 : Colors.black54;
    final paragraphs = article.body
        .split(RegExp(r'\n\s*\n'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(18, 12, 18, 58 + bottomInset),
      children: [
        Text(
          article.category.toUpperCase(),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          article.title,
          style: TextStyle(
            color: textColor,
            fontSize: 30,
            height: 1.08,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (article.summary.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            article.summary,
            style: TextStyle(
              color: mutedColor,
              fontSize: 16,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _MetaPill(icon: Icons.edit_rounded, label: article.authorName),
            if (dateText.isNotEmpty)
              _MetaPill(icon: Icons.calendar_today_rounded, label: dateText),
            if (article.movieTitle.isNotEmpty)
              _MetaPill(icon: Icons.movie_rounded, label: article.movieTitle),
          ],
        ),
        if (article.imageUrl.isNotEmpty) ...[
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: article.imageUrl,
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => const SizedBox.shrink(),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Divider(color: isDark ? Colors.white12 : Colors.black12),
        const SizedBox(height: 12),
        for (final paragraph in paragraphs) ...[
          Text(
            paragraph,
            style: TextStyle(color: textColor, fontSize: 16, height: 1.58),
          ),
          const SizedBox(height: 16),
        ],
        if (article.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: article.tags
                .map(
                  (tag) => Chip(
                    label: Text(tag),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
        ],
        if (onOpenSource != null) ...[
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onOpenSource,
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Kaynağı Aç'),
          ),
        ],
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isDark ? Colors.white60 : Colors.black54),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.black54,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
