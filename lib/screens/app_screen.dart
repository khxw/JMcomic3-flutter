import 'package:flutter/material.dart';
import 'package:jmcomic3/configs/android_display_mode.dart';
import 'package:jmcomic3/configs/daily_sign.dart';
import 'package:jmcomic3/configs/versions.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/bookshelf_screen.dart';
import 'package:jmcomic3/screens/browser_screen.dart';
import 'package:jmcomic3/screens/components/compose_ui.dart';
import 'package:jmcomic3/screens/search_screen.dart';
import 'package:jmcomic3/screens/user_screen.dart';

class AppScreen extends StatefulWidget {
  const AppScreen({Key? key}) : super(key: key);

  @override
  State<AppScreen> createState() => _AppScreenState();
}

class _AppScreenState extends State<AppScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pageMotionController;
  late final Animation<double> _pageMotion;
  var _selectedIndex = 0;
  var _transitionDirection = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageMotionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 1,
    );
    _pageMotion = CurvedAnimation(
      parent: _pageMotionController,
      curve: Curves.easeOutQuart,
    );
    Future<void>.delayed(Duration.zero, () async {
      if (!mounted) return;
      versionPop(context);
      await checkDailySignStatus(context);
      if (!mounted) return;
      versionEvent.subscribe(_versionSub);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    versionEvent.unsubscribe(_versionSub);
    _pageMotionController.dispose();
    super.dispose();
  }

  void _versionSub(_) {
    versionPop(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      reapplyAndroidDisplayMode();
    }
  }

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      _transitionDirection = index > _selectedIndex ? 1 : -1;
      _selectedIndex = index;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageMotionController.value = 1;
    } else {
      _pageMotionController.forward(from: 0);
    }
  }

  List<Widget> _screens() {
    return [
      _withNavigationInset(
        BrowserScreenWrapper(onSearchRequested: _openSearch),
      ),
      _withNavigationInset(const BookshelfScreen()),
      _withNavigationInset(const UserScreen()),
    ];
  }

  Widget _withNavigationInset(Widget child) {
    final media = MediaQuery.of(context);
    const navigationInset = 76.0;
    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(
          bottom: media.padding.bottom + navigationInset,
        ),
        viewPadding: media.viewPadding.copyWith(
          bottom: media.viewPadding.bottom + navigationInset,
        ),
      ),
      child: child,
    );
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SearchScreen(),
      ),
    );
  }

  List<ComposeNavigationDestination> _destinations(BuildContext context) {
    final l10n = context.l10n;
    return [
      ComposeNavigationDestination(
        label: l10n.navBrowse,
        icon: Icons.explore_outlined,
        selectedIcon: Icons.explore_rounded,
      ),
      ComposeNavigationDestination(
        label: l10n.navLibrary,
        icon: Icons.collections_bookmark_outlined,
        selectedIcon: Icons.collections_bookmark_rounded,
      ),
      ComposeNavigationDestination(
        label: l10n.profile,
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardVisible = media.viewInsets.bottom > 0;
    final screens = _screens();
    final pages = IndexedStack(
      key: const ValueKey('app-pages'),
      index: _selectedIndex,
      children: [
        for (var index = 0; index < screens.length; index++)
          TickerMode(
            enabled: index == _selectedIndex,
            child: RepaintBoundary(child: screens[index]),
          ),
      ],
    );

    return Scaffold(
      extendBody: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              key: const ValueKey('app-page-motion'),
              animation: _pageMotion,
              child: pages,
              builder: (context, child) {
                final remaining = 1 - _pageMotion.value;
                return Transform.translate(
                  offset: Offset(_transitionDirection * remaining * 10, 0),
                  child: child,
                );
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ComposeFloatingNavigationBar(
              key: const ValueKey('compose-bottom-navigation'),
              destinations: _destinations(context),
              selectedIndex: _selectedIndex,
              visible: !keyboardVisible,
              onSelected: _onItemTapped,
            ),
          ),
        ],
      ),
    );
  }
}
