import 'package:event/event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_styled_toast/flutter_styled_toast.dart';
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
const _dailySignCheckCooldown = Duration(minutes: 5);
DateTime? _lastDailySignCheckAt;
int? _lastDailySignCheckUid;

final dailySignEvent = Event();

void _setDailySignStatus(DailySignStatus status) {
  dailySignStatus = status;
  dailySignEvent.broadcast();
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
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  showToastWidget(
    Container(
      key: const ValueKey('daily-sign-toast'),
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.fromLTRB(11, 9, 15, 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: .98),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: .68),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .15),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 29,
            height: 29,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: loading
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                      backgroundColor: accent.withValues(alpha: .18),
                    ),
                  )
                : Icon(icon, size: 17, color: accent),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    ),
    context: context,
    position: const StyledToastPosition(
      align: Alignment.bottomCenter,
      offset: 28,
    ),
    duration: const Duration(milliseconds: 1400),
    animDuration: const Duration(milliseconds: 180),
    animation: StyledToastAnimation.slideFromBottomFade,
    reverseAnimation: StyledToastAnimation.fade,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
    dismissOtherToast: true,
    textDirection: Directionality.of(context),
  );
}

Future<void> checkDailySignStatus(BuildContext context,
    {bool toast = false}) async {
  if (loginStatus != LoginStatus.loginSuccess) {
    _lastDailySignCheckAt = null;
    _lastDailySignCheckUid = null;
    _setDailySignStatus(DailySignStatus.unchecked);
    return;
  }
  if (!toast &&
      _lastDailySignCheckUid == selfInfo.uid &&
      _lastDailySignCheckAt != null &&
      DateTime.now().difference(_lastDailySignCheckAt!) <
          _dailySignCheckCooldown &&
      dailySignStatus != DailySignStatus.unchecked) {
    return;
  }
  _setDailySignStatus(DailySignStatus.checking);
  if (toast) {
    _showDailySignToast(
      context,
      loading: true,
      icon: Icons.event_available_rounded,
      accent: Theme.of(context).colorScheme.primary,
      message: context.l10n.tr('正在签到...', en: 'Signing in...'),
    );
  }
  try {
    final msg = await methods.daily(selfInfo.uid);
    _lastDailySignCheckUid = selfInfo.uid;
    _lastDailySignCheckAt = DateTime.now();
    if (toast) {
      if (!context.mounted) return;
      _showDailySignToast(
        context,
        icon: Icons.check_circle_rounded,
        accent: Theme.of(context).colorScheme.tertiary,
        message: msg.isNotEmpty ? msg : context.l10n.tr("已签到", en: "Signed in"),
      );
    }
    _setDailySignStatus(DailySignStatus.signed);
  } catch (e, st) {
    debugPrient("$e\n$st");
    _lastDailySignCheckUid = selfInfo.uid;
    _lastDailySignCheckAt = DateTime.now();
    if (toast) {
      if (!context.mounted) return;
      _showDailySignToast(
        context,
        icon: Icons.error_outline_rounded,
        accent: Theme.of(context).colorScheme.error,
        message: context.l10n.tr('签到失败：$e', en: 'Sign-in failed: $e'),
      );
    }
    _setDailySignStatus(DailySignStatus.error);
  }
}
