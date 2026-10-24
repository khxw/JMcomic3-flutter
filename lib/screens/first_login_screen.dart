import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import '../basic/commons.dart';
import '../configs/versions.dart';
import 'components/content_loading.dart';
import 'components/app_icon.dart';
import '../configs/is_pro.dart';
import '../configs/login.dart';
import '../configs/network_api_host.dart';
import '../configs/network_cdn_host.dart';
import 'app_screen.dart';
import 'components/recommend_links_panel.dart';

const firstLoginScreen = FirstLoginScreen();

class FirstLoginScreen extends StatefulWidget {
  const FirstLoginScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _FirstLoginScreenState();
}

class _FirstLoginScreenState extends State<FirstLoginScreen> {
  bool _logging = false;
  String _username = "";
  String _password = "";
  int _onClickVersion = 0;

  Future<void> _continueAsGuest() async {
    setState(() {
      _logging = true;
    });
    await enterGuestMode();
    await reloadIsPro();
    if (!mounted) {
      return;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (BuildContext context) {
        return const AppScreen();
      },
    ));
  }

  Widget _usernameField() {
    final l10n = context.l10n;
    return ListTile(
      title: Text(l10n.account),
      subtitle: Text(_username),
      onTap: () async {
        final input = await displayTextInputDialog(
          context,
          hint: l10n.inputAccount,
          title: l10n.account,
          src: _username,
        );
        if (input != null) {
          setState(() {
            _username = input;
          });
        }
      },
    );
  }

  Widget _passwordField() {
    final l10n = context.l10n;
    return ListTile(
      title: Text(l10n.password),
      subtitle: Text(_password.isEmpty ? "" : '********'),
      onTap: () async {
        final input = await displayTextInputDialog(
          context,
          hint: l10n.inputPassword,
          title: l10n.password,
          isPasswd: true,
          src: _password,
        );
        if (input != null) {
          setState(() {
            _password = input;
          });
        }
      },
    );
  }

  late final _saveButton = IconButton(
    onPressed: () async {
      setState(() {
        _logging = true;
      });
      await login(_username, _password, context);
      await reloadIsPro();
      if (loginStatus != LoginStatus.loginSuccess) {
        defaultToast(context, loginMessage);
        setState(() {
          _logging = false;
        });
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (BuildContext context) {
            return const AppScreen();
          },
        ));
      }
    },
    icon: const Icon(Icons.save),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: const Text('JMComic3 Mod'),
        actions: _logging
            ? []
            : [
                IconButton(
                  onPressed: _continueAsGuest,
                  tooltip: l10n.guestMode,
                  icon: const Icon(Icons.explore_outlined),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _onClickVersion++;
                    });
                    if (_onClickVersion >= 7) {
                      openUrl(String.fromCharCodes(base64Decode(
                          "aHR0cHM6Ly9qbWNvbWljMS5yb2Nrcy9zaWdudXA=")));
                    }
                  },
                  icon: Text(currentVersion()),
                ),
                _saveButton,
              ],
      ),
      body: _logging ? _loading() : _form(),
    );
  }

  Widget _loading() {
    return const Center(child: ContentLoading());
  }

  Widget _form() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        Row(
          children: [
            const AppIcon(size: 54, borderRadius: 15),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.tr('欢迎使用', en: 'Welcome'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.l10n.tr(
                      '登录账号，或直接以游客模式开始阅读',
                      en: 'Sign in or continue directly in guest mode',
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              _usernameField(),
              const Divider(height: 1),
              _passwordField(),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('first-login-submit'),
                    onPressed: _saveButton.onPressed,
                    icon: const Icon(Icons.login_rounded, size: 19),
                    label: Text(context.l10n.login),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            key: const ValueKey('first-login-guest'),
            leading: const Icon(Icons.explore_outlined),
            title: Text(context.l10n.guestMode),
            subtitle: Text(context.l10n.guestModeSubtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _continueAsGuest,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          context.l10n.networkSettings,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              apiHostSetting(),
              const Divider(height: 1),
              cdnHostSetting(),
            ],
          ),
        ),
        const LoginAgreementHint(
          padding: EdgeInsets.fromLTRB(4, 14, 4, 4),
        ),
        const RecommendLinksPanel(),
      ],
    );
  }
}
