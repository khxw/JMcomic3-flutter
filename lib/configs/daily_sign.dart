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
const _dailyStatusCooldown = Duration(minutes: 5);
bool _dailySignInFlight = false;
bool _dailyStatusInFlight = false;
DateTime? _dailySignedDate;
DateTime? _lastDailyStatusQueryAt;
int? _lastDailyStatusQueryUid;

final dailySignEvent = Event();

void _setDailySignStatus(DailySignStatus status) {
  dailySignStatus = status;
  dailySignEvent.broadcast();
}

void resetDailySignStatus() {
  _dailySignInFlight = false;
  _dailyStatusInFlight = false;
  _dailySignedDate = null;
  _lastDailyStatusQueryAt = null;
  _lastDailyStatusQueryUid = null;
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
    _dailySignedDate = DateUtils.dateOnly(DateTime.now());
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

Future<void> refreshDailySignStatus() async {
  if (loginStatus != LoginStatus.loginSuccess) {
    resetDailySignStatus();
    return;
  }
  if (_dailyStatusInFlight || _dailySignInFlight) return;
  final uid = selfInfo.uid;
  final lastQuery = _lastDailyStatusQueryAt;
  if (_lastDailyStatusQueryUid == uid &&
      lastQuery != null &&
      DateTime.now().difference(lastQuery) < _dailyStatusCooldown) {
    return;
  }
  _dailyStatusInFlight = true;
  _lastDailyStatusQueryUid = uid;
  _lastDailyStatusQueryAt = DateTime.now();
  _setDailySignStatus(DailySignStatus.checking);
  try {
    final data = await methods.dailyStatus(uid);
    final signed = _signedOnDate(data, DateTime.now());
    _dailySignedDate = signed ? DateUtils.dateOnly(DateTime.now()) : null;
    _setDailySignStatus(
      signed ? DailySignStatus.signed : DailySignStatus.unchecked,
    );
  } catch (error, stackTrace) {
    debugPrient(
      "daily status refresh failed: "
      "${error.runtimeType}/${stackTrace.runtimeType}",
    );
    final signedToday = _dailySignedDate == DateUtils.dateOnly(DateTime.now());
    _setDailySignStatus(
      signedToday ? DailySignStatus.signed : DailySignStatus.unchecked,
    );
  } finally {
    _dailyStatusInFlight = false;
  }
}

bool _signedOnDate(Map<String, dynamic> data, DateTime date) {
  final record = data['record'];
  if (record is! List) return false;
  final expectedDay = date.day.toString().padLeft(2, '0');
  for (final week in record) {
    if (week is! List) continue;
    for (final item in week) {
      if (item is! Map) continue;
      final day = '${item['date'] ?? ''}'.padLeft(2, '0');
      if (day == expectedDay) {
        return item['signed'] == true;
      }
    }
  }
  return false;
}
