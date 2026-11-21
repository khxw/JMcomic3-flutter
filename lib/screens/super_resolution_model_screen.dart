import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/super_resolution.dart';
import 'package:jmcomic3/configs/super_resolution_models.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import 'components/app_back_button.dart';

class SuperResolutionModelScreen extends StatefulWidget {
  const SuperResolutionModelScreen({super.key});

  @override
  State<SuperResolutionModelScreen> createState() =>
      _SuperResolutionModelScreenState();
}

class _SuperResolutionModelScreenState
    extends State<SuperResolutionModelScreen> {
  bool _loading = true;
  String? _busyModelId;
  String? _error;
  int _received = 0;
  int? _total;
  List<SuperResolutionModel> _models = const [];
  String? _homeDir;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final homeDir = await methods.getHomeDir();
      final models = await loadSuperResolutionModels();
      if (!mounted) return;
      setState(() {
        _homeDir = homeDir;
        _models = models;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _download(SuperResolutionModel model) async {
    final homeDir = _homeDir;
    if (homeDir == null || _busyModelId != null) return;
    final confirmed = await confirmDialog(
      context,
      context.l10n.tr('下载超分模型', en: 'Download super-resolution model'),
      context.l10n.tr(
        '将下载 ${formatModelBytes(model.archiveBytes)}，'
        '并在校验 ${model.sha256.substring(0, 12)}… 后安装。',
        en: 'Download ${formatModelBytes(model.archiveBytes)} and verify '
            '${model.sha256.substring(0, 12)}… before installation.',
      ),
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busyModelId = model.id;
      _received = 0;
      _total = model.archiveBytes;
    });
    try {
      await installSuperResolutionModel(
        homeDir: homeDir,
        model: model,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total ?? model.archiveBytes;
          });
        },
      );
      await loadSuperResolutionState(force: true);
      invalidateSuperResolutionCache();
      if (!mounted) return;
      defaultToast(
        context,
        context.l10n.tr('超分模型安装完成', en: 'Model installed'),
      );
    } catch (error) {
      if (mounted) {
        defaultToast(
          context,
          context.l10n.tr('模型下载失败：$error', en: 'Model download failed: $error'),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyModelId = null;
          _received = 0;
          _total = null;
        });
      }
    }
  }

  Future<void> _delete(SuperResolutionModel model) async {
    final homeDir = _homeDir;
    if (homeDir == null || _busyModelId != null) return;
    final confirmed = await confirmDialog(
      context,
      context.l10n.tr('删除超分模型', en: 'Delete model'),
      context.l10n.tr(
        '删除后再次阅读时需要重新下载模型。',
        en: 'The model must be downloaded again before its next use.',
      ),
    );
    if (!confirmed || !mounted) return;
    await deleteSuperResolutionModel(homeDir, model.id);
    await loadSuperResolutionState(force: true);
    invalidateSuperResolutionCache();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      key: const ValueKey('super-resolution-model-page'),
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(l10n.tr('漫画超分模型', en: 'Comic upscale models')),
        actions: [
          IconButton(
            tooltip: l10n.tr('刷新', en: 'Refresh'),
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: [
                      _InfoCard(
                        text: l10n.tr(
                          '模型按需下载，不包含在 APK 中。下载后会校验 SHA-256，'
                          '失败时不影响正常阅读。',
                          en: 'Models are downloaded on demand and are not '
                              'bundled in the APK. SHA-256 is verified before '
                              'installation, and failures never block reading.',
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        _InfoCard(
                          text: l10n.tr(
                            '模型清单加载失败：$_error',
                            en: 'Unable to load model manifest: $_error',
                          ),
                          error: true,
                        ),
                      ],
                      if (!_loading && _models.isEmpty) ...[
                        const SizedBox(height: 12),
                        _InfoCard(
                          text: l10n.tr(
                            '当前仓库还没有发布超分模型包。',
                            en: 'No model package is currently published.',
                          ),
                        ),
                      ],
                      for (final model in _models) ...[
                        const SizedBox(height: 12),
                        _ModelCard(
                          model: model,
                          installed: _homeDir != null &&
                              isSuperResolutionModelInstalled(
                                _homeDir!,
                                model,
                              ),
                          busy: _busyModelId == model.id,
                          received: _received,
                          total: _total,
                          onDownload: () => _download(model),
                          onDelete: () => _delete(model),
                          onLicense: () => launch(model.licenseUrl),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String text;
  final bool error;

  const _InfoCard({required this.text, this.error = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error ? scheme.errorContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (error ? scheme.error : scheme.outlineVariant)
              .withValues(alpha: .45),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: error ? scheme.onErrorContainer : scheme.onSurfaceVariant,
          height: 1.45,
        ),
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  final SuperResolutionModel model;
  final bool installed;
  final bool busy;
  final int received;
  final int? total;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onLicense;

  const _ModelCard({
    required this.model,
    required this.installed,
    required this.busy,
    required this.received,
    required this.total,
    required this.onDownload,
    required this.onDelete,
    required this.onLicense,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final progress = total != null && total! > 0
        ? (received / total!).clamp(0.0, 1.0)
        : null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${model.scale}× · ${model.version} · '
                      '${formatModelBytes(model.archiveBytes)}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (installed)
                Icon(Icons.check_circle_rounded, color: scheme.primary),
            ],
          ),
          if (model.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(model.description),
          ],
          if (busy) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 6),
            Text(
              l10n.tr(
                '正在下载 ${formatModelBytes(received)}'
                '${total == null ? '' : ' / ${formatModelBytes(total!)}'}',
                en: 'Downloading ${formatModelBytes(received)}'
                    '${total == null ? '' : ' / ${formatModelBytes(total!)}'}',
              ),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: busy || installed ? null : onDownload,
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  installed
                      ? l10n.tr('已安装', en: 'Installed')
                      : l10n.tr('下载并安装', en: 'Download and install'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onLicense,
                icon: const Icon(Icons.description_outlined),
                label: Text(model.licenseName),
              ),
              if (installed)
                TextButton.icon(
                  onPressed: busy ? null : onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(l10n.tr('删除模型', en: 'Delete model')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
