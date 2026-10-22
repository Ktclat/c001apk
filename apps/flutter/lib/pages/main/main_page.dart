import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../components/floating_tab_bar.dart';
import '../../utils/navigation_diagnostics.dart';
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
  bool _userScrollActive = false;
  bool _floatingActive = false;
  bool _accessibleNavigation = false;
  bool _usingRail = false;
  bool _reducedMotion = false;
  Size? _navigationWindow;
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

  void _revealDock(String reason) {
    NavigationDiagnostics.instance.reveal(reason);
    _scrollTravel = 0;
    _dockVisible.value = true;
  }

  /// Follow user scrolling, including wheel updates and the ballistic tail of
  /// a touch fling. dragDetails is null for both, even on the real feed list.
  bool _handleRootScroll(int page, ScrollNotification notification) {
    final source = notification.context;
    final tickerEnabled = source == null || TickerMode.of(source);
    final currentRoute =
        source == null ? null : ModalRoute.of(source)?.isCurrent;
    void record(String decision, {double? consumed}) {
      NavigationDiagnostics.instance.rootNotification(notification, decision,
          page: page,
          selected: _selectedIndex,
          userSession: _userScrollActive,
          tickerEnabled: tickerEnabled,
          currentRoute: currentRoute,
          visible: _dockVisible.value,
          accumulated: _scrollTravel,
          consumed: consumed);
    }

    if (!_floatingActive || _accessibleNavigation || page != _selectedIndex) {
      record(!_floatingActive
          ? 'floating_inactive'
          : _accessibleNavigation
              ? 'accessible_navigation'
              : 'inactive_root');
      return false;
    }
    if (!tickerEnabled || currentRoute == false) {
      record(!tickerEnabled ? 'ticker_disabled' : 'route_not_current');
      return false;
    }
    // Restore on a Home tab change, not an embedded horizontal media carousel.
    if (notification.metrics.axis == Axis.horizontal) {
      var decision = 'horizontal_ignored';
      if (notification.depth == 0 &&
          notification.metrics is PageMetrics &&
          notification is ScrollUpdateNotification &&
          (notification.scrollDelta ?? 0).abs() > 0) {
        _userScrollActive = false;
        _revealDock('home_tab_transition');
        decision = 'home_tab_reveal';
      }
      record(decision);
      return false;
    }
    if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      _userScrollActive = true;
    } else if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userScrollActive = true;
      _scrollTravel = 0;
    }
    var decision = 'non_update';
    double? consumed;
    final metrics = notification.metrics;
    if (metrics.pixels <= metrics.minScrollExtent + 0.5) {
      _revealDock('top');
      decision = 'top_reveal';
    } else if (notification is ScrollUpdateNotification &&
        (_userScrollActive || notification.dragDetails != null)) {
      final rawDelta = notification.scrollDelta ?? 0;
      // Bounce outside content bounds must not reverse the navigation state.
      final current = metrics.pixels
          .clamp(metrics.minScrollExtent, metrics.maxScrollExtent);
      final previous = (metrics.pixels - rawDelta)
          .clamp(metrics.minScrollExtent, metrics.maxScrollExtent);
      final delta = current - previous;
      consumed = delta;
      decision = delta == 0 ? 'no_consumed_distance' : 'below_threshold';
      if (delta != 0) {
        if (_scrollTravel.sign != delta.sign) _scrollTravel = 0;
        _scrollTravel = (_scrollTravel + delta).clamp(-80.0, 80.0);
        if (_scrollTravel >= 28 && _dockVisible.value) {
          _dockVisible.value = false;
          NavigationDiagnostics.instance.dockVisibilityChanged(false);
          decision = 'hide_threshold';
        } else if (_scrollTravel <= -20 && !_dockVisible.value) {
          _dockVisible.value = true;
          NavigationDiagnostics.instance.dockVisibilityChanged(true);
          decision = 'reveal_threshold';
        } else if (_scrollTravel >= 28) {
          decision = 'already_hidden';
        } else if (_scrollTravel <= -20) {
          decision = 'already_visible';
        }
      }
    }
    if (notification is ScrollUpdateNotification &&
        !_userScrollActive &&
        notification.dragDetails == null &&
        decision == 'non_update') {
      decision = 'no_user_session';
    }
    record(decision, consumed: consumed);
    if (notification is ScrollEndNotification) _userScrollActive = false;
    // Keep RefreshIndicator, nested tabs and other observers connected.
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
    NavigationDiagnostics.instance.reveal('account_session_change');
    _userScrollActive = false;
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
                  // Floating mode stays an overlay across window shapes.
                  // Only classic navigation switches to a rail.
                  final media = MediaQuery.of(context);
                  if (_navigationWindow != constraints.biggest) {
                    _navigationWindow = constraints.biggest;
                    _userScrollActive = false;
                    _pageSwitch.value = 1;
                    _revealDock('window_change');
                  }
                  final safeWidth =
                      constraints.maxWidth - media.viewPadding.horizontal;
                  final useRail = !GStorage.floatingTabBar &&
                      (constraints.maxWidth >= 600 ||
                          constraints.maxWidth >= constraints.maxHeight);
                  final keyboardOpen =
                      MediaQuery.viewInsetsOf(context).bottom > 0;
                  // Hide bottom navigation while typing to avoid covering
                  // chat, search and reply input fields.
                  final floating =
                      !useRail && !keyboardOpen && GStorage.floatingTabBar;
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
                    _userScrollActive = false;
                    _floatingActive = floating;
                    _accessibleNavigation = accessible;
                    _pageSwitch.value = 1;
                    _revealDock('mode_or_accessibility_change');
                  }
                  final safeBottom = math.max(media.viewPadding.bottom,
                      media.systemGestureInsets.bottom);
                  final bottomGap = constraints.maxHeight < 600 ? 8.0 : 12.0;
                  const sideInset = 16.0;
                  final dockWidth = FloatingTabBar.widthFor(
                      context, safeWidth - 2 * sideInset);
                  final dockHeight = FloatingTabBar.heightFor(context);
                  final dockBottom = bottomGap + safeBottom;
                  // Keep scroll content full-bleed behind the floating bar,
                  // but allow every root list to scroll its final item above
                  // the navigation affordance.
                  final scrollClearance =
                      floating ? dockHeight + dockBottom + 16.0 : 0.0;

                  NavigationDiagnostics.instance.rootConfiguration(
                      media, constraints.biggest,
                      floatingSetting: GStorage.floatingTabBar,
                      floatingActive: floating,
                      rail: useRail,
                      selectedRoot: _selectedIndex,
                      visible: _dockVisible.value);
                  return Scaffold(
                    body: Stack(
                      children: [
                        Positioned.fill(
                          child: FloatingNavigationInset(
                            bottom: scrollClearance,
                            child: SafeArea(
                              top: false,
                              bottom: false,
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
                                                onNotification:
                                                    (notification) =>
                                                        _handleRootScroll(index,
                                                            notification),
                                                child: NotificationListener<
                                                    RootNavigationContentChanged>(
                                                  onNotification: (_) {
                                                    if (index ==
                                                        _selectedIndex) {
                                                      _userScrollActive = false;
                                                      _revealDock(
                                                          'root_content_change');
                                                    }
                                                    return false;
                                                  },
                                                  child: pages[index],
                                                ),
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
                        ),
                        if (floating)
                          Positioned(
                            left: media.viewPadding.left,
                            right: media.viewPadding.right,
                            bottom: dockBottom,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: sideInset),
                              child: Center(
                                heightFactor: 1,
                                child: ValueListenableBuilder<bool>(
                                  valueListenable: _dockVisible,
                                  // Keep the actual dock subtree intact while
                                  // animating visibility: avoid feed rebuilds.
                                  child: SizedBox(
                                    width: dockWidth,
                                    child: StreamBuilder<int>(
                                      initialData: _selectedIndex,
                                      stream: _indexSctream.stream,
                                      builder: (_, snapshot) => FloatingTabBar(
                                        height: dockHeight,
                                        dockWidth: dockWidth,
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
    _userScrollActive = false;
    _dockVisible.value = true;
    NavigationDiagnostics.instance.reveal('root_selection_or_reselect');
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
    NavigationDiagnostics.instance.rootSelection(index);
    _indexSctream.add(index);
  }
}
