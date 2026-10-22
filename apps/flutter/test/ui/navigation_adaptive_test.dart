import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:c001apk_flutter/logic/local_follow/local_follow_store.dart';
import 'package:c001apk_flutter/logic/accounts/account_store.dart';
import 'package:c001apk_flutter/pages/local_follow/local_follow_page.dart';
import 'package:c001apk_flutter/pages/home/topic/controller.dart';
import 'package:c001apk_flutter/pages/home/topic/home_topic_page.dart';
import 'package:c001apk_flutter/pages/carousel/carousel_page.dart';
import 'package:c001apk_flutter/pages/carousel/carousel_controller.dart';
import 'package:c001apk_flutter/components/cards/feed_card.dart';
import 'dart:ui' as ui;
import 'package:c001apk_flutter/utils/navigation_diagnostics.dart';
import 'package:c001apk_flutter/utils/floating_navigation_policy.dart';
import 'package:c001apk_flutter/components/settings/floating_navigation_policy_tile.dart';
import 'package:c001apk_flutter/components/update_check_tile.dart';
import 'package:c001apk_flutter/pages/settings/navigation_diagnostics_page.dart';
import 'package:c001apk_flutter/main.dart';
import 'package:c001apk_flutter/pages/home/feed/home_feed_controller.dart';
import 'package:c001apk_flutter/pages/home/feed/home_feed_page.dart';
import 'package:c001apk_flutter/pages/home/home_page.dart';
import 'package:c001apk_flutter/logic/model/feed/datum.dart';
import 'package:c001apk_flutter/logic/state/loading_state.dart';
import 'package:c001apk_flutter/utils/app_theme.dart';
import 'package:c001apk_flutter/components/floating_tab_bar.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:c001apk_flutter/utils/global_data.dart';
import 'package:c001apk_flutter/logic/network/request.dart';
import 'package:flutter/material.dart' hide CarouselController;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'localization_test.dart' show EmptyGuestAdapter;

class AdaptiveRouteAdapter extends EmptyGuestAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    if (options.queryParameters['url'] ==
        '/page?url=V9_HOME_TAB_FOLLOW&type=topic') {
      return Future.value(ResponseBody.fromString('{"data":[]}', 200, headers: {
        Headers.contentTypeHeader: ['application/json']
      }));
    }
    if (options.uri.path.endsWith('/user/feedList') ||
        options.queryParameters['url'] ==
            '/page?url=V9_HOME_TAB_FOLLOW&type=circle' ||
        (options.queryParameters['url']
                ?.toString()
                .contains('synthetic-category') ??
            false)) {
      final rows = options.queryParameters['page'] == 1
          ? List.generate(
              30,
              (i) => {
                    ...EmptyGuestAdapter.feed,
                    'id': 2000 + i,
                    'entityId': 2000 + i,
                    'dateline': 1760000030 - i,
                    'message': '合成路线验证第${i + 1}条',
                    'uid': 10
                  })
          : [];
      return Future.value(
          ResponseBody.fromString(jsonEncode({'data': rows}), 200, headers: {
        Headers.contentTypeHeader: ['application/json']
      }));
    }
    return super.fetch(options, requestStream, cancelFuture);
  }
}

Future<void> finishFixtureIo(
    WidgetTester tester, Future<void> Function() action) async {
  var done = false;
  Object? error;
  await tester.runAsync(() async {
    action().then((_) => done = true, onError: (Object e) {
      error = e;
      done = true;
    });
  });
  for (var i = 0; i < 100 && !done; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  if (error != null) {
    throw error!;
  }
  expect(done, isTrue, reason: 'Synthetic local-storage operation must finish');
}

Future<void> settleAtEnd(WidgetTester tester, ScrollPosition position) async {
  // Variable-height cards and pagination refine their estimated scroll extent.
  for (var i = 0; i < 8; i++) {
    final extent = position.maxScrollExtent;
    position.jumpTo(extent);
    await tester.pumpAndSettle();
    if ((position.maxScrollExtent - extent).abs() < 0.1 &&
        (position.pixels - position.maxScrollExtent).abs() < 0.1) break;
  }
}

Future<void> showLastActionVisible(WidgetTester tester, Finder last,
    Finder viewport, Finder dock, ScrollPosition position) async {
  expect(last, findsOneWidget);
  final action = find.descendant(
      of: last, matching: find.byIcon(Icons.thumb_up_alt_outlined));
  final targetBottom = tester.getRect(dock).top - 20;
  final shift = tester.getRect(action).bottom - targetBottom;
  position.jumpTo((position.pixels + shift).clamp(0, position.maxScrollExtent));
  await tester.pumpAndSettle();
  expect(action.hitTestable(), findsOneWidget);
  final rect = tester.getRect(action);
  debugPrint(
      'Last action rect=$rect usable=${tester.getRect(viewport).top}..${tester.getRect(dock).top - 16}');
  expect(rect.top, greaterThanOrEqualTo(tester.getRect(viewport).top));
  expect(rect.bottom, lessThanOrEqualTo(tester.getRect(dock).top - 16));
}

Future<void> captureRoot(WidgetTester tester, GlobalKey key, String path,
    {double pixelRatio = 1}) async {
  final prior = debugDisableShadows;
  try {
    debugDisableShadows = false;
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    boundary.markNeedsPaint();
    await tester.pump();
    await tester.runAsync(() async {
      final frame = await boundary.toImage(pixelRatio: pixelRatio);
      final png = await frame.toByteData(format: ui.ImageByteFormat.png);
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
      frame.dispose();
    });
  } finally {
    debugDisableShadows = prior;
  }
  expect(tester.takeException(), isNull);
}

// Actual app, synthetic network data. Not an Android device screenshot.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-locale-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
    GStorage.blackList = await Hive.openBox('blackList');
    GStorage.favFeed = await Hive.openBox('favFeed');
    GStorage.historyFeed = await Hive.openBox('historyFeed');
    GStorage.searchHistory = await Hive.openBox('searchHistory');
    await GStorage.settings.putAll({
      SettingsBoxKey.xAppDevice: 'synthetic-test-device',
      SettingsBoxKey.userAgent: 'SyntheticTest/1.0',
      SettingsBoxKey.versionName: '16.2.0',
      SettingsBoxKey.versionCode: '2604201',
      SettingsBoxKey.apiVersion: '16',
      SettingsBoxKey.sdkInt: '33',
    });
    final loader = FontLoader(AppFontChoice.bundledFontFamily);
    for (final name in [
      'Regular',
      'Medium',
      'Bold',
    ]) {
      final path = 'assets/fonts/NotoSansCJKsc-$name.otf';
      expect(File(path).existsSync(), isTrue,
          reason: 'Missing pinned font: run bash tools/fetch_fonts.sh');
      loader.addFont(File(path).readAsBytes().then((bytes) {
        return ByteData.sublistView(bytes);
      }));
    }
    await loader.load();

    // The test engine substitutes square Ahem glyphs for Material icons.
    // Load the real font so visual reviews cover actual navigation icons.
    final executable = Platform.resolvedExecutable;
    var flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot == null) {
      const sdkMarker = '/bin/cache/dart-sdk/bin/';
      final index = executable.indexOf(sdkMarker);
      if (index >= 0) flutterRoot = executable.substring(0, index);
    }
    expect(flutterRoot, isNotNull);
    final icons = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    expect(icons.existsSync(), isTrue,
        reason: 'Missing Flutter MaterialIcons OTF for visual review');
    final iconLoader = FontLoader('MaterialIcons');
    iconLoader.addFont(
        icons.readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
    await iconLoader.load();
    GlobalData().isLogin = false;
    Request();
    Request.dio.httpClientAdapter = EmptyGuestAdapter();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/package_info'),
            (_) async => {
                  'appName': 'c001apk',
                  'packageName': 'synthetic.test',
                  'version': '1.0.0',
                  'buildNumber': '1',
                });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => temp.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/shared_preferences'),
            (call) async =>
                call.method == 'getAll' ? <String, Object>{} : true);
  });

  setUp(() async {
    await GStorage.setFloatingNavigationPolicy(
        FloatingNavigationPolicy.automatic);
  });

  tearDown(() async {
    NavigationDiagnostics.instance.clear();
    Get.reset();
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  testWidgets(
      'diagnostics records Home FEED touch signals and exact suppression gates',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 890);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await finishFixtureIo(tester, () => GStorage.setFloatingTabBar(true));
    await tester.pumpWidget(const C001APKAPP());
    await tester.pumpAndSettle();
    final feed = Get.find<HomeFeedController>(tag: 'FEED');
    feed.isEnd = true;
    feed.loadingState.value = Success(List.generate(
        60,
        (i) => Datum.fromJson({
              ...EmptyGuestAdapter.feed,
              'id': 1000 + i,
              'message': 'PRIVATE-FIXTURE-TEXT-$i',
            })));
    await tester.pumpAndSettle();
    final list = find.descendant(
        of: find.byWidgetPredicate(
            (w) => w is HomeFeedPage && w.tabType == TabType.FEED),
        matching: find.byType(ListView));
    final dock = find.byType(FloatingTabBar);
    double opacity() => tester
        .widget<AnimatedOpacity>(
            find.ancestor(of: dock, matching: find.byType(AnimatedOpacity)))
        .opacity;
    final recorder = NavigationDiagnostics.instance;
    recorder.clear();
    await tester.drag(list, const Offset(0, -140));
    await tester.pumpAndSettle();
    expect(recorder.counts, isEmpty, reason: 'No opt-in: no scroll capture');
    feed.scrollController!.jumpTo(0);
    await tester.pumpAndSettle();
    recorder.start();
    await tester.drag(list, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    expect(recorder.counts['feed.FEED.pointer.move'], greaterThan(0));
    expect(recorder.counts['feed.FEED.positionChanged'], greaterThan(0));
    expect(recorder.counts['home.vertical.forwarded'], greaterThan(0));
    expect(recorder.counts['root.vertical.hide_threshold'], greaterThan(0));
    expect(
        recorder.environment['selectedHomeIndex'], Platform.isAndroid ? 1 : 0);
    expect(recorder.environment['homeTabCount'], Platform.isAndroid ? 6 : 5);
    expect(recorder.environment['selectedHomeTab'], 'FEED');
    expect(recorder.report(), isNot(contains('PRIVATE-FIXTURE-TEXT')));
    expect(recorder.report(), isNot(contains('synthetic-test-device')));

    feed.scrollController!.jumpTo(0);
    await tester.pumpAndSettle();
    recorder.start();
    feed.scrollController!.jumpTo(300);
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    expect(recorder.counts['root.vertical.no_user_session'], greaterThan(0));
    expect(recorder.counts['feed.FEED.pointer.move'], isNull);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    await tester.pumpAndSettle();
    recorder.start();
    await tester.drag(list, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    expect(
        recorder.counts['root.vertical.accessible_navigation'], greaterThan(0));
    expect(recorder.environment['accessibleNavigation'], true);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    await tester.pumpAndSettle();
    recorder.start();
    await tester.drag(list, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    expect(recorder.environment['disableAnimations'], true);
    expect(recorder.counts['root.vertical.hide_threshold'], greaterThan(0));
    for (var i = 0; i < 100; i++) {
      recorder.reveal('bounded-test');
    }
    expect(recorder.events.length, NavigationDiagnostics.maxEvents);
    recorder.recording = false;
    final stopped = jsonEncode(recorder.events);
    await tester.drag(list, const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(jsonEncode(recorder.events), stopped);
    recorder.clear();
    expect(recorder.counts, isEmpty);
    expect(recorder.events, isEmpty);
    await tester.tap(find.text('热门'));
    await tester.pumpAndSettle();
    expect(recorder.environment['selectedHomeTab'], 'HOT',
        reason: 'Selection updates even for empty tab without a vertical drag');
    await tester.tap(find.byKey(const ValueKey('floating-tab-hit-我的')));
    await tester.pumpAndSettle();
    expect(recorder.environment['selectedRoot'], 2,
        reason: 'Root selection does not depend on a parent rebuild');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'reported Xiaomi window policy preserves accessibility default and permits explicit touch hide',
      (tester) async {
    tester.view.devicePixelRatio = 3.25;
    tester.view.physicalSize = const Size(1200, 2670);
    tester.view.viewPadding = const FakeViewPadding(top: 140);
    tester.view.padding = const FakeViewPadding(top: 140);
    tester.view.systemGestureInsets = const FakeViewPadding(top: 179);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetSystemGestureInsets);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await finishFixtureIo(tester, () async {
      await GStorage.settings.delete(SettingsBoxKey.floatingNavigationPolicy);
      await GStorage.setFloatingTabBar(true);
    });
    expect(
        GStorage.floatingNavigationPolicy, FloatingNavigationPolicy.automatic);
    expect(FloatingNavigationPolicy.fromStorage(999),
        FloatingNavigationPolicy.automatic);
    final key = GlobalKey();
    await tester
        .pumpWidget(RepaintBoundary(key: key, child: const C001APKAPP()));
    await tester.pumpAndSettle();
    final feed = Get.find<HomeFeedController>(tag: 'FEED');
    feed.isEnd = true;
    feed.loadingState.value = Success(List.generate(
        60,
        (i) => Datum.fromJson({
              ...EmptyGuestAdapter.feed,
              'id': 1000 + i,
              'message': 'Synthetic offline policy regression $i'
            })));
    await tester.pumpAndSettle();
    final list = find.descendant(
        of: find.byWidgetPredicate(
            (w) => w is HomeFeedPage && w.tabType == TabType.FEED),
        matching: find.byType(ListView));
    final dock = find.byType(FloatingTabBar);
    Finder ancestor(Type type) =>
        find.ancestor(of: dock, matching: find.byType(type));
    double opacity() =>
        tester.widget<AnimatedOpacity>(ancestor(AnimatedOpacity)).opacity;
    Future<void> capture(String name) =>
        captureRoot(tester, key, 'build/review/policy/$name.png');
    final recorder = NavigationDiagnostics.instance;
    recorder.start();
    await tester.drag(list, const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(feed.scrollController!.offset, greaterThan(28));
    expect(opacity(), 1);
    expect(
        recorder.counts['root.vertical.accessible_navigation'], greaterThan(0));
    expect(recorder.environment['floatingNavigationPolicy'], 'automatic');
    expect(recorder.environment['rootWindowDp'], [1200 / 3.25, 2670 / 3.25]);
    await capture('00-automatic-accessibility-visible');

    await finishFixtureIo(
        tester,
        () => GStorage.setFloatingNavigationPolicy(
            FloatingNavigationPolicy.hideOnScroll));
    await tester.pumpAndSettle();
    expect(GStorage.settings.get(SettingsBoxKey.floatingNavigationPolicy), 1);
    expect(recorder.environment['accessibleNavigation'], true);
    expect(recorder.environment['floatingNavigationPolicy'], 'hideOnScroll');
    expect(recorder.environment['policySuppressionReason'], isNull);
    feed.scrollController!.jumpTo(0);
    await tester.pumpAndSettle();
    recorder.start();
    final gesture = await tester.startGesture(tester.getCenter(list));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -20),
        timeStamp: const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -10),
        timeStamp: const Duration(milliseconds: 24));
    await gesture.moveBy(const Offset(0, -10),
        timeStamp: const Duration(milliseconds: 32));
    await tester.pump(const Duration(milliseconds: 16));
    expect(feed.scrollController!.offset, lessThan(28));
    expect(opacity(), 1);
    await capture('01-explicit-short-touch-visible');
    await gesture.up(timeStamp: const Duration(milliseconds: 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(feed.scrollController!.offset, greaterThan(28));
    expect(opacity(), 0,
        reason:
            'User-started ballistic distance hides despite accessibility flag only after explicit choice');
    expect(tester.widget<AnimatedOpacity>(ancestor(AnimatedOpacity)).duration,
        Duration.zero);
    expect(tester.widget<IgnorePointer>(ancestor(IgnorePointer).first).ignoring,
        true);
    expect(
        tester
            .widget<ExcludeSemantics>(ancestor(ExcludeSemantics).first)
            .excluding,
        true);
    expect(tester.widget<ExcludeFocus>(ancestor(ExcludeFocus).first).excluding,
        true);
    expect(find.byKey(const ValueKey('floating-tab-hit-我的')).hitTestable(),
        findsNothing);
    await tester.pumpAndSettle();
    await capture('02-explicit-ballistic-hidden');
    expect(recorder.counts['root.vertical.hide_threshold'], greaterThan(0));
    expect(recorder.counts['feed.FEED.pointer.move'], greaterThan(0));
    expect(recorder.counts['root.vertical.accessible_navigation'], isNull);
    await tester.drag(list, const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('floating-tab-hit-我的')))
            .height,
        greaterThanOrEqualTo(48));
    await capture('03-reverse-revealed');
    feed.scrollController!.jumpTo(0);
    await tester.pumpAndSettle();
    recorder.start();
    feed.scrollController!.jumpTo(300);
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    expect(recorder.counts['root.vertical.no_user_session'], greaterThan(0));
    await tester.drag(list, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    await tester.tap(find.text('热门'));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    await tester.tap(find.text('动态'));
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    await finishFixtureIo(
        tester,
        () => GStorage.setFloatingNavigationPolicy(
            FloatingNavigationPolicy.automatic));
    await tester.pumpAndSettle();
    expect(opacity(), 1,
        reason: 'Returning to Auto restores accessibility protection');
    await finishFixtureIo(
        tester,
        () => GStorage.setFloatingNavigationPolicy(
            FloatingNavigationPolicy.hideOnScroll));
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    await finishFixtureIo(
        tester,
        () => GStorage.setFloatingNavigationPolicy(
            FloatingNavigationPolicy.alwaysVisible));
    await tester.pumpAndSettle();
    expect(opacity(), 1,
        reason: 'Policy transition reveals and clears old session');
    recorder.start();
    await tester.drag(list, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    expect(
        recorder.counts['root.vertical.policy_always_visible'], greaterThan(0));
    await capture('04-always-visible');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('policy selector requires explicit app choice and persists it',
      (tester) async {
    await finishFixtureIo(
        tester,
        () => GStorage.setFloatingNavigationPolicy(
            FloatingNavigationPolicy.automatic));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.devicePixelRatio = 3.25;
    tester.view.physicalSize = const Size(1200, 2670);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: AppFontChoice.bundledFontFamily),
            home: const Scaffold(body: FloatingNavigationPolicyTile()))));
    await tester.tap(find.text('悬浮导航隐藏方式'));
    await tester.pumpAndSettle();
    expect(find.textContaining('系统当前报告无障碍导航需求'), findsOneWidget);
    expect(
        GStorage.floatingNavigationPolicy, FloatingNavigationPolicy.automatic);
    await captureRoot(
        tester, key, 'build/review/policy/05-explicit-policy-picker.png');
    await tester.tap(find.text('滚动时隐藏'));
    await finishFixtureIo(tester, () => GStorage.settings.flush());
    await tester.pumpAndSettle();
    expect(GStorage.floatingNavigationPolicy,
        FloatingNavigationPolicy.hideOnScroll);
    expect(tester.platformDispatcher.accessibilityFeatures.accessibleNavigation,
        true);
    expect(find.text('滚动时隐藏'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 240);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: AppFontChoice.bundledFontFamily),
            home: const Scaffold(body: FloatingNavigationPolicyTile()))));
    await tester.pumpAndSettle();
    expect(find.text('滚动时隐藏'), findsOneWidget,
        reason: 'Recreated settings widget reads persisted choice');
    await tester.tap(find.text('悬浮导航隐藏方式'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('始终显示'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await captureRoot(
        tester, key, 'build/review/policy/06-short-font2-policy-picker.png');
    await tester.tap(find.text('始终显示'));
    await finishFixtureIo(tester, () => GStorage.settings.flush());
    await tester.pumpAndSettle();
    expect(GStorage.floatingNavigationPolicy,
        FloatingNavigationPolicy.alwaysVisible);
    await tester.tap(find.text('悬浮导航隐藏方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(GStorage.floatingNavigationPolicy,
        FloatingNavigationPolicy.alwaysVisible);
  });

  testWidgets('diagnostics UI is opt-in and copies only on explicit tap',
      (tester) async {
    final recorder = NavigationDiagnostics.instance;
    recorder.clear();
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 890);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: AppFontChoice.bundledFontFamily),
            home: const NavigationDiagnosticsPage())));
    await tester.pumpAndSettle();
    expect(recorder.recording, false);
    expect(copied, isNull);
    await tester.tap(find.text('开始新记录'));
    await tester.pumpAndSettle();
    expect(recorder.recording, true);
    recorder.reveal('test_only_not_device');
    await tester.tap(find.text('停止并查看'));
    await tester.pumpAndSettle();
    expect(recorder.recording, false);
    expect(copied, isNull);
    await tester.tap(find.text('复制报告'));
    await tester.pumpAndSettle();
    expect(jsonDecode(copied!)['schema'], 1);
    if (NavigationBuildIdentity.diagnostic) {
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .clearSnackBars();
      await tester.pumpAndSettle();
      await AppUpdates.check(
          tester.element(find.byType(NavigationDiagnosticsPage)));
      await tester.pumpAndSettle();
      expect(find.text('独立诊断版不检查正式更新，也不会替换原应用'), findsOneWidget);
    }
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await captureRoot(tester, key,
        'build/review/diagnostics/${NavigationBuildIdentity.diagnostic ? 'standalone' : 'normal'}-opt-in-report-ui.png');
    await tester.tap(find.text('清空记录'));
    await tester.pumpAndSettle();
    expect(recorder.events, isEmpty);
    recorder.environment['nonFiniteTest'] = double.infinity;
    expect(() => jsonDecode(recorder.report()), returnsNormally);
    recorder.environment.remove('nonFiniteTest');
  });

  final cases = [
    (
      'xiaomi-aspect-density3',
      const Size(400, 890),
      3.0,
      1.0,
      const EdgeInsets.fromLTRB(0, 32, 0, 24)
    ),
    (
      'compact-large-text',
      const Size(320, 640),
      2.0,
      2.0,
      const EdgeInsets.fromLTRB(0, 24, 0, 48)
    ),
    (
      'phone360',
      const Size(360, 800),
      2.0,
      1.0,
      const EdgeInsets.fromLTRB(0, 24, 0, 24)
    ),
    (
      'phone393',
      const Size(393, 852),
      2.0,
      1.3,
      const EdgeInsets.fromLTRB(0, 24, 0, 24)
    ),
    (
      'phone412-large-text',
      const Size(412, 915),
      2.0,
      2.0,
      const EdgeInsets.fromLTRB(0, 24, 0, 48)
    ),
    ('wide-phone', const Size(480, 900), 2.0, 1.0, EdgeInsets.zero),
    (
      'landscape-cutout',
      const Size(890, 400),
      2.0,
      1.0,
      const EdgeInsets.fromLTRB(44, 0, 24, 24)
    ),
    (
      'short-window-large-text',
      const Size(480, 240),
      2.0,
      2.0,
      const EdgeInsets.fromLTRB(24, 0, 0, 24)
    ),
    (
      'tablet',
      const Size(600, 960),
      2.0,
      1.3,
      const EdgeInsets.fromLTRB(0, 24, 0, 24)
    ),
  ];
  for (final config in cases) {
    testWidgets('adaptive real root pages ${config.$1}', (tester) async {
      final size = config.$2;
      final dpr = config.$3;
      final inset = config.$5;
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = size * dpr;
      final padding = FakeViewPadding(
          left: inset.left * dpr,
          top: inset.top * dpr,
          right: inset.right * dpr,
          bottom: inset.bottom * dpr);
      tester.view.viewPadding = padding;
      tester.view.padding = padding;
      final gestureBottom = config.$1 == 'phone360' ? 40.0 : inset.bottom;
      tester.view.systemGestureInsets =
          FakeViewPadding(bottom: gestureBottom * dpr);
      addTearDown(tester.view.resetSystemGestureInsets);
      tester.platformDispatcher.textScaleFactorTestValue = config.$4;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await finishFixtureIo(tester, () => GStorage.setFloatingTabBar(true));
      final key = GlobalKey();
      await tester
          .pumpWidget(RepaintBoundary(key: key, child: const C001APKAPP()));
      await tester.pumpAndSettle();
      final feed = Get.find<HomeFeedController>(tag: 'FEED');
      feed.isEnd = true;
      feed.loadingState.value = Success(List.generate(
          30,
          (i) => Datum.fromJson({
                ...EmptyGuestAdapter.feed,
                'id': 1000 + i,
                'message': '适配验证第${i + 1}条：内容在悬浮栏下面滚动，末尾操作仍可完整到达。'
              })));
      await tester.pumpAndSettle();
      final dock = find.byType(FloatingTabBar);
      final floating = dock.evaluate().isNotEmpty;
      final baseline = Platform.environment['ADAPTIVE_BASELINE'] == 'true';
      Future<void> capture(String name) => captureRoot(tester, key,
          'build/review/${baseline ? "adaptive-before" : "adaptive-after"}/${config.$1}-$name.png',
          pixelRatio: dpr);

      double opacity() => tester
          .widget<AnimatedOpacity>(
              find.ancestor(of: dock, matching: find.byType(AnimatedOpacity)))
          .opacity;
      if (floating) {
        final rect = tester.getRect(dock);
        expect(rect.left, greaterThanOrEqualTo(inset.left + 8));
        expect(rect.right, lessThanOrEqualTo(size.width - inset.right - 8));
        expect(rect.bottom, lessThanOrEqualTo(size.height - inset.bottom - 8));
        for (final label in ['主页', '关注', '我的']) {
          final hit =
              tester.getRect(find.byKey(ValueKey('floating-tab-hit-$label')));
          expect(hit.width, greaterThanOrEqualTo(48));
          expect(hit.height, greaterThanOrEqualTo(48));
        }
        if (!baseline && config.$4 >= 1.3) expect(rect.width, greaterThan(268));
      }
      if (!baseline) {
        expect(dock, findsOneWidget);
        expect(tester.getRect(dock).bottom,
            lessThanOrEqualTo(size.height - gestureBottom));
      }
      await capture('home-top');
      final list = find.byWidgetPredicate(
          (w) => w is ListView && w.controller == feed.scrollController);
      final feedStart =
          tester.getTopLeft(list) + Offset(tester.getSize(list).width / 2, 40);
      await tester.dragFrom(feedStart, const Offset(0, -140));
      await tester.pumpAndSettle();
      if (floating) {
        expect(opacity(), 0);
        expect(find.byKey(const ValueKey('floating-tab-hit-我的')).hitTestable(),
            findsNothing);
        expect(
            tester
                .widget<ExcludeFocus>(find
                    .ancestor(of: dock, matching: find.byType(ExcludeFocus))
                    .first)
                .excluding,
            isTrue);
        expect(
            tester
                .widget<ExcludeSemantics>(find
                    .ancestor(of: dock, matching: find.byType(ExcludeSemantics))
                    .first)
                .excluding,
            isTrue);
      }
      await capture('home-down');
      await tester.dragFrom(feedStart, const Offset(0, 80));
      await tester.pumpAndSettle();
      if (floating) expect(opacity(), 1);
      // Keep the dock visible to prove clearance, independent of auto-hide.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      await tester.pumpAndSettle();
      final feedPosition = feed.scrollController!.position;
      await settleAtEnd(tester, feedPosition);
      // The 80dp terminal status remains reachable above the visible dock.
      if (floating) {
        final status = find.text('没有更多了');
        final shift =
            tester.getRect(status).bottom - (tester.getRect(dock).top - 20);
        feedPosition.jumpTo((feedPosition.pixels + shift)
            .clamp(0, feedPosition.maxScrollExtent));
        await tester.pumpAndSettle();
        expect(tester.getRect(status).top,
            greaterThanOrEqualTo(tester.getRect(list).top));
        expect(tester.getRect(status).bottom,
            lessThanOrEqualTo(tester.getRect(dock).top - 16));
        await capture('home-terminal-status');
      }
      // Bring the final card's actionable row into the usable viewport too.
      feedPosition.jumpTo((feedPosition.maxScrollExtent - 80)
          .clamp(0, feedPosition.maxScrollExtent));
      await tester.pumpAndSettle();
      final last =
          find.byWidgetPredicate((w) => w is FeedCard && w.data.id == 1029);
      expect(last, findsOneWidget);
      if (floating) {
        await showLastActionVisible(tester, last, list, dock, feedPosition);
      }
      await capture('home-last-visible-dock');
      if (floating) {
        await tester.tap(find.byKey(const ValueKey('floating-tab-hit-我的')));
      } else {
        await tester.tap(find.descendant(
            of: find.byType(NavigationRail),
            matching: find.byIcon(Icons.person_outline)));
      }
      await tester.pumpAndSettle();
      await capture('my-top');
      final scroll = find
          .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable))
          .first;
      final position = tester.state<ScrollableState>(scroll).position;
      if (!baseline && position.maxScrollExtent > 50) {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures();
        await tester.pumpAndSettle();
        final headerY = tester.getTopLeft(find.text('点击登录')).dy;
        final myStart = tester.getTopLeft(find.byType(CustomScrollView)) +
            Offset(tester.getSize(find.byType(CustomScrollView)).width / 2, 40);
        await tester.dragFrom(myStart, const Offset(0, -100));
        await tester.pumpAndSettle();
        expect(opacity(), 0);
        final movedHeader = find.text('点击登录');
        if (movedHeader.evaluate().isNotEmpty) {
          expect(tester.getTopLeft(movedHeader).dy, lessThan(headerY));
        } else {
          expect(position.pixels, greaterThan(28));
        }
        await capture('my-down');
        await tester.dragFrom(myStart, const Offset(0, 80));
        await tester.pumpAndSettle();
        expect(opacity(), 1);
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(accessibleNavigation: true);
        await tester.pumpAndSettle();
      }
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final lastMy = find
          .ancestor(of: find.text('私信与信息'), matching: find.byType(InkWell))
          .first;
      expect(lastMy, findsOneWidget);
      if (floating) {
        final shift =
            tester.getRect(lastMy).bottom - (tester.getRect(dock).top - 16);
        position.jumpTo(
            (position.pixels + shift).clamp(0, position.maxScrollExtent));
        await tester.pumpAndSettle();
        expect(lastMy.hitTestable(), findsOneWidget);
        expect(
            tester.getRect(lastMy).top,
            greaterThanOrEqualTo(
                tester.getRect(find.byType(CustomScrollView)).top));
        expect(tester.getRect(lastMy).bottom,
            lessThanOrEqualTo(tester.getRect(dock).top - 15.99));
      }
      if (!baseline && !floating) {
        expect(tester.getRect(lastMy).bottom,
            lessThanOrEqualTo(size.height - inset.bottom));
      }
      await capture('my-last-visible-dock');
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final routeSize in [const Size(400, 890), const Size(480, 240)]) {
    testWidgets(
        'actual local follow and nested topic content scroll the dock $routeSize',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = routeSize;
      if (routeSize.height < 300) {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.view.padding = const FakeViewPadding(bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(bottom: 24);
      }
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.runAsync(() async {
        await GStorage.setFloatingTabBar(true);
        await LocalFollowStore().follow('10', '合成作者', '');
      });
      Request.dio.httpClientAdapter = AdaptiveRouteAdapter();
      final routeCaptureKey = GlobalKey();
      await tester.pumpWidget(
          RepaintBoundary(key: routeCaptureKey, child: const C001APKAPP()));
      await tester.pumpAndSettle();
      Future<void> captureRoute(String phase) => captureRoot(
          tester,
          routeCaptureKey,
          'build/review/adaptive-after/routes-${routeSize.width.toInt()}x${routeSize.height.toInt()}-$phase.png');
      final dock = find.byType(FloatingTabBar);
      double opacity() => tester
          .widget<AnimatedOpacity>(
              find.ancestor(of: dock, matching: find.byType(AnimatedOpacity)))
          .opacity;
      await tester.tap(find.byKey(const ValueKey('floating-tab-hit-关注')));
      await tester.pumpAndSettle();
      final local = find.descendant(
          of: find.byType(LocalFollowFeedView),
          matching: find.byType(ListView));
      expect(local, findsOneWidget);
      await captureRoute('follow-top');
      debugPrint(
          'Local Follow usable band: ${tester.getRect(local).top}..${tester.getRect(dock).top - 16}');
      expect(tester.getRect(dock).top - 16 - tester.getRect(local).top,
          greaterThanOrEqualTo(24),
          reason: 'At least a full action must fit above dock');
      final localStart = tester.getTopLeft(local) +
          Offset(tester.getSize(local).width / 2, 40);
      await tester.dragFrom(localStart, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(opacity(), 0);
      await tester.dragFrom(localStart, const Offset(0, 90));
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      await tester.pumpAndSettle();
      final localPosition = tester
          .state<ScrollableState>(find
              .descendant(of: local, matching: find.byType(Scrollable))
              .first)
          .position;
      await settleAtEnd(tester, localPosition);
      localPosition.jumpTo((localPosition.maxScrollExtent - 80)
          .clamp(0, localPosition.maxScrollExtent));
      await tester.pumpAndSettle();
      final lastFollow =
          find.byWidgetPredicate((w) => w is FeedCard && w.data.id == 2029);
      await showLastActionVisible(
          tester, lastFollow, local, dock, localPosition);
      await captureRoute("follow-last-action");
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('floating-tab-hit-主页')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('话题').first);
      await tester.pumpAndSettle();
      final topic = Get.find<HomeTopicController>(tag: 'TOPIC');
      // Inject offline category data into the actual production controller.
      // ignore: invalid_use_of_protected_member
      topic.change([
        Datum.fromJson({
          'entityType': 'card',
          'entities': [
            {'title': '分类一', 'url': 'synthetic-category-1'},
            {'title': '分类二', 'url': 'synthetic-category-2'},
            {'title': '空分类', 'url': 'empty-category'},
          ]
        })
      ], status: RxStatus.success());
      await tester.pumpAndSettle();
      final topicFeed =
          Get.find<CarouselController>(tag: 'synthetic-category-2分类二');
      topicFeed.isEnd = true;
      topicFeed.loadingState.value = Success(List.generate(30,
          (i) => Datum.fromJson({...EmptyGuestAdapter.feed, 'id': 3000 + i})));
      await tester.pumpAndSettle();
      final content = find.descendant(
          of: find.byType(CarouselPage), matching: find.byType(ListView));
      expect(content, findsOneWidget);
      final topicScrollable =
          find.descendant(of: content, matching: find.byType(Scrollable)).first;
      debugPrint(
          'Topic before: ${tester.state<ScrollableState>(topicScrollable).position}');
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      await tester.pumpAndSettle();
      final topicPosition =
          tester.state<ScrollableState>(topicScrollable).position;
      await settleAtEnd(tester, topicPosition);
      topicPosition.jumpTo((topicPosition.maxScrollExtent - 80)
          .clamp(0, topicPosition.maxScrollExtent));
      await tester.pumpAndSettle();
      final lastTopic =
          find.byWidgetPredicate((w) => w is FeedCard && w.data.id == 3029);
      await showLastActionVisible(
          tester, lastTopic, content, dock, topicPosition);
      await captureRoute("topic-last-action");
      final visibleDockTop = tester.getRect(dock).top;
      topicPosition.jumpTo(0);
      await tester.pumpAndSettle();
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      await tester.pumpAndSettle();
      await tester.dragFrom(
          tester.getTopLeft(content) +
              Offset(tester.getSize(content).width / 2, 40),
          const Offset(0, -160));
      await tester.pumpAndSettle();
      debugPrint(
          'Topic after: ${tester.state<ScrollableState>(topicScrollable).position}');
      expect(opacity(), 0);
      await captureRoute('topic-hidden');
      final sidebar = find
          .descendant(
              of: find.byType(HomeTopicPage), matching: find.byType(ListView))
          .first;
      final sidebarScroll =
          find.descendant(of: sidebar, matching: find.byType(Scrollable)).first;
      final sidebarPosition =
          tester.state<ScrollableState>(sidebarScroll).position;
      final lastCategory = find.text('空分类');
      final sidebarShift =
          tester.getRect(lastCategory).bottom - (visibleDockTop - 16);
      if (sidebarShift > 0) {
        sidebarPosition.jumpTo((sidebarPosition.pixels + sidebarShift)
            .clamp(0, sidebarPosition.maxScrollExtent));
        await tester.pumpAndSettle();
      }
      expect(opacity(), 0,
          reason: 'Programmatic sidebar positioning is not scroll intent');
      expect(lastCategory.hitTestable(), findsOneWidget);
      expect(tester.getRect(lastCategory).top,
          greaterThanOrEqualTo(tester.getRect(sidebar).top));
      expect(tester.getRect(lastCategory).bottom,
          lessThanOrEqualTo(visibleDockTop - 16));
      await tester.tap(lastCategory);
      await tester.pumpAndSettle();
      expect(opacity(), 1,
          reason:
              'Changing nested vertical topic category to empty must restore root navigation');
      void expectStateVisible(Finder state, {bool interactive = true}) {
        expect(state, findsOneWidget);
        if (interactive) {
          expect(state.hitTestable(), findsOneWidget);
        }
        final rect = tester.getRect(state);
        expect(
            rect.top,
            greaterThanOrEqualTo(
                tester.getRect(find.byType(CarouselPage).first).top));
        expect(rect.bottom, lessThanOrEqualTo(tester.getRect(dock).top - 16));
      }

      expectStateVisible(find.text('暂无内容'));
      await captureRoute('topic-empty-restored');
      final emptyController =
          Get.find<CarouselController>(tag: 'empty-category空分类');
      emptyController.loadingState.value = LoadingState.loading();
      await tester.pump();
      expectStateVisible(find.byType(CircularProgressIndicator),
          interactive: false);
      await captureRoute('topic-loading');
      emptyController.loadingState.value = LoadingState.error('加载失败，点击重试');
      await tester.pumpAndSettle();
      final retry = find.text('加载失败，点击重试');
      expectStateVisible(retry);
      await captureRoute('topic-error-retry');
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expectStateVisible(find.text('暂无内容'));
      final longError = '${List.filled(40, '详细错误说明').join('\n')}\n点击重试';
      emptyController.loadingState.value = LoadingState.error(longError);
      await tester.pumpAndSettle();
      final errorScroll = find
          .descendant(
              of: find.byType(CarouselPage).first,
              matching: find.byType(Scrollable))
          .first;
      final errorPosition = tester.state<ScrollableState>(errorScroll).position;
      expect(errorPosition.maxScrollExtent, greaterThan(0));
      errorPosition.jumpTo(errorPosition.maxScrollExtent);
      await tester.pumpAndSettle();
      final errorRect = tester.getRect(find.text(longError));
      expect(
          errorRect.bottom, lessThanOrEqualTo(tester.getRect(dock).top - 16));
      expect(
          errorRect.bottom, greaterThan(tester.getRect(errorScroll).top + 10));
      expect(opacity(), 1);
      await captureRoute('topic-long-error-end');
      await tester.tapAt(Offset(errorRect.center.dx, errorRect.bottom - 6));
      await tester.pumpAndSettle();
      expectStateVisible(find.text('暂无内容'));
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => LocalFollowStore().unfollow('10'));
      Request.dio.httpClientAdapter = EmptyGuestAdapter();
    });
  }
  testWidgets(
      'server Follow content identity restores hidden dock and classic rail remains opt-in',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 890);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() => GlobalData().isLogin = false);
    await tester.runAsync(() async {
      await AccountStore().saveLogin(
          uid: "321",
          username: "synthetic",
          token: "synthetic-fixture-not-credential");
      await GStorage.setFloatingTabBar(true);
      await GStorage.settings.put(FollowFeedSelection.storageKey, 1);
    });
    Request.dio.httpClientAdapter = AdaptiveRouteAdapter();
    await tester.pumpWidget(const C001APKAPP());
    await tester.pumpAndSettle();
    final dock = find.byType(FloatingTabBar);
    double opacity() => tester
        .widget<AnimatedOpacity>(
            find.ancestor(of: dock, matching: find.byType(AnimatedOpacity)))
        .opacity;
    await tester.tap(find.byKey(const ValueKey('floating-tab-hit-关注')));
    await tester.pumpAndSettle();
    final list = find.descendant(
        of: find.byWidgetPredicate(
            (w) => w is HomeFeedPage && w.tabType == TabType.FOLLOW),
        matching: find.byType(ListView));
    expect(list, findsOneWidget);
    debugPrint(
        'Follow before drag: ${tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)).first).position}');
    await tester.drag(list, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    await tester.tap(find.byTooltip('切换关注内容'));
    await tester.pumpAndSettle();
    await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<FollowFeedSelection>, '话题关注'));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    expect(find.text('暂无内容'), findsOneWidget);
    await finishFixtureIo(tester, () => GStorage.settings.flush());
    await finishFixtureIo(tester, () => GStorage.setFloatingTabBar(false));
    tester.view.physicalSize = const Size(850, 390);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(dock, findsNothing);
    await finishFixtureIo(tester, () => GStorage.setFloatingTabBar(true));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsNothing);
    expect(dock, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    Request.dio.httpClientAdapter = EmptyGuestAdapter();
    await finishFixtureIo(tester, () => AccountStore().useGuest());
  });
}
