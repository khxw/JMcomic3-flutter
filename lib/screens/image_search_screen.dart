import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'components/app_back_button.dart';
import 'components/compose_ui.dart';

typedef ImageSearchFilePicker = Future<String?> Function();

enum _ImageSourceKind { gallery, files }

class ImageSearchScreen extends StatefulWidget {
  final ImageSearchFilePicker? pickGallery;
  final ImageSearchFilePicker? pickFiles;

  const ImageSearchScreen({
    this.pickGallery,
    this.pickFiles,
    Key? key,
  }) : super(key: key);

  @override
  State<ImageSearchScreen> createState() => _ImageSearchScreenState();
}

class _ImageSearchScreenState extends State<ImageSearchScreen> {
  String? _imagePath;
  String? _error;
  bool _searching = false;
  _ImageSourceKind? _openingSource;
  bool _hasSearched = false;
  List<ImageSearchHit> _hits = const [];

  Future<String?> _pickFromGallery() async {
    if (Platform.isAndroid) {
      return methods.androidPickImageFromGallery();
    }
    return _pickFromFiles();
  }

  Future<String?> _pickFromFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif'],
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.single.path;
  }

  Future<void> _chooseImage(
    _ImageSourceKind source,
    ImageSearchFilePicker picker,
  ) async {
    if (_searching || _openingSource != null) return;
    String? path;
    setState(() {
      _openingSource = source;
      _error = null;
    });
    try {
      path = await picker();
    } catch (_) {
      if (mounted) {
        setState(() {
          _openingSource = null;
          _error = context.l10n.tr(
            '无法打开图片来源，请检查系统权限后重试',
            en: 'Could not open the image source. Check system permissions.',
          );
          _hasSearched = true;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _openingSource = null);
    if (path == null || path.trim().isEmpty || !mounted) return;

    setState(() {
      _imagePath = path;
      _searching = true;
      _hasSearched = false;
      _error = null;
      _hits = const [];
    });
    try {
      final response = await methods.imageSearch(path);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _hasSearched = true;
        _hits = response.hits
            .where((hit) => hit.searchQuery.isNotEmpty)
            .toList(growable: false);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _hasSearched = true;
        _error = _imageSearchErrorMessage(error);
      });
    }
  }

  String _imageSearchErrorMessage(Object error) {
    final text = error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Exception: ', '')
        .trim();
    final lower = text.toLowerCase();
    if (text.contains('413')) {
      return context.l10n.tr(
        '图片文件太大，请换一张较小的图片',
        en: 'The image is too large. Choose a smaller image.',
      );
    }
    if (text.contains('415')) {
      return context.l10n.tr(
        '不支持这种图片格式，请使用 JPG、PNG 或 WebP',
        en: 'Unsupported image format. Use JPG, PNG, or WebP.',
      );
    }
    if (text.contains('429')) {
      return context.l10n.tr(
        '识图服务请求过于频繁，请稍后重试',
        en: 'Too many image searches. Try again shortly.',
      );
    }
    if (lower.contains('larger than 24 mb')) {
      return context.l10n.tr(
        '图片文件太大，请换一张不超过 24 MB 的图片',
        en: 'The image is too large. Choose one under 24 MB.',
      );
    }
    if (lower.contains('unsupported image')) {
      return context.l10n.tr(
        '不支持这种图片格式，请使用 JPG、PNG、WebP 或 GIF',
        en: 'Unsupported image format. Use JPG, PNG, WebP, or GIF.',
      );
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return context.l10n.tr(
        '识图请求超时，请检查网络后重试',
        en: 'Image search timed out. Check your network and retry.',
      );
    }
    return context.l10n.tr(
      '以图搜漫失败，请检查网络或稍后重试',
      en: 'Image search failed. Check your network or try again later.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      key: const ValueKey('image-search-page'),
      backgroundColor: scheme.surface,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(
          context.l10n.tr('以图搜漫', en: 'Search by image'),
        ),
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _buildIntro(context),
                const SizedBox(height: 14),
                _buildSourcePicker(context),
                if (_imagePath != null) ...[
                  const SizedBox(height: 14),
                  _buildPreview(context),
                ],
                if (_searching) ...[
                  const SizedBox(height: 14),
                  _buildProgress(context),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  _buildError(context),
                ],
                if (_hasSearched && !_searching && _error == null) ...[
                  const SizedBox(height: 20),
                  _buildResults(context),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntro(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ComposeSurface(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(
              Icons.image_search_rounded,
              color: scheme.onPrimaryContainer,
              size: 27,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.tr(
                    '用封面或漫画截图找到作品',
                    en: 'Find a comic from a cover or screenshot',
                  ),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.l10n.tr(
                    '支持带人物、对白或完整封面的图片。越清晰、干扰越少，识别越准确。',
                    en: 'Images with characters, dialogue, or a full cover work best. Clearer images produce better matches.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourcePicker(BuildContext context) {
    final disabled = _searching || _openingSource != null;
    final gallery = _ImageSourceCard(
      key: const ValueKey('image-search-gallery'),
      icon: Icons.photo_library_rounded,
      title: _openingSource == _ImageSourceKind.gallery
          ? context.l10n.tr('正在打开相册...', en: 'Opening gallery...')
          : context.l10n.tr('从相册选择', en: 'Choose from gallery'),
      subtitle: context.l10n.tr(
        '打开系统相册或照片选择器',
        en: 'Open the system gallery or photo picker',
      ),
      busy: _openingSource == _ImageSourceKind.gallery,
      onTap: disabled
          ? null
          : () => _chooseImage(
                _ImageSourceKind.gallery,
                widget.pickGallery ?? _pickFromGallery,
              ),
    );
    final files = _ImageSourceCard(
      key: const ValueKey('image-search-files'),
      icon: Icons.folder_open_rounded,
      title: _openingSource == _ImageSourceKind.files
          ? context.l10n.tr('正在打开文件管理...', en: 'Opening files...')
          : context.l10n.tr('从文件管理选择', en: 'Choose from files'),
      subtitle: context.l10n.tr(
        '浏览文件夹中的 JPG、PNG、WebP 或 GIF',
        en: 'Browse JPG, PNG, WebP, or GIF files',
      ),
      busy: _openingSource == _ImageSourceKind.files,
      onTap: disabled
          ? null
          : () => _chooseImage(
                _ImageSourceKind.files,
                widget.pickFiles ?? _pickFromFiles,
              ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 580) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: gallery),
              const SizedBox(width: 12),
              Expanded(child: files),
            ],
          );
        }
        return Column(
          children: [
            gallery,
            const SizedBox(height: 10),
            files,
          ],
        );
      },
    );
  }

  Widget _buildPreview(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        key: const ValueKey('image-search-preview'),
        height: 190,
        color: scheme.surfaceContainerHighest,
        child: Image.file(
          File(_imagePath!),
          width: double.infinity,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => Center(
            child: Icon(
              Icons.broken_image_outlined,
              size: 38,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ComposeSurface(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          SizedBox(
            width: 25,
            height: 25,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.tr('正在识别漫画', en: 'Recognizing comic'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.l10n.tr(
                    '图片会发送至 soutubot.moe 进行本次识别',
                    en: 'The image is sent to soutubot.moe for this search',
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ComposeSurface(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _error!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_hits.isEmpty) {
      return ComposeSurface(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
        child: Column(
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 42,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.tr(
                '没有识别到可搜索的漫画',
                en: 'No searchable comic was found',
              ),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.tr(
                '请换一张更清晰、裁切更完整的图片',
                en: 'Try a clearer image with the cover or panel fully visible.',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.tr(
                  '识别到 ${_hits.length} 个候选',
                  en: '${_hits.length} matches found',
                ),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Text(
              context.l10n.tr('按相似度排序', en: 'Ranked by similarity'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < _hits.length; index++) ...[
          _ImageSearchHitCard(
            key: ValueKey('image-search-candidate-$index'),
            hit: _hits[index],
            onTap: () => Navigator.of(context).pop(_hits[index]),
          ),
          if (index != _hits.length - 1) const SizedBox(height: 9),
        ],
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.privacy_tip_outlined,
              size: 15,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                context.l10n.tr(
                  '识图由 soutubot.moe 提供；图片会发送至该服务进行本次识别。',
                  en: 'Recognition is provided by soutubot.moe; the image is sent there for this search.',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ImageSourceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool busy;

  const _ImageSourceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.busy = false,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: .62),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: busy
                    ? SizedBox(
                        key: const ValueKey('image-source-opening'),
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                      )
                    : Icon(
                        Icons.chevron_right_rounded,
                        key: const ValueKey('image-source-idle'),
                        color: scheme.onSurfaceVariant,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageSearchHitCard extends StatelessWidget {
  final ImageSearchHit hit;
  final VoidCallback onTap;

  const _ImageSearchHitCard({
    required this.hit,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isJm = hit.source.toLowerCase() == 'jmcomic';
    final details = <String>[
      hit.sourceLabel,
      if (_imageLanguageLabel(hit.language).isNotEmpty)
        _imageLanguageLabel(hit.language),
      if (hit.page > 0)
        context.l10n.tr('第 ${hit.page} 页', en: 'Page ${hit.page}'),
    ].join(' · ');
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: .62),
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        leading: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Text(
            '${hit.similarity.round()}%',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        title: Text(
          hit.displayTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Icon(
          isJm ? Icons.menu_book_rounded : Icons.search_rounded,
          color: scheme.primary,
        ),
      ),
    );
  }
}

String _imageLanguageLabel(String value) {
  switch (value.toLowerCase()) {
    case 'zh':
    case 'cn':
    case 'chinese':
      return '中文';
    case 'ja':
    case 'jp':
    case 'japanese':
      return '日文';
    case 'en':
    case 'gb':
    case 'english':
      return '英文';
    case 'ko':
    case 'kr':
    case 'korean':
      return '韩文';
    default:
      return value;
  }
}
