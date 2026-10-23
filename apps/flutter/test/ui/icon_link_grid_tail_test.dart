import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:c001apk_flutter/components/item_card.dart';
import 'package:c001apk_flutter/components/cards/icon_link_grid_card.dart';
import 'package:c001apk_flutter/logic/model/feed/datum.dart';
import 'package:c001apk_flutter/utils/app_theme.dart';
import 'package:expandable_page_view/expandable_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

const fixtureRoot = 'test/fixtures/icon_grid';
final evidenceRoot = Platform.environment['ICON_GRID_EVIDENCE'];
const before = bool.fromEnvironment('BEFORE');
final captureKey = GlobalKey();
Datum fixture(int count) => Datum.fromJson(count == 0
    ? {
        'entityType': 'card',
        'entityTemplate': 'iconLinkGridCard',
        'entities': []
      }
    : jsonDecode(File('$fixtureRoot/count-$count.json').readAsStringSync()));
Widget harness(int count, double scale, {Datum? card}) => GetMaterialApp(
      theme: applyAppTypography(ThemeData(
          useMaterial3: true,
          colorScheme:
              ColorScheme.fromSeed(seedColor: const Color(0xFF6650A4)))),
      getPages: [
        GetPage(
            name: '/t/:tag',
            page: () =>
                Scaffold(body: Text('destination:${Get.parameters['tag']}')))
      ],
      home: RepaintBoundary(
          key: captureKey,
          child: Builder(
              builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    appBar: AppBar(title: const Text('首页'), actions: [
                      IconButton(
                          onPressed: () {}, icon: const Icon(Icons.search))
                    ]),
                    body: ListView(padding: const EdgeInsets.all(8), children: [
                      const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('推荐    关注    热门')),
                      itemCard(card ?? fixture(count), isHomeCard: true),
                      const SizedBox(height: 12),
                      const Card(
                          child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('离线合成动态\n仅用于组件布局对照，不代表线上内容。'))),
                    ]),
                    bottomNavigationBar:
                        NavigationBar(selectedIndex: 0, destinations: const [
                      NavigationDestination(
                          icon: Icon(Icons.home_outlined), label: '首页'),
                      NavigationDestination(
                          icon: Icon(Icons.apps), label: '应用'),
                      NavigationDestination(
                          icon: Icon(Icons.person_outline), label: '我的')
                    ]),
                  )))),
    );
Future<void> capture(WidgetTester tester, String name) async {
  for (final image
      in find.byType(CachedNetworkImage).hitTestable().evaluate()) {
    final raw = tester.widget<RawImage>(find.descendant(
        of: find.byWidget(image.widget), matching: find.byType(RawImage)));
    expect(raw.image, isNotNull,
        reason: 'No placeholders in accepted captures');
    expect(raw.image!.width, 90);
    expect(raw.image!.height, 90);
  }
  if (evidenceRoot == null) return;
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$evidenceRoot/${before ? 'before' : 'after'}/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> warm(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (var i = 1; i <= 10; i++) {
      final bytes = await File('$fixtureRoot/icon-$i.png').readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      PaintingBinding.instance.imageCache.putIfAbsent(
          CachedNetworkImageProvider('https://fixture.invalid/icon-$i.png'),
          () => OneFrameImageStreamCompleter(
              Future.value(ImageInfo(image: frame.image))));
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('icon-grid-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => temp.path);
    final loader = FontLoader(AppFontChoice.bundledFontFamily);
    for (final name in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(File('assets/fonts/NotoSansCJKsc-$name.otf')
          .readAsBytes()
          .then(ByteData.sublistView));
    }
    await loader.load();
    var flutterRoot = Platform.environment['FLUTTER_ROOT'];
    const sdkMarker = '/bin/cache/dart-sdk/bin/';
    final sdkIndex = Platform.resolvedExecutable.indexOf(sdkMarker);
    if (flutterRoot == null && sdkIndex >= 0) {
      flutterRoot = Platform.resolvedExecutable.substring(0, sdkIndex);
    }
    expect(flutterRoot, isNotNull);
    final icons = FontLoader('MaterialIcons')
      ..addFont(File(
              '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then(ByteData.sublistView));
    await icons.load();
  });
  tearDown(() => Get.reset());
  tearDownAll(() async {
    await temp.delete(recursive: true);
  });
  for (final count in [0, 1, 4, 5, 6, 10]) {
    testWidgets('production component count $count', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await warm(tester);
      await tester.pumpWidget(harness(count, 1));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pumpAndSettle();
      await capture(tester, 'count-$count-page-1');
      if (!before && count == 0) {
        expect(find.byType(ExpandablePageView), findsNothing);
        expect(tester.takeException(), isNull);
        return;
      }
      final pager =
          tester.widget<ExpandablePageView>(find.byType(ExpandablePageView));
      expect(pager.itemCount, before ? count ~/ 5 : (count + 4) ~/ 5);
      final pages = before ? count ~/ 5 : (count + 4) ~/ 5;
      for (var p = 0; p < pages; p++) {
        pager.controller!.jumpToPage(p);
        await tester.pumpAndSettle();
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pumpAndSettle();
        await capture(tester, 'count-$count-page-${p + 1}');
        for (var i = p * 5; i < (p + 1) * 5 && i < count; i++) {
          final title = fixture(count).entities![i].title!;
          expect(find.text(title).hitTestable(), findsOneWidget);
          final tile = find.ancestor(
              of: find.text(title), matching: find.byType(InkWell));
          final decoded = tester.widget<RawImage>(
              find.descendant(of: tile, matching: find.byType(RawImage)));
          expect(decoded.image, isNotNull);
          expect(decoded.image!.width, 90);
          expect(tester.getSize(tile).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('tail item must be reachable regression', (tester) async {
    await warm(tester);
    await tester.pumpWidget(harness(6, 1));
    await tester.pumpAndSettle();
    final pager =
        tester.widget<ExpandablePageView>(find.byType(ExpandablePageView));
    expect(pager.itemCount, 2);
    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('入口六').hitTestable(), findsOneWidget);
    await tester.tap(find.text('入口六'));
    await tester.pumpAndSettle();
    expect(find.text('destination:入口六'), findsOneWidget);
  });
  for (final spec in [
    (240.0, 640.0, 2.0),
    (320.0, 640.0, 1.6),
    (800.0, 360.0, 1.6)
  ]) {
    testWidgets('responsive ${spec.$1} scale ${spec.$3}', (tester) async {
      tester.view.physicalSize = Size(spec.$1, spec.$2);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await warm(tester);
      await tester.pumpWidget(harness(10, spec.$3));
      await tester.pumpAndSettle();
      await capture(tester, 'width-${spec.$1.toInt()}-scale-${spec.$3}');
      if (!before) {
        for (final tile in tester.widgetList<InkWell>(find.descendant(
            of: find.byType(IconLinkGridCard),
            matching: find.byType(InkWell)))) {
          final size = tester.getSize(find.byWidget(tile));
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
  if (!before) {
    testWidgets('live data shrinks grows and replaces without stale page',
        (tester) async {
      var data = fixture(10);
      late StateSetter update;
      await warm(tester);
      await tester.pumpWidget(MaterialApp(
          theme: applyAppTypography(ThemeData()),
          home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
            update = setState;
            return IconLinkGridCard(dataList: data.entities!);
          }))));
      await tester.pumpAndSettle();
      var pager =
          tester.widget<ExpandablePageView>(find.byType(ExpandablePageView));
      pager.controller!.jumpToPage(1);
      await tester.pumpAndSettle();
      expect(find.text('入口十').hitTestable(), findsOneWidget);
      update(() {
        data = fixture(10);
        data.entities![9].title = '替换十';
      });
      await tester.pumpAndSettle();
      expect(find.text('替换十').hitTestable(), findsOneWidget);
      update(() {
        data = fixture(10);
        data.entities!.addAll(fixture(5).entities!);
      });
      await tester.pumpAndSettle();
      pager =
          tester.widget<ExpandablePageView>(find.byType(ExpandablePageView));
      expect(pager.itemCount, 3);
      expect(pager.controller!.page, 1);
      expect(find.text('入口十').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      update(() => data = fixture(6));
      await tester.pumpAndSettle();
      pager =
          tester.widget<ExpandablePageView>(find.byType(ExpandablePageView));
      expect(pager.itemCount, 2);
      expect(pager.controller!.page, 1);
      expect(find.text('入口六').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      update(() => data = fixture(1));
      await tester.pumpAndSettle();
      expect(find.text('入口一').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      update(() => data = fixture(10));
      await tester.pumpAndSettle();
      pager =
          tester.widget<ExpandablePageView>(find.byType(ExpandablePageView));
      pager.controller!.jumpToPage(1);
      await tester.pumpAndSettle();
      update(() => data = fixture(0));
      await tester.pumpAndSettle();
      expect(find.byType(ExpandablePageView), findsNothing);
      expect(tester.takeException(), isNull);
      update(() => data = fixture(6));
      await tester.pumpAndSettle();
      pager =
          tester.widget<ExpandablePageView>(find.byType(ExpandablePageView));
      pager.controller!.jumpToPage(1);
      await tester.pumpAndSettle();
      expect(find.text('入口六').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    for (final spec in [(80, '😀'), (81, '😀'), (12000, '长'), (100000, '长')]) {
      testWidgets('bounded title ${spec.$1} code points at 240dp 2x',
          (tester) async {
        tester.view.physicalSize = const Size(240, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final data = fixture(1);
        final original = spec.$2 * spec.$1;
        data.entities!.single.title = original;
        await warm(tester);
        await tester.pumpWidget(harness(1, 2, card: data));
        await tester.pumpAndSettle();
        final textFinder = find.descendant(
            of: find.byType(IconLinkGridCard), matching: find.byType(Text));
        final text = tester.widget<Text>(textFinder);
        final capped = spec.$2 * 80;
        expect(text.data, spec.$1 > 80 ? '$capped…' : capped);
        expect(text.data!.runes.length, spec.$1 > 80 ? 81 : 80);
        expect(text.maxLines, 2);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(text.semanticsLabel, spec.$1 > 80 ? '$capped，标题过长，已缩略' : capped);
        expect(text.data!.contains('�'), isFalse);
        final target =
            find.ancestor(of: textFinder, matching: find.byType(InkWell));
        expect(tester.getSize(target).height, inInclusiveRange(48, 120));
        expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
        expect(
            find
                .byType(Tooltip)
                .evaluate()
                .any((e) => (e.widget as Tooltip).message == original),
            isFalse);
        await capture(tester, 'title-${spec.$1}-width-240-scale-2');
        await tester.tap(textFinder);
        await tester.pumpAndSettle();
        expect(find.text('destination:入口一'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('narrow Home scroll reaches page two last item and opens it',
        (tester) async {
      tester.view.physicalSize = const Size(240, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await warm(tester);
      await tester.pumpWidget(harness(10, 2));
      await tester.pumpAndSettle();
      expect(find.text('入口一').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('入口五'));
      await tester.pumpAndSettle();
      expect(find.text('入口五').hitTestable(), findsOneWidget);
      final nextPage = find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == '第 2 页，共 2 页');
      await tester.ensureVisible(nextPage);
      await tester.pumpAndSettle();
      expect(nextPage.hitTestable(), findsOneWidget);
      await tester.tap(nextPage);
      await tester.pumpAndSettle();
      expect(tester.widget<Semantics>(nextPage).properties.selected, isTrue);
      await tester.ensureVisible(find.text('入口十'));
      await tester.pumpAndSettle();
      expect(find.text('入口十').hitTestable(), findsOneWidget);
      await capture(tester, 'width-240-scale-2-page-2-last-reachable');
      await tester.tap(find.text('入口十'));
      await tester.pumpAndSettle();
      expect(find.text('destination:入口十'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('many-page indicators remain bounded and 48dp tappable',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final entries = List.generate(100, (i) => fixture(10).entities![i % 10]);
      await warm(tester);
      await tester.pumpWidget(MaterialApp(
          theme: applyAppTypography(ThemeData()),
          home: Scaffold(body: IconLinkGridCard(dataList: entries))));
      await tester.pumpAndSettle();
      for (final semantic in tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((w) => w.properties.label?.startsWith('第 ') ?? false)) {
        final ink = find.descendant(
            of: find.byWidget(semantic), matching: find.byType(InkWell));
        expect(tester.getSize(ink), const Size(48, 48));
      }
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(-1200, 0));
      await tester.pumpAndSettle();
      final last = find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == '第 20 页，共 20 页');
      expect(last.hitTestable(), findsOneWidget);
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(tester.widget<Semantics>(last).properties.selected, isTrue);
      expect(tester.takeException(), isNull);
    });
    testWidgets('every original topic destination is preserved',
        (tester) async {
      await warm(tester);
      await tester.pumpWidget(harness(10, 1));
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        final pager =
            tester.widget<ExpandablePageView>(find.byType(ExpandablePageView));
        pager.controller!.jumpToPage(i ~/ 5);
        await tester.pumpAndSettle();
        final title = fixture(10).entities![i].title!;
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(find.text('destination:$title'), findsOneWidget);
        Get.back<void>();
        await tester.pumpAndSettle();
      }
    });
  }
}
