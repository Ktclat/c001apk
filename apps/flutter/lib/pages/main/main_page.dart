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
import '../../components/floating_dock_motion.dart';
import '../../utils/navigation_diagnostics.dart';
import '../../utils/floating_navigation_policy.dart';
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

class _MainPageState extends State<MainPage> with TickerProviderStateMixin {
  final ReturnTopController _pageScrollController =
      Get.put(ReturnTopController(), tag: 'home');
  int _selectedIndex = 0;
  final _indexSctream = StreamController<int>.broadcast();
  late final MainController _mainController = Get.put(MainController());
  var _contrller = PageController();
  bool _resetting = false;
  // Scroll updates only dock motion, not the image-heavy PageView.
  late final FloatingDockMotion _dockMotion = FloatingDockMotion(vsync: this);
  bool _userScrollActive = false;
  bool _floatingActive = false;
  bool _accessibleNavigation = false;
  FloatingNavigationPolicy _navigationPolicy =
      FloatingNavigationPolicy.automatic;
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
    _dockMotion.reveal();
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
          visible: _dockMotion.value < 1,
          accumulated: _dockMotion.signedTravel,
          progress: _dockMotion.value,
          consumed: consumed);
    }

    final suppression =
        _navigationPolicy.suppressionReason(_accessibleNavigation);
    if (!_floatingActive || suppression != null || page != _selectedIndex) {
      record(!_floatingActive
          ? 'floating_inactive'
          : suppression ?? 'inactive_root');
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
      if (!_userScrollActive) _dockMotion.beginUserScroll();
      _userScrollActive = true;
    } else if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userScrollActive = true;
      _dockMotion.beginUserScroll();
    }
    // A window/policy reset may occur while a finger remains down. Its next
    // genuine drag update starts a fresh session; old ballistic/programmatic
    // updates still cannot inherit the cancelled one.
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null &&
        !_userScrollActive) {
      _dockMotion.beginUserScroll();
      _userScrollActive = true;
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
      decision = _dockMotion.consume(delta);
    }
    if (notification is ScrollUpdateNotification &&
        !_userScrollActive &&
        notification.dragDetails == null &&
        decision == 'non_update') {
      decision = 'no_user_session';
    }
    record(decision, consumed: consumed);
    if (notification is ScrollEndNotification && _userScrollActive) {
      _dockMotion.endUserScroll();
      _userScrollActive = false;
    }
    // Keep RefreshIndicator, nested tabs and other observers connected.
    return false;
  }

  @override
  void initState() {
    super.initState();
    _mainController.checkLoginInfo();
    AccountStore.changes.addListener(_sessionChanged);
    _dockMotion.addListener(_recordDockMotion);
  }

  void _recordDockMotion() {
    NavigationDiagnostics.instance
        .dockMotionChanged(_dockMotion.value, _dockMotion.travelExtent);
  }

  void _sessionChanged() {
    if (!mounted || _resetting) return;
    _dockMotion.reveal();
    NavigationDiagnostics.instance.reveal('account_session_change');
    _userScrollActive = false;
    _dockMotion.beginUserScroll();
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
    _dockMotion.dispose();
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
        valueListenable: GStorage.settings.listenable(keys: [
          SettingsBoxKey.floatingTabBar,
          SettingsBoxKey.floatingNavigationPolicy
        ]),
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
                  final policy = GStorage.floatingNavigationPolicy;
                  final reduceMotion = media.disableAnimations || accessible;
                  if (_usingRail != useRail || _reducedMotion != reduceMotion) {
                    _usingRail = useRail;
                    _reducedMotion = reduceMotion;
                    _pageSwitch.value = 1;
                  }
                  // Reset when the dock enters/leaves the layout. This also
                  // prevents rail/IME scrolls from hiding a future portrait dock.
                  if (_floatingActive != floating ||
                      _accessibleNavigation != accessible ||
                      _navigationPolicy != policy) {
                    _userScrollActive = false;
                    _floatingActive = floating;
                    _accessibleNavigation = accessible;
                    _navigationPolicy = policy;
                    _pageSwitch.value = 1;
                    _revealDock('mode_accessibility_or_policy_change');
                  }
                  final safeBottom = math.max(media.viewPadding.bottom,
                      media.systemGestureInsets.bottom);
                  final bottomGap = constraints.maxHeight < 600 ? 8.0 : 12.0;
                  const sideInset = 16.0;
                  final dockWidth = FloatingTabBar.widthFor(
                      context, safeWidth - 2 * sideInset);
                  final dockHeight = FloatingTabBar.heightFor(context);
                  final dockBottom = bottomGap + safeBottom;
                  if (_dockMotion.configure(
                      extent: dockHeight + dockBottom,
                      motionDisabled: media.disableAnimations)) {
                    _userScrollActive = false;
                  }
                  // Keep scroll content full-bleed behind the floating bar,
                  // but allow every root list to scroll its final item above
                  // the navigation affordance.
                  final scrollClearance =
                      floating ? dockHeight + dockBottom + 16.0 : 0.0;

                  _recordDockMotion();
                  NavigationDiagnostics.instance.rootConfiguration(
                      media, constraints.biggest,
                      floatingSetting: GStorage.floatingTabBar,
                      policy: policy.name,
                      policySuppression: policy.suppressionReason(accessible),
                      floatingActive: floating,
                      rail: useRail,
                      selectedRoot: _selectedIndex,
                      visible: _dockMotion.value < 1);
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
                                child: AnimatedBuilder(
                                  animation: _dockMotion,
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
                                  builder: (context, dock) => AnimatedSlide(
                                    duration: Duration.zero,
                                    curve: Curves.easeOutCubic,
                                    offset: Offset(
                                        0,
                                        _dockMotion.value *
                                            _dockMotion.travelExtent /
                                            dockHeight),
                                    child: AnimatedOpacity(
                                      duration: Duration.zero,
                                      opacity: 1 - _dockMotion.value,
                                      child: IgnorePointer(
                                        ignoring: !_dockMotion.fullyShown,
                                        child: ExcludeSemantics(
                                          excluding: !_dockMotion.fullyShown,
                                          child: ExcludeFocus(
                                            excluding: !_dockMotion.fullyShown,
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
    _dockMotion.beginUserScroll();
    _userScrollActive = false;
    _dockMotion.reveal();
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
