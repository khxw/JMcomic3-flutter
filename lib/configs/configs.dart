import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jmcomic3/basic/methods.dart';
import 'package:jmcomic3/basic/platform.dart';
import 'package:jmcomic3/configs/Authentication.dart';
import 'package:jmcomic3/configs/android_display_mode.dart';
import 'package:jmcomic3/configs/android_version.dart';
import 'package:jmcomic3/configs/app_font_size.dart';
import 'package:jmcomic3/configs/app_locale.dart';
import 'package:jmcomic3/configs/app_orientation.dart';
import 'package:jmcomic3/configs/display_jmcode.dart';
import 'package:jmcomic3/configs/download_thread_count.dart';
import 'package:jmcomic3/configs/no_animation.dart';
import 'package:jmcomic3/configs/pager_column_number.dart';
import 'package:jmcomic3/configs/pager_cover_rate.dart';
import 'package:jmcomic3/configs/passed.dart';
import 'package:jmcomic3/configs/proxy.dart';
import 'package:jmcomic3/configs/recommend_links.dart';
import 'package:jmcomic3/configs/search_title_words.dart';
import 'package:jmcomic3/configs/theme.dart';
import 'package:jmcomic3/configs/two_page_direction.dart';
import 'package:jmcomic3/configs/using_right_click_pop.dart';
import 'package:jmcomic3/configs/volume_key_control.dart';
import 'package:jmcomic3/configs/web_dav_password.dart';
import 'package:jmcomic3/configs/web_dav_sync_switch.dart';
import 'package:jmcomic3/configs/web_dav_url.dart';
import 'package:jmcomic3/configs/web_dav_username.dart';

import 'auto_clean.dart';
import 'categories_sort.dart';
import 'download_and_export_to.dart';
import 'export_path.dart';
import 'export_rename.dart';
import 'disable_recommend_content.dart';
import 'ignore_upgrade_pop.dart';
import 'ignore_view_log.dart';
import 'is_pro.dart';
import 'network_api_host.dart';
import 'network_cdn_host.dart';
import 'reader_controller_type.dart';
import 'reader_direction.dart';
import 'reader_preload.dart';
import 'reader_slider_position.dart';
import 'reader_type.dart';
import 'versions.dart';
import 'login.dart';
import 'pager_controller_mode.dart';
import 'pager_view_mode.dart';

Future initConfigs(BuildContext context) async {
  final androidVersionFuture = initAndroidVersion();
  final hostFuture = Future.wait<void>([
    initApiHost(),
    initCdnHost(),
    initProxy(),
  ]);
  final settingsFuture = Future.wait<void>([
    initPassed(),
    initAndroidDisplayMode(),
    initVersion(),
    initPagerControllerMode(),
    initPagerViewMode(),
    initReaderType(),
    initTwoPageDirection(),
    initReaderDirection(),
    initReaderControllerType(),
    initReaderPreload(),
    initReaderSliderPosition(),
    initPagerColumnCount(),
    initPagerCoverRate(),
    initAutoClean(),
    initTheme(),
    initAppLocale(),
    initDisableRecommendContent(),
    initExportPath(),
    initDownloadThreadCount(),
    initUsingRightClickPop(),
    initWebDavSyncSwitch(),
    initWebDavUrl(),
    initWebDavUserName(),
    initWebDavPassword(),
    initVolumeKeyControl(),
    initNoAnimation(),
    initDownloadAndExportTo(),
    initExportRename(),
    initDisplayJmcode(),
    initSearchTitleWords(),
    initCategoriesSort(),
    initFontSizeAdjust(),
    initAppOrientation(),
    initIgnoreVewLog(),
    initIgnoreUpgradePop(),
  ]);
  final loginFuture = hostFuture.then<void>((_) async {
    unawaited(_prefetchHome());
    await initLogin(context);
  });
  final authenticationFuture =
      androidVersionFuture.then<void>((_) => initAuthentication());

  await Future.wait<void>([
    androidVersionFuture,
    hostFuture,
    settingsFuture,
    loginFuture,
    authenticationFuture,
  ]);
  unawaited(runAutoCleanIfNeeded());
  unawaited(reloadIsPro());
  unawaited(initRecommendLinks());
  if (normalPlatform) autoCheckNewVersion();
}

Future<void> _prefetchHome() async {
  try {
    final initial = await Future.wait<dynamic>([
      methods.categories(),
      methods.comics("latest", sortByNew, 1),
    ]);
    final categories = initial[0] as CategoriesResponse;
    final prefetchedSlugs = <String>{'latest'};
    final requests = <Future<dynamic>>[];
    for (final category in categories.categories.take(4)) {
      final rawSlug = category.slug.trim();
      final slug = rawSlug.isEmpty ? 'latest' : rawSlug;
      if (prefetchedSlugs.add(slug)) {
        requests.add(methods.comics(slug, sortByNew, 1));
      }
    }
    if (requests.isNotEmpty) {
      await Future.wait<dynamic>(requests);
    }
  } catch (_) {
    // The browser page owns the visible retry/error state.
  }
}
