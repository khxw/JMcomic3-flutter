import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

String proCenterExpiryLabel(int unixSeconds) {
  if (unixSeconds <= 0) return '有效期未提供';
  final date = DateTime.fromMillisecondsSinceEpoch(
    unixSeconds * 1000,
  ).toLocal();
  if (date.year >= 2099) return '长期有效';
  String two(int value) => value.toString().padLeft(2, '0');
  return '有效期至 ${date.year}-${two(date.month)}-${two(date.day)}';
}

class ProCenterBackground extends StatelessWidget {
  final Widget child;

  const ProCenterBackground({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primary.withValues(alpha: .07),
            scheme.surface,
          ],
          stops: const [0, .38],
        ),
      ),
      child: child,
    );
  }
}

class ProCenterHeroCard extends StatelessWidget {
  final String username;
  final bool active;
  final String expiry;

  const ProCenterHeroCard({
    required this.username,
    required this.active,
    required this.expiry,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: .78),
            scheme.tertiaryContainer.withValues(alpha: .42),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.onPrimaryContainer.withValues(alpha: .08),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -5,
            bottom: -16,
            child: Icon(
              active ? Icons.offline_bolt_rounded : Icons.offline_bolt_outlined,
              size: 112,
              color: scheme.onPrimaryContainer.withValues(alpha: .07),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: scheme.onPrimaryContainer.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(
                      active
                          ? Icons.offline_bolt_rounded
                          : Icons.offline_bolt_outlined,
                      size: 29,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          active ? '发电状态已激活' : '发电状态未激活',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          username.trim().isEmpty ? '游客账号' : username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onPrimaryContainer
                                .withValues(alpha: .72),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.onPrimaryContainer.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 15,
                      color: scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        expiry,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ProCenterSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? child;
  final VoidCallback? onTap;
  final Widget? trailing;

  const ProCenterSectionCard({
    required this.icon,
    required this.title,
    this.subtitle,
    this.child,
    this.onTap,
    this.trailing,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: 14),
            child!,
          ],
        ],
      ),
    );

    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: .45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

class ProCenterInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const ProCenterInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: scheme.onSurfaceVariant),
          const SizedBox(width: 9),
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: valueColor ?? scheme.onSurface,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProCenterServerCard extends StatefulWidget {
  const ProCenterServerCard({super.key});

  @override
  State<ProCenterServerCard> createState() => _ProCenterServerCardState();
}

class _ProCenterServerCardState extends State<ProCenterServerCard> {
  String _serverName = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    methods.getProServerName().then((value) {
      if (!mounted) return;
      setState(() {
        _serverName = value;
        _loading = false;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = switch (_serverName) {
      'HK' => context.l10n.tr('风力发电', en: 'Wind route'),
      'US' => context.l10n.tr('水力发电', en: 'Water route'),
      _ => context.l10n.tr('未选择', en: 'Not selected'),
    };
    return ProCenterSectionCard(
      icon: Icons.alt_route_rounded,
      title: context.l10n.tr('发电方式', en: 'Service route'),
      subtitle: _loading
          ? context.l10n.tr('正在读取当前线路', en: 'Loading the current route')
          : value,
      onTap: _chooseServer,
    );
  }

  Future<void> _chooseServer() async {
    final serverName = await chooseMapDialog<String>(
      context,
      title: context.l10n.tr('选择发电方式', en: 'Choose service route'),
      values: {
        context.l10n.tr('风力发电', en: 'Wind route'): 'HK',
        context.l10n.tr('水力发电', en: 'Water route'): 'US',
      },
    );
    if (serverName == null || serverName.isEmpty) return;
    await methods.setProServerName(serverName);
    if (!mounted) return;
    setState(() => _serverName = serverName);
  }
}
