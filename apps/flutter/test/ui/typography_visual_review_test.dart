import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:c001apk_flutter/components/html_text.dart';
import 'package:c001apk_flutter/utils/app_theme.dart';
import 'package:c001apk_flutter/utils/reading_preset.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// A reproducible, *synthetic* screenshot review. Never uses real user content
/// or network data, and never claims to substitute for Android-device testing.
void main() {
  late Directory temporary;
  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('noto-ui-review-');
    Hive.init(temporary.path);
    GStorage.settings = await Hive.openBox<dynamic>('typography-review');
    // flutter_test normally uses Ahem (square placeholder glyphs). Load the
    // actual bundled Chinese OTF files before taking the visual screenshot,
    // otherwise a green snapshot test proves nothing about font quality.
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
  });
  setUp(() async {
    await GStorage.settings.clear();
    expect(GStorage.fontChoice, AppFontChoice.notoSans);
    expect(GStorage.readingPreset, ReadingPreset.comfortable);
  });
  tearDown(() => Get.reset());
  tearDownAll(() async {
    await GStorage.settings.flush();
    await GStorage.settings.close();
    await temporary.delete(recursive: true);
  });

  Widget preview() {
    final fontChoice = GStorage.fontChoice;
    final theme = applyAppTypography(
      ThemeData(
        useMaterial3: true,
        platform: TargetPlatform.android,
        fontFamily: fontChoice.familyForPlatform(TargetPlatform.android),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff386899)),
      ),
      fontChoice: fontChoice,
    );
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('中文排版验收'),
          leading: const Icon(Icons.arrow_back),
        ),
        body: RepaintBoundary(
          key: const Key('typography-review'),
          child: Container(
            color: theme.colorScheme.surface,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const CircleAvatar(child: Icon(Icons.person_outline)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('科技观察者',
                                      style: theme.textTheme.titleMedium),
                                  Text('来自头条推荐 · Redmi Note 11T Pro+',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      )),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        htmlText(
                          '【科技周报】智能终端发布新品与行业观察',
                          role: HtmlTextRole.feedTitle,
                        ),
                        const SizedBox(height: 8),
                        htmlText(
                          '新的手机设计更注重手感与续航，AI 功能也在持续进步。'
                          '阅读应该轻松，不需要每一个字都显得粗重。\n\n'
                          '**周五新鲜事** · Noto Sans CJK SC 123 ABC\n'
                          '这是一段用于检查标点、字重和换行的中文内容。',
                          role: HtmlTextRole.feedBody,
                        ),
                        const SizedBox(height: 12),
                        Text('#数码日常  #软件体验',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('图文详情 · 长文阅读',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 14),
                        htmlText('文章标题：不同字重应该有明确区分',
                            role: HtmlTextRole.articleTitle),
                        const SizedBox(height: 9),
                        htmlText(
                          '这是文章正文。中文和 English 以及 2026 年的数字需要'
                          '保持均匀的视觉重量；逗号、句号和书名号《示例》不能拥挤。\n\n'
                          '第二段内容用于观察行高、段落间距及连续阅读节奏。',
                          role: HtmlTextRole.articleBody,
                        ),
                        const Divider(height: 30),
                        Text('评论区', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        htmlText(
                          '字号适中、笔画清晰，而且不会被上下两行挤在一起。',
                          role: HtmlTextRole.replyBody,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Noto Chinese UI has safe hierarchy and exports review image',
      (tester) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(preview());
    await tester.pumpAndSettle();

    expect(find.text('中文排版验收'), findsOneWidget);
    expect(find.textContaining('**周五新鲜事**'), findsNothing);
    final paragraph = tester.widget<Text>(find.text('科技观察者'));
    expect(paragraph.style?.fontFamily, AppFontChoice.bundledFontFamily);
    expect(tester.takeException(), isNull);

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('typography-review')),
    );
    expect(boundary.debugNeedsPaint, isFalse);

    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final output = File('build/review/noto-typography.png');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes!.buffer.asUint8List());
      expect(await output.length(), greaterThan(10000));
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('large accessibility text fits narrow Chinese UI',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 800),
          textScaler: TextScaler.linear(1.3),
        ),
        child: preview(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
