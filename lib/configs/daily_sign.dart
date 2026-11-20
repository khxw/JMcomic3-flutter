import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/commons.dart';
import 'package:jmcomic3/basic/log.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

enum DailySignStatus {
  unchecked,
  checking,
  signed,
  error,
}

DailySignStatus dailySignStatus = DailySignStatus.unchecked;
bool _dailySignInFlight = false;

final dailySignEvent = Event();

void _setDailySignStatus(DailySignStatus status) {
  dailySignStatus = status;
  dailySignEvent.broadcast();
}

void resetDailySignStatus() {
  _dailySignInFlight = false;
  _setDailySignStatus(DailySignStatus.unchecked);
}

String dailySignStatusLabel(BuildContext context) {
  switch (dailySignStatus) {
    case DailySignStatus.checking:
      return context.l10n.tr("检测中...", en: "Checking...");
    case DailySignStatus.signed:
      return context.l10n.tr("已签到", en: "Signed in");
    case DailySignStatus.error:
      return context.l10n.tr("签到失败", en: "Sign-in failed");
    case DailySignStatus.unchecked:
      return context.l10n.tr("未检测签到", en: "Not checked");
  }
}

void _showDailySignToast(
  BuildContext context, {
  required String message,
  required IconData icon,
  required Color accent,
  bool loading = false,
}) {
  showAppPrompt(
    context,
    key: const ValueKey('daily-sign-toast'),
    message: message,
    icon: icon,
    accent: accent,
    loading: loading,
  );
}

Future<void> signInDaily(BuildContext context) async {
  if (loginStatus != LoginStatus.loginSuccess) {
    _setDailySignStatus(DailySignStatus.unchecked);
    return;
  }
  if (_dailySignInFlight || dailySignStatus == DailySignStatus.signed) return;
  _dailySignInFlight = true;
  _setDailySignStatus(DailySignStatus.checking);
  _showDailySignToast(
    context,
    loading: true,
    icon: Icons.event_available_rounded,
    accent: Theme.of(context).colorScheme.primary,
    message: context.l10n.tr('正在签到...', en: 'Signing in...'),
  );
  try {
    final msg = await methods.daily(selfInfo.uid);
    if (context.mounted) {
      _showDailySignToast(
        context,
        icon: Icons.check_circle_rounded,
        accent: Theme.of(context).colorScheme.tertiary,
        message: msg.isNotEmpty ? msg : context.l10n.tr("已签到", en: "Signed in"),
      );
    }
    _setDailySignStatus(DailySignStatus.signed);
    await refreshSelfInfo();
  } catch (e, st) {
    debugPrient("$e\n$st");
    if (context.mounted) {
      _showDailySignToast(
        context,
        icon: Icons.error_outline_rounded,
        accent: Theme.of(context).colorScheme.error,
        message: context.l10n.tr('签到失败：$e', en: 'Sign-in failed: $e'),
      );
    }
    _setDailySignStatus(DailySignStatus.error);
  } finally {
    _dailySignInFlight = false;
  }
}
