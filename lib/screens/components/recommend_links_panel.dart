import 'package:flutter/material.dart';

import '../../basic/commons.dart';
import '../../configs/disable_recommend_content.dart';
import '../../configs/is_pro.dart';
import '../../configs/recommend_links.dart';
import '../../configs/versions.dart';
import '../../l10n/app_localizations.dart';

class RecommendLinksPanel extends StatefulWidget {
  final EdgeInsetsGeometry padding;

  const RecommendLinksPanel({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  @override
  State<StatefulWidget> createState() => _RecommendLinksPanelState();
}

class _RecommendLinksPanelState extends State<RecommendLinksPanel> {
  @override
  void initState() {
    recommendLinksEvent.subscribe(_setState);
    disableRecommendContentEvent.subscribe(_setState);
    super.initState();
  }

  @override
  void dispose() {
    recommendLinksEvent.unsubscribe(_setState);
    disableRecommendContentEvent.unsubscribe(_setState);
    super.dispose();
  }

  void _setState(_) {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final links = currentRecommendLinks();
    if (hasProAccess && currentDisableRecommendContent()) {
      return const SizedBox.shrink();
    }

    final filteredLinks = links.entries.where((entry) {
      return !entry.key.contains("网络加速");
    }).toList();

    final displayLinks = <String, String>{};
    final usedUrls = <String>{};
    void addLink(String label, String url) {
      final normalized = url.trim();
      if (label.trim().isEmpty ||
          normalized.isEmpty ||
          !usedUrls.add(normalized)) {
        return;
      }
      displayLinks[label.trim()] = normalized;
    }

    for (final entry in filteredLinks) {
      addLink(entry.key, entry.value);
    }
    addLink(
      context.l10n.tr('项目主页', en: 'Project page'),
      projectHomeUrl,
    );
    addLink(
      context.l10n.tr('问题反馈', en: 'Feedback'),
      '$projectHomeUrl/issues',
    );

    return Container(
      key: const ValueKey('profile-project-links'),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: .48),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 17,
                color: scheme.primary,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  context.l10n.tr('项目链接', en: 'Project links'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final entry in displayLinks.entries)
                Material(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => openUrl(entry.value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 7,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Text(
                              entry.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
