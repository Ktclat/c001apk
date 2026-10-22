import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:c001apk_flutter/components/cards/carousel_card.dart';
import 'dart:ui' as ui;
import 'package:c001apk_flutter/main.dart';
import 'package:c001apk_flutter/pages/home/feed/home_feed_controller.dart';
import 'package:c001apk_flutter/logic/model/feed/datum.dart';
import 'package:c001apk_flutter/logic/state/loading_state.dart';
import 'package:c001apk_flutter/utils/app_theme.dart';
import 'package:c001apk_flutter/components/floating_tab_bar.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:c001apk_flutter/utils/global_data.dart';
import 'package:c001apk_flutter/logic/network/request.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'localization_test.dart' show EmptyGuestAdapter;

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

  tearDown(() async {
    Get.reset();
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  testWidgets(
      'production Home feed scroll ownership, fling, wheel and top reset',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 850);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.runAsync(() => GStorage.setFloatingTabBar(true));
    final key = GlobalKey();
    final horizontalDepths = <int>{};
    await tester.pumpWidget(NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.horizontal &&
            notification is ScrollUpdateNotification) {
          horizontalDepths.add(notification.depth);
        }
        return false;
      },
      child: RepaintBoundary(key: key, child: const C001APKAPP()),
    ));
    await tester.pumpAndSettle();
    final feed = Get.find<HomeFeedController>(tag: 'FEED');
    feed.isEnd = true;
    feed.loadingState.value = Success(List.generate(
        40,
        (i) => Datum.fromJson({
              ...EmptyGuestAdapter.feed,
              'id': 1000 + i,
              'message': '滚动回归验证第${i + 1}条：真实主页与动态列表，合成离线内容。',
            })));
    await tester.pumpAndSettle();
    final list = find.byWidgetPredicate(
        (w) => w is ListView && w.controller == feed.scrollController);
    double opacity() => tester
        .widget<AnimatedOpacity>(find.ancestor(
            of: find.byType(FloatingTabBar),
            matching: find.byType(AnimatedOpacity)))
        .opacity;
    final frames = <String>[];
    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final prefix =
            Platform.environment['AUTOHIDE_CAPTURE_PREFIX'] ?? 'autohide';
        final file = File('build/review/$prefix-$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes.buffer.asUint8List());
        image.dispose();
      });
      frames.add(
          '$name offset=${feed.scrollController!.offset.toStringAsFixed(2)} targetOpacity=${opacity()}');
      expect(tester.takeException(), isNull);
    }

    expect(opacity(), 1);
    await capture('00-visible');
    final motionExtent =
        tester.view.physicalSize.height / tester.view.devicePixelRatio -
            tester.getRect(find.byType(FloatingTabBar)).top;
    // Real touch events, not constructed ScrollNotifications. The first move
    // crosses touch slop; less than 28dp is consumed before release.
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
    final shortTouchOpacity = opacity();
    expect(shortTouchOpacity,
        closeTo(1 - feed.scrollController!.offset / motionExtent, .0001));
    expect(shortTouchOpacity, greaterThan(0));
    expect(shortTouchOpacity, lessThan(1));
    await capture('01-short-touch');
    await gesture.up(timeStamp: const Duration(milliseconds: 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(feed.scrollController!.offset, greaterThan(28));
    await capture('02-fling-hide-start');
    expect(opacity(), lessThan(shortTouchOpacity),
        reason:
            'Inherited ballistic touch movement must advance hide progress');
    await tester.pump(const Duration(milliseconds: 90));
    await capture('03-fling-hide-mid');
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    await capture('04-fling-hidden');
    await tester.drag(list, const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    await capture('05-upward-revealed');
    feed.scrollController!.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.sendEventToBinding(PointerScrollEvent(
        position: tester.getCenter(list), scrollDelta: const Offset(0, 120)));
    await tester.pumpAndSettle();
    expect(feed.scrollController!.offset, greaterThan(0));
    expect(opacity(), 0,
        reason: 'Real pointer scroll must hide the production dock');
    await capture('06-wheel-hidden');
    feed.scrollController!.jumpTo(0);
    await tester.pumpAndSettle();
    expect(opacity(), 1, reason: 'Returning to top must restore navigation');
    await capture('07-top-revealed');
    // A real production carousel lives inside the vertical feed and the Home
    // TabBarView. Its horizontal pages must not restore hidden navigation.
    final rows = (feed.loadingState.value as Success).response as List<Datum>;
    feed.loadingState.value = Success([
      Datum.fromJson({
        'entityType': 'card',
        'entityTemplate': 'imageCarouselCard_1',
        'entities': [
          {'url': '/feed/1001', 'pic': '', 'title': '合成轮播一'},
          {'url': '/feed/1002', 'pic': '', 'title': '合成轮播二'},
        ]
      }),
      ...rows,
    ]);
    await tester.pumpAndSettle();
    await tester.sendEventToBinding(PointerScrollEvent(
        position: tester.getCenter(list), scrollDelta: const Offset(0, 35)));
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    horizontalDepths.clear();
    await tester.drag(find.byType(CarouselCard), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(opacity(), 0,
        reason: 'An embedded PageView must not reset dock state');
    expect(horizontalDepths, contains(3),
        reason:
            'At app observer: carousel/list/Home/root viewport depth = 3; root listener sees depth 2');
    horizontalDepths.clear();
    await tester.tap(find.text('热门').first);
    await tester.pumpAndSettle();
    expect(opacity(), 1,
        reason: 'An actual Home subtab change restores navigation');
    expect(horizontalDepths, contains(1),
        reason:
            'At app observer: Home/root viewport depth = 1; root listener sees depth 0');
    final hot = Get.find<HomeFeedController>(tag: 'HOT');
    hot.isEnd = true;
    hot.loadingState.value = Success(rows);
    await tester.pumpAndSettle();
    hot.scrollController!.jumpTo(120);
    await tester.pumpAndSettle();
    expect(opacity(), 1,
        reason: 'Programmatic interior positioning is not user scrolling');
    await tester.tap(find.text('动态').first);
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(opacity(), 0);
    hot.scrollController!.jumpTo(0);
    await tester.pumpAndSettle();
    expect(opacity(), 0,
        reason: 'Inactive kept-alive Home tab cannot reveal the dock');
    feed.scrollController!
        .jumpTo(feed.scrollController!.position.maxScrollExtent - 30);
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(opacity(), 0, reason: 'Bottom bounce must not reveal navigation');
    // Top overscroll and bounce remain visible; downward content scrolling
    // hides, including with animations disabled but without TalkBack enabled.
    feed.scrollController!.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, -150));
    await tester.pump();
    expect(opacity(), 0);
    await tester.runAsync(() => File('build/review/autohide-frames.txt')
        .writeAsString(frames.join('\n')));
    await tester.pumpWidget(const SizedBox());
  });
}
