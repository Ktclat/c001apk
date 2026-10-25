import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:c001apk_flutter/components/markdown_body.dart';
import 'package:c001apk_flutter/logic/network/request.dart';
import 'package:c001apk_flutter/pages/feed/feed_page.dart';
import 'package:c001apk_flutter/utils/app_theme.dart';
import 'package:c001apk_flutter/utils/global_data.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../network/guest_detail_test.dart' show GuestDetailAdapter;

/// Synthetic actual FeedPage frames with pinned Noto. Never device evidence.
void main() {
  late Directory temporary;
  late GuestDetailAdapter adapter;
  final evidence =
      Platform.environment['MARKDOWN_EVIDENCE'] ?? 'build/review/markdown';
  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('markdown-visual-');
    Hive.init(temporary.path);
    GStorage.settings = await Hive.openBox('markdown-visual-settings');
    GStorage.blackList = await Hive.openBox('markdown-visual-blacklist');
    GStorage.favFeed = await Hive.openBox('markdown-visual-favorites');
    final font = FontLoader(AppFontChoice.bundledFontFamily);
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(File('assets/fonts/NotoSansCJKsc-$weight.otf')
          .readAsBytes()
          .then(ByteData.sublistView));
    }
    await font.load();
    final root = Platform.environment['FLUTTER_ROOT'];
    expect(root, isNotNull);
    final icons = FontLoader('MaterialIcons')
      ..addFont(File(
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then(ByteData.sublistView));
    await icons.load();
    // Synthetic code pixels use the pinned SDK's Roboto Mono, not Ahem.
    // This is not evidence of an OEM device's monospace font mapping.
    final codeFont = FontLoader('monospace')
      ..addFont(File('$root/bin/cache/dart-sdk/bin/resources/devtools/assets/'
              'fonts/Roboto_Mono/RobotoMono-Regular.ttf')
          .readAsBytes()
          .then(ByteData.sublistView));
    await codeFont.load();
    Request();
  });
  setUp(() async {
    await GStorage.settings.clear();
    await GStorage.settings.putAll({
      SettingsBoxKey.xAppDevice: 'synthetic-visual-device',
      SettingsBoxKey.versionCode: '2604201',
      SettingsBoxKey.versionName: '16.2.0',
      SettingsBoxKey.apiVersion: '16',
      SettingsBoxKey.sdkInt: '33',
      SettingsBoxKey.userAgent: 'SyntheticVisual/1.0',
      SettingsBoxKey.recordHistory: false,
    });
    GlobalData().isLogin = false;
    GlobalData().uid = '';
    adapter = GuestDetailAdapter();
    Request.dio.httpClientAdapter = adapter;
  });
  tearDown(() async {
    Get.reset();
    Request().captchaVerifier = null;
  });
  tearDownAll(() async {
    await Hive.close();
    await temporary.delete(recursive: true);
  });

  const body = '# 中文阅读标题\n\n正文保留舒适阅读字号、中文行距和所选字体。\n\n'
      '**重点信息**，*强调内容*与~~过时内容~~。\n\n'
      '> 引用：内容安全与阅读体验都需要验证。\n\n'
      '- 第一项：保留段落结构\n- [x] 已完成：只读任务标记\n- [ ] 待完成：状态清晰可读\n\n'
      '[打开站内动态](/feed/456) · [官方网站](https://www.coolapk.com)\n\n'
      '![合成图片说明](https://image.coolapk.com/synthetic.jpg)\n\n'
      '```dart\nfinal message = "中文代码，不执行 <script>";\n```';

  for (final config in [
    (
      name: 'xiaomi-light',
      size: const Size(1200, 2670),
      dpr: 3.25,
      scale: 1.0,
      dark: false
    ),
    (
      name: 'narrow-large',
      size: const Size(320, 640),
      dpr: 1.0,
      scale: 2.0,
      dark: false
    ),
    (
      name: 'xiaomi-dark',
      size: const Size(1200, 2670),
      dpr: 3.25,
      scale: 1.0,
      dark: true
    ),
  ]) {
    testWidgets('actual Markdown and raw source frames ${config.name}',
        (tester) async {
      tester.view.physicalSize = config.size;
      tester.view.devicePixelRatio = config.dpr;
      if (config.dpr == 3.25) {
        tester.view.padding = const FakeViewPadding(top: 140);
        tester.view.viewPadding = const FakeViewPadding(top: 140);
        tester.view.systemGestureInsets = const FakeViewPadding(top: 179);
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetSystemGestureInsets);
      final key = GlobalKey();
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final picture = await boundary.toImage(pixelRatio: config.dpr);
          final bytes =
              await picture.toByteData(format: ui.ImageByteFormat.png);
          await Directory(evidence).create(recursive: true);
          await File('$evidence/${config.name}-$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }

      Future<void> load(Map<String, dynamic> data) async {
        adapter.apiBody = {
          'data': {...adapter.webBody['data'], 'feedTypeName': '图文', ...data}
        };
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        Get.reset();
        await tester.pumpWidget(RepaintBoundary(
            key: key,
            child: GetMaterialApp(
              debugShowCheckedModeBanner: false,
              theme: applyAppTypography(ThemeData(
                  useMaterial3: true,
                  brightness:
                      config.dark ? Brightness.dark : Brightness.light)),
              builder: FlutterSmartDialog.init(
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(config.scale)),
                      child: child!)),
              initialRoute: '/feed/123',
              getPages: [
                GetPage(name: '/feed/:id', page: () => const FeedPage())
              ],
            )));
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 16));
          final texts = tester.widgetList<FeedText>(find.byType(FeedText));
          if (texts.isNotEmpty &&
              texts.every((text) => text.content != null) &&
              find.text('正在准备原文分段…').evaluate().isEmpty &&
              find
                  .descendant(
                      of: find.byType(FeedText),
                      matching: find.byType(CircularProgressIndicator))
                  .evaluate()
                  .isEmpty &&
              find
                  .descendant(
                      of: find.byType(FeedText),
                      matching: find.byType(RichText))
                  .evaluate()
                  .isNotEmpty) {
            break;
          }
        }
        expect(find.byType(FeedText), findsWidgets);
        expect(
            tester
                .widgetList<FeedText>(find.byType(FeedText))
                .every((text) => text.content != null),
            isTrue);
        await tester.pumpAndSettle();
      }

      Future<void> raw() async {
        await tester.tap(find.byType(PopupMenuButton<FeedMenuItem>));
        await tester.pumpAndSettle();
        expect(find.text('查看原文'), findsOneWidget);
        await tester.tap(find.text('查看原文'));
        await tester.pumpAndSettle();
        expect(find.byType(RawSourceText), findsWidgets);
      }

      await load({'message': body});
      await capture('markdown-top');
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      final code = find.byWidgetPredicate((widget) =>
          widget is SelectableText &&
          (widget.data?.startsWith('final message') ?? false));
      expect(code, findsOneWidget);
      // Center the actual code/links region, not the unrelated comments footer.
      final codeTop = tester.getTopLeft(code).dy + scroll.offset;
      scroll.jumpTo((codeTop - config.size.height / config.dpr / 2)
          .clamp(0, scroll.position.maxScrollExtent));
      await capture('markdown-bottom-links-code');
      await raw();
      await capture('raw-source');
      expect(
          tester
              .widgetList<SelectableText>(find.byType(SelectableText))
              .map((w) => w.data),
          contains(body));
      await load({'message': '| 名称 | 数值 |\n| --- | --- |\n| 表格 | 原文完整保留 |'});
      expect(find.text('表格暂不支持排版，已保留完整原文'), findsOneWidget);
      await capture('table-fallback');
      await load({'message': '**开头**\n\n${'> ' * 40}复杂嵌套保留原文'});
      expect(find.text('正文较长或结构复杂，已保留完整原文'), findsOneWidget);
      await capture('complex-fallback');
      final original = jsonEncode([
        {'type': 'text', 'message': '# 结构化文章\n\n**正文**保留顺序。'},
        {
          'type': 'shareUrl',
          'title': '原有分享资料',
          'url': 'https://example.com/source'
        },
      ]);
      await load({
        'message': '摘要',
        'title': '原始标题 &amp; 标记',
        'message_raw_output': original
      });
      await capture('structured-formatted');
      await raw();
      expect(find.text('原始结构化正文（JSON）'), findsOneWidget);
      expect(
          tester
              .widgetList<SelectableText>(find.byType(SelectableText))
              .map((w) => w.data),
          contains(original));
      await capture('structured-raw');
      expect(adapter.requests.where((r) => r.uri.path.endsWith('/replyList')),
          isEmpty);
      expect(adapter.requests.where((r) => r.uri.host == 'image.coolapk.com'),
          isEmpty);
    });
  }
}
