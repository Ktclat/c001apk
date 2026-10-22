import 'dart:async';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../components/floating_tab_bar.dart';
import '../../pages/home/return_top_controller.dart';
import '../../pages/home/home_page.dart';
import '../../pages/main/main_controller.dart';
import '../../pages/message/message_page.dart';
import '../local_follow/local_follow_page.dart';
import '../../logic/accounts/account_store.dart';
import '../../utils/storage_util.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage>
    with SingleTickerProviderStateMixin {
  final ReturnTopController _pageScrollController =
      Get.put(ReturnTopController(), tag: 'home');
  int _selectedIndex = 0;
  final _indexSctream = StreamController<int>.broadcast();
  late final MainController _mainController = Get.put(MainController());
  var _contrller = PageController();
  bool _resetting = false;
  // Scroll toggles this notifier without rebuilding the image-heavy PageView.
  final ValueNotifier<bool> _dockVisible = ValueNotifier<bool>(true);
  double _scrollTravel = 0;
  bool _floatingActive = false;
  bool _accessibleNavigation = false;
  bool _usingRail = false;
  bool _reducedMotion = false;
  // Translate only the incoming content. No outgoing feed, alpha layer, or
  // intermediate root page participates in this short navigation transition.
  late final AnimationController _pageSwitch = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
    value: 1,
  );
  late final CurvedAnimation _pageSettle = CurvedAnimation(
    parent: _pageSwitch,
    curve: Curves.easeOutCubic,
  );

  void _revealDock() {
    _scrollTravel = 0;
    _dockVisible.value = true;
  }

  /// Hide on a deliberate downward drag and reappear on upward scrolling.
  /// This avoids covering a long paragraph while the user is reading.
  bool _handleRootScroll(int page, ScrollNotification notification) {
    if (!_floatingActive || _accessibleNavigation || page != _selectedIndex) {
      return false;
    }
    // A nested Home tab can become empty/non-scrollable. Its programmatic
    // horizontal transition must restore navigation, not just horizontal drags.
    if (notification.metrics.axis == Axis.horizontal) {
      if (notification is ScrollUpdateNotification) _revealDock();
      return false;
    }
    if (notification is ScrollEndNotification) {
      _scrollTravel = 0;
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;
      if (_scrollTravel.sign != delta.sign) _scrollTravel = 0;
      _scrollTravel = (_scrollTravel + delta).clamp(-80.0, 80.0);
      if (_scrollTravel >= 28 && _dockVisible.value) {
        _dockVisible.value = false;
      } else if (_scrollTravel <= -20 && !_dockVisible.value) {
        _dockVisible.value = true;
      }
    }
    // Never swallow notifications: refresh indicators and nested tabs
    // continue receiving their scroll events.
    return false;
  }

  @override
  void initState() {
    super.initState();
    _mainController.checkLoginInfo();
    AccountStore.changes.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (!mounted || _resetting) return;
    _dockVisible.value = true;
    _scrollTravel = 0;
    _pageSwitch.value = 1;
    setState(() => _resetting = true);
    // Unmount old account pages for a complete frame before reusing the
    // existing Get controller tags. Routes containing old account data close.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Get.until((route) => route.isFirst);
      _contrller.dispose();
      _contrller = PageController(initialPage: _selectedIndex);
      setState(() => _resetting = false);
      _mainController.checkLoginInfo();
    });
  }

  @override
  void dispose() {
    AccountStore.changes.removeListener(_sessionChanged);
    _pageSettle.dispose();
    _pageSwitch.dispose();
    _dockVisible.dispose();
    _indexSctream.close();
    _contrller.dispose();
    Get.delete<ReturnTopController>(tag: 'home');
    Get.delete<MainController>();
    super.dispose();
  }

  void onBackPressed() async {
    if (_selectedIndex != 0) {
      onDestinationSelected(0);
    } else {
      if (Platform.isAndroid) {
        AndroidIntent intent = const AndroidIntent(
          action: 'android.intent.action.MAIN',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
          category: 'android.intent.category.HOME',
        );
        await intent.launch();
      } else {
        SystemNavigator.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const pages = [
      HomePage(),
      FollowFeedPage(),
      MessagePage(),
    ];

    const barDestinations = <NavigationDestination>[
      NavigationDestination(
        selectedIcon: Icon(Icons.home),
        icon: Icon(Icons.home_outlined),
        label: '主页',
      ),
      NavigationDestination(
        selectedIcon: Icon(Icons.feed),
        icon: Icon(Icons.feed_outlined),
        label: '关注',
      ),
      NavigationDestination(
        selectedIcon: Icon(Icons.person),
        icon: Icon(Icons.person_outline),
        label: '我的',
      ),
    ];

    const railDestinations = <NavigationRailDestination>[
      NavigationRailDestination(
        selectedIcon: Icon(Icons.home),
        icon: Icon(Icons.home_outlined),
        label: Text('主页'),
      ),
      NavigationRailDestination(
        selectedIcon: Icon(Icons.feed),
        icon: Icon(Icons.feed_outlined),
        label: Text('关注'),
      ),
      NavigationRailDestination(
        selectedIcon: Icon(Icons.person),
        icon: Icon(Icons.person_outline),
        label: Text('我的'),
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, obj) async {
        onBackPressed();
      },
      child: ValueListenableBuilder(
        valueListenable:
            GStorage.settings.listenable(keys: [SettingsBoxKey.floatingTabBar]),
        builder: (context, _, __) => _resetting
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : LayoutBuilder(
                builder: (context, constraints) {
                  // Tablets should keep the navigation rail even when held
                  // upright; orientation alone is not sufficient.
                  final useRail = constraints.maxWidth >= 600 ||
                      constraints.maxWidth >= constraints.maxHeight;
                  final keyboardOpen =
                      MediaQuery.viewInsetsOf(context).bottom > 0;
                  // Hide bottom navigation while typing to avoid covering
                  // chat, search and reply input fields.
                  final floating =
                      !useRail && !keyboardOpen && GStorage.floatingTabBar;
                  final media = MediaQuery.of(context);
                  final accessible = media.accessibleNavigation;
                  final reduceMotion = media.disableAnimations || accessible;
                  if (_usingRail != useRail || _reducedMotion != reduceMotion) {
                    _usingRail = useRail;
                    _reducedMotion = reduceMotion;
                    _pageSwitch.value = 1;
                  }
                  // Reset when the dock enters/leaves the layout. This also
                  // prevents rail/IME scrolls from hiding a future portrait dock.
                  if (_floatingActive != floating ||
                      _accessibleNavigation != accessible) {
                    _floatingActive = floating;
                    _accessibleNavigation = accessible;
                    _pageSwitch.value = 1;
                    _revealDock();
                  }
                  final safeBottom = media.viewPadding.bottom;
                  final bottomGap = constraints.maxHeight < 600 ? 8.0 : 12.0;
                  final sideInset = constraints.maxWidth < 340 ? 8.0 : 16.0;
                  final dockHeight = FloatingTabBar.heightFor(context);
                  final dockBottom = bottomGap + safeBottom;
                  // Keep scroll content full-bleed behind the floating bar,
                  // but allow every root list to scroll its final item above
                  // the navigation affordance.
                  final scrollClearance =
                      floating ? dockHeight + dockBottom + 16.0 : 0.0;

                  return Scaffold(
                    body: Stack(
                      children: [
                        Positioned.fill(
                          child: FloatingNavigationInset(
                            bottom: scrollClearance,
                            child: Row(
                              children: [
                                if (useRail)
                                  StreamBuilder<int>(
                                    initialData: _selectedIndex,
                                    stream: _indexSctream.stream,
                                    builder: (_, snapshot) => NavigationRail(
                                      destinations: railDestinations,
                                      selectedIndex: snapshot.data ?? 0,
                                      onDestinationSelected:
                                          onDestinationSelected,
                                    ),
                                  ),
                                Expanded(
                                  child: AnimatedBuilder(
                                    animation: _pageSettle,
                                    // A stable child keeps animation ticks out
                                    // of the PageView/feed build and layout.
                                    child: RepaintBoundary(
                                      child: PageView(
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        controller: _contrller,
                                        children: [
                                          for (var index = 0;
                                              index < pages.length;
                                              index++)
                                            NotificationListener<
                                                ScrollNotification>(
                                              onNotification: (notification) =>
                                                  _handleRootScroll(
                                                      index, notification),
                                              child: pages[index],
                                            ),
                                        ],
                                      ),
                                    ),
                                    builder: (context, child) =>
                                        Transform.translate(
                                      key: const ValueKey(
                                          'root-page-transition'),
                                      offset: Offset(
                                          0,
                                          reduceMotion
                                              ? 0
                                              : 4 * (1 - _pageSettle.value)),
                                      child: child,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (floating)
                          Positioned(
                            left: media.viewPadding.left,
                            right: media.viewPadding.right,
                            bottom: dockBottom,
                            child: Padding(
                              padding:
                                  EdgeInsets.symmetric(horizontal: sideInset),
                              child: Center(
                                heightFactor: 1,
                                child: ValueListenableBuilder<bool>(
                                  valueListenable: _dockVisible,
                                  // Keep the actual dock subtree intact while
                                  // animating visibility: avoid feed rebuilds.
                                  child: SizedBox(
                                    width: FloatingTabBar.width,
                                    child: StreamBuilder<int>(
                                      initialData: _selectedIndex,
                                      stream: _indexSctream.stream,
                                      builder: (_, snapshot) => FloatingTabBar(
                                        height: dockHeight,
                                        destinations: barDestinations,
                                        selectedIndex: snapshot.data ?? 0,
                                        onDestinationSelected:
                                            onDestinationSelected,
                                      ),
                                    ),
                                  ),
                                  builder: (context, visible, dock) =>
                                      AnimatedSlide(
                                    duration: reduceMotion
                                        ? Duration.zero
                                        : const Duration(milliseconds: 180),
                                    curve: Curves.easeOutCubic,
                                    offset: visible
                                        ? Offset.zero
                                        : const Offset(0, 1.5),
                                    child: AnimatedOpacity(
                                      duration: reduceMotion
                                          ? Duration.zero
                                          : const Duration(milliseconds: 150),
                                      opacity: visible ? 1 : 0,
                                      child: IgnorePointer(
                                        ignoring: !visible,
                                        child: ExcludeSemantics(
                                          excluding: !visible,
                                          child: ExcludeFocus(
                                            excluding: !visible,
                                            child: dock!,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    bottomNavigationBar: !useRail && !keyboardOpen && !floating
                        ? StreamBuilder<int>(
                            initialData: _selectedIndex,
                            stream: _indexSctream.stream,
                            builder: (_, snapshot) => NavigationBar(
                              destinations: barDestinations,
                              selectedIndex: snapshot.data ?? 0,
                              onDestinationSelected: onDestinationSelected,
                              labelBehavior: NavigationDestinationLabelBehavior
                                  .onlyShowSelected,
                            ),
                          )
                        : null,
                  );
                },
              ),
      ),
    );
  }

  void onDestinationSelected(int index) {
    if (_resetting || !_contrller.hasClients) return;
    _scrollTravel = 0;
    _dockVisible.value = true;
    if (index == 0 && _selectedIndex == 0) {
      _pageScrollController.setIndex(998);
    } else if (index == 1 && _selectedIndex == 1) {
      _pageScrollController.setIndex(TabType.FOLLOW.index);
    }
    // Avoid animating two image-heavy root pages simultaneously.
    if (index == _selectedIndex) return;
    _contrller.jumpToPage(index);
    final media = MediaQuery.of(context);
    if (media.disableAnimations || media.accessibleNavigation) {
      _pageSwitch.value = 1;
    } else {
      // Rapid taps restart one bounded transition; no animation queue builds.
      _pageSwitch.forward(from: 0);
    }
    _selectedIndex = index;
    _indexSctream.add(index);
  }
}
