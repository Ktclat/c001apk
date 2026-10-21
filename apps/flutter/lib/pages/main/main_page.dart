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

class _MainPageState extends State<MainPage> {
  final ReturnTopController _pageScrollController =
      Get.put(ReturnTopController(), tag: 'home');
  int _selectedIndex = 0;
  final _indexSctream = StreamController<int>.broadcast();
  late final MainController _mainController = Get.put(MainController());
  var _contrller = PageController();
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    _mainController.checkLoginInfo();
    AccountStore.changes.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (!mounted || _resetting) return;
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
                  final portrait =
                      constraints.maxHeight > constraints.maxWidth;
                  final floating = portrait && GStorage.floatingTabBar;
                  final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
                  const bottomGap = 12.0;
                  const sideInset = 16.0;
                  final floatHeight = FloatingTabBar.heightFor(context);
                  // Reserve space for the overlay so the last line of a
                  // scrolling feed and its refresh affordances are accessible.
                  final reservedBottom = floating
                      ? floatHeight + bottomGap + safeBottom + 12
                      : 0.0;

                  return Scaffold(
                    body: Stack(
                      children: [
                        Positioned.fill(
                          bottom: reservedBottom,
                          child: Row(
                            children: [
                              if (!portrait)
                                StreamBuilder<int>(
                                  initialData: _selectedIndex,
                                  stream: _indexSctream.stream,
                                  builder: (_, snapshot) => NavigationRail(
                                    destinations: railDestinations,
                                    selectedIndex: snapshot.data ?? 0,
                                    onDestinationSelected: onDestinationSelected,
                                  ),
                                ),
                              Expanded(
                                child: PageView(
                                  physics: const NeverScrollableScrollPhysics(),
                                  controller: _contrller,
                                  children: pages,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (floating)
                          Positioned(
                            left: sideInset,
                            right: sideInset,
                            bottom: bottomGap + safeBottom,
                            child: StreamBuilder<int>(
                              initialData: _selectedIndex,
                              stream: _indexSctream.stream,
                              builder: (_, snapshot) => FloatingTabBar(
                                height: floatHeight,
                                destinations: barDestinations,
                                selectedIndex: snapshot.data ?? 0,
                                onDestinationSelected: onDestinationSelected,
                              ),
                            ),
                          ),
                      ],
                    ),
                    bottomNavigationBar: portrait && !floating
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
    if (index == 0 && _selectedIndex == 0) {
      _pageScrollController.setIndex(998);
    } else if (index == 1 && _selectedIndex == 1) {
      _pageScrollController.setIndex(TabType.FOLLOW.index);
    }
    // Avoid animating two image-heavy root pages simultaneously.
    if (index == _selectedIndex) return;
    _contrller.jumpToPage(index);
    _selectedIndex = index;
    _indexSctream.add(index);
  }
}
