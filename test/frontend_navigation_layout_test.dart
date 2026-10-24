import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/basic/local_bookshelf.dart';
import 'package:jmcomic3/basic/methods.dart' as native;
import 'package:jmcomic3/configs/auto_clean.dart';
import 'package:jmcomic3/configs/categories_sort.dart';
import 'package:jmcomic3/configs/login.dart' as login_config;
import 'package:jmcomic3/configs/pager_column_number.dart';
import 'package:jmcomic3/configs/pager_controller_mode.dart';
import 'package:jmcomic3/configs/pager_cover_rate.dart';
import 'package:jmcomic3/configs/pager_view_mode.dart';
import 'package:jmcomic3/configs/theme.dart';
import 'package:jmcomic3/configs/versions.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/app_screen.dart';
import 'package:jmcomic3/screens/bookshelf_screen.dart';
import 'package:jmcomic3/screens/browser_screen.dart';
import 'package:jmcomic3/screens/category_comics_screen.dart';
import 'package:jmcomic3/screens/comic_search_screen.dart';
import 'package:jmcomic3/screens/components/comic_list.dart';
import 'package:jmcomic3/screens/components/compose_ui.dart';
import 'package:jmcomic3/screens/components/content_loading.dart';
import 'package:jmcomic3/screens/components/images.dart';
import 'package:jmcomic3/screens/search_screen.dart';
import 'package:jmcomic3/screens/settings_screen.dart';
import 'package:jmcomic3/screens/user_screen.dart';

const _channel = MethodChannel('methods');
const _previewKey = ValueKey('layout-preview');
const _searchHint = 'Search comics, authors or keywords';
final _saveScreenshots = Platform.environment['LAYOUT_SCREENSHOTS'] == '1';
var _versionInitialized = false;

class _Fixture {
  int? browseTotal;
  int browseBatchSize = 2;
  bool signedIn = false;
  final requests = <Map<String, dynamic>>[];
  final properties = <String, String>{
    'guest_mode': 'true',
    'pager_controller_mode': PagerControllerMode.pager.toString(),
    'pager_view_mode': PagerViewMode.titleAndCover.toString(),
    'pager_cover_rate': PagerCoverRate.rate3x4.toString(),
    'pager_column_number': '3',
    'categoriesSort': '[]',
    'latestVersionRepoCache': 'MrYu-JMComic/JMcomic3-flutter',
  };
  final _pendingCover = Completer<String>();
  final coverPaths = <int, String>{};

  List<Map<String, dynamic>> calls(String method) =>
      requests.where((request) => request['method'] == method).toList();

  Future<String> handle(MethodCall call) async {
    final request = Map<String, dynamic>.from(
      jsonDecode(call.arguments as String) as Map,
    );
    requests.add(request);
    final method = request['method'];
    final params = request['params'];
    Object response;
    switch (method) {
      case 'load_property':
        response = properties[params] ?? '';
        break;
      case 'save_property':
        final values = jsonDecode(params as String) as Map;
        properties[values['k'] as String] = values['v'] as String;
        response = '';
        break;
      case 'pre_login':
        response = {
          'pre_set': signedIn,
          'pre_login': signedIn,
          'self_info': signedIn
              ? {
                  'uid': 42,
                  'username': 'Shelf reader',
                  'email': 'reader@example.invalid',
                  'emailverified': 'yes',
                  'photo': '?v=0?v=',
                  'fname': 'Reader',
                  'gender': '',
                  'message': '',
                  'coin': 0,
                  'album_favorites': 6,
                  's': '',
                  'level_name': 'Reader',
                  'level': 1,
                  'nextLevelExp': 100,
                  'exp': '0',
                  'expPercent': 0.0,
                  'badges': <Object>[],
                  'album_favorites_max': 100,
                }
              : null,
          'message': '',
        };
        break;
      case 'pro_info_all':
        response = {
          'pro_info_af': {'is_pro': true, 'expire': 4102444800},
          'pro_info_pat': {'is_pro': true},
        };
        break;
      case 'logout':
        response = '';
        break;
      case 'daily':
        response = '';
        break;
      case 'favorite':
        response = {
          'total': 6,
          'count': 6,
          'list': <Object>[],
          'folder_list': [
            {'FID': 1, 'UID': 42, 'name': 'Reading'},
            {'FID': 2, 'UID': 42, 'name': 'Finished'},
          ],
        };
        break;
      case 'categories':
        response = {
          'categories': [
            for (final category in const [
              (1, 'Alpha', 'alpha'),
              (2, 'Beta', 'beta'),
              (3, 'Gamma', 'gamma'),
            ])
              {
                'id': category.$1,
                'name': category.$2,
                'slug': category.$3,
                'total_albums': 6,
              },
          ],
          'blocks': [
            {
              'title': 'Topics',
              'content': [
                'Adventure',
                'Nature',
                'A long category label stays complete and wraps instead of being truncated',
              ],
            },
          ],
        };
        break;
      case 'comics':
      case 'comic_search':
        if (method == 'comics' && browseTotal != null) {
          final page = (jsonDecode(params as String) as Map)['page'] as int;
          final start = (page - 1) * browseBatchSize;
          response = {
            'total': browseTotal,
            'content': [
              for (var index = start;
                  index < start + browseBatchSize && index < browseTotal!;
                  index++)
                {
                  'id': 8000 + index,
                  'name': 'Browse result $index',
                  'author': '',
                  'description': '',
                  'image': '',
                  'category': {'title': 'Adventure'},
                  'category_sub': {'title': 'Illustration'},
                },
            ],
          };
          break;
        }
        response = {
          'total': 6,
          'content': [
            for (var index = 0; index < 6; index++)
              {
                'id': index + 7000,
                'name': const [
                  'A quiet forest',
                  'Beyond the horizon',
                  'The city after rain',
                  'A new beginning',
                  'Stories from the coast',
                  'Under the evening sky',
                ][index],
                'author': 'Layout fixture',
                'description': '',
                'image': '',
                'category': {'title': 'Adventure'},
                'category_sub': {'title': 'Illustration'},
              },
          ],
        };
        break;
      case 'favorites':
        response = {
          'total': 6,
          'count': 6,
          'list': [
            for (var index = 0; index < 6; index++)
              {
                'id': 7000 + index,
                'name': 'Shelf result $index',
                'author': 'Bookshelf fixture',
                'description': '',
                'image': '',
                'category': {'title': 'Adventure'},
                'category_sub': {'title': 'Collection'},
              },
          ],
          'folder_list': [
            {'FID': 1, 'UID': 42, 'name': 'Reading'},
            {'FID': 2, 'UID': 42, 'name': 'Finished'},
          ],
        };
        break;
      case 'last_search_histories':
        response = [
          {'search_query': 'quiet forest', 'last_search_time': 1770000000},
        ];
        break;
      case 'jm_3x4_cover':
        final id = int.parse(params as String);
        final path = coverPaths[id];
        if (path == null) return _pendingCover.future;
        response = path;
        break;
      default:
        throw StateError('Unexpected method: $method');
    }
    return jsonEncode({
      'error_message': '',
      'response_data': response is String ? response : jsonEncode(response),
    });
  }

  Future<void> createPreviewCovers() async {
    final directory = Directory('build/layout-validation/fixture-images');
    await directory.create(recursive: true);
    for (var index = 0; index < 6; index++) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final base = Colors.primaries[index * 2 + 1];
      canvas.drawRect(
          const Rect.fromLTWH(0, 0, 240, 320), Paint()..color = base.shade200);
      canvas.drawCircle(const Offset(177, 72), 35,
          Paint()..color = Colors.white.withValues(alpha: .72));
      final hills = Path()
        ..moveTo(0, 215)
        ..quadraticBezierTo(80, 95, 170, 235)
        ..quadraticBezierTo(215, 140, 240, 185)
        ..lineTo(240, 320)
        ..lineTo(0, 320)
        ..close();
      canvas.drawPath(hills, Paint()..color = base.shade700);
      canvas.drawRect(const Rect.fromLTWH(20, 282, 118, 4),
          Paint()..color = Colors.white.withValues(alpha: .7));
      final picture = recorder.endRecording();
      final bitmap = await picture.toImage(240, 320);
      final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${directory.path}/cover_$index.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      coverPaths[index + 7000] = file.absolute.path;
      bitmap.dispose();
      picture.dispose();
    }
  }
}

Widget _host(Widget child, {double textScale = 1}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _saveScreenshots
          ? lightTheme.copyWith(
              textTheme:
                  lightTheme.textTheme.apply(fontFamily: 'LayoutPreview'),
              primaryTextTheme: lightTheme.primaryTextTheme
                  .apply(fontFamily: 'LayoutPreview'),
            )
          : lightTheme,
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: RepaintBoundary(key: _previewKey, child: child!),
      ),
      home: child,
    );

Future<_Fixture> _prepare(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  bool guest = true,
  bool signedIn = false,
  PagerControllerMode mode = PagerControllerMode.pager,
}) async {
  final fixture = _Fixture()..signedIn = signedIn;
  fixture.properties['guest_mode'] = '$guest';
  if (signedIn) {
    fixture.properties['guest_mode'] = 'false';
  }
  fixture.properties['pager_controller_mode'] = mode.toString();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_channel, fixture.handle);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    clearAllImageMemoryCaches();
    imageCache.clear();
    imageCache.clearLiveImages();
    messenger.setMockMethodCallHandler(_channel, null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  // Clear response caches through the same public path as ending a session.
  await native.methods.logout();
  resetLocalBookshelfMemory();
  clearAllImageMemoryCaches();
  if (!_versionInitialized) {
    await initVersion();
    _versionInitialized = true;
  }
  await initCategoriesSort();
  await initPagerControllerMode();
  await initPagerViewMode();
  await initAutoClean();
  await initPagerCoverRate();
  await initPagerColumnCount();
  if (_saveScreenshots) {
    await tester.runAsync(() async {
      final font = File('C:/Windows/Fonts/segoeui.ttf');
      if (await font.exists()) {
        final bytes = ByteData.sublistView(await font.readAsBytes());
        for (final family in ['LayoutPreview', 'Roboto']) {
          await (FontLoader(family)..addFont(Future.value(bytes))).load();
        }
      }
      final config = jsonDecode(
          await File('.dart_tool/package_config.json').readAsString()) as Map;
      final sdk = Uri.parse(config['flutterRoot'] as String).toFilePath();
      final icons = File(
          '$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
      if (await icons.exists()) {
        await (FontLoader('MaterialIcons')
              ..addFont(Future.value(
                  ByteData.sublistView(await icons.readAsBytes()))))
            .load();
      }
      await fixture.createPreviewCovers();
    });
  }
  await tester.pumpWidget(_host(const Scaffold(
    body: SizedBox(key: ValueKey('login-context')),
  )));
  await login_config.initLogin(
    tester.element(find.byKey(const ValueKey('login-context'))),
  );
  await tester.pumpAndSettle();
  return fixture;
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!_saveScreenshots) return;
  await tester.runAsync(() async {
    // Let local mock cover I/O finish before recording the actual widget tree.
    for (var frame = 0; frame < 10; frame++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    }
  });
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_previewKey),
  );
  await tester.runAsync(() async {
    final bitmap = await boundary.toImage();
    final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/layout-validation/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    bitmap.dispose();
  });
}

void main() {
  testWidgets('home renders a carousel and category rails', (tester) async {
    final fixture = await _prepare(tester, size: const Size(1280, 900));
    await tester.pumpWidget(_host(const AppScreen()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-carousel')), findsOneWidget);
    expect(find.text('Latest A Comics'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-rail:alpha')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-rail:beta')), findsOneWidget);
    final requests = fixture.calls('comics');
    expect(
      requests.map((request) {
        final params = jsonDecode(request['params'] as String) as Map;
        return '${params['categories_slug']}:${params['page']}';
      }),
      containsAll(['alpha:1', 'beta:1', 'gamma:1']),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('floating navigation preserves active page and category state',
      (tester) async {
    final fixture = await _prepare(tester, size: const Size(839, 700));
    await tester.pumpWidget(_host(const AppScreen()));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ComposeFloatingNavigationBar>(
            find.byType(ComposeFloatingNavigationBar),
          )
          .selectedIndex,
      0,
    );
    expect(
      find.byKey(const ValueKey('app-page-motion')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AnimatedAlign>(
            find.byKey(const ValueKey('compose-navigation-indicator')),
          )
          .alignment,
      Alignment.centerLeft,
    );
    final browserState = tester.state(find.byType(BrowserScreen));
    await tester.drag(
      find.byKey(const ValueKey('home-feed')),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(ComposeFloatingNavigationBar),
      matching: find.byIcon(Icons.collections_bookmark_outlined),
    ));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ComposeFloatingNavigationBar>(
            find.byType(ComposeFloatingNavigationBar),
          )
          .selectedIndex,
      1,
    );
    expect(
      tester
          .widget<AnimatedAlign>(
            find.byKey(const ValueKey('compose-navigation-indicator')),
          )
          .alignment,
      Alignment.center,
    );
    expect(find.byType(BookshelfScreen), findsOneWidget);
    await _capture(tester, 'bookshelf-desktop');

    for (final width in [840.0, 1440.0, 839.0]) {
      tester.view.physicalSize = Size(width, 700);
      await tester.pumpAndSettle();
      expect(find.byType(ComposeFloatingNavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(
        tester
            .widget<ComposeFloatingNavigationBar>(
              find.byType(ComposeFloatingNavigationBar),
            )
            .selectedIndex,
        1,
      );
      expect(tester.state(find.byType(BrowserScreen, skipOffstage: false)),
          same(browserState));
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.descendant(
      of: find.byType(ComposeFloatingNavigationBar),
      matching: find.byIcon(Icons.explore_outlined),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-carousel')), findsOneWidget);
    expect(tester.state(find.byType(BrowserScreen)), same(browserState));
    expect(fixture.calls('categories'), hasLength(1));
  });

  testWidgets('bottom navigation jumps directly from home to profile',
      (tester) async {
    final fixture = await _prepare(tester, size: const Size(390, 780));
    await tester.pumpWidget(_host(const AppScreen()));
    await tester.pumpAndSettle();
    final browserState = tester.state(find.byType(BrowserScreen));

    await tester.tap(find.descendant(
      of: find.byType(ComposeFloatingNavigationBar),
      matching: find.byIcon(Icons.person_outline_rounded),
    ));
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      tester
          .widget<ComposeFloatingNavigationBar>(
            find.byType(ComposeFloatingNavigationBar),
          )
          .selectedIndex,
      2,
    );
    expect(find.byType(UserScreen), findsOneWidget);
    expect(find.byType(BookshelfScreen), findsNothing);
    expect(
      find.byType(BookshelfScreen, skipOffstage: false),
      findsOneWidget,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.byType(ComposeFloatingNavigationBar),
      matching: find.byIcon(Icons.explore_outlined),
    ));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(BrowserScreen)), same(browserState));
    expect(fixture.calls('categories'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved category order reorders home sections', (tester) async {
    await _prepare(tester);
    await tester.pumpWidget(_host(const AppScreen()));
    await tester.pumpAndSettle();

    await saveCategoriesSort([2, 1, 3]);
    await tester.pumpAndSettle();
    final beta = find.byKey(const ValueKey('home-section:beta'));
    final alpha = find.byKey(const ValueKey('home-section:alpha'));
    expect(beta, findsOneWidget);
    expect(alpha, findsOneWidget);
    expect(
      tester.getTopLeft(beta).dy,
      lessThan(tester.getTopLeft(alpha).dy),
    );
    expect(tester.takeException(), isNull);
    await _capture(tester, 'browse-desktop');
  });

  testWidgets('home settings menu uses grouped action cards', (tester) async {
    await _prepare(tester, size: const Size(390, 780));
    await tester.pumpWidget(_host(const AppScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('browser-settings-sheet')),
      findsOneWidget,
    );
    expect(find.text('Layout & display'), findsOneWidget);
    expect(find.text('Cache & network'), findsOneWidget);
    for (final key in const [
      'browser-menu-view-mode',
      'browser-menu-controller',
      'browser-menu-cover-rate',
      'browser-menu-columns',
      'browser-menu-clean',
      'browser-menu-auto-clean',
      'browser-menu-api-host',
      'browser-menu-cdn-host',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await _capture(tester, 'home-settings-menu');
  });

  testWidgets('home category more route returns without intermediate page',
      (tester) async {
    await _prepare(tester, size: const Size(390, 780));
    await tester.pumpWidget(_host(const AppScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('More').first);
    await tester.pumpAndSettle();
    expect(find.byType(CategoryComicsScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byType(CategoryComicsScreen), findsNothing);
    expect(find.byKey(const ValueKey('home-carousel')), findsOneWidget);
  });

  testWidgets('standalone search page loads history and opens a query result',
      (tester) async {
    final fixture = await _prepare(tester);
    await tester.pumpWidget(_host(const AppScreen()));
    await tester.pumpAndSettle();
    expect(find.text(_searchHint), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ComposeFloatingNavigationBar),
        matching: find.byIcon(Icons.search_rounded),
      ),
      findsNothing,
    );
    await tester.tap(find.text(_searchHint));
    await tester.pump(const Duration(milliseconds: 160));
    expect(fixture.calls('last_search_histories'), isEmpty);
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.byType(ComicSearchScreen), findsNothing);
    expect(fixture.calls('last_search_histories').single['params'], '20');
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('quiet forest'), findsOneWidget);
    await _capture(tester, 'search-desktop');
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text(_searchHint));
    await tester.pumpAndSettle();
    await tester.tap(find.text('quiet forest'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.byType(ComicSearchScreen), findsNothing);
    expect(fixture.calls('comic_search').single['params'],
        jsonEncode({'search_query': 'quiet forest', 'sort_by': '', 'page': 1}));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile search page handles the keyboard inset', (tester) async {
    await _prepare(tester, size: const Size(320, 640));
    await tester.pumpWidget(_host(const AppScreen(), textScale: 1.4));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(ComposeFloatingNavigationBar),
        matching: find.byIcon(Icons.search_rounded),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('home-search-entry')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    final history = find.text('quiet forest');
    expect(history, findsOneWidget);
    expect(tester.getRect(history).right, lessThanOrEqualTo(308));

    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(tester.getRect(history).right, lessThanOrEqualTo(308));
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact browse and guest library fit large text',
      (tester) async {
    await _prepare(tester, size: const Size(320, 780));
    await tester.pumpWidget(_host(const AppScreen(), textScale: 2));
    await tester.pumpAndSettle();
    expect(find.text(_searchHint), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byKey(const ValueKey('home-carousel')), findsOneWidget);
    expect(find.byKey(const ValueKey('weekly-floating-tab')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'browse-compact-large-text');
    await tester.tap(find.descendant(
      of: find.byType(ComposeFloatingNavigationBar),
      matching: find.byIcon(Icons.person_outline_rounded),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Guest Mode'), findsOneWidget);
    final user = find.byType(UserScreen);
    final scroll = find.descendant(
      of: user,
      matching: find.byType(SingleChildScrollView),
    );
    // The compact account card now uses its own inset. Validate against the
    // actual card bounds rather than the previous card's fixed text offset.
    final accountCard =
        tester.getRect(find.byKey(const ValueKey('profile-account-card')));
    final guestTitle = tester.getRect(find.text('Guest Mode'));
    expect(guestTitle.left, greaterThan(accountCard.left));
    expect(guestTitle.right, lessThan(accountCard.right));
    expect(tester.takeException(), isNull);
    await _capture(tester, 'library-compact-large-text');
    await tester.drag(scroll, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Download List').hitTestable(), findsOneWidget);
    expect(find.text('Comments').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed-out library stays usable at 320px and desktop',
      (tester) async {
    await _prepare(tester, size: const Size(320, 780), guest: false);
    await tester.pumpWidget(_host(const UserScreen(), textScale: 2));
    await tester.pumpAndSettle();
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Login / Register'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'library-signed-out-compact-large-text');
    await tester.pumpWidget(_host(const UserScreen()));
    tester.view.physicalSize = const Size(1600, 800);
    await tester.pumpAndSettle();
    final account = tester.getRect(find.text('Account'));
    final library = tester.getRect(find.text('Library'));
    expect(account.right, lessThan(library.left));
    final view = find.descendant(
      of: find.byType(UserScreen),
      matching: find.byWidgetPredicate((widget) =>
          widget is ConstrainedBox && widget.constraints.maxWidth == 1120),
    );
    expect(tester.getSize(view).width, 1120);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'library-desktop');
  });

  testWidgets('local bookshelf opens folders before showing comics',
      (tester) async {
    await _prepare(tester, size: const Size(390, 780));
    await toggleLocalBookshelf(
      ComicBasic(
        id: 7000,
        author: 'Shelf author',
        description: '',
        name: 'Local shelf A',
        image: '',
      ),
      group: 'Reading',
    );
    await toggleLocalBookshelf(
      ComicBasic(
        id: 7001,
        author: 'Another author',
        description: '',
        name: 'Local shelf B',
        image: '',
      ),
      group: 'Finished',
    );
    await toggleLocalBookshelf(
      ComicBasic(
        id: 7002,
        author: 'Third author',
        description: '',
        name: 'Local shelf C',
        image: '',
      ),
      group: 'Reading',
    );
    await tester.pumpWidget(_host(const AppScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(ComposeFloatingNavigationBar),
      matching: find.byIcon(Icons.collections_bookmark_outlined),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Local shelf A'), findsNothing);
    expect(find.textContaining('2 groups · 3 comics'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('bookshelf-options-menu')), findsOneWidget);
    expect(find.byType(ComicList), findsNothing);
    expect(
      find.byKey(const ValueKey('bookshelf-folder-all')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bookshelf-folder-Reading')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bookshelf-folder-Finished')),
      findsOneWidget,
    );
    final allFolder =
        tester.getRect(find.byKey(const ValueKey('bookshelf-folder-all')));
    final readingFolder = tester.getRect(
      find.byKey(const ValueKey('bookshelf-folder-Reading')),
    );
    final finishedFolder = tester.getRect(
      find.byKey(const ValueKey('bookshelf-folder-Finished')),
    );
    expect(allFolder.width, lessThan(125));
    expect(readingFolder.top, allFolder.top);
    expect(finishedFolder.top, allFolder.top);
    expect(finishedFolder.left, greaterThan(allFolder.right));
    expect(readingFolder.left, greaterThan(finishedFolder.right));
    expect(tester.takeException(), isNull);
    await _capture(tester, 'bookshelf-folders-mobile');

    await tester.tap(
      find.byKey(const ValueKey('bookshelf-folder-Reading')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bookshelf-group-page-Reading')),
      findsOneWidget,
    );
    expect(find.byType(ComicList), findsOneWidget);
    expect(find.text('Local shelf A'), findsOneWidget);
    expect(find.text('Local shelf C'), findsOneWidget);
    expect(find.text('Local shelf B'), findsNothing);
    expect(find.textContaining('2 comics'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('bookshelf-group-options-menu')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 comics · Title'), findsOneWidget);
    expect(find.text('Local shelf A'), findsOneWidget);
    expect(find.text('Local shelf C'), findsOneWidget);
    expect(find.text('Local shelf B'), findsNothing);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'bookshelf-group-contents');

    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bookshelf-folder-grid')),
      findsOneWidget,
    );
    expect(find.byType(ComicList), findsNothing);
  });

  testWidgets('content loading uses a compact indicator', (tester) async {
    await _prepare(tester, size: const Size(390, 780));
    await tester.pumpWidget(_host(
      const SizedBox.expand(
        child: ContentLoading(label: 'Loading bookshelf'),
      ),
    ));
    await tester.pump();
    final progress = find.byType(CircularProgressIndicator);
    expect(progress, findsOneWidget);
    expect(tester.getSize(progress), const Size(36, 36));
    expect(find.text('Loading bookshelf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('comic image loading uses a bounded compact spinner',
      (tester) async {
    await _prepare(tester, size: const Size(390, 780));
    await tester.pumpWidget(_host(
      SizedBox.expand(
        child: Builder(
          builder: (context) => buildLoading(context, 390, 700),
        ),
      ),
    ));
    await tester.pump();
    final loadingIcon = find.byIcon(Icons.downloading_rounded);
    expect(loadingIcon, findsOneWidget);
    expect(tester.widget<Icon>(loadingIcon).size, closeTo(21.08, .01));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(_host(
      SizedBox(
        width: 60,
        height: 80,
        child: Builder(
          builder: (context) => buildLoading(context, 60, 80),
        ),
      ),
    ));
    await tester.pump();
    expect(
      tester.widget<Icon>(find.byIcon(Icons.downloading_rounded)).size,
      closeTo(12.65, .01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings page groups options into compact cards',
      (tester) async {
    await _prepare(tester, size: const Size(390, 780));
    await tester.pumpWidget(_host(const SettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-common')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-reading')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-storage')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-account')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-sync')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-common-expanded')),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('Theme'),
        matching: find.byKey(const ValueKey('settings-common-expanded')),
      ),
      findsOneWidget,
    );
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Organized by workflow'), findsNothing);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'settings-grouped');
    await tester.drag(
      find.byKey(const ValueKey('settings-list')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-system')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-system')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings route returns to profile with a short transition',
      (tester) async {
    await _prepare(tester, size: const Size(390, 780));
    await tester.pumpWidget(_host(const UserScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byType(UserScreen), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('bookshelf folder cards fit compact large text', (tester) async {
    await _prepare(tester, size: const Size(320, 700));
    await toggleLocalBookshelf(
      ComicBasic(
        id: 7200,
        author: 'Folder fixture',
        description: '',
        name: 'Folder comic',
        image: '',
      ),
      group: 'A long folder name that still fits',
    );
    await createLocalBookshelfGroup('Empty folder');
    await tester.pumpWidget(_host(
      const BookshelfScreen(),
      textScale: 2,
    ));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey(
          'bookshelf-folder-A long folder name that still fits',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bookshelf-folder-Empty folder')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('bookshelf group management creates, renames and deletes groups',
      (tester) async {
    await _prepare(tester, size: const Size(390, 780));
    await tester.pumpWidget(_host(const AppScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(ComposeFloatingNavigationBar),
      matching: find.byIcon(Icons.collections_bookmark_outlined),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('bookshelf-options-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage groups'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('bookshelf-group-management-page')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('bookshelf-group-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('bookshelf-group-name-field')),
      'Archive',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bookshelf-group-save')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bookshelf-group-item-Archive')),
      findsOneWidget,
    );
    expect(localBookshelfGroupNames, contains('Archive'));
    await _capture(tester, 'bookshelf-group-management-list');

    await tester.tap(
      find.byKey(const ValueKey('bookshelf-group-menu-Archive')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bookshelf-group-rename-Archive')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('bookshelf-group-name-field')),
      'Favorites',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bookshelf-group-save')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bookshelf-group-item-Favorites')),
      findsOneWidget,
    );
    expect(localBookshelfGroupNames, isNot(contains('Archive')));

    await tester.tap(
      find.byKey(const ValueKey('bookshelf-group-menu-Favorites')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bookshelf-group-delete-Favorites')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('bookshelf-group-delete-confirm')),
    );
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('bookshelf-groups-empty')), findsOneWidget);
    expect(localBookshelfGroupNames, isEmpty);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'bookshelf-group-management');
  });

  testWidgets('bookshelf group operations keep existing comics in sync',
      (tester) async {
    await _prepare(tester, size: const Size(390, 780));
    await toggleLocalBookshelf(
      ComicBasic(
        id: 7100,
        author: 'Group fixture',
        description: '',
        name: 'Movable shelf comic',
        image: '',
      ),
      group: 'Reading',
    );

    expect(await createLocalBookshelfGroup('Archive'), isTrue);
    expect(await moveLocalBookshelfItem(7100, 'Archive'), isTrue);
    expect(localBookshelfItems.single.group, 'Archive');
    expect(localBookshelfGroupCount('Archive'), 1);

    expect(await renameLocalBookshelfGroup('Archive', 'Favorites'), isTrue);
    expect(localBookshelfItems.single.group, 'Favorites');
    expect(localBookshelfGroupNames, contains('Favorites'));

    await deleteLocalBookshelfGroup('Favorites');
    expect(localBookshelfItems.single.group, isEmpty);
    expect(localBookshelfGroupNames, isNot(contains('Favorites')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone home keeps search, carousel and weekly tab in place',
      (tester) async {
    await _prepare(tester, size: const Size(390, 780));
    await tester.pumpWidget(_host(const AppScreen()));
    await tester.pumpAndSettle();

    final search = find.byKey(const ValueKey('home-search-entry'));
    final carousel = find.byKey(const ValueKey('home-carousel'));
    final weekly = find.byKey(const ValueKey('weekly-floating-tab'));
    final nav = find.byType(ComposeFloatingNavigationBar);
    expect(search, findsOneWidget);
    expect(carousel, findsOneWidget);
    expect(weekly, findsOneWidget);
    expect(find.text('Latest A Comics'), findsOneWidget);
    expect(
        tester.getTopLeft(search).dy, lessThan(tester.getTopLeft(carousel).dy));
    expect(tester.getRect(weekly).bottom,
        lessThanOrEqualTo(tester.getRect(nav).top));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'browse-mobile');
  });

  testWidgets('phone search page keeps tag labels complete', (tester) async {
    final fixture = await _prepare(tester, size: const Size(390, 780));
    await tester.pumpWidget(_host(const AppScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-search-entry')));
    await tester.pumpAndSettle();
    const longTag =
        'A long category label stays complete and wraps instead of being truncated';
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.history_rounded), findsOneWidget);
    expect(find.byIcon(Icons.local_offer_outlined), findsNothing);
    expect(tester.widget<Text>(find.text(longTag)).maxLines, isNull);
    final history = find
        .ancestor(
          of: find.text('quiet forest'),
          matching: find.byType(InkWell),
        )
        .first;
    expect(tester.getSize(history).height, lessThanOrEqualTo(44));
    expect(tester.getRect(find.text(longTag)).right, lessThanOrEqualTo(380));
    expect(tester.takeException(), isNull);
    await _capture(tester, 'search-mobile-restored');
    await tester.tap(find.text('Nature'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.byType(ComicSearchScreen), findsNothing);
    expect(fixture.calls('comic_search').single['params'],
        jsonEncode({'search_query': 'Nature', 'sort_by': '', 'page': 1}));
  });
}
