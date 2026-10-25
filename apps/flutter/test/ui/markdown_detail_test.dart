import 'dart:io';

import 'package:c001apk_flutter/components/html_text.dart';
import 'package:c001apk_flutter/components/markdown_body.dart';
import 'package:c001apk_flutter/logic/reading/markdown_content.dart';
import 'package:c001apk_flutter/utils/app_theme.dart';
import 'package:c001apk_flutter/utils/reading_preset.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory temporary;
  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('markdown-detail-');
    Hive.init(temporary.path);
    GStorage.settings = await Hive.openBox('markdown-settings');
  });
  setUp(() async {
    await GStorage.settings.clear();
  });
  tearDown(() => Get.reset());
  tearDownAll(() async {
    await Hive.close();
    await temporary.delete(recursive: true);
  });

  Widget host(Widget child, {bool dark = false, double scale = 1}) =>
      GetMaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            ),
          ),
        ),
      );

  Future<void> awaitHtml(WidgetTester tester, String visible) async {
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (find
          .textContaining(visible, findRichText: true)
          .evaluate()
          .isNotEmpty) {
        return;
      }
    }
    fail('Bounded asynchronous HTML renderer did not publish: $visible');
  }

  for (final font in AppFontChoice.values) {
    for (final reading in ReadingPreset.values) {
      for (final dark in [false, true]) {
        testWidgets('detail inherits $font/$reading dark=$dark at 2x', (
          tester,
        ) async {
          // Hive persistence uses real I/O. Do not await it in the widget
          // test's fake-clock zone without pumping the scheduler.
          await tester.runAsync(() async {
            await GStorage.settings.put(SettingsBoxKey.fontChoice, font.index);
            await GStorage.settings
                .put(SettingsBoxKey.readingPreset, reading.index);
          });
          const source = '# 中文标题\n\n**重点** 与普通正文 👩🏽‍💻\n\n'
              '> 引用\n\n```\nlong_code_abcdefghijklmnopqrstuvwxyz_123456789\n```';
          final content = MarkdownContent.parse(source);
          await tester.pumpWidget(
            host(
              FeedText(
                source: source,
                content: content,
                role: HtmlTextRole.articleBody,
              ),
              dark: dark,
              scale: 2,
            ),
          );
          await awaitHtml(tester, '中文标题');
          await tester.pumpAndSettle();
          final html = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
          expect(
            html.textStyle!.fontFamily,
            font.familyForPlatform(defaultTargetPlatform),
          );
          expect(html.textStyle!.fontSize, reading.articleBodySize);
          expect(html.textStyle!.height, reading.bodyHeight);
          expect(html.textStyle!.locale, const Locale('zh', 'CN'));
          expect(html.textStyle!.fontWeight, FontWeight.w400);
          final code = tester
              .widgetList<SelectableText>(find.byType(SelectableText))
              .firstWhere(
                  (text) => text.data?.startsWith('long_code_') ?? false);
          expect(code.style!.fontFamily, 'monospace');
          if (html.textStyle!.fontFamily != null) {
            expect(code.style!.fontFamilyFallback,
                contains(html.textStyle!.fontFamily));
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('task state is readable and semantic without OS checkbox glyphs',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      const source = '# 任务\n\n- [x] 已完成\n- [ ] 待完成';
      await tester.pumpWidget(
        host(FeedText(source: source, content: MarkdownContent.parse(source))),
      );
      await awaitHtml(tester, '[x] 已完成');
      await tester.pumpAndSettle();
      expect(find.textContaining('[x] 已完成', findRichText: true), findsWidgets);
      expect(find.textContaining('[ ] 待完成', findRichText: true), findsWidgets);
      expect(find.bySemanticsLabel(RegExp(r'\[x\].*已完成')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp(r'\[ \].*待完成')), findsWidgets);
      expect(tester.takeException(), isNull);
    } finally {
      // Flutter verifies handles before package:test addTearDown callbacks.
      semantics.dispose();
    }
  });

  testWidgets('raw source is exact/selectable and never HTML or an image', (
    tester,
  ) async {
    const source = '# 标题\r\n<script>unsafe</script> 👩🏽‍💻 &amp; <!--break-->';
    await tester.pumpWidget(
      host(
        FeedText(
          source: source,
          content: MarkdownContent.parse(source),
          forcePlain: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      source,
    );
    expect(find.byType(HtmlWidget), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets(
    'fallback notice never silently labels unsupported content formatted',
    (tester) async {
      const source = '| a | b |\n| --- | --- |\n| 1 | 2 |';
      await tester.pumpWidget(
        host(FeedText(source: source, content: MarkdownContent.parse(source))),
      );
      await tester.pumpAndSettle();
      expect(find.text('表格暂不支持排版，已保留完整原文'), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        source,
      );
    },
  );

  testWidgets('Markdown and HTML images cannot create network image widgets', (
    tester,
  ) async {
    const source = '![测试](https://image.coolapk.com/synthetic.jpg)';
    await tester.pumpWidget(
      host(FeedText(source: source, content: MarkdownContent.parse(source))),
    );
    await awaitHtml(tester, '图片未加载');
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('图片未加载', findRichText: true), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'approved link uses existing feed route without launching media',
    (tester) async {
      const source = '[打开动态](/feed/123)';
      await tester.pumpWidget(
        GetMaterialApp(
          getPages: [
            GetPage(
              name: '/feed/:id',
              page: () => const Scaffold(body: Text('目标动态')),
            ),
          ],
          home: Scaffold(
            body: FeedText(
              source: source,
              content: MarkdownContent.parse(source),
            ),
          ),
        ),
      );
      await awaitHtml(tester, '打开动态');
      await tester.pumpAndSettle();
      final html = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
      expect(await html.onTapUrl!('/feed/123'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('目标动态'), findsOneWidget);
    },
  );
  testWidgets(
    'pathological raw grapheme never creates an oversized paragraph',
    (tester) async {
      final source = 'a${'\u0301' * 10000}';
      await tester.pumpWidget(
        host(
          RawSourceText(source: source, style: const TextStyle(fontSize: 15)),
        ),
      );
      for (var i = 0;
          i < 100 && find.byType(SelectableText).evaluate().isEmpty;
          i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      final text =
          tester.widget<SelectableText>(find.byType(SelectableText)).data!;
      expect(text.length, lessThanOrEqualTo(4000));
      expect(find.text('单个字形过长，暂按编码片段显示；原文内容未修改'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final source in [
    '# 新 Markdown\n\n<img src="https://evil.test/x"\n>',
    '<img src="https://evil.test/x"',
    '<a href="javascript:alert(1)"\n>click</a>',
  ]) {
    testWidgets(
        'mixed Markdown, malformed HTML and unsafe schemes stay inert: $source',
        (tester) async {
      await tester.pumpWidget(
        host(FeedText(source: source, content: MarkdownContent.parse(source))),
      );
      final content = MarkdownContent.parse(source);
      await awaitHtml(
          tester,
          source.startsWith('<a')
              ? 'click'
              : content.kind == DetailTextKind.html ||
                      content.kind == DetailTextKind.markdown
                  ? '图片未加载'
                  : source);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
