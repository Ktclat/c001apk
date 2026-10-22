import 'dart:io';
import 'package:c001apk_flutter/logic/accounts/account_store.dart';
import 'package:dio/dio.dart';
import 'dart:ui' as ui;
import 'package:c001apk_flutter/main.dart';
import 'package:c001apk_flutter/components/cards/feed_card.dart';
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

  testWidgets('actual root navigation visual and interaction review',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 850);
    tester.view.viewPadding = const FakeViewPadding(bottom: 24);
    tester.view.padding = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.runAsync(() => GStorage.setFloatingTabBar(true));
    final semantics = tester.ensureSemantics();
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      final key = GlobalKey();
      await tester
          .pumpWidget(RepaintBoundary(key: key, child: const C001APKAPP()));
      await tester.pumpAndSettle();
      final frameGeometry = <String, List<Rect>>{};
      List<int>? pressBaseline;
      Future<void> capture(String name) async {
        final bar = find.byType(FloatingTabBar);
        if (bar.evaluate().isNotEmpty) {
          for (final label in ['主页', '关注', '我的']) {
            final text = find.descendant(of: bar, matching: find.text(label));
            expect(text, findsOneWidget);
            final paragraph =
                find.descendant(of: text, matching: find.byType(RichText));
            expect(
                tester
                    .renderObject<RenderParagraph>(paragraph)
                    .didExceedMaxLines,
                isFalse);
          }
        }
        if (name.startsWith('switch-')) {
          final rects = <Rect>[tester.getRect(bar)];
          for (final label in ['主页', '关注', '我的']) {
            final hit = find.byKey(ValueKey('floating-tab-hit-$label'));
            final icon = find.descendant(of: hit, matching: find.byType(Icon));
            final text = find.descendant(of: hit, matching: find.text(label));
            expect(tester.getRect(icon).bottom,
                lessThanOrEqualTo(tester.getRect(text).top));
            expect(tester.getRect(icon).center.dx,
                closeTo(tester.getRect(text).center.dx, 0.01));
            rects.addAll([
              tester.getRect(hit),
              tester.getRect(icon),
              tester.getRect(text)
            ]);
          }
          final series = name.substring(0, name.lastIndexOf('-'));
          if (frameGeometry.containsKey(series)) {
            expect(rects, frameGeometry[series]);
          }
          frameGeometry[series] = rects;
          final selected = [
            '主页',
            '关注',
            '我的'
          ][tester.widget<FloatingTabBar>(bar).selectedIndex];
          final transform = tester
              .widget<Transform>(
                  find.byKey(ValueKey('floating-tab-indicator-$selected')))
              .transform;
          debugPrint(
              '$name jellyScaleX=${transform.storage[0]} jellyScaleY=${transform.storage[5]}');
          final painted = tester.getRect(
              find.byKey(ValueKey('floating-tab-indicator-paint-$selected')));
          expect(tester.getRect(bar).contains(painted.topLeft), isTrue);
          expect(tester.getRect(bar).contains(painted.bottomRight), isTrue);
          if (name.endsWith('-0ms') || name.endsWith('-240ms')) {
            expect(transform.storage[0], closeTo(1, 0.0001));
            expect(transform.storage[5], closeTo(1, 0.0001));
          }
        }
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          if (name.startsWith('pressed-')) {
            final raw =
                (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
            final rect = tester.getRect(find.byType(FloatingTabBar));
            final pixels = <int>[];
            for (var y = (rect.top * 2).ceil();
                y < (rect.bottom * 2).floor();
                y++) {
              for (var x = (rect.left * 2).ceil();
                  x < (rect.right * 2).floor();
                  x++) {
                for (var c = 0; c < 3; c++) {
                  pixels.add(raw.getUint8((y * image.width + x) * 4 + c));
                }
              }
            }
            if (name == 'pressed-baseline-home') {
              pressBaseline = pixels;
            } else {
              final changed = List.generate(pixels.length, (i) => i)
                  .where((i) => (pixels[i] - pressBaseline![i]).abs() > 3)
                  .length;
              expect(changed, greaterThan(60),
                  reason:
                      'Held same-tab press must visibly change dock pixels without jelly');
              debugPrint('$name changedColorChannels=$changed');
            }
          }
          if (name.startsWith('switch-')) {
            final rgba =
                (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
            final icons = find.descendant(
                of: find.byType(FloatingTabBar), matching: find.byType(Icon));
            expect(icons, findsNWidgets(3));
            final inkCounts = <int>[];
            for (var i = 0; i < 3; i++) {
              final rect = tester.getRect(icons.at(i));
              var ink = 0;
              for (var y = (rect.top * 2).ceil();
                  y < (rect.bottom * 2).floor();
                  y++) {
                for (var x = (rect.left * 2).ceil();
                    x < (rect.right * 2).floor();
                    x++) {
                  final pixel = (y * image.width + x) * 4;
                  if (rgba.getUint8(pixel) < 128 &&
                      rgba.getUint8(pixel + 1) < 128 &&
                      rgba.getUint8(pixel + 2) < 128) ink++;
                }
              }
              inkCounts.add(ink);
              expect(ink, greaterThan(40),
                  reason: '$name destination $i must actually paint its icon');
            }
            debugPrint('$name iconInkPixels=$inkCounts');
          }
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
              'build/review/${const String.fromEnvironment('REVIEW_STAGE', defaultValue: 'fixed')}/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        final transition = find.byKey(const ValueKey('root-page-transition'));
        debugPrint(
            '$name pageOffsetY=${transition.evaluate().isEmpty ? 0 : tester.widget<Transform>(transition).transform.getTranslation().y}');
        final dock = find.byType(FloatingTabBar);
        if (dock.evaluate().isNotEmpty) {
          debugPrint(
              '$name textScale=${MediaQuery.textScalerOf(tester.element(dock)).scale(1)}');
          debugPrint('$name dock=${tester.getRect(dock)}');
          final opacity =
              find.ancestor(of: dock, matching: find.byType(AnimatedOpacity));
          debugPrint(
              '$name opacity=${tester.widget<AnimatedOpacity>(opacity).opacity}');
          final focusable = FocusManager.instance.rootScope.descendants
              .where((node) =>
                  node.canRequestFocus &&
                  !node.skipTraversal &&
                  node.context
                          ?.findAncestorWidgetOfExactType<FloatingTabBar>() !=
                      null)
              .length;
          debugPrint('$name dockFocusable=$focusable');
          for (final label in ['主页', '关注', '我的']) {
            debugPrint(
                '$name target $label=${tester.getRect(find.byKey(ValueKey('floating-tab-hit-$label')))}');
          }
        }
      }

      double pageOffset() {
        final transition = find.byKey(const ValueKey('root-page-transition'));
        return transition.evaluate().isEmpty
            ? 0
            : tester.widget<Transform>(transition).transform.getTranslation().y;
      }

      void expectJellyRest() {
        final bar = find.byType(FloatingTabBar);
        final label = [
          '主页',
          '关注',
          '我的'
        ][tester.widget<FloatingTabBar>(bar).selectedIndex];
        final indicator = find.byKey(ValueKey('floating-tab-indicator-$label'));
        final matrix = tester.widget<Transform>(indicator).transform;
        expect(matrix.storage[0], 1);
        expect(matrix.storage[5], 1);
        final builder = find
            .ancestor(of: indicator, matching: find.byType(AnimatedBuilder))
            .first;
        expect(
            (tester.widget<AnimatedBuilder>(builder).animation
                    as AnimationController)
                .isAnimating,
            isFalse);
      }

      expect(pageOffset(), 0, reason: 'No startup animation');
      expectJellyRest();
      await capture('portrait-home');
      for (final label in ['我的', '主页']) {
        await tester.tap(find.byKey(ValueKey('floating-tab-hit-$label')));
        await tester.pump();
        expect(
            pageOffset(),
            const bool.fromEnvironment('EXPECT_PAGE_MOTION', defaultValue: true)
                ? 4
                : 0);
        expect(
            tester
                .widget<PageView>(find.byType(PageView).first)
                .controller!
                .page,
            ['主页', '关注', '我的'].indexOf(label));
        await capture('switch-$label-0ms');
        await tester.pump(const Duration(milliseconds: 60));
        await capture('switch-$label-60ms');
        await tester.pump(const Duration(milliseconds: 60));
        await capture('switch-$label-120ms');
        await tester.pump(const Duration(milliseconds: 60));
        await capture('switch-$label-180ms');
        await tester.pump(const Duration(milliseconds: 60));
        await capture('switch-$label-240ms');
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('floating-tab-hit-我的')));
      await tester.pump();
      for (var ms = 0; ms <= 320; ms += 20) {
        if (ms > 0) await tester.pump(const Duration(milliseconds: 20));
        await capture('switch-dense-my-${ms}ms');
      }
      await tester.tap(find.byKey(const ValueKey('floating-tab-hit-主页')));
      await tester.pumpAndSettle();
      final previousHighlight = FocusManager.instance.highlightStrategy;
      addTearDown(
          () => FocusManager.instance.highlightStrategy = previousHighlight);
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      final homeFocus = FocusManager.instance.rootScope.descendants.firstWhere(
          (node) =>
              node.context?.findAncestorWidgetOfExactType<InkWell>()?.key ==
              const ValueKey('floating-tab-hit-主页'));
      homeFocus.requestFocus();
      await tester.pumpAndSettle();
      expect(homeFocus.hasFocus, isTrue);
      await capture('keyboard-focus-home');
      homeFocus.unfocus();
      FocusManager.instance.highlightStrategy = previousHighlight;
      await tester.pumpAndSettle();
      await capture('pressed-baseline-home');
      final pressed = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('floating-tab-hit-主页'))));
      await tester.pump();
      // Resolve the tap-down deadline, then advance the ink highlight itself.
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(milliseconds: 80));
      expectJellyRest();
      await capture('pressed-home-200ms');
      await tester.pump(const Duration(milliseconds: 40));
      await capture('pressed-home-240ms');
      await pressed.up();
      await tester.pumpAndSettle();
      // Latest tap wins, without visiting the intermediate root destination.
      for (final label in ['我的', '关注', '主页']) {
        await tester.tap(find.byKey(ValueKey('floating-tab-hit-$label')));
        await tester.pump(const Duration(milliseconds: 40));
        expect(
            tester
                .widget<FloatingTabBar>(find.byType(FloatingTabBar))
                .selectedIndex,
            ['主页', '关注', '我的'].indexOf(label));
      }
      await tester.pump(const Duration(milliseconds: 240));
      // Flutter completes a simulation on the first frame after its endpoint.
      await tester.pump(const Duration(milliseconds: 16));
      expect(pageOffset(), 0);
      expectJellyRest();
      expect(
          tester.widget<PageView>(find.byType(PageView).first).controller!.page,
          0);
      await tester.tap(find.byKey(const ValueKey('floating-tab-hit-主页')));
      await tester.pump();
      expect(pageOffset(), 0, reason: 'Reselect must not replay transition');
      expectJellyRest();
      await tester.pumpAndSettle();
      // Interrupt an active transition with a rail and reduced-motion change.
      await tester.tap(find.byKey(const ValueKey('floating-tab-hit-我的')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      tester.view.physicalSize = const Size(850, 390);
      await tester.pump();
      expect(pageOffset(), 0);
      tester.view.physicalSize = const Size(390, 850);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('floating-tab-hit-主页')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await tester.pump();
      expect(pageOffset(), 0);
      expectJellyRest();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.pumpAndSettle();
      for (final label in ['关注', '我的', '主页']) {
        await tester.tap(find.byKey(ValueKey('floating-tab-hit-$label')));
        await tester.pumpAndSettle();
        await capture('portrait-$label');
      }
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();
      await capture('dark-home');
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      final feed = Get.find<HomeFeedController>(tag: 'FEED');
      feed.isEnd = true;
      feed.loadingState.value = Success(List.generate(
          25,
          (i) => Datum.fromJson({
                ...EmptyGuestAdapter.feed,
                'id': 1000 + i,
                'message': '合成动态第${i + 1}条：这里用于检查滚动、文字阅读与悬浮导航栏的遮挡。',
              })));
      await tester.pumpAndSettle();
      await capture('populated-home');
      final list = find.byWidgetPredicate(
          (w) => w is ListView && w.controller == feed.scrollController);
      final dirtyBuilds = <String, int>{};
      const watched = {
        'MainPage',
        'PageView',
        'HomePage',
        'HomeFeedPage',
        'FollowFeedPage',
        'MessagePage',
        'FeedCard',
        'FloatingTabBar'
      };
      final priorBuildHook = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        priorBuildHook?.call(element, builtOnce);
        final type = element.widget.runtimeType.toString();
        if (watched.contains(type)) {
          dirtyBuilds.update(type, (n) => n + 1, ifAbsent: () => 1);
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = priorBuildHook);
      var fetches = 0;
      final requests = InterceptorsWrapper(onRequest: (options, handler) {
        fetches++;
        handler.next(options);
      });
      Request.dio.interceptors.add(requests);
      addTearDown(() => Request.dio.interceptors.remove(requests));
      Map<String, State> rootStates() => {
            for (final type in ['HomePage', 'FollowFeedPage', 'MessagePage'])
              type: tester.state(find.byWidgetPredicate(
                  (w) => w.runtimeType.toString() == type,
                  skipOffstage: false)),
          };
      final beforeStates = rootStates();
      final beforeController = Get.find<HomeFeedController>(tag: 'FEED');
      final beforeOffset = beforeController.scrollController!.offset;
      void clearCounts() {
        dirtyBuilds.clear();
        fetches = 0;
      }

      void logCounts(String phase) => debugPrint(
          'NAV_WORK phase=$phase builds=$dirtyBuilds requests=$fetches');

      // Repeated warm switches: intentionally skip SAME selected tab, which means return-to-top.
      clearCounts();
      for (var round = 0; round < 10; round++) {
        for (final label in ['我的', '关注', '主页']) {
          await tester.tap(find.byKey(ValueKey('floating-tab-hit-$label')));
          await tester.pumpAndSettle();
        }
      }
      logCounts('30-warm-switches');
      expect(fetches, 0, reason: 'Warm root switching must not refetch');
      final afterStates = rootStates();
      for (final type in beforeStates.keys) {
        expect(identical(beforeStates[type], afterStates[type]), isTrue);
      }
      expect(
          identical(
              beforeController, Get.find<HomeFeedController>(tag: 'FEED')),
          isTrue);
      expect(beforeController.scrollController!.offset,
          closeTo(beforeOffset, 0.01));

      // Separate mount/layout work at selection from animation-only ticks.
      await tester.tap(find.byKey(const ValueKey('floating-tab-hit-我的')));
      await tester.pump();
      clearCounts();
      final contentRenderObjects = find
          .descendant(
              of: find.byType(PageView).first,
              matching: find.byWidgetPredicate((w) => w is RenderObjectWidget),
              skipOffstage: false)
          .evaluate()
          .map((e) => e.findRenderObject())
          .toSet();
      var contentPaints = 0;
      final priorPaintHook = debugOnProfilePaint;
      addTearDown(() => debugOnProfilePaint = priorPaintHook);
      debugOnProfilePaint = (object) {
        priorPaintHook?.call(object);
        if (contentRenderObjects.contains(object)) contentPaints++;
      };
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      logCounts('animation-only-320ms');
      debugPrint(
          'NAV_WORK phase=animation-only-320ms contentPaints=$contentPaints');
      expect(contentPaints, 0);
      final indicator = find.byKey(const ValueKey('floating-tab-indicator-我的'));
      final indicatorBuilder = find
          .ancestor(of: indicator, matching: find.byType(AnimatedBuilder))
          .first;
      final jellyController = tester
          .widget<AnimatedBuilder>(indicatorBuilder)
          .animation as AnimationController;
      expect(jellyController.isAnimating, isFalse);
      expect(jellyController.status, AnimationStatus.completed);
      debugPrint(
          'NAV_WORK jellyCompleted=true dockSplashFactory=${tester.widget<InkWell>(find.byKey(const ValueKey('floating-tab-hit-我的'))).splashFactory.runtimeType}');
      // Positive control: prove the same paintChild hook and subtree set work.
      final visibleText = find
          .descendant(
              of: find.byType(PageView).first, matching: find.byType(RichText))
          .first;
      tester.renderObject<RenderParagraph>(visibleText).markNeedsPaint();
      await tester.pump();
      expect(contentPaints, greaterThan(0));
      debugPrint('NAV_WORK positive-control contentPaints=$contentPaints');
      debugOnProfilePaint = priorPaintHook;
      // Material's own ripple can outlast the 240ms navigation pulse.
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      for (final type in [
        'MainPage',
        'PageView',
        'HomePage',
        'HomeFeedPage',
        'FollowFeedPage',
        'MessagePage',
        'FeedCard'
      ]) {
        expect(dirtyBuilds[type] ?? 0, 0,
            reason: '$type should not rebuild per animation tick');
      }
      expect(fetches, 0);
      // Return home to preserve existing test scenario assumptions.
      await tester.tap(find.byKey(const ValueKey('floating-tab-hit-主页')));
      await tester.pumpAndSettle();

      // Optional dock-only work isolation: dispatch ScrollUpdateNotification through actual
      // ListView element WITHOUT changing scroll position. Real drag remains separate UX test.
      clearCounts();
      ScrollUpdateNotification(
        metrics: beforeController.scrollController!.position,
        context: tester.element(list),
        scrollDelta: 40,
        dragDetails: DragUpdateDetails(
            globalPosition: Offset.zero, delta: const Offset(0, -40)),
      ).dispatch(tester.element(list));
      await tester.pumpAndSettle();
      logCounts('dock-only-hide');
      expect(dirtyBuilds['HomeFeedPage'] ?? 0, 0);
      expect(dirtyBuilds['FeedCard'] ?? 0, 0);
      expect(fetches, 0);
      ScrollUpdateNotification(
        metrics: beforeController.scrollController!.position,
        context: tester.element(list),
        scrollDelta: -40,
        dragDetails: DragUpdateDetails(
            globalPosition: Offset.zero, delta: const Offset(0, 40)),
      ).dispatch(tester.element(list));
      await tester.pumpAndSettle();
      // These counts are deterministic work-regression evidence, NOT frame-time/FPS measurements.
      // Capture 0/80/160ms independently; screenshot rasterization must not enter timing metrics.

      await tester.drag(list, const Offset(0, -300));
      await tester.pumpAndSettle();
      await capture('scrolled-down');
      final dock = find.byType(FloatingTabBar);
      double opacity() => tester
          .widget<AnimatedOpacity>(
              find.ancestor(of: dock, matching: find.byType(AnimatedOpacity)))
          .opacity;
      expect(opacity(), 0);
      final semanticsLabels = <String>[];
      void collectLabels(SemanticsNode node) {
        semanticsLabels.add(node.getSemanticsData().label);
        node.visitChildren((child) {
          collectLabels(child);
          return true;
        });
      }

      collectLabels(tester
          .binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
      expect(semanticsLabels, isNot(contains('主页')));
      expect(
          FocusManager.instance.rootScope.descendants.where((node) =>
              node.canRequestFocus &&
              !node.skipTraversal &&
              node.context?.findAncestorWidgetOfExactType<FloatingTabBar>() !=
                  null),
          isEmpty);
      final hiddenRenderObjects = find
          .descendant(
              of: dock,
              matching: find.byWidgetPredicate((w) => w is RenderObjectWidget))
          .evaluate()
          .map((e) => e.findRenderObject())
          .toSet();
      expect(
          tester
              .hitTestOnBinding(const Offset(195, 780))
              .path
              .any((entry) => hiddenRenderObjects.contains(entry.target)),
          isFalse);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      tester.view.padding = FakeViewPadding.zero;
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await capture('hidden-keyboard-open');
      tester.view.viewInsets = FakeViewPadding.zero;
      tester.view.padding = const FakeViewPadding(bottom: 24);
      await tester.pumpAndSettle();
      await capture('hidden-keyboard-closed');
      expect(opacity(), 1);
      await tester.drag(list, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(opacity(), 0);
      await tester.tap(find.text('热门').first);
      await tester.pumpAndSettle();
      await capture('hidden-home-subtab');
      expect(opacity(), 1);
      await tester.tap(find.text('动态').first);
      await tester.pumpAndSettle();
      await tester.drag(list, const Offset(0, 180));
      await tester.pumpAndSettle();
      await capture('scrolled-up');
      expect(opacity(), 1);
      feed.scrollController!
          .jumpTo(feed.scrollController!.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await capture('final-item-clearance');
      final lastCard =
          find.byWidgetPredicate((w) => w is FeedCard && w.data.id == 1024);
      expect(lastCard, findsOneWidget);
      expect(
          tester.getRect(lastCard).bottom, lessThan(tester.getRect(dock).top));
      feed.scrollController!.jumpTo(100);
      await tester.pumpAndSettle();
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(
              accessibleNavigation: true, disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpAndSettle();
      await tester.drag(list, const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      expect(
          tester
              .widget<AnimatedSlide>(
                  find.ancestor(of: dock, matching: find.byType(AnimatedSlide)))
              .duration,
          Duration.zero);
      await capture('accessible-navigation');
      for (final label in ['我的', '主页']) {
        await tester.tap(find.byKey(ValueKey('floating-tab-hit-$label')));
        await tester.pump();
        expect(pageOffset(), 0);
        final matrix = tester
            .widget<Transform>(
                find.byKey(ValueKey('floating-tab-indicator-$label')))
            .transform;
        expect(matrix.storage[0], 1);
        expect(matrix.storage[5], 1);
      }
      await tester.pumpAndSettle();
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await tester.pumpAndSettle();
      await tester.drag(list, const Offset(0, -100));
      await tester.pump();
      expect(opacity(), 0);
      await tester.drag(list, const Offset(0, 100));
      await tester.pump();
      expect(opacity(), 1);
      await capture('reduced-motion');
      for (final features in [
        const FakeAccessibilityFeatures(disableAnimations: true),
        const FakeAccessibilityFeatures(accessibleNavigation: true)
      ]) {
        tester.platformDispatcher.accessibilityFeaturesTestValue = features;
        await tester.pumpAndSettle();
        for (final label in ['我的', '主页']) {
          await tester.tap(find.byKey(ValueKey('floating-tab-hit-$label')));
          await tester.pump();
          expect(pageOffset(), 0);
          expectJellyRest();
        }
        await tester.pumpAndSettle();
      }
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      tester.view.physicalSize = const Size(320, 780);
      for (final scale in [1.3, 1.5, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpAndSettle();
        await capture('narrow-text-$scale');
        expect(find.descendant(of: dock, matching: find.text('主页')),
            findsOneWidget);
        for (final label in ['主页', '关注', '我的']) {
          final rect =
              tester.getRect(find.byKey(ValueKey('floating-tab-hit-$label')));
          expect(rect.width, greaterThanOrEqualTo(48));
          expect(rect.height, greaterThanOrEqualTo(48));
        }
      }
      await tester
          .runAsync(() => GStorage.settings.put(SettingsBoxKey.fontScale, 1.3));
      await tester.pumpAndSettle();
      await capture('combined-text-2.6');
      expect(MediaQuery.textScalerOf(tester.element(dock)).scale(1),
          closeTo(2.6, 0.001));
      expect(
          find.descendant(of: dock, matching: find.text('主页')), findsOneWidget);
      await tester
          .runAsync(() => GStorage.settings.put(SettingsBoxKey.fontScale, 1.0));
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      tester.view.physicalSize = const Size(850, 390);
      tester.view.viewPadding =
          const FakeViewPadding(left: 32, right: 24, bottom: 24);
      tester.view.padding =
          const FakeViewPadding(left: 32, right: 24, bottom: 24);
      await tester.pumpAndSettle();
      await capture('landscape-safe-insets');
      expect(find.byType(NavigationRail), findsNothing);
      expect(dock, findsOneWidget);
      await tester.drag(list, const Offset(0, -100));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(600, 850);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsNothing);
      expect(dock, findsOneWidget);
      await capture('portrait-600-overlay');
      // Returning to content top restores a hidden dock after resizing.
      final scrollable = tester.state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first);
      scrollable.position.jumpTo(0);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(390, 850);
      tester.view.padding = const FakeViewPadding(bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(bottom: 24);
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      await capture('wide-return-portrait');
      await tester.pumpWidget(const SizedBox.shrink());
      Get.reset();
      GlobalData().isLogin = true;
      await tester
          .pumpWidget(RepaintBoundary(key: key, child: const C001APKAPP()));
      await tester.pumpAndSettle();
      final fab = find.byType(FloatingActionButton);
      expect(fab, findsOneWidget);
      expect(tester.getRect(fab).bottom, lessThan(tester.getRect(dock).top));
      await capture('synthetic-login-fab-clearance');
      await tester.tap(find.byKey(const ValueKey('floating-tab-hit-我的')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      AccountStore.changes.value++;
      await tester.pumpAndSettle();
      expect(pageOffset(), 0,
          reason: 'Account reset cancels an active transition');
      expect(tester.widget<FloatingTabBar>(dock).selectedIndex, 2);
      GlobalData().isLogin = false;
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDisableShadows = previousShadows;
      semantics.dispose();
    }
  });
  testWidgets('English long-label component fixture retains accessible text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 780);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final semantics = tester.ensureSemantics();
    final priorShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      final key = GlobalKey();
      for (final scale in [1.0, 1.3, 2.0, 2.6]) {
        await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: ThemeData(
                  useMaterial3: true,
                  fontFamily: AppFontChoice.bundledFontFamily),
              home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: Builder(
                        builder: (context) => Center(
                                child: FloatingTabBar(
                              destinations: const [
                                NavigationDestination(
                                    icon: Icon(Icons.home_outlined),
                                    label: 'Home'),
                                NavigationDestination(
                                    icon: Icon(Icons.feed_outlined),
                                    label: 'Following'),
                                NavigationDestination(
                                    icon: Icon(Icons.person_outline),
                                    label: 'Profile'),
                              ],
                              selectedIndex: 0,
                              onDestinationSelected: (_) {},
                              height: FloatingTabBar.heightFor(context),
                            ))),
                  )),
            )));
        await tester.pumpAndSettle();
        for (final label in ['Home', 'Following', 'Profile']) {
          final hit = find.byKey(ValueKey('floating-tab-hit-$label'));
          expect(tester.getSize(hit).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(hit).height, greaterThanOrEqualTo(48));
          final icon = find.descendant(of: hit, matching: find.byType(Icon));
          final text = find.descendant(of: hit, matching: find.text(label));
          expect(text, findsOneWidget);
          expect(tester.getRect(icon).bottom,
              lessThanOrEqualTo(tester.getRect(text).top));
          expect(tester.widget<Text>(text).overflow, TextOverflow.ellipsis);
          expect(find.byTooltip(label), findsOneWidget);
          expect(find.bySemanticsLabel(label), findsOneWidget);
        }
        final paragraph = find.descendant(
            of: find.text('Following'), matching: find.byType(RichText));
        debugPrint(
            'English fixture scale=$scale FollowingEllipsized=${tester.renderObject<RenderParagraph>(paragraph).didExceedMaxLines}');
        if (scale >= 2) {
          expect(
              tester.renderObject<RenderParagraph>(paragraph).didExceedMaxLines,
              isTrue);
        }
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
              'build/review/${const String.fromEnvironment('REVIEW_STAGE', defaultValue: 'fixed')}/english-component-$scale.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
      }
    } finally {
      debugDisableShadows = priorShadows;
      semantics.dispose();
    }
  });
}
