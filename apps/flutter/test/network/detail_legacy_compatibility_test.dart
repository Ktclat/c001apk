import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:c001apk_flutter/components/markdown_body.dart';
import 'package:c001apk_flutter/logic/network/request.dart';
import 'package:c001apk_flutter/pages/feed/feed_page.dart';
import 'package:c001apk_flutter/utils/global_data.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'guest_detail_test.dart' show GuestDetailAdapter;

/// The real detail/controller/renderer path is exercised. Only the transport
/// and image cache boundary are replaced; no network client is created here.
class _OfflineDetailImages extends BaseCacheManager {
  final requests = <String>[];

  @override
  Stream<FileResponse> getFileStream(String url,
      {String? key, Map<String, String>? headers, bool withProgress = false}) {
    requests.add(url);
    return Stream<FileResponse>.error(StateError('Synthetic offline image'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late GuestDetailAdapter adapter;
  late _OfflineDetailImages images;

  setUpAll(() async {
    temporary =
        await Directory.systemTemp.createTemp('detail-legacy-boundary-');
    Hive.init(temporary.path);
    GStorage.settings = await Hive.openBox('legacy-detail-settings');
    GStorage.blackList = await Hive.openBox('legacy-detail-blacklist');
    GStorage.favFeed = await Hive.openBox('legacy-detail-favorites');
    Request();
  });
  setUp(() async {
    await GStorage.settings.clear();
    await GStorage.settings.putAll({
      SettingsBoxKey.xAppDevice: 'synthetic-legacy-detail-device',
      SettingsBoxKey.versionCode: '2604201',
      SettingsBoxKey.versionName: '16.2.0',
      SettingsBoxKey.apiVersion: '16',
      SettingsBoxKey.sdkInt: '33',
      SettingsBoxKey.userAgent: 'SyntheticLegacyDetail/1.0',
      SettingsBoxKey.recordHistory: false,
      SettingsBoxKey.showEmoji: true,
    });
    Get.testMode = true;
    GlobalData().isLogin = false;
    GlobalData().uid = 'synthetic-legacy-owner';
    GlobalData().sessionGeneration++;
    adapter = GuestDetailAdapter();
    Request.dio.httpClientAdapter = adapter;
    images = _OfflineDetailImages();
    // Do not read the lazy default, which would initialize real storage/HTTP.
    CachedNetworkImageProvider.defaultCacheManager = images;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  tearDown(() {
    Get.reset();
    Request().captchaVerifier = null;
    GlobalData().isLogin = false;
    GlobalData().uid = '';
  });
  tearDownAll(() async {
    await Hive.close();
    await temporary.delete(recursive: true);
  });

  Future<void> awaitRendered(WidgetTester tester,
      {required bool Function() ready, required String reason}) async {
    for (var frame = 0; frame < 100; frame++) {
      // Dio needs fake timer pumps; parser/HtmlWidget isolates need real turns.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      if (ready()) {
        await tester.pumpAndSettle();
        return;
      }
    }
    fail(reason);
  }

  Future<void> load(WidgetTester tester, Map<String, dynamic> data,
      {String? visible}) async {
    adapter.apiBody = {
      'data': {...adapter.webBody['data'], 'feedTypeName': '图文', ...data},
    };
    await tester.pumpWidget(GetMaterialApp(
      builder: FlutterSmartDialog.init(),
      initialRoute: '/feed/123',
      getPages: [
        GetPage(name: '/feed/:id', page: () => const FeedPage()),
        GetPage(
          name: '/imageview',
          page: () => const Scaffold(body: Text('合成图片浏览目的页')),
        ),
      ],
    ));
    await awaitRendered(tester, ready: () {
      if (!adapter.detailServed.isCompleted ||
          find.byType(PopupMenuButton<FeedMenuItem>).evaluate().isEmpty) {
        return false;
      }
      final bodies = tester.widgetList<FeedText>(find.byType(FeedText));
      if (bodies.any((body) => body.content == null)) return false;
      if (visible != null) {
        return find
            .textContaining(visible, findRichText: true)
            .evaluate()
            .isNotEmpty;
      }
      return bodies.isEmpty ||
          find
              .descendant(
                  of: find.byType(FeedText), matching: find.byType(RichText))
              .evaluate()
              .isNotEmpty;
    }, reason: 'The real detail body must publish its prepared renderer');
    expect(adapter.requests.where((r) => r.uri.path.endsWith('/replyList')),
        isEmpty);
    expect(tester.takeException(), isNull);
  }

  Future<void> raw(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<FeedMenuItem>));
    await tester.pumpAndSettle();
    expect(find.text('查看原文'), findsOneWidget);
    await tester.tap(find.text('查看原文'));
    await awaitRendered(tester,
        ready: () =>
            find.byType(RawSourceText).evaluate().isNotEmpty &&
            find.byType(SelectableText).evaluate().isNotEmpty,
        reason: 'Original source must be available through the real overflow');
  }

  List<String?> selectedSource(WidgetTester tester) => tester
      .widgetList<SelectableText>(find.byType(SelectableText))
      .map((text) => text.data)
      .toList();

  Rect glyphRect(WidgetTester tester, String label) {
    final paragraph = tester.renderObject<RenderParagraph>(
        find.textContaining(label, findRichText: true).first);
    final offset = paragraph.text.toPlainText().indexOf(label);
    expect(offset, greaterThanOrEqualTo(0));
    final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + label.length));
    expect(boxes, isNotEmpty);
    return boxes.first.toRect().shift(paragraph.localToGlobal(Offset.zero));
  }

  Future<void> close(WidgetTester tester) async {
    final dismissed = SmartDialog.dismiss(status: SmartStatus.allToast);
    await tester.pump(SmartDialog.config.toast.animationTime);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    await dismissed;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets('actual detail preserves legacy HTTP image entity URL and icon',
      (tester) async {
    const source = '<div>旧正文'
        '<img src="https://fixture.invalid/inline.gif?x=1&amp;y=2">'
        '<img src="synthetic-icon"></div>';
    await load(tester, {'message': source}, visible: '旧正文');
    final network = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .toList();
    expect(network, hasLength(1));
    expect(
        network.single.imageUrl, 'https://fixture.invalid/inline.gif?x=1&y=2');
    expect(images.requests, ['https://fixture.invalid/inline.gif?x=1&y=2']);
    expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
    await close(tester);
  });

  testWidgets('actual legacy text nodes preserve local emoji and wrappers',
      (tester) async {
    await load(tester, {'message': '<div><span>安全包裹</span><p>[微笑]</p></div>'},
        visible: '安全包裹');
    final assets = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<AssetImage>()
        .map((image) => image.assetName);
    expect(assets, contains('assets/emojis/coolapk_emotion_6_weixiao.png'));
    expect(find.textContaining('[微笑]', findRichText: true), findsNothing);
    expect(images.requests, isEmpty);
    await close(tester);
  });

  testWidgets(
      'actual plain detail decodes entities once and hides break marker',
      (tester) async {
    await load(tester, {'message': '甲 &amp; 乙<!--break-->丙'},
        visible: '甲 & 乙丙');
    expect(find.textContaining('&amp;', findRichText: true), findsNothing);
    expect(
        find.textContaining('<!--break-->', findRichText: true), findsNothing);
    expect(images.requests, isEmpty);
    await close(tester);
  });

  testWidgets('encoded legacy tags remain visible text and cannot fetch',
      (tester) async {
    const source = '&lt;img src="https://fixture.invalid/encoded.gif"&gt;'
        '甲 &amp; 乙';
    await load(tester, {'message': source}, visible: '<img src=');
    expect(find.textContaining('甲 & 乙', findRichText: true), findsWidgets);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(images.requests, isEmpty);
    await close(tester);
  });

  testWidgets('legacy newlines and simple bold survive the detail boundary',
      (tester) async {
    const source = '第一行\n<a href="/u/12">用户</a>\n最后一行 **重点**';
    await load(tester, {'message': source}, visible: '重点');
    expect(find.textContaining('第一行', findRichText: true), findsWidgets);
    expect(find.textContaining('最后一行', findRichText: true), findsWidgets);
    expect(find.textContaining('**重点**', findRichText: true), findsNothing);
    final first = glyphRect(tester, '第一行');
    final last = glyphRect(tester, '最后一行');
    expect(last.top, greaterThan(first.top));
    expect(images.requests, isEmpty);
    await close(tester);
  });

  testWidgets('actual legacy image link keeps gallery routing and decoded URL',
      (tester) async {
    const url = 'https://image.coolapk.com/synthetic.jpg?x=1&y=2';
    await load(
        tester,
        {
          'message':
              '<a href="https://image.coolapk.com/synthetic.jpg?x=1&amp;y=2">查看旧图片</a>',
        },
        visible: '查看旧图片');
    expect(images.requests, isEmpty);
    await tester.tapAt(glyphRect(tester, '查看旧图片').center);
    await tester.pumpAndSettle();
    expect(find.text('合成图片浏览目的页'), findsOneWidget);
    expect((Get.arguments as Map)['imgList'], [url]);
    expect(images.requests, isEmpty);
    await close(tester);
  });

  testWidgets('unsafe legacy schemes remain inert through the actual page',
      (tester) async {
    const source = '<span>安全文字</span>'
        '<a href="javascript:alert(1)" onclick="bad()">不可执行链接</a>'
        '<img src="httpx://fixture.invalid/not-http.gif">'
        '<img src="file:///synthetic.gif">'
        '<img src="data:x">';
    await load(tester, {'message': source}, visible: '安全文字');
    expect(find.textContaining('不可执行链接', findRichText: true), findsWidgets);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(images.requests, isEmpty);
    await tester.tapAt(glyphRect(tester, '不可执行链接').center);
    await tester.pumpAndSettle();
    expect(find.byType(FeedPage), findsOneWidget);
    expect(images.requests, isEmpty);
    await close(tester);
  });

  testWidgets('mixed new Markdown HTML and raw source never auto-fetch images',
      (tester) async {
    const source = '# 新 Markdown\n\n'
        '<img src="https://fixture.invalid/mixed.gif">\n\n'
        '![图片](https://fixture.invalid/markdown.gif)<!--break-->';
    await load(tester, {'message': source}, visible: '图片未加载');
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(images.requests, isEmpty);
    await raw(tester);
    expect(selectedSource(tester), contains(source));
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(images.requests, isEmpty);
    await close(tester);
  });

  for (final imageOnly in [false, true]) {
    testWidgets(
        'structured ${imageOnly ? 'image-only' : 'plain'} detail offers exact inert raw fields',
        (tester) async {
      const title = '原始标题 &amp; 标记';
      const cover = 'https://fixture.invalid/original-cover.gif?x=1&y=2';
      final original = imageOnly
          ? '[ { "type": "image", "url": "https://fixture.invalid/body.gif" } ]'
          : '[ { "type": "text", "message": "甲<!--break-->乙" } ]';
      await load(
          tester,
          {
            'message': '摘要不应替代原文',
            'title': title,
            'message_cover': cover,
            'message_raw_output': original,
          },
          visible: null);
      final priorRequests = List<String>.of(images.requests);
      await raw(tester);
      expect(find.text('原始标题'), findsOneWidget);
      expect(find.text('原始封面地址（仅文本）'), findsOneWidget);
      expect(find.text('原始结构化正文（JSON）'), findsOneWidget);
      expect(selectedSource(tester), containsAll([title, cover, original]));
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(images.requests, priorRequests);
      expect(jsonDecode(original), isA<List>());
      await close(tester);
    });
  }
  for (final markdown in [false, true]) {
    testWidgets(
        'retained ${markdown ? 'Markdown' : 'legacy'} link cannot route after owner change',
        (tester) async {
      final source =
          markdown ? '# 新正文\n\n[旧链接](/u/12)' : '<a href="/u/12">旧链接</a>';
      await load(tester, {'message': source}, visible: '旧链接');
      final renderer = tester.widget<HtmlWidget>(find.descendant(
          of: find.byType(FeedText), matching: find.byType(HtmlWidget)));
      GlobalData().sessionGeneration++;
      await renderer.onTapUrl!('/u/12');
      await tester.pumpAndSettle();
      expect(Get.currentRoute, '/feed/123');
      expect(images.requests, isEmpty);
      await close(tester);
    });
  }

  testWidgets(
      'structured metadata keeps legacy title and literal caption styles',
      (tester) async {
    const title = '# 原有标题 <b>加粗</b>';
    const label = '<b>**分享标签**</b> &amp; [微笑]';
    const caption = '&amp; **原有说明** [微笑]';
    await load(
        tester,
        {
          'title': title,
          'message_raw_output': jsonEncode([
            {'type': 'text', 'message': '合成短正文'},
            {'type': 'shareUrl', 'title': label, 'url': '/u/12'},
            {
              'type': 'image',
              'url': 'https://fixture.invalid/body@800x10.gif',
              'description': caption
            },
          ]),
        },
        visible: caption);
    expect(find.textContaining('# 原有标题', findRichText: true), findsOneWidget);
    final captionWidget = tester.widget<Text>(find.text(caption));
    expect(captionWidget.textAlign, TextAlign.center);
    expect(captionWidget.style!.fontSize, 14);
    expect(find.text(label), findsOneWidget);
    final share = tester.widget<InkWell>(find
        .ancestor(of: find.text(label), matching: find.byType(InkWell))
        .first);
    GlobalData().sessionGeneration++;
    share.onTap!();
    await tester.pumpAndSettle();
    expect(Get.currentRoute, '/feed/123');
    await close(tester);
  });
}
