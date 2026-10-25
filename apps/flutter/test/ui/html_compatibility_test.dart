import 'dart:async';
import 'dart:io';

import 'package:c001apk_flutter/components/cards/notification_card.dart';
import 'package:c001apk_flutter/components/html_text.dart';
import 'package:c001apk_flutter/logic/model/feed/datum.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:c001apk_flutter/utils/utils.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Records the production image-provider request without creating an HTTP client.
class _OfflineImages extends BaseCacheManager {
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
  late _OfflineImages images;

  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('html-compatibility-');
    Hive.init(temporary.path);
    GStorage.settings = await Hive.openBox('settings');
    await GStorage.settings.put(SettingsBoxKey.showEmoji, false);
  });
  setUp(() {
    Get.testMode = true;
    // Each test file has its own isolate. Assign without reading the lazy
    // default, which would initialize platform storage and a real HTTP client.
    images = _OfflineImages();
    CachedNetworkImageProvider.defaultCacheManager = images;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  tearDown(() {
    Get.reset();
  });
  tearDownAll(() async {
    await Hive.close();
    await temporary.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(GetMaterialApp(
      builder: FlutterSmartDialog.init(),
      initialRoute: '/',
      getPages: [
        GetPage(
          name: '/',
          page: () => Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 360, child: child),
            ),
          ),
        ),
        GetPage(
          name: '/feed/:id',
          page: () => Scaffold(body: Text('feed:${Get.parameters['id']}')),
        ),
        GetPage(
          name: '/t/:value',
          page: () => Scaffold(body: Text('topic:${Get.parameters['value']}')),
        ),
        GetPage(
          name: '/coolpic',
          page: () => const Scaffold(body: Text('topic picture destination')),
        ),
      ],
    ));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    SmartDialog.dismiss(status: SmartStatus.allToast);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  Future<void> tapNotification(WidgetTester tester, String note) async {
    await mount(
      tester,
      NotificationCard(data: Datum(note: note, fromusername: '合成通知')),
    );
    // Tap the real card's bottom padding, not a nested HtmlWidget link.
    await tester.tapAt(tester.getBottomLeft(find.byType(NotificationCard)) +
        const Offset(15, -8));
    await tester.pumpAndSettle();
  }

  test('plain text conversion preserves existing br/entity/paragraph rules',
      () {
    expect(Utils.parseHtmlString('<p>甲<br>乙<br/>丙</p><p>丁 &amp; &#20013;</p>'),
        '甲\n乙\n丙丁 & 中');
    expect(Utils.parseHtmlString('甲\n乙<img src="data:x" alt="不追加 alt">丙'),
        '甲\n乙丙');
    expect(
        Utils.parseHtmlString(normalizePostMarkup('甲\r\n乙\n\n\n**丙** &amp; 丁')),
        '甲\n乙\n\n丙 & 丁');
  });

  for (final example in [
    (
      '<a>没有地址</a><a href="&#47;feed&#47;42?x=1&amp;y=2">首个地址</a>'
          '<a href="/feed/99">第二个地址</a>',
      'feed:42',
    ),
    ('<a HREF="/t/A&amp;B">实体主题</a>', 'topic:A&B'),
    ('<a href="/t/topic?x=1&amp;type=8">图片主题</a>', 'topic picture destination'),
  ]) {
    testWidgets('notification selects decoded first href: ${example.$2}',
        (tester) async {
      await tapNotification(tester, example.$1);
      expect(find.text(example.$2), findsOneWidget);
      expect(find.text('feed:99'), findsNothing);
      expect(images.requests, isEmpty);
      await close(tester);
    });
  }

  for (final note in [
    '&lt;a href="/feed/99"&gt;转义文本不是链接&lt;/a&gt;',
    '<a href="">空地址</a><a href="/feed/99">不能跳过首个 href</a>',
    '<a href="javascript:alert(1)">不支持的协议</a>',
  ]) {
    testWidgets('notification does not broaden link policy: $note',
        (tester) async {
      await tapNotification(tester, note);
      expect(find.byType(NotificationCard), findsOneWidget);
      expect(Get.currentRoute, '/');
      expect(images.requests, isEmpty);
      await close(tester);
    });
  }

  testWidgets('rendered HTML link decodes ampersands before existing routing',
      (tester) async {
    await mount(tester, htmlText('<a href="/t/topic?x=1&amp;type=8">实体链接</a>'));
    final paragraph = tester
        .renderObject<RenderParagraph>(find.text('实体链接', findRichText: true));
    // RichText spans the 360px line: tap a glyph box, not its empty center.
    final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 4));
    expect(boxes, isNotEmpty);
    await tester.tapAt(paragraph.localToGlobal(boxes.first.toRect().center));
    await tester.pumpAndSettle();
    expect(find.text('topic picture destination'), findsOneWidget);
    await close(tester);
  });

  testWidgets('inline images retain offline scheme and entity handling',
      (tester) async {
    await mount(
        tester,
        htmlText(
          '<img src="https://fixture.invalid/inline.gif?x=1&amp;y=2">'
          '<img src="httpx://fixture.invalid/not-http.gif">'
          '<img src="file:///synthetic.gif">'
          '<img src="data:x">'
          '<img src="synthetic-icon">',
        ));
    final network = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .toList();
    expect(network, hasLength(1));
    expect(
        network.single.imageUrl, 'https://fixture.invalid/inline.gif?x=1&y=2');
    expect(images.requests, ['https://fixture.invalid/inline.gif?x=1&y=2']);
    expect(find.text('file:///synthetic.gif'), findsOneWidget);
    expect(find.text('data:x'), findsOneWidget);
    expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
    // Existing networkImage rejects httpx; file/data remain textual fallbacks.
    // The offline cache records any accidental extra fetch, rather than hiding it.
    await close(tester);
  });
}
