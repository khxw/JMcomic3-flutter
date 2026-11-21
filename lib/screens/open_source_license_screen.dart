import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/open_source_licenses.dart';
import 'package:jmcomic3/configs/versions.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

import 'components/app_back_button.dart';

const _featuredPackages = <String>[
  'Tencent ncnn',
  'waifu2x-ncnn-vulkan',
  'zoomable_positioned_list',
  'zoomable_positioned_list Fuchsia components',
];

Future<Map<String, List<LicenseEntry>>>? _groupedLicenses;
Map<String, List<LicenseEntry>>? _groupedLicenseCache;

Map<String, List<LicenseEntry>>? get cachedGroupedLicenses =>
    _groupedLicenseCache;

Future<Map<String, List<LicenseEntry>>> loadGroupedLicenses({
  bool force = false,
}) {
  if (!force && _groupedLicenses != null) return _groupedLicenses!;
  return _groupedLicenses = _collectGroupedLicenses();
}

Future<Map<String, List<LicenseEntry>>> _collectGroupedLicenses() async {
  await ensureOpenSourceLicensesRegistered();
  final grouped = <String, List<LicenseEntry>>{};
  await for (final entry in LicenseRegistry.licenses) {
    for (final package in entry.packages) {
      final name = package.trim();
      if (name.isEmpty) continue;
      grouped.putIfAbsent(name, () => []).add(entry);
    }
  }
  final Map<String, List<LicenseEntry>> result = {
    for (final pair in grouped.entries)
      pair.key: List<LicenseEntry>.unmodifiable(pair.value),
  };
  _groupedLicenseCache = result;
  return result;
}

class OpenSourceLicenseScreen extends StatefulWidget {
  final String? applicationVersion;

  const OpenSourceLicenseScreen({
    super.key,
    this.applicationVersion,
  });

  @override
  State<OpenSourceLicenseScreen> createState() =>
      _OpenSourceLicenseScreenState();
}

class _OpenSourceLicenseScreenState extends State<OpenSourceLicenseScreen> {
  final TextEditingController _searchController = TextEditingController();
  late Future<Map<String, List<LicenseEntry>>> _licenses;
  Map<String, List<LicenseEntry>>? _initialLicenses;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _initialLicenses = cachedGroupedLicenses;
    _licenses = loadGroupedLicenses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openPackage(String package, List<LicenseEntry> entries) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LicenseDetailScreen(
          package: package,
          entries: entries,
        ),
      ),
    );
  }

  void _reload() {
    setState(() {
      _initialLicenses = cachedGroupedLicenses;
      _licenses = loadGroupedLicenses(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('open-source-license-page'),
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(context.l10n.tr('开源许可', en: 'Open-source licenses')),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: FutureBuilder<Map<String, List<LicenseEntry>>>(
              future: _licenses,
              initialData: _initialLicenses,
              builder: (context, snapshot) {
                final licenses = snapshot.data;
                if (licenses == null &&
                    snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || licenses == null) {
                  return _LicenseLoadError(
                    onRetry: _reload,
                  );
                }
                final packageNames = licenses.keys.toList()..sort(_compare);
                final filtered = _query.isEmpty
                    ? packageNames
                    : packageNames
                        .where((name) =>
                            name.toLowerCase().contains(_query.toLowerCase()))
                        .toList();
                final featured = _featuredPackages
                    .where(licenses.containsKey)
                    .toList(growable: false);
                return CustomScrollView(
                  key: const ValueKey('open-source-license-list'),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      sliver: SliverToBoxAdapter(
                        child: _LicenseHeader(
                          packages: licenses.length,
                          version:
                              widget.applicationVersion ?? currentVersion(),
                        ),
                      ),
                    ),
                    if (featured.isNotEmpty &&
                        filtered.length == packageNames.length)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                        sliver: SliverToBoxAdapter(
                          child: _FeaturedLicenses(
                            packages: featured,
                            licenses: licenses,
                            onOpen: _openPackage,
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    context.l10n.tr(
                                      '全部组件',
                                      en: 'All components',
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                Text(
                                  '${filtered.length}',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              key: const ValueKey('license-search'),
                              controller: _searchController,
                              textInputAction: TextInputAction.search,
                              onChanged: (value) =>
                                  setState(() => _query = value.trim()),
                              decoration: InputDecoration(
                                hintText: context.l10n.tr(
                                  '搜索组件或包名',
                                  en: 'Search components or package names',
                                ),
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _query.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: context.l10n.tr(
                                          '清除',
                                          en: 'Clear',
                                        ),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _query = '');
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                filled: true,
                                fillColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerLow,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (filtered.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptySearch(query: _query),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                        sliver: SliverList.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final package = filtered[index];
                            final entries = licenses[package]!;
                            return _LicensePackageCard(
                              package: package,
                              entryCount: entries.length,
                              onTap: () => _openPackage(package, entries),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _LicenseHeader extends StatelessWidget {
  final int packages;
  final String version;

  const _LicenseHeader({
    required this.packages,
    required this.version,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: .78),
            scheme.surfaceContainerLow,
          ],
        ),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: .45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: .82),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Image.asset('lib/assets/app_icon_foreground.png'),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'JMComic3 Mod',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      version,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$packages ${context.l10n.tr('组件', en: 'components')}',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            context.l10n.tr(
              '本应用基于 Flutter 构建，并包含 NCNN、Waifu2x 及其他开源组件。'
              '各组件版权归原作者所有，点击组件可查看完整许可证。',
              en: 'This app is built with Flutter and includes NCNN, Waifu2x '
                  'and other open-source components. Copyright belongs to the '
                  'respective authors; tap a component for the full license.',
            ),
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeaderChip(
                icon: Icons.flutter_dash_rounded,
                text: 'Flutter / Dart',
              ),
              _HeaderChip(icon: Icons.memory_rounded, text: 'NCNN'),
              _HeaderChip(icon: Icons.auto_awesome_rounded, text: 'Waifu2x'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HeaderChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .75),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _FeaturedLicenses extends StatelessWidget {
  final List<String> packages;
  final Map<String, List<LicenseEntry>> licenses;
  final void Function(String, List<LicenseEntry>) onOpen;

  const _FeaturedLicenses({
    required this.packages,
    required this.licenses,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.tr('核心组件', en: 'Core components'),
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: packages.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: MediaQuery.sizeOf(context).width >= 360 ? 2 : 1,
            mainAxisExtent: 108,
            crossAxisSpacing: 9,
            mainAxisSpacing: 9,
          ),
          itemBuilder: (context, index) {
            final package = packages[index];
            final entries = licenses[package]!;
            final (icon, license) = _featuredMetadata(package);
            return Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(17),
              child: InkWell(
                key: ValueKey('license-featured-${_packageSlug(package)}'),
                borderRadius: BorderRadius.circular(17),
                onTap: () => onOpen(package, entries),
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            icon,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const Spacer(),
                          const Icon(Icons.chevron_right_rounded, size: 20),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _displayPackageName(package),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        license,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _LicensePackageCard extends StatelessWidget {
  final String package;
  final int entryCount;
  final VoidCallback onTap;

  const _LicensePackageCard({
    required this.package,
    required this.entryCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: ValueKey('license-package-${_packageSlug(package)}'),
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  package,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                context.l10n.tr('$entryCount 份许可', en: '$entryCount licenses'),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class LicenseDetailScreen extends StatelessWidget {
  final String package;
  final List<LicenseEntry> entries;

  const LicenseDetailScreen({
    super.key,
    required this.package,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      key: const ValueKey('license-detail-page'),
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(
          package,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: SelectionArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      context.l10n.tr(
                        '以下许可证文本可长按选择复制。',
                        en: 'Long-press the license text to select and copy it.',
                      ),
                      style: TextStyle(color: scheme.onPrimaryContainer),
                    ),
                  ),
                  for (var index = 0; index < entries.length; index++) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: .4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.tr(
                              '许可证 ${index + 1}',
                              en: 'License ${index + 1}',
                            ),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          for (final paragraph in entries[index].paragraphs)
                            Padding(
                              padding: EdgeInsets.only(
                                left: math.max(0, paragraph.indent) * 12,
                                bottom: 8,
                              ),
                              child: Text(
                                paragraph.text,
                                style: const TextStyle(
                                  height: 1.48,
                                  fontFamily: 'monospace',
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LicenseLoadError extends StatelessWidget {
  final VoidCallback onRetry;

  const _LicenseLoadError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 40),
            const SizedBox(height: 10),
            Text(
              context.l10n.tr(
                '无法加载许可证列表。',
                en: 'Unable to load license information.',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: onRetry,
              child: Text(context.l10n.tr('重试', en: 'Retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  final String query;

  const _EmptySearch({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          context.l10n.tr(
            '没有找到与“$query”匹配的组件。',
            en: 'No components match "$query".',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

int _compare(String left, String right) =>
    left.toLowerCase().compareTo(right.toLowerCase());

String _packageSlug(String package) =>
    package.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

String _displayPackageName(String package) {
  return switch (package) {
    'Tencent ncnn' => 'NCNN',
    'waifu2x-ncnn-vulkan' => 'Waifu2x',
    'zoomable_positioned_list' => 'Zoomable Positioned List',
    'zoomable_positioned_list Fuchsia components' => 'Fuchsia components',
    _ => package,
  };
}

(IconData, String) _featuredMetadata(String package) {
  return switch (package) {
    'Tencent ncnn' => (Icons.memory_rounded, 'BSD 3-Clause'),
    'waifu2x-ncnn-vulkan' => (Icons.auto_awesome_rounded, 'MIT'),
    'zoomable_positioned_list' => (Icons.view_carousel_outlined, 'MIT'),
    'zoomable_positioned_list Fuchsia components' => (
        Icons.flutter_dash_rounded,
        'BSD 3-Clause',
      ),
    _ => (Icons.inventory_2_outlined, 'Open source'),
  };
}
