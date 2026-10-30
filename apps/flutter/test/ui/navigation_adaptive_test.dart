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
import 'package:c001apk_flutter/pages/settings/settings_page.dart';
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
import 'message_shortcuts_test_support.dart';

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
    await GStorage.settings.delete('floatingNavigationPolicy');
    await GStorage.settings.delete(SettingsBoxKey.hideFloatingTabBarOnScroll);
  });

  tearDown(() async {
    NavigationDiagnostics.instance.clear();
    Get.reset();
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  testWidgets('scroll-hide changes restore navigation and clear old scroll intent',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 850);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    await finishFixtureIo(tester, () => GStorage.setFloatingTabBar(true));
    await tester.pumpWidget(const C001APKAPP());
    await tester.pumpAndSettle();
    final rows = List.generate(
        60,
        (i) => Datum.fromJson({
              ...EmptyGuestAdapter.feed,
              'id': 6000 + i,
              'message': 'Synthetic scroll-hide option regression $i',
            }));
    var feed = Get.find<HomeFeedController>(tag: 'FEED');
    feed.isEnd = true;
    feed.loadingState.value = Success(rows);
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

    await tester.fling(list, const Offset(0, -220), 1800);
    await tester.pump(const Duration(milliseconds: 16));
    expect(opacity(), 0);
    expect(feed.scrollController!.position.isScrollingNotifier.value, true);
    await finishFixtureIo(
        tester, () => GStorage.setHideFloatingTabBarOnScroll(false));
    await tester.pump();
    expect(opacity(), 1,
        reason: 'Disabling scroll hide reveals an already hidden dock');
    expect(tester.widget<IgnorePointer>(ancestor(IgnorePointer).first).ignoring,
        false);
    expect(
        tester
            .widget<ExcludeSemantics>(ancestor(ExcludeSemantics).first)
            .excluding,
        false);
    expect(tester.widget<ExcludeFocus>(ancestor(ExcludeFocus).first).excluding,
        false);
    expect(find.byKey(const ValueKey('floating-tab-hit-我的')).hitTestable(),
        findsOneWidget);
    expect(NavigationDiagnostics.instance.environment['floatingNavigationPolicy'],
        'alwaysVisible');

    await finishFixtureIo(
        tester, () => GStorage.setHideFloatingTabBarOnScroll(true));
    await tester.pump();
    final oldOffset = feed.scrollController!.offset;
    await tester.pump(const Duration(milliseconds: 80));
    expect(feed.scrollController!.offset, greaterThan(oldOffset),
        reason: 'The pre-setting-change ballistic tail really continued');
    expect(opacity(), 1,
        reason: 'Re-enabling must wait for a new genuine scroll gesture');
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(opacity(), 0, reason: 'A new gesture can hide after re-enabling');

    await finishFixtureIo(
        tester, () => GStorage.setHideFloatingTabBarOnScroll(false));
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(opacity(), 1, reason: 'Scrolling cannot hide when the option is off');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(dock, findsNothing, reason: 'The keyboard still hides navigation');
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(opacity(), 1);

    // Recreate the real app to exercise the stored preference, not local state.
    await tester.pumpWidget(const SizedBox());
    Get.reset();
    await tester.pumpWidget(const C001APKAPP());
    await tester.pumpAndSettle();
    feed = Get.find<HomeFeedController>(tag: 'FEED');
    feed.isEnd = true;
    feed.loadingState.value = Success(rows);
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(GStorage.hideFloatingTabBarOnScroll, false);
    expect(opacity(), 1);
    await tester.tap(find.byKey(const ValueKey('floating-tab-hit-我的')));
    await tester.pumpAndSettle();
    expect(find.text('点击登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
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
    expect(recorder.counts['root.vertical.hide_progress'], greaterThan(0));
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
    expect(opacity(), 0);
    expect(recorder.counts['root.vertical.accessible_navigation'], isNull);
    expect(recorder.counts['root.vertical.hide_progress'], greaterThan(0));
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
      'scroll-linked dock motion follows real Home gestures and cancels interrupted settle',
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
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetSystemGestureInsets);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await finishFixtureIo(tester, () async {
      await GStorage.setFloatingTabBar(true);
    });
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
        captureRoot(tester, key, 'build/review/motion/$name.png');
    final recorder = NavigationDiagnostics.instance;
    feed.scrollController!.jumpTo(200);
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    final baselineTop = tester.getRect(dock).top;
    final baselinePadding = tester.widget<ListView>(list).padding;
    final extent = tester.getSize(dock).height + 12;
    recorder.start();
    double progress() =>
        (recorder.environment['dockProgress'] as num).toDouble();
    Future<void> frame(String name, {double? consumed}) async {
      final actualTranslation = tester.getRect(dock).top - baselineTop;
      expect(actualTranslation, closeTo(progress() * extent, .01));
      expect(opacity(), closeTo(1 - progress(), .0001));
      expect(tester.widget<ListView>(list).padding, baselinePadding);
      debugPrint('MOTION_FRAME ${jsonEncode({
            'frame': name,
            'consumedDp': consumed,
            'progress': progress(),
            'opacity': opacity(),
            'translationY': actualTranslation
          })}');
      if (progress() > 0) {
        expect(
            tester
                .widget<IgnorePointer>(ancestor(IgnorePointer).first)
                .ignoring,
            true);
        expect(
            tester
                .widget<ExcludeSemantics>(ancestor(ExcludeSemantics).first)
                .excluding,
            true);
        expect(
            tester.widget<ExcludeFocus>(ancestor(ExcludeFocus).first).excluding,
            true);
        expect(find.byKey(const ValueKey('floating-tab-hit-我的')).hitTestable(),
            findsNothing);
      }
      await capture(name);
    }

    await frame('00-shown');
    var gesture = await tester.startGesture(tester.getCenter(list));
    await tester.pump();
    var time = 0;
    var step = 0;
    for (final movement in [-24.0, -12.0, -12.0, -12.0, 12.0]) {
      final beforeOffset = feed.scrollController!.offset;
      final beforeProgress = progress();
      time += 40;
      await gesture.moveBy(Offset(0, movement),
          timeStamp: Duration(milliseconds: time));
      await tester.pump(const Duration(milliseconds: 16));
      final consumed = feed.scrollController!.offset - beforeOffset;
      expect(progress(),
          closeTo((beforeProgress + consumed / extent).clamp(0.0, 1.0), .0001));
      if (consumed != 0) expect(progress(), greaterThan(0));
      expect(progress(), lessThan(1));
      await frame('${++step}-scroll-linked', consumed: consumed);
    }
    // A stationary pointer sample prevents this deliberate idle-settle case
    // from being confused with the separate real ballistic regression.
    await gesture.moveBy(Offset.zero,
        timeStamp: const Duration(milliseconds: 1000));
    await gesture.up(timeStamp: const Duration(milliseconds: 1016));
    await tester.pump();
    final beforeSettle = progress();
    await tester.pump(const Duration(milliseconds: 20));
    expect(progress(), lessThan(beforeSettle));
    expect(progress(), greaterThan(0));
    await frame('06-idle-settle');
    final interruptedProgress = progress();
    gesture = await tester.startGesture(tester.getCenter(list));
    await tester.pump();
    final beforeOffset = feed.scrollController!.offset;
    await gesture.moveBy(const Offset(0, -24),
        timeStamp: const Duration(milliseconds: 40));
    await tester.pump();
    final consumed = feed.scrollController!.offset - beforeOffset;
    expect(
        progress(),
        closeTo(
            (interruptedProgress + consumed / extent).clamp(0.0, 1.0), .0001));
    await frame('07-interrupted-by-drag', consumed: consumed);
    final resumedProgress = progress();
    final resumedOffset = feed.scrollController!.offset;
    await gesture.moveBy(const Offset(0, -24),
        timeStamp: const Duration(milliseconds: 80));
    await tester.pump();
    final resumedConsumed = feed.scrollController!.offset - resumedOffset;
    expect(resumedConsumed, greaterThan(0));
    expect(
        progress(), closeTo(resumedProgress + resumedConsumed / extent, .0001));
    await frame('07b-resumed-consumed-drag', consumed: resumedConsumed);
    await gesture.moveBy(Offset.zero,
        timeStamp: const Duration(milliseconds: 1000));
    await gesture.up(timeStamp: const Duration(milliseconds: 1016));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(progress(), greaterThan(0));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(
            accessibleNavigation: true, disableAnimations: true);
    await tester.pump();
    expect(opacity(), 1);
    expect(progress(), 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(progress(), 0, reason: 'No orphaned settle ticker after motion-off');
    await frame('08-motion-off-cancels-settle');
    await tester.drag(list, const Offset(0, -120));
    await tester.pump();
    expect(opacity(), 0);
    await frame('09-motion-off-instant-hidden');
    await tester.drag(list, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    await tester.pumpAndSettle();
    Future<void> startPartialSettle(Finder scrollView) async {
      final g = await tester.startGesture(tester.getCenter(scrollView));
      await tester.pump();
      await g.moveBy(const Offset(0, -24),
          timeStamp: const Duration(milliseconds: 40));
      await tester.pump();
      await g.moveBy(const Offset(0, -35),
          timeStamp: const Duration(milliseconds: 80));
      await tester.pump();
      await g.moveBy(Offset.zero,
          timeStamp: const Duration(milliseconds: 1000));
      await g.up(timeStamp: const Duration(milliseconds: 1016));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(progress(), greaterThan(0));
      expect(progress(), lessThan(1));
    }

    await startPartialSettle(list);
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pump();
    expect(dock, findsNothing);
    expect(progress(), 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(progress(), 0);
    await capture('10-keyboard-cancels-settle');
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    await startPartialSettle(list);
    tester.view.physicalSize = const Size(2670, 1200);
    await tester.pump();
    expect(progress(), 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(progress(), 0);
    expect(opacity(), 1);
    await capture('11-window-change-cancels-settle');
    tester.view.physicalSize = const Size(1200, 2670);
    await tester.pumpAndSettle();
    await startPartialSettle(list);
    await tester.tap(find.text('热门'));
    await tester.pumpAndSettle();
    expect(progress(), 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(progress(), 0);
    await tester.tap(find.text('动态'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('floating-tab-hit-我的')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1200, 1200);
    await tester.pumpAndSettle();
    final myList = find.byType(CustomScrollView).first;
    await startPartialSettle(myList);
    // A system Back action can change root while the partially departed dock
    // is correctly non-interactive. This is navigation, not scroll evidence.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(recorder.environment['selectedRoot'], 0);
    expect(progress(), 0);
    await tester.pump(const Duration(milliseconds: 500));
    expect(progress(), 0);
    await capture('12-system-back-cancels-settle');
    tester.view.physicalSize = const Size(1200, 2670);
    await tester.pumpAndSettle();
    feed.scrollController!.jumpTo(200);
    await tester.pumpAndSettle();
    await frame('20-linked-shown');
    final sequence = await tester.startGesture(tester.getCenter(list));
    await tester.pump();
    var sequenceTime = 0;
    for (var i = 0; i < 6; i++) {
      sequenceTime += 40;
      final beforePixels = feed.scrollController!.position.pixels;
      await sequence.moveBy(Offset(0, i < 2 ? -24 : -20),
          timeStamp: Duration(milliseconds: sequenceTime));
      await tester.pump(const Duration(milliseconds: 16));
      await frame('${21 + i}-linked-hide',
          consumed: feed.scrollController!.position.pixels - beforePixels);
    }
    expect(progress(), 1);
    expect(
        tester.getRect(dock).top,
        greaterThanOrEqualTo(
            tester.view.physicalSize.height / tester.view.devicePixelRatio -
                .01));
    for (var i = 0; i < 3; i++) {
      sequenceTime += 40;
      final beforePixels = feed.scrollController!.position.pixels;
      await sequence.moveBy(const Offset(0, 20),
          timeStamp: Duration(milliseconds: sequenceTime));
      await tester.pump(const Duration(milliseconds: 16));
      await frame('${27 + i}-linked-reveal',
          consumed: feed.scrollController!.position.pixels - beforePixels);
    }
    await sequence.moveBy(Offset.zero,
        timeStamp: const Duration(milliseconds: 1000));
    await sequence.up(timeStamp: const Duration(milliseconds: 1016));
    await tester.pumpAndSettle();
    expect(progress(), 0);
    await frame('30-linked-shown-again');
    feed.scrollController!.jumpTo(200);
    await tester.pumpAndSettle();
    final heldDrag = await tester.startGesture(tester.getCenter(list));
    await tester.pump();
    await heldDrag.moveBy(const Offset(0, -24),
        timeStamp: const Duration(milliseconds: 40));
    await tester.pump();
    await heldDrag.moveBy(const Offset(0, -24),
        timeStamp: const Duration(milliseconds: 80));
    await tester.pump();
    expect(progress(), greaterThan(0));
    tester.view.physicalSize = const Size(1239, 2670);
    await tester.pump();
    expect(progress(), 0);
    final heldBefore = feed.scrollController!.position.pixels;
    await heldDrag.moveBy(const Offset(0, -12),
        timeStamp: const Duration(milliseconds: 120));
    await tester.pump();
    final heldConsumed = feed.scrollController!.position.pixels - heldBefore;
    expect(heldConsumed, greaterThan(0));
    expect(progress(), closeTo(heldConsumed / extent, .0001));
    await capture('31-resized-held-drag-progress');
    await heldDrag.moveBy(Offset.zero,
        timeStamp: const Duration(milliseconds: 1000));
    await heldDrag.up(timeStamp: const Duration(milliseconds: 1016));
    await tester.pumpAndSettle();
    debugPrint(
        'HELD_DRAG_RESIZE consumedDp=$heldConsumed releasedProgress=${progress()}');
    expect(progress(), 0,
        reason:
            'A genuine continued drag after resize must regain a user session and settle on release');
    await capture('32-resized-held-drag-settled');
    tester.view.physicalSize = const Size(1200, 2670);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final file = File('build/review/motion/diagnostic-report.json');
      await file.writeAsString(recorder.report());
    });
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'reported Xiaomi window default policy hides and exposes accessible reveal',
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
      await GStorage.settings.delete('floatingNavigationPolicy');
      await GStorage.setFloatingTabBar(true);
    });
    final semantics = tester.ensureSemantics();
    SemanticsOwner semanticsOwner() => tester
        .renderObject(
            find.byKey(const ValueKey('floating-navigation-accessibility')))
        .owner!
        .semanticsOwner!;
    List<SemanticsNode> semanticNodes() {
      final result = <SemanticsNode>[];
      void visit(SemanticsNode node) {
        result.add(node);
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(semanticsOwner().rootSemanticsNode!);
      return result;
    }

    SemanticsNode semanticLabel(String label) => semanticNodes()
        .singleWhere((node) => node.getSemanticsData().label == label);
    void revealThroughAccessibility() {
      semanticsOwner().performAction(
          semanticLabel('页面导航').id,
          ui.SemanticsAction.customAction,
          CustomSemanticsAction.getIdentifier(
              const CustomSemanticsAction(label: '显示底部导航')));
    }

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
        captureRoot(tester, key, 'build/review/defaults/$name.png');
    final recorder = NavigationDiagnostics.instance;
    recorder.start();
    await tester.drag(list, const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(feed.scrollController!.offset, greaterThan(28));
    expect(opacity(), 0);
    expect(recorder.counts['root.vertical.accessible_navigation'], isNull);
    expect(recorder.environment['floatingNavigationPolicy'], 'hideOnScroll');
    expect(recorder.environment['policySuppressionReason'], isNull);
    expect(recorder.environment['rootWindowDp'], [1200 / 3.25, 2670 / 3.25]);
    await capture('00-default-accessibility-hidden');
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
    final touchOpacity = opacity();
    expect(touchOpacity, greaterThan(0));
    expect(touchOpacity, lessThan(1),
        reason:
            'Default scroll hide follows movement despite accessibility navigation');
    await capture('01-explicit-short-touch-partial');
    await gesture.up(timeStamp: const Duration(milliseconds: 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(feed.scrollController!.offset, greaterThan(28));
    expect(opacity(), lessThan(touchOpacity));
    await capture('02-explicit-ballistic-progress');
    for (var i = 0; opacity() > 0 && i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(opacity(), 0,
        reason: 'User-started ballistic movement completes the default hide');
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
    await capture('02-explicit-ballistic-hidden');
    expect(recorder.counts['root.vertical.hide_progress'], greaterThan(0));
    expect(recorder.counts['feed.FEED.pointer.move'], greaterThan(0));
    expect(recorder.counts['root.vertical.accessible_navigation'], isNull);
    expect(feed.scrollController!.position.isScrollingNotifier.value, true);
    final oldFlingOffset = feed.scrollController!.offset;
    revealThroughAccessibility();
    await tester.pump(const Duration(milliseconds: 80));
    expect(feed.scrollController!.offset, greaterThan(oldFlingOffset),
        reason: 'The old user-started ballistic tail really continued');
    expect(opacity(), 1,
        reason: 'Explicit reveal cancels inherited hide intent');
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    await tester.drag(list, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(opacity(), 0, reason: 'A new genuine gesture can hide again');
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
    await tester.pump();
    final root = tester.getSemantics(
        find.byKey(const ValueKey('floating-navigation-accessibility')));
    final data = root.getSemanticsData();
    expect(data.label, '页面导航');
    expect(data.hasFlag(ui.SemanticsFlag.isFocusable), true);
    const action = CustomSemanticsAction(label: '显示底部导航');
    expect(data.customSemanticsActionIds,
        contains(CustomSemanticsAction.getIdentifier(action)));
    expect(
        semanticNodes().where((node) => node.getSemanticsData().label == '我的'),
        isEmpty);
    expect(
        semanticNodes().any((node) =>
            node.getSemanticsData().label.contains('动态') &&
            node.getSemanticsData().hasAction(ui.SemanticsAction.tap)),
        true,
        reason: 'Feed/header semantics remain independent actionable children');
    semanticsOwner().performAction(root.id, ui.SemanticsAction.customAction,
        CustomSemanticsAction.getIdentifier(action));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    expect(find.byKey(const ValueKey('floating-tab-hit-我的')).hitTestable(),
        findsOneWidget);
    for (final label in ['主页', '关注', '我的']) {
      expect(
          semanticLabel(label)
              .getSemanticsData()
              .hasAction(ui.SemanticsAction.tap),
          true);
    }
    await capture('04-accessibility-action-revealed');
    semanticsOwner()
        .performAction(semanticLabel('我的').id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(recorder.environment['selectedRoot'], 2);
    expect(find.text('点击登录'), findsOneWidget);
    semanticsOwner()
        .performAction(semanticLabel('主页').id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(recorder.environment['selectedRoot'], 0);
    // A new genuine gesture still hides after explicit accessibility reveal.
    await tester.drag(list, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(opacity(), 0);

    semantics.dispose();

    // Legacy Auto, Hide, AlwaysVisible and unknown values never gate behavior.
    for (final oldValue in [0, 1, 2, 999]) {
      await finishFixtureIo(tester,
          () => GStorage.settings.put('floatingNavigationPolicy', oldValue));
      await tester.pumpWidget(const SizedBox());
      Get.reset();
      await tester.pumpWidget(const C001APKAPP());
      await tester.pumpAndSettle();
      final restoredFeed = Get.find<HomeFeedController>(tag: 'FEED');
      restoredFeed.isEnd = true;
      restoredFeed.loadingState.value = Success(List.generate(60,
          (i) => Datum.fromJson({...EmptyGuestAdapter.feed, 'id': 2000 + i})));
      await tester.pumpAndSettle();
      await tester.drag(list, const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(opacity(), 0,
          reason: 'Legacy value $oldValue is inert after restart');
      expect(GStorage.settings.get('floatingNavigationPolicy'), oldValue);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('floating settings expose a persistent scroll-hide toggle',
      (tester) async {
    tester.view.devicePixelRatio = 3.25;
    tester.view.physicalSize = const Size(1200, 2670);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await finishFixtureIo(tester, () => GStorage.setFloatingTabBar(false));
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: GetMaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: AppFontChoice.bundledFontFamily),
          home: const SettingsPage(),
        )));
    await tester.tap(find.text('外观与导航'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('悬浮 Tab 导航'));
    await tester.pumpAndSettle();
    expect(find.text('滚动时隐藏悬浮导航'), findsNothing);
    await tester.tap(find.text('悬浮 Tab 导航'));
    await finishFixtureIo(tester, () => GStorage.settings.flush());
    await tester.pumpAndSettle();
    expect(GStorage.floatingTabBar, true);
    expect(find.text('滚动时隐藏悬浮导航'), findsOneWidget);
    expect(GStorage.hideFloatingTabBarOnScroll, true);
    await tester.ensureVisible(find.text('滚动时隐藏悬浮导航'));
    await tester.tap(find.text('滚动时隐藏悬浮导航'));
    await finishFixtureIo(tester, () => GStorage.settings.flush());
    await tester.pumpAndSettle();
    expect(GStorage.hideFloatingTabBarOnScroll, false);
    await captureRoot(
        tester, key, 'build/review/defaults/05-single-floating-toggle.png');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 240);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('悬浮 Tab 导航'), 100,
        scrollable: find.byType(Scrollable).last, maxScrolls: 40);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await captureRoot(tester, key,
        'build/review/defaults/06-short-font2-floating-toggle.png');
    await tester.tap(find.text('悬浮 Tab 导航'));
    await finishFixtureIo(tester, () => GStorage.settings.flush());
    await tester.pumpAndSettle();
    expect(GStorage.floatingTabBar, false);
    expect(GStorage.hideFloatingTabBarOnScroll, false,
        reason: 'Disabling the dock preserves the scroll-hide preference');
    await tester.pumpWidget(const SizedBox());
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

  testWidgets(
      'held dock scrub changes real roots without reselect or hide regression',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 850);
    tester.view.padding = const FakeViewPadding(top: 32, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 24);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await finishFixtureIo(tester, () => GStorage.setFloatingTabBar(true));
    final key = GlobalKey();
    await tester
        .pumpWidget(RepaintBoundary(key: key, child: const C001APKAPP()));
    await tester.pumpAndSettle();
    final feed = Get.find<HomeFeedController>(tag: 'FEED');
    feed.isEnd = true;
    feed.loadingState.value = Success(List.generate(
        40,
        (i) => Datum.fromJson({
              ...EmptyGuestAdapter.feed,
              'id': 1000 + i,
              'message': '合成离线验证第${i + 1}条：在悬浮导航栏内左右拖动，直接选择页面。',
            })));
    await tester.pumpAndSettle();
    feed.scrollController!.jumpTo(200);
    await tester.pumpAndSettle();
    final dock = find.byType(FloatingTabBar);
    Offset target(String label) =>
        tester.getCenter(find.byKey(ValueKey('floating-tab-hit-$label')));
    int selection() => tester.widget<FloatingTabBar>(dock).selectedIndex;
    double opacity() => tester
        .widget<AnimatedOpacity>(
            find.ancestor(of: dock, matching: find.byType(AnimatedOpacity)))
        .opacity;
    Future<void> capture(String name) =>
        captureRoot(tester, key, 'build/review/tab-drag/$name.png',
            pixelRatio: 2);
    final originalRect = tester.getRect(dock);
    await capture('00-home-before');
    final scrub = await tester.startGesture(target('主页'));
    await scrub.moveBy(const Offset(23, 0));
    await tester.pumpAndSettle();
    expect(selection(), 0);
    expect(feed.scrollController!.offset, 200,
        reason: 'Dwelling inside Home is not a tap-again scroll-to-top');
    await scrub.moveTo(target('关注'));
    await tester.pumpAndSettle();
    expect(selection(), 1);
    await capture('01-held-follow');
    await scrub.moveTo(target('我的'));
    await tester.pumpAndSettle();
    expect(selection(), 2);
    await capture('02-held-my');
    await scrub.moveTo(target('关注'));
    await tester.pumpAndSettle();
    expect(selection(), 1);
    await scrub.moveTo(target('主页'));
    await tester.pumpAndSettle();
    expect(selection(), 0);
    expect(feed.scrollController!.offset, 200);
    expect(tester.getRect(dock), originalRect);
    await scrub.up();
    await tester.pumpAndSettle();
    await capture('03-reversed-home');
    expect(opacity(), 1);

    final list = find.descendant(
        of: find.byWidgetPredicate(
            (w) => w is HomeFeedPage && w.tabType == TabType.FEED),
        matching: find.byType(ListView));
    final padding = tester.widget<ListView>(list).padding;
    // A second finger may start content scrolling while the first is still
    // held on the dock. IgnorePointer alone cannot cancel that old hit path.
    final heldScrub = await tester.startGesture(target('主页'), pointer: 7);
    await heldScrub.moveBy(const Offset(23, 0));
    await tester.pump();
    final scroll =
        await tester.startGesture(tester.getCenter(list), pointer: 8);
    await scroll.moveBy(const Offset(0, -24));
    await tester.pump(const Duration(milliseconds: 16));
    await scroll.moveBy(const Offset(0, -12));
    await tester.pump(const Duration(milliseconds: 16));
    expect(opacity(), greaterThan(0));
    expect(opacity(), lessThan(1));
    expect(tester.getRect(dock).top, greaterThan(originalRect.top));
    expect(tester.widget<ListView>(list).padding, padding);
    expect(selection(), 0);
    await capture('04-progressive-scroll-hide');
    await scroll.moveBy(const Offset(0, -140));
    await scroll.up();
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    await heldScrub.moveTo(originalRect.centerRight - const Offset(30, 0));
    await heldScrub.up();
    await tester.pumpAndSettle();
    expect(selection(), 0, reason: 'A pre-hide held pointer cannot select');
    expect(opacity(), 0);
    expect(find.byKey(const ValueKey('floating-tab-hit-我的')).hitTestable(),
        findsNothing);
    final hiddenScrub = await tester
        .startGesture(originalRect.centerLeft + const Offset(30, 0));
    await hiddenScrub.moveBy(const Offset(160, 0));
    await hiddenScrub.up();
    await tester.pumpAndSettle();
    expect(selection(), 0, reason: 'Hidden dock must not receive a new scrub');
    await capture('05-hidden-no-scrub');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('standard bottom bar scrubs real roots outside safe-area padding',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 890);
    tester.view.padding =
        const FakeViewPadding(left: 18, top: 32, right: 8, bottom: 24);
    tester.view.viewPadding =
        const FakeViewPadding(left: 18, top: 32, right: 8, bottom: 24);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await finishFixtureIo(tester, () => GStorage.setFloatingTabBar(false));
    final key = GlobalKey();
    await tester
        .pumpWidget(RepaintBoundary(key: key, child: const C001APKAPP()));
    await tester.pumpAndSettle();
    final bar = find.byType(NavigationBar);
    expect(bar, findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    final rect = tester.getRect(bar);
    Offset target(int index) => tester.getCenter(find
        .descendant(of: bar, matching: find.byType(NavigationDestination))
        .at(index));
    int selection() => tester.widget<NavigationBar>(bar).selectedIndex;
    Future<void> capture(String name) =>
        captureRoot(tester, key, 'build/review/tab-drag/standard-$name.png',
            pixelRatio: 2);
    for (var i = 0; i < 3; i++) {
      expect(target(i).dx,
          closeTo(rect.left + 18 + (rect.width - 26) / 3 * (i + .5), .01));
    }
    await capture('00-home');
    final gesture = await tester.startGesture(target(0));
    for (final i in [1, 2, 1, 0]) {
      await gesture.moveTo(target(i));
      await tester.pumpAndSettle();
      expect(selection(), i);
      expect(tester.getRect(bar), rect);
      await capture(
          'held-${i == 0 ? 'home-return' : i == 1 ? 'follow' : 'my'}');
    }
    await gesture.up();
    await tester.pumpAndSettle();
    final safeAreaDrag =
        await tester.startGesture(Offset(rect.left + 40, rect.bottom - 4));
    await safeAreaDrag.moveTo(target(2));
    await safeAreaDrag.up();
    await tester.pumpAndSettle();
    expect(selection(), 0, reason: 'Bottom gesture inset is not a tab target');
    await tester.tap(find
        .descendant(of: bar, matching: find.byType(NavigationDestination))
        .at(2));
    await tester.pumpAndSettle();
    expect(selection(), 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
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
      // A configuration change reveals; subsequent programmatic positioning
      // must not count as user scroll or hide the dock during clearance checks.
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
  for (final window in [
    (
      'compact',
      const Size(320, 640),
      2.0,
      const EdgeInsets.fromLTRB(0, 24, 0, 48)
    ),
    (
      'xiaomi-observed',
      const Size(1200 / 3.25, 2670 / 3.25),
      3.25,
      const EdgeInsets.fromLTRB(0, 140 / 3.25, 0, 0)
    ),
    (
      'xiaomi-landscape',
      const Size(2670 / 3.25, 1200 / 3.25),
      3.25,
      const EdgeInsets.fromLTRB(140 / 3.25, 0, 0, 24)
    ),
  ]) {
    for (final scale in [1.0, 2.0, 2.6]) {
      testWidgets('real root My shortcut accessibility ${window.$1} $scale',
          (tester) async {
        final size = window.$2;
        final dpr = window.$3;
        final inset = window.$4;
        tester.view.devicePixelRatio = dpr;
        tester.view.physicalSize = size * dpr;
        final padding = FakeViewPadding(
          left: inset.left * dpr,
          top: inset.top * dpr,
          right: inset.right * dpr,
          bottom: inset.bottom * dpr,
        );
        tester.view.viewPadding = padding;
        tester.view.padding = padding;
        tester.view.systemGestureInsets = FakeViewPadding(
          top: window.$1 == 'xiaomi-observed' ? 179 : 0,
          bottom: inset.bottom * dpr,
        );
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetSystemGestureInsets);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        GlobalData().isLogin = false;
        await finishFixtureIo(tester, () async {
          await GStorage.setFloatingTabBar(true);
          await GStorage.setFontChoice(AppFontChoice.notoSans);
          await GStorage.settings.put(SettingsBoxKey.fontScale, 1.0);
        });
        final semantics = tester.ensureSemantics();
        try {
          final key = GlobalKey();
          await tester
              .pumpWidget(RepaintBoundary(key: key, child: const C001APKAPP()));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('floating-tab-hit-我的')));
          await tester.pumpAndSettle();
          final dock = find.byType(FloatingTabBar);
          final viewport = find.byType(CustomScrollView);
          final scroll = find
              .descendant(of: viewport, matching: find.byType(Scrollable))
              .first;
          final position = tester.state<ScrollableState>(scroll).position;
          Future<void> capture(String suffix) => captureRoot(tester, key,
              'build/review/profile-shortcuts/${window.$1}-scale-$scale-$suffix.png',
              pixelRatio: dpr);

          Future<void> expectReachable(Finder target) async {
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
            final shift =
                tester.getRect(target).bottom - (tester.getRect(dock).top - 16);
            if (shift > 0) {
              position.jumpTo(
                  (position.pixels + shift).clamp(0, position.maxScrollExtent));
              await tester.pumpAndSettle();
            }
            expect(target.hitTestable(), findsOneWidget);
            expect(tester.getRect(target).top,
                greaterThanOrEqualTo(tester.getRect(viewport).top - .01));
            expect(tester.getRect(target).bottom,
                lessThanOrEqualTo(tester.getRect(dock).top - 15.99));
            expect(tester.takeException(), isNull);
          }

          await capture('my-top');
          for (final title in messageShortcutTitles) {
            await expectReachable(messageShortcut(title));
            expectMessageShortcutLayout(tester, title);
          }
          await capture('last-shortcut');
          await settleAtEnd(tester, position);
          final lastMy = find
              .ancestor(of: find.text('私信与信息'), matching: find.byType(InkWell))
              .first;
          await expectReachable(lastMy);
          expect(tester.getRect(lastMy).height, greaterThanOrEqualTo(48));
          expect(tester.getRect(dock).bottom,
              lessThanOrEqualTo(size.height - inset.bottom));
          for (final label in ['主页', '关注', '我的']) {
            expect(
                find.byKey(ValueKey('floating-tab-hit-$label')).hitTestable(),
                findsOneWidget);
          }
          await capture('my-bottom');
          await tester.pumpWidget(const SizedBox());
        } finally {
          semantics.dispose();
        }
      });
    }
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
