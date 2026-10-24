import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:jmcomic3/configs/user_agreement.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/app_icon.dart';

class UserAgreementScreen extends StatefulWidget {
  const UserAgreementScreen({super.key});

  @override
  State<UserAgreementScreen> createState() => _UserAgreementScreenState();
}

class _UserAgreementScreenState extends State<UserAgreementScreen> {
  var _step = 0;
  var _agreed = false;
  var _saving = false;
  var _allowPop = false;

  Future<void> _accept() async {
    if (!_agreed || _saving) return;
    setState(() => _saving = true);
    try {
      await acceptCurrentUserAgreement();
      if (!mounted) return;
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.tr(
              '无法保存协议状态，请重试。',
              en: 'Could not save your choice. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          context.l10n.tr('退出应用', en: 'Exit app'),
        ),
        content: Text(
          context.l10n.tr(
            '未同意用户协议，将无法继续使用应用。确定退出吗？',
            en: 'You cannot continue without accepting the agreement. Exit the app?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.tr('返回', en: 'Back')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.tr('退出', en: 'Exit')),
          ),
        ],
      ),
    );
    if (shouldExit != true) return;
    if (Platform.isAndroid) {
      await SystemNavigator.pop();
    } else {
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _allowPop,
      child: Scaffold(
        key: const ValueKey('user-agreement-screen'),
        backgroundColor: scheme.surface,
        body: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _step == 0
              ? _WelcomeStep(
                  key: const ValueKey('agreement-welcome-step'),
                  onContinue: () => setState(() => _step = 1),
                )
              : _AgreementStep(
                  key: const ValueKey('agreement-terms-step'),
                  agreed: _agreed,
                  saving: _saving,
                  onBack: () => setState(() => _step = 0),
                  onAgreedChanged: (value) {
                    setState(() => _agreed = value);
                  },
                  onAccept: _accept,
                  onExit: _confirmExit,
                ),
        ),
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  final VoidCallback onContinue;

  const _WelcomeStep({
    super.key,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.surface,
            scheme.tertiaryContainer.withValues(alpha: .62),
          ],
          stops: const [0, .56, 1],
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 44,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Spacer(),
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: .22),
                                  blurRadius: 28,
                                  offset: const Offset(0, 14),
                                ),
                              ],
                            ),
                            child: const AppIcon(
                              size: 96,
                              borderRadius: 24,
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            'JMComic3 Mod',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.l10n.tr(
                              '浏览、阅读与管理你的漫画收藏',
                              en: 'Browse, read, and manage your comic collection',
                            ),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const _WelcomeFeatures(),
                          const Spacer(),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              key: const ValueKey('agreement-welcome-continue'),
                              onPressed: onContinue,
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                child: Text(
                                  context.l10n.tr(
                                    '继续',
                                    en: 'Continue',
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            context.l10n.tr(
                              '下一步将展示用户协议',
                              en: 'The next step shows the user agreement',
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
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
        ),
      ),
    );
  }
}

class _WelcomeFeatures extends StatelessWidget {
  const _WelcomeFeatures();

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        Icons.explore_rounded,
        context.l10n.tr('发现与搜索', en: 'Discover'),
      ),
      (
        Icons.menu_book_rounded,
        context.l10n.tr('舒适阅读', en: 'Read'),
      ),
      (
        Icons.collections_bookmark_rounded,
        context.l10n.tr('本地书架', en: 'Library'),
      ),
      (
        Icons.download_for_offline_rounded,
        context.l10n.tr('下载管理', en: 'Downloads'),
      ),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 9,
      runSpacing: 9,
      children: [
        for (final item in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.surface.withValues(alpha: .74),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: .7),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.$1, size: 17),
                const SizedBox(width: 6),
                Text(item.$2),
              ],
            ),
          ),
      ],
    );
  }
}

class _AgreementStep extends StatelessWidget {
  final bool agreed;
  final bool saving;
  final VoidCallback onBack;
  final ValueChanged<bool> onAgreedChanged;
  final VoidCallback onAccept;
  final VoidCallback onExit;

  const _AgreementStep({
    super.key,
    required this.agreed,
    required this.saving,
    required this.onBack,
    required this.onAgreedChanged,
    required this.onAccept,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      key: const ValueKey('agreement-back'),
                      onPressed: saving ? null : onBack,
                      tooltip: context.l10n.tr('返回', en: 'Back'),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        context.l10n.tr('用户协议', en: 'User agreement'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        userAgreementVersion,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: .55),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: const SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(17, 17, 17, 22),
                      child: UserAgreementContent(),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Material(
                  color: agreed
                      ? scheme.primaryContainer.withValues(alpha: .55)
                      : scheme.surfaceContainerHighest.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(15),
                  clipBehavior: Clip.antiAlias,
                  child: CheckboxListTile(
                    key: const ValueKey('agreement-accept-checkbox'),
                    value: agreed,
                    onChanged: saving
                        ? null
                        : (value) => onAgreedChanged(value ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      context.l10n.tr(
                        '我已阅读并同意用户协议',
                        en: 'I have read and agree to the user agreement',
                      ),
                    ),
                    dense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton(
                      key: const ValueKey('agreement-exit'),
                      onPressed: saving ? null : onExit,
                      child: Text(
                        context.l10n.tr('不同意', en: 'Decline'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('agreement-accept'),
                        onPressed: agreed && !saving ? onAccept : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  context.l10n.tr(
                                    '同意并继续',
                                    en: 'Agree and continue',
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
