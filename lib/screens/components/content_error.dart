import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'error_types.dart';

class ContentError extends StatefulWidget {
  final Object? error;
  final StackTrace? stackTrace;
  final Future<void> Function() onRefresh;

  const ContentError({
    Key? key,
    required this.error,
    required this.stackTrace,
    required this.onRefresh,
  }) : super(key: key);

  @override
  State<ContentError> createState() => _ContentErrorState();
}

class _ContentErrorState extends State<ContentError> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _logError();
  }

  @override
  void didUpdateWidget(covariant ContentError oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.error != widget.error) _logError();
  }

  void _logError() {
    debugPrient('${widget.error}');
    debugPrient('${widget.stackTrace}');
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } catch (error, stackTrace) {
      debugPrient(
        'content refresh failed: ${error.runtimeType}/${stackTrace.runtimeType}',
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = errorType('${widget.error}');
    final scheme = Theme.of(context).colorScheme;
    late final IconData icon;
    late final String title;
    late final String detail;

    switch (type) {
      case ERROR_TYPE_NETWORK:
        icon = Icons.wifi_off_rounded;
        title = context.l10n.tr('网络连接失败', en: 'Connection failed');
        detail = context.l10n.tr(
          '请检查网络后重新加载',
          en: 'Check your network and try again',
        );
        break;
      case ERROR_TYPE_PERMISSION:
        icon = Icons.folder_off_outlined;
        title = context.l10n.tr('无法访问内容', en: 'Unable to access content');
        detail = context.l10n.tr(
          '请检查存储权限或路径设置',
          en: 'Check storage permissions or path settings',
        );
        break;
      case ERROR_TYPE_TIME:
        icon = Icons.schedule_rounded;
        title = context.l10n.tr('设备时间异常', en: 'Check device time');
        detail = context.l10n.tr(
          '请将系统时间校准后重新加载',
          en: 'Correct the system time and try again',
        );
        break;
      case ERROR_TYPE_UNDER_REVIEW:
        icon = Icons.hourglass_top_rounded;
        title = context.l10n.tr('内容暂不可用', en: 'Content unavailable');
        detail = context.l10n.tr(
          '资源可能正在审核，请稍后再试',
          en: 'This resource may be under review. Try again later',
        );
        break;
      default:
        icon = Icons.cloud_off_rounded;
        title = context.l10n.tr('内容加载失败', en: 'Unable to load content');
        detail = context.l10n.tr(
          '服务暂时没有响应，请稍后重新加载',
          en: 'The service did not respond. Try again shortly',
        );
        break;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 20,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainer.withValues(alpha: .84),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: .56),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 68,
                        height: 68,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: .62),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 34, color: scheme.primary),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        detail,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.45,
                            ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const ValueKey('content-error-refresh'),
                          onPressed: _refreshing ? null : _refresh,
                          icon: _refreshing
                              ? const SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 19),
                          label: Text(
                            _refreshing
                                ? context.l10n.tr('正在刷新', en: 'Refreshing')
                                : context.l10n.tr('重新加载', en: 'Reload'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
