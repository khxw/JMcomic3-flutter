import 'dart:async';
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
import '../configs/remember_login.dart';
import 'app_screen.dart';

const firstLoginScreen = FirstLoginScreen();

class FirstLoginScreen extends StatefulWidget {
  const FirstLoginScreen({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _FirstLoginScreenState();
}

class _FirstLoginScreenState extends State<FirstLoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _logging = false;
  bool _obscurePassword = true;
  bool _rememberCredentials = true;
  int _onClickVersion = 0;

  Future<void> _loadRememberedCredentials() async {
    try {
      final saved = await loadRememberedLogin();
      if (!mounted) return;
      setState(() {
        _usernameController.text = saved.username;
        _passwordController.text = saved.password;
        _rememberCredentials = saved.remember;
      });
    } catch (_) {
      // The fields remain editable when remembered credentials cannot be read.
    }
  }

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

  Future<void> _submitLogin() async {
    if (_logging) return;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      defaultToast(
        context,
        context.l10n.tr(
          '请输入账号和密码',
          en: 'Enter your account and password',
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _logging = true;
    });
    await login(
      username,
      password,
      context,
      rememberCredentials: _rememberCredentials,
    );
    await reloadIsPro();
    if (!mounted) return;
    if (loginStatus != LoginStatus.loginSuccess) {
      defaultToast(context, loginMessage);
      setState(() {
        _logging = false;
      });
      return;
    }
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (BuildContext context) {
        return const AppScreen();
      },
    ));
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadRememberedCredentials());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('JMComic3 Mod'),
        actions: _logging
            ? []
            : [
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
              ],
      ),
      body: _logging ? _loading() : _form(),
    );
  }

  Widget _loading() {
    return const Center(child: ContentLoading());
  }

  Widget _form() {
    final l10n = context.l10n;
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
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: TextField(
                  key: const ValueKey('first-login-username'),
                  controller: _usernameController,
                  enabled: !_logging,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.account,
                    hintText: l10n.inputAccount,
                    prefixIcon: const Icon(Icons.alternate_email_rounded),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: TextField(
                  key: const ValueKey('first-login-password'),
                  controller: _passwordController,
                  enabled: !_logging,
                  autofillHints: const [AutofillHints.password],
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submitLogin(),
                  decoration: InputDecoration(
                    labelText: l10n.password,
                    hintText: l10n.inputPassword,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: l10n.tr(
                        _obscurePassword ? '显示密码' : '隐藏密码',
                        en: _obscurePassword
                            ? 'Show password'
                            : 'Hide password',
                      ),
                      onPressed: _logging
                          ? null
                          : () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
              ),
              CheckboxListTile(
                key: const ValueKey('first-login-remember-credentials'),
                value: _rememberCredentials,
                enabled: !_logging,
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  l10n.tr(
                    '记住账号密码',
                    en: 'Remember account and password',
                  ),
                ),
                onChanged: _logging
                    ? null
                    : (value) {
                        final remember = value ?? false;
                        setState(() => _rememberCredentials = remember);
                        if (!remember) {
                          unawaited(
                            clearRememberedLogin().catchError((_) {}),
                          );
                        }
                      },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('first-login-submit'),
                    onPressed: _logging ? null : _submitLogin,
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
      ],
    );
  }
}
