import 'dart:async';

import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/bool_property.dart';
import 'package:jmcomic3/configs/is_pro.dart';
import 'package:jmcomic3/configs/remember_login.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/configs/user_agreement.dart';

enum LoginStatus {
  notSet,
  logging,
  loginField,
  loginSuccess,
  guest,
}

late SelfInfo _selfInfo;
LoginStatus _status = LoginStatus.notSet;
String _loginMessage = "";
const _guestModePropertyName = "guest_mode";
bool _guestMode = false;
final Event _event = Event();

SelfInfo get selfInfo => _selfInfo;

Event get loginEvent => _event;

LoginStatus get loginStatus => _status;

String get loginMessage => _loginMessage;

bool get hasJwtAccess => _status == LoginStatus.loginSuccess;

bool get isGuestMode => _status == LoginStatus.guest;

set _loginState(LoginStatus value) {
  _status = value;
  _event.broadcast();
}

Future initLogin(BuildContext context) async {
  try {
    _guestMode = parseBoolPropertyValue(
      await methods.loadProperty(_guestModePropertyName),
      fallback: false,
    );
    _loginState = LoginStatus.logging;
    final preLogin = await methods.preLogin();
    _loginMessage = preLogin.message ?? "";
    if (!preLogin.preSet) {
      _loginState = _guestMode ? LoginStatus.guest : LoginStatus.notSet;
    } else if (preLogin.preLogin) {
      _guestMode = false;
      await methods.saveProperty(_guestModePropertyName, "false");
      _selfInfo = preLogin.selfInfo!;
      _loginState = LoginStatus.loginSuccess;
      fav(context);
    } else {
      _loginState = _guestMode ? LoginStatus.guest : LoginStatus.loginField;
    }
  } catch (e, st) {
    debugPrient("$e\n$st");
    _loginState = _guestMode ? LoginStatus.guest : LoginStatus.loginField;
  } finally {
    reloadIsPro();
  }
}

List<FavoriteFolderItem> favData = [];

Widget createFavoriteFolderItemTile(BuildContext context) {
  return ListTile(
    leading: const Icon(Icons.create_new_folder_outlined),
    title: Text(context.l10n.tr("创建收藏文件夹", en: "Create favorites folder")),
    onTap: () async {
      if (!await ensureJwtAccess(
        context,
        feature: context.l10n.tr("创建收藏夹", en: "Create favorites folder"),
      )) {
        return;
      }
      var name = await displayTextInputDialog(
        context,
        title: context.l10n.tr("创建收藏文件夹", en: "Create favorites folder"),
        hint: context.l10n.tr("文件夹名称", en: "Folder name"),
      );
      if (name == null) {
        return;
      }
      await methods.createFavoriteFolder(name);
      fav(context);
      defaultToast(
          context, context.l10n.tr("创建成功", en: "Created successfully"));
    },
  );
}

Widget deleteFavoriteFolderItemTile(BuildContext context) {
  return ListTile(
    leading: const Icon(Icons.folder_delete_outlined),
    title: Text(context.l10n.tr("删除收藏文件夹", en: "Delete favorites folder")),
    onTap: () async {
      if (!await ensureJwtAccess(
        context,
        feature: context.l10n.tr("删除收藏夹", en: "Delete favorites folder"),
      )) {
        return;
      }
      var j = favData.map((i) {
        return MapEntry(i.name, i.fid);
      }).toList();
      j.add(MapEntry(context.l10n.tr("默认 / 不删除", en: "Default / Keep"), 0));
      var v = await chooseMapDialog<int>(
        context,
        title: context.l10n.tr("删除资料夹", en: "Delete folder"),
        values: Map.fromEntries(j),
      );
      if (v != null && v != 0) {
        await methods.deleteFavoriteFolder(v);
        fav(context);
        defaultToast(
            context, context.l10n.tr("删除成功", en: "Deleted successfully"));
      }
    },
  );
}

Widget renameFavoriteFolderItemTile(BuildContext context) {
  return ListTile(
    leading: const Icon(Icons.drive_file_rename_outline_rounded),
    title: Text(context.l10n.tr("重命名收藏文件夹", en: "Rename favorites folder")),
    onTap: () async {
      if (!await ensureJwtAccess(
        context,
        feature: context.l10n.tr("重命名收藏夹", en: "Rename favorites folder"),
      )) {
        return;
      }
      var j = favData.map((i) {
        return MapEntry(i.name, i.fid);
      }).toList();
      j.add(MapEntry(context.l10n.tr("默认 / 不重命名", en: "Default / Keep"), 0));
      var v = await chooseMapDialog<int>(
        context,
        title: context.l10n.tr("重命名资料夹", en: "Rename folder"),
        values: Map.fromEntries(j),
      );
      if (v != null && v != 0) {
        var name = await displayTextInputDialog(
          context,
          title: context.l10n.tr("重命名收藏文件夹", en: "Rename favorites folder"),
          hint: context.l10n.tr("文件夹名称", en: "Folder name"),
        );
        if (name == null) {
          return;
        }
        await methods.renameFavoriteFolder(v, name);
        fav(context);
        defaultToast(
            context, context.l10n.tr("重命名成功", en: "Renamed successfully"));
      }
    },
  );
}

Future fav(BuildContext buildContext) async {
  try {
    favData = (await methods.favorite()).folderList;
  } catch (e, st) {
    debugPrient("$e\n$st");
    defaultToast(buildContext, "$e");
  }
}

Future login(
  String username,
  String password,
  BuildContext context, {
  bool rememberCredentials = true,
}) async {
  try {
    _loginState = LoginStatus.logging;
    final selfInfo = await methods.login(username, password);
    _guestMode = false;
    await methods.saveProperty(_guestModePropertyName, "false");
    _selfInfo = selfInfo;
    _loginState = LoginStatus.loginSuccess;
    try {
      await saveRememberedLogin(
        username,
        password,
        remember: rememberCredentials,
      );
    } catch (error, stackTrace) {
      debugPrient(
          "remember login failed: ${error.runtimeType}/${stackTrace.runtimeType}");
    }
    fav(context);
  } catch (e, st) {
    debugPrient("$e\n$st");
    _loginState = LoginStatus.loginField;
    _loginMessage = "$e";
  }
}

Future<void> enterGuestMode() async {
  _guestMode = true;
  await methods.saveProperty(_guestModePropertyName, "true");
  _loginMessage = "";
  _loginState = LoginStatus.guest;
}

Future<void> logoutAccount() async {
  await methods.logout();
  favData = [];
  _guestMode = true;
  _loginMessage = "";
  _loginState = LoginStatus.guest;
  try {
    await methods.saveProperty(_guestModePropertyName, "true");
  } catch (error, stackTrace) {
    debugPrient(
        "guest mode persistence failed: ${error.runtimeType}/${stackTrace.runtimeType}");
  }
}

Future<bool> ensureJwtAccess(
  BuildContext context, {
  String? feature,
}) async {
  if (hasJwtAccess) {
    return true;
  }
  final shouldLogin = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      final l10n = context.l10n;
      final targetFeature = feature ?? l10n.tr("该功能", en: "This feature");
      return AlertDialog(
        title: Text(l10n.tr("登录提醒", en: "Login required")),
        content: Text(
          isGuestMode
              ? l10n.tr("当前是游客模式，$targetFeature 需要登录后才能使用。",
                  en: "Guest mode is active. $targetFeature requires login.")
              : l10n.tr("$targetFeature 需要登录后才能使用。",
                  en: "$targetFeature requires login."),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
            },
            child: Text(l10n.tr("取消", en: "Cancel")),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            child: Text(l10n.tr("去登录", en: "Go login")),
          ),
        ],
      );
    },
  );
  if (shouldLogin == true) {
    await loginDialog(context);
  }
  return hasJwtAccess;
}

Future loginDialog(BuildContext context) async {
  final scheme = Theme.of(context).colorScheme;
  await showDialog<void>(
    context: context,
    useSafeArea: true,
    barrierColor: scheme.scrim.withValues(alpha: .58),
    builder: (_) => const _LoginDialog(),
  );
}

Future showLoginAgreementBottomSheet(BuildContext context) async {
  await showMaterialModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: .56),
    useRootNavigator: true,
    enableDrag: true,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260),
    builder: (context) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .88,
            child: const _LoginAgreementSheet(),
          ),
        ),
      );
    },
  );
}

Future showUserAgreementBottomSheet(BuildContext context) {
  return showLoginAgreementBottomSheet(context);
}

Widget userAgreementSetting(BuildContext context) {
  return ListTile(
    leading: const Icon(Icons.description_outlined),
    onTap: () => showUserAgreementBottomSheet(context),
    title: Text(context.l10n.tr("用户协议", en: "User agreement")),
    subtitle:
        Text(context.l10n.tr("查看当前应用使用协议", en: "View current app agreement")),
  );
}

class LoginAgreementHint extends StatelessWidget {
  final EdgeInsetsGeometry padding;

  const LoginAgreementHint({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 8),
  });

  @override
  Widget build(BuildContext context) {
    final agreeStyle = Theme.of(context).textTheme.bodyMedium
        //        ?.copyWith(color: Colors.grey)
        ;
    final agreeLinkStyle = agreeStyle?.copyWith(
      decoration: TextDecoration.underline,
      // decorationColor: Colors.grey.shade600,
      // color: Colors.grey.shade600,
    );
    return Padding(
      padding: padding,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(context.l10n.tr("使用前请阅读 ", en: "Review the "),
              style: agreeStyle),
          InkWell(
            onTap: () => showLoginAgreementBottomSheet(context),
            child: Text(context.l10n.tr("使用协议", en: "Terms of use"),
                style: agreeLinkStyle),
          ),
        ],
      ),
    );
  }
}

class _LoginAgreementSheet extends StatelessWidget {
  const _LoginAgreementSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      key: const ValueKey('user-agreement-sheet'),
      color: scheme.surface,
      elevation: 18,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 9, 10, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primaryContainer,
                    scheme.tertiaryContainer.withValues(alpha: .52),
                  ],
                ),
                border: Border(
                  bottom: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: .55),
                  ),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: .22),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 13),
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: .66),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          Icons.policy_outlined,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.tr('用户协议', en: 'User agreement'),
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.l10n.tr(
                                '使用前请了解数据、内容与更新规则',
                                en: 'Review data, content, and update rules',
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onPrimaryContainer
                                    .withValues(alpha: .72),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('user-agreement-close'),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: context.l10n.tr('关闭', en: 'Close'),
                        icon: Icon(
                          Icons.close_rounded,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: .58),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '${context.l10n.tr("版本", en: "Version")} '
                        '$userAgreementVersion',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                key: const ValueKey('user-agreement-scroll'),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                children: [
                  const UserAgreementContent(),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 11, 16, 14),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(
                  top: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: .55),
                  ),
                ),
              ),
              child: FilledButton.icon(
                key: const ValueKey('user-agreement-got-it'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check_rounded, size: 19),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Text(
                    context.l10n.tr('我已阅读', en: 'I have read this'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog();

  @override
  State<StatefulWidget> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog>
    with WidgetsBindingObserver {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  Timer? _keyboardResetTimer;
  var _keyboardInsetCeiling = 0.0;
  var _rememberCredentials = true;
  var _obscurePassword = true;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final saved = await loadRememberedLogin();
      if (!mounted) return;
      setState(() {
        _usernameController.text = saved.username;
        _passwordController.text = saved.password;
        _rememberCredentials = saved.remember;
      });
    } catch (_) {
      // The fields remain editable when saved credentials cannot be read.
    }
  }

  @override
  void dispose() {
    _keyboardResetTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _keyboardResetTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final currentInset = MediaQuery.viewInsetsOf(context).bottom;
      _keyboardResetTimer = Timer(
        Duration(milliseconds: currentInset > 0 ? 180 : 450),
        () {
          if (!mounted) return;
          final settledInset = MediaQuery.viewInsetsOf(context).bottom;
          if (settledInset > 0) {
            if (settledInset > _keyboardInsetCeiling + .5) {
              setState(() => _keyboardInsetCeiling = settledInset);
            }
          } else if (_keyboardInsetCeiling > 0) {
            setState(() => _keyboardInsetCeiling = 0);
          }
        },
      );
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = context.l10n.tr(
            '请输入账号和密码',
            en: 'Enter your account and password',
          ));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    await login(
      username,
      password,
      context,
      rememberCredentials: _rememberCredentials,
    );
    await reloadIsPro();
    if (!mounted) return;
    if (loginStatus == LoginStatus.loginSuccess) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = loginMessage.trim().isEmpty
          ? context.l10n.tr('登录失败，请检查账号和密码', en: 'Login failed')
          : loginMessage;
    });
  }

  Future<void> _continueAsGuest() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    await enterGuestMode();
    await reloadIsPro();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom > _keyboardInsetCeiling
        ? media.viewInsets.bottom
        : _keyboardInsetCeiling;
    final stableMedia = media.copyWith(
      viewInsets: media.viewInsets.copyWith(bottom: keyboardInset),
    );
    final maxDialogHeight =
        media.size.height - keyboardInset - media.padding.vertical - 48;
    return MediaQuery(
      data: stableMedia,
      child: Dialog(
        key: const ValueKey('login-dialog'),
        alignment: Alignment.bottomCenter,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        insetAnimationDuration: const Duration(milliseconds: 220),
        insetAnimationCurve: Curves.easeOutCubic,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .55),
          ),
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween(
            end: maxDialogHeight.clamp(220, 760).toDouble(),
          ),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, maxHeight, child) => ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 440,
              maxHeight: maxHeight,
            ),
            child: child,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  scheme.primaryContainer,
                                  scheme.tertiaryContainer
                                      .withValues(alpha: .72),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.person_rounded,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.tr(
                                    '登录 JMComic3',
                                    en: 'Sign in to JMComic3',
                                  ),
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  context.l10n.tr(
                                    '登录后可同步收藏、评论与阅读记录',
                                    en: 'Sync favorites, comments, and reading history',
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: context.l10n.tr('关闭', en: 'Close'),
                            onPressed: _busy
                                ? null
                                : () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded, size: 21),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      AutofillGroup(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              key: const ValueKey('login-username'),
                              controller: _usernameController,
                              enabled: !_busy,
                              autofillHints: const [AutofillHints.username],
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: context.l10n.account,
                                hintText: context.l10n.inputAccount,
                                prefixIcon:
                                    const Icon(Icons.alternate_email_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                TextField(
                                  key: const ValueKey('login-password'),
                                  controller: _passwordController,
                                  enabled: !_busy,
                                  autofillHints: const [
                                    AutofillHints.password,
                                  ],
                                  keyboardType: TextInputType.text,
                                  autocorrect: false,
                                  enableSuggestions: true,
                                  obscureText: false,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submit(),
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: _obscurePassword
                                        ? Colors.transparent
                                        : null,
                                    fontFamily: 'monospace',
                                    letterSpacing: 2,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: context.l10n.password,
                                    hintText: context.l10n.inputPassword,
                                    prefixIcon:
                                        const Icon(Icons.lock_outline_rounded),
                                    suffixIcon: IconButton(
                                      tooltip: context.l10n.tr(
                                        _obscurePassword ? '显示密码' : '隐藏密码',
                                        en: _obscurePassword
                                            ? 'Show password'
                                            : 'Hide password',
                                      ),
                                      onPressed: _busy
                                          ? null
                                          : () {
                                              setState(() {
                                                _obscurePassword =
                                                    !_obscurePassword;
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
                                if (_obscurePassword)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          left: 56,
                                          right: 56,
                                        ),
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: ValueListenableBuilder<
                                              TextEditingValue>(
                                            valueListenable:
                                                _passwordController,
                                            builder: (context, value, child) {
                                              return Text(
                                                '•' * value.text.length,
                                                maxLines: 1,
                                                overflow: TextOverflow.clip,
                                                style: theme.textTheme.bodyLarge
                                                    ?.copyWith(
                                                  fontFamily: 'monospace',
                                                  letterSpacing: 2,
                                                ),
                                              );
                                            },
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
                      const SizedBox(height: 4),
                      Row(
                        key: const ValueKey('login-remember-row'),
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: Checkbox(
                              key: const ValueKey('login-remember-credentials'),
                              value: _rememberCredentials,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              onChanged: _busy
                                  ? null
                                  : (value) {
                                      final remember = value ?? false;
                                      setState(
                                        () => _rememberCredentials = remember,
                                      );
                                      if (!remember) {
                                        unawaited(
                                          clearRememberedLogin()
                                              .catchError((_) {}),
                                        );
                                      }
                                    },
                            ),
                          ),
                          Flexible(
                            flex: 3,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: _busy
                                  ? null
                                  : () {
                                      final remember = !_rememberCredentials;
                                      setState(
                                        () => _rememberCredentials = remember,
                                      );
                                      if (!remember) {
                                        unawaited(
                                          clearRememberedLogin()
                                              .catchError((_) {}),
                                        );
                                      }
                                    },
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Text(
                                  context.l10n.tr(
                                    '记住账号密码',
                                    en: 'Remember account and password',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            flex: 4,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      context.l10n.tr(
                                        '使用前请阅读',
                                        en: 'Review the',
                                      ),
                                      maxLines: 1,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () =>
                                          showLoginAgreementBottomSheet(
                                              context),
                                      child: Text(
                                        context.l10n.tr(
                                          '使用协议',
                                          en: 'Terms of use',
                                        ),
                                        maxLines: 1,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
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
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      Container(
                        key: const ValueKey('login-error'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer.withValues(alpha: .55),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 17,
                              color: scheme.error,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                _error!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton.icon(
                      key: const ValueKey('login-submit'),
                      onPressed: _busy ? null : _submit,
                      icon: _busy
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login_rounded, size: 19),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Text(
                          _busy
                              ? context.l10n.loggingIn
                              : context.l10n.tr('登录', en: 'Sign in'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      key: const ValueKey('login-guest'),
                      onPressed: _busy ? null : _continueAsGuest,
                      child: Text(context.l10n.guestMode),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
