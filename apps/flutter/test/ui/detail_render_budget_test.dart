import 'dart:io';

import 'package:c001apk_flutter/components/markdown_body.dart';
import 'package:c001apk_flutter/logic/reading/detail_body_snapshot.dart';
import 'package:c001apk_flutter/logic/reading/markdown_content.dart';
import 'package:c001apk_flutter/utils/app_theme.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory temporary;
  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('detail-layout-budget-');
    Hive.init(temporary.path);
    GStorage.settings = await Hive.openBox('detail-layout-settings');
    final font = FontLoader(AppFontChoice.bundledFontFamily);
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(File('assets/fonts/NotoSansCJKsc-$weight.otf')
          .readAsBytes()
          .then(ByteData.sublistView));
    }
    await font.load();
  });
  tearDown(() => Get.reset());
  tearDownAll(() async {
    await Hive.close();
    await temporary.delete(recursive: true);
  });
  Widget host(Widget child) => GetMaterialApp(
        theme: applyAppTypography(ThemeData()),
        home: Scaffold(
            body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: SingleChildScrollView(child: child))),
      );
  Future<void> settleSource(WidgetTester tester) async {
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (find.byType(SelectableText).evaluate().isNotEmpty) return;
    }
    fail('Source page did not publish');
  }

  for (final entry in <String, String>{
    'code': '```\n${List.filled(8, '${'中' * 8000}\n\n').join()}```',
    'paragraph': '中' * 2001,
    'many nodes': '# 标题\n\n${List.filled(80, '- 项').join('\n')}',
    'newlines': List.filled(80, '行').join('\n'),
    'emoji expansion': List.filled(25, '[微笑]').join(),
  }.entries) {
    testWidgets(
        'post-expansion ${entry.key} uses exact bounded source, never eager HTML',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final content = MarkdownContent.parse(entry.value);
      expect(content.source, entry.value);
      expect(content.kind, DetailTextKind.fallback);
      expect(content.notice, DetailRenderBudget.notice);
      await tester
          .pumpWidget(host(FeedText(source: entry.value, content: content)));
      await settleSource(tester);
      expect(find.byType(HtmlWidget), findsNothing);
      final displayed = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((w) => w.data!)
          .toList();
      expect(displayed, hasLength(1));
      expect(displayed.single.length, lessThanOrEqualTo(4000));
      expect(entry.value, startsWith(displayed.single));
      expect(tester.takeException(), isNull);
    });
  }

  for (final source in [
    '<p>${'中' * 2000}</p><p>${'文' * 2000}</p>',
    '```\n${'中' * 1999}\n```',
    List.filled(24, '[微笑]').join(),
  ]) {
    testWidgets(
        'maximum accepted formatted payload remains bounded ${source.length}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final content = MarkdownContent.parse(source);
      expect(content.kind, isNot(DetailTextKind.fallback));
      expect(DetailRenderBudget.reason(content.emojiHtml), isNull);
      await tester.pumpWidget(host(FeedText(source: source, content: content)));
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
        if (find.byType(RichText).evaluate().isNotEmpty &&
            !tester.binding.hasScheduledFrame) {
          break;
        }
      }
      await tester.pumpAndSettle();
      expect(find.byType(HtmlWidget), findsOneWidget);
      for (final widget
          in tester.widgetList<SelectableText>(find.byType(SelectableText))) {
        expect(widget.data!.length,
            lessThanOrEqualTo(DetailRenderBudget.maxCodeUnits));
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final invalidate in [false, true]) {
    testWidgets(
        'raw Next deferred scrolling respects owner=$invalidate in fixed layout',
        (tester) async {
      var current = true, navigations = 0;
      final scroll = ScrollController();
      final position = RawSourcePosition();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
        controller: scroll,
        child: SizedBox(
            height: 6000,
            child: Stack(children: [
              Positioned(
                  top: 1000,
                  left: 0,
                  width: 300,
                  child: RawSourceText(
                      source: '中' * 9000,
                      style: const TextStyle(fontSize: 1),
                      position: position,
                      isCurrent: () => current,
                      onPageNavigation: () => navigations++)),
            ])),
      ))));
      await settleSource(tester);
      scroll.jumpTo(1200);
      await tester.pump();
      final next =
          tester.widget<TextButton>(find.widgetWithText(TextButton, '下一段'));
      next.onPressed!();
      // Queued before page preparation can enqueue its own ensureVisible.
      if (invalidate) {
        tester.binding.addPostFrameCallback((_) => current = false);
      }
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      if (!invalidate) {
        for (var i = 0; i < 50 && scroll.offset != 1000; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
        }
      }
      expect(navigations, 1);
      expect(scroll.offset, closeTo(invalidate ? 1200 : 1000, .1));
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'retained raw Next does not mutate paging state after owner change',
      (tester) async {
    var current = true, navigations = 0;
    final position = RawSourcePosition();
    await tester.pumpWidget(host(RawSourceText(
      source: '中' * 9000,
      style: const TextStyle(fontSize: 1),
      position: position,
      isCurrent: () => current,
      onPageNavigation: () => navigations++,
    )));
    await settleSource(tester);
    final next =
        tester.widget<TextButton>(find.widgetWithText(TextButton, '下一段'));
    current = false;
    next.onPressed!();
    expect(position.index, 0);
    expect(position.offsets, [0]);
    expect(position.splitEnds, [0]);
    expect(navigations, 0);
    await tester.pumpWidget(const SizedBox());
    next.onPressed!();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'repeated and retained raw Next/Previous callbacks consume one page',
      (tester) async {
    final position = RawSourcePosition();
    var navigations = 0;
    await tester.pumpWidget(host(RawSourceText(
      source: '${'甲' * 4000}${'乙' * 4000}${'丙' * 1000}',
      style: const TextStyle(fontSize: 1),
      position: position,
      onPageNavigation: () => navigations++,
    )));
    Future<void> expectPage(String text, int index) async {
      await settleSource(tester);
      expect(tester.widget<SelectableText>(find.byType(SelectableText)).data,
          text);
      expect(position.index, index);
    }

    VoidCallback action(String label) => tester
        .widget<TextButton>(find.widgetWithText(TextButton, label))
        .onPressed!;
    await expectPage('甲' * 4000, 0);
    final firstNext = action('下一段');
    firstNext();
    firstNext();
    expect(position.index, 1);
    expect(position.offsets, [0, 4000]);
    await expectPage('乙' * 4000, 1);
    firstNext();
    expect(position.index, 1);
    final oldPrevious = action('上一段');
    action('下一段')();
    await expectPage('丙' * 1000, 2);
    oldPrevious();
    expect(position.index, 2);
    final lastPrevious = action('上一段');
    lastPrevious();
    lastPrevious();
    expect(position.index, 1);
    await expectPage('乙' * 4000, 1);
    lastPrevious();
    expect(position.index, 1);
    action('上一段')();
    await expectPage('甲' * 4000, 0);
    expect(position.offsets, [0, 4000, 8000]);
    expect(navigations, 4);
    await tester.pumpWidget(const SizedBox());
    firstNext();
    lastPrevious();
    expect(tester.takeException(), isNull);
  });
}
