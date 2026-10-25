import 'dart:io';
import 'dart:ui' as ui;

import 'package:c001apk_flutter/components/cards/message_second_card.dart';
import 'package:c001apk_flutter/pages/ffflist/ffflist_page.dart';
import 'package:c001apk_flutter/pages/history/history_page.dart';
import 'package:c001apk_flutter/utils/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'message_shortcuts_test_support.dart';

Widget shortcutHarness({
  required double scale,
  bool isLogin = false,
  double? cardWidth,
}) =>
    GetMaterialApp(
      theme: applyAppTypography(ThemeData(useMaterial3: true)),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      getPages: [
        for (final route in ['/history', '/ffflist'])
          GetPage(
            name: route,
            page: () => Scaffold(body: Text('destination:$route')),
          ),
      ],
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(10),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: cardWidth,
              child: Builder(
                builder: (context) => messageSeconfCard(isLogin, context),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader(AppFontChoice.bundledFontFamily);
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      final font = File('assets/fonts/NotoSansCJKsc-$weight.otf');
      expect(font.existsSync(), isTrue,
          reason: 'Run bash tools/fetch_fonts.sh before font/layout tests');
      loader.addFont(
          font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  tearDown(Get.reset);

  for (final size in [
    const Size(320, 640),
    const Size(1200 / 3.25, 2670 / 3.25),
    const Size(2670 / 3.25, 1200 / 3.25),
  ]) {
    for (final scale in [1.0, 2.0, 2.6]) {
      testWidgets('shortcut labels and targets fit $size at $scale',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(shortcutHarness(scale: scale));
          await tester.pumpAndSettle();
          for (final title in messageShortcutTitles) {
            await tester.ensureVisible(messageShortcut(title));
            await tester.pumpAndSettle();
            expect(messageShortcut(title).hitTestable(), findsOneWidget);
            expectMessageShortcutLayout(tester, title);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        } finally {
          semantics.dispose();
        }
      });
    }
  }

  testWidgets('columns respond to card width rather than window width',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(890, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final semantics = tester.ensureSemantics();
    try {
      for (final config in [(300.0, 3), (200.0, 2), (140.0, 1)]) {
        await tester
            .pumpWidget(shortcutHarness(scale: 2.6, cardWidth: config.$1));
        await tester.pumpAndSettle();
        final firstTop =
            tester.getTopLeft(messageShortcut(messageShortcutTitles.first)).dy;
        final firstRow = messageShortcutTitles.where((title) =>
            (tester.getTopLeft(messageShortcut(title)).dy - firstTop).abs() <
            .01);
        expect(firstRow.length, config.$2);
        for (final title in messageShortcutTitles) {
          await tester.ensureVisible(messageShortcut(title));
          await tester.pumpAndSettle();
          expectMessageShortcutLayout(tester, title);
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    } finally {
      semantics.dispose();
    }
  });

  for (final isLogin in [false, true]) {
    testWidgets('shortcut routes and account guards stay intact: $isLogin',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final semantics = tester.ensureSemantics();
      try {
        final expectedTypes = [
          HistoryType.Favorite,
          HistoryType.History,
          FFFListType.RECENT,
          FFFListType.COLLECTION,
          FFFListType.LIKE,
          FFFListType.REPLY,
        ];
        await tester.pumpWidget(shortcutHarness(scale: 2.6, isLogin: isLogin));
        await tester.pumpAndSettle();
        for (var i = 0; i < messageShortcutTitles.length; i++) {
          for (final useSemantics in [false, true]) {
            final title = messageShortcutTitles[i];
            final target = messageShortcut(title);
            if (useSemantics) {
              final node = tester
                  .getSemantics(find.bySemanticsLabel(RegExp('^$title\$')));
              tester
                  .renderObject(target)
                  .owner!
                  .semanticsOwner!
                  .performAction(node.id, ui.SemanticsAction.tap);
            } else {
              await tester.tap(target);
            }
            await tester.pumpAndSettle();
            if (isLogin || i < 2) {
              final route = i < 2 ? '/history' : '/ffflist';
              expect(find.text('destination:$route'), findsOneWidget);
              expect(Get.currentRoute, route);
              expect(Get.arguments, {'type': expectedTypes[i]});
              Get.back<void>();
              await tester.pumpAndSettle();
            } else {
              expect(Get.currentRoute, '/');
              expect(find.textContaining('destination:'), findsNothing);
            }
          }
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        semantics.dispose();
      }
    });
  }
}
