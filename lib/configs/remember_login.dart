import 'package:jmcomic3/basic/methods.dart';

const _rememberEnabledKey = 'remember_login_credentials';
const _rememberedUsernameKey = 'remember_login_username';
const _rememberedPasswordKey = 'remember_login_password';

typedef RememberedLogin = ({
  String username,
  String password,
  bool remember,
});

Future<RememberedLogin> loadRememberedLogin() async {
  final enabled =
      (await methods.loadProperty(_rememberEnabledKey)).trim().toLowerCase();
  if (enabled == 'false') {
    return (username: '', password: '', remember: false);
  }

  final username = await methods.loadProperty(_rememberedUsernameKey);
  final password = await methods.loadProperty(_rememberedPasswordKey);
  if (username.isNotEmpty || password.isNotEmpty) {
    return (
      username: username,
      password: password,
      remember: true,
    );
  }

  try {
    final legacyUsername = await methods.loadUsername();
    final legacyPassword = await methods.loadPassword();
    if (legacyUsername.isNotEmpty || legacyPassword.isNotEmpty) {
      await saveRememberedLogin(
        legacyUsername,
        legacyPassword,
        remember: true,
      );
      return (
        username: legacyUsername,
        password: legacyPassword,
        remember: true,
      );
    }
  } catch (_) {
    // The fields remain editable when legacy credentials cannot be read.
  }
  return (username: '', password: '', remember: true);
}

Future<void> saveRememberedLogin(
  String username,
  String password, {
  required bool remember,
}) async {
  await Future.wait([
    methods.saveProperty(_rememberEnabledKey, remember ? 'true' : 'false'),
    methods.saveProperty(
      _rememberedUsernameKey,
      remember ? username : '',
    ),
    methods.saveProperty(
      _rememberedPasswordKey,
      remember ? password : '',
    ),
  ]);
}

Future<void> clearRememberedLogin() {
  return saveRememberedLogin('', '', remember: false);
}
