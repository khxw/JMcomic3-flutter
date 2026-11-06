import 'package:flutter/foundation.dart';

import 'app_log.dart';

export 'app_log.dart';

void initializeAppLogging() {
  FlutterError.onError = (details) {
    AppLog.add(
      '${details.exceptionAsString()}\n${details.stack ?? ''}',
      level: AppLogLevel.error,
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLog.add(
      '$error\n$stackTrace',
      level: AppLogLevel.error,
    );
    return false;
  };
  AppLog.add('Application started');
}

void debugPrient(Object? message) {
  AppLog.add(message);
  if (!kDebugMode) {
    return;
  }
  debugPrint("$message");
}
