import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/Authentication.dart';
import 'package:jmcomic3/configs/configs.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/configs/user_agreement.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/app_icon.dart';

import '../basic/web_dav_sync.dart';
import '../configs/passed.dart';
import 'app_screen.dart';
import 'first_login_screen.dart';
import 'network_setting_screen.dart';
import 'user_agreement_screen.dart';

class InitScreen extends StatefulWidget {
  const InitScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _InitScreenState();
}

class _InitScreenState extends State<InitScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      key: const ValueKey('branded-init-screen'),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primaryContainer,
              scheme.surface,
              scheme.tertiaryContainer.withValues(alpha: .55),
            ],
            stops: const [0, .58, 1],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: TweenAnimationBuilder<double>(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 420),
                tween: Tween(begin: 0, end: 1),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppIcon(size: 88, borderRadius: 23),
                    const SizedBox(height: 20),
                    Text(
                      'JMComic3 Mod',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.4,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      context.l10n.tr(
                        '正在准备你的阅读空间',
                        en: 'Preparing your reading space',
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      key: const ValueKey('init-loading-indicator'),
                      width: 150,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: const LinearProgressIndicator(minHeight: 5),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      context.l10n.initializing,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future _init() async {
    try {
      await methods.init();
      await initConfigs(context);
      debugPrient("STATE : $loginStatus");
      if (!currentPassed()) {
        await firstPassed();
      }
      if (!await hasAcceptedCurrentUserAgreement()) {
        if (!mounted) return;
        final accepted = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const UserAgreementScreen(),
          ),
        );
        if (!mounted || accepted != true) return;
      }
      await _continueStartup();
    } catch (e, st) {
      debugPrient("$e\n$st");
      defaultToast(context, context.l10n.initFailedSetNetwork);
      Future.delayed(Duration.zero, () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (BuildContext context) {
            return const NetworkSettingScreen();
          }),
        );
      });
    }
  }

  Future<void> _continueStartup() async {
    if (currentAuthentication()) {
      await webDavSyncAuto(context);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      return;
    }
    if (loginStatus == LoginStatus.notSet) {
      await webDavSyncAuto(context);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => firstLoginScreen),
      );
      return;
    }
    await webDavSyncAuto(context);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AppScreen()),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () {
      test();
    });
  }

  test() async {
    if (await verifyAuthentication(context)) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (BuildContext context) {
          return const AppScreen();
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.authTitle),
      ),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          child: MaterialButton(
            onPressed: () async {
              test();
            },
            child: Text(context.l10n.authPrompt),
          ),
        ),
      ),
    );
  }
}
