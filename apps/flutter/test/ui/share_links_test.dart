import 'package:c001apk_flutter/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:hive/hive.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-share-links-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
    await GStorage.settings.put(SettingsBoxKey.openInBrowser, false);
  });
  tearDown(Get.reset);
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test('article share has a one-line title and both encoded links', () {
    expect(Utils.getShareText('123', ShareType.feed, title: '文章\n标题'),
        '文章 标题\nhttps://www.coolapk1s.com/feed/123\nhttps://www.coolapk.com/feed/123\n分享自c001apk');
    expect(Utils.getShareText('摄影 & 日常', ShareType.t, title: '摄影话题'),
        '摄影话题\nhttps://www.coolapk1s.com/t/%E6%91%84%E5%BD%B1%20%26%20%E6%97%A5%E5%B8%B8\nhttps://www.coolapk.com/t/%E6%91%84%E5%BD%B1%20%26%20%E6%97%A5%E5%B8%B8\n分享自c001apk');
  });

  test('share summary truncates only between complete emoji graphemes', () {
    final title = List.filled(101, '👨‍👩‍👧‍👦').join();
    expect(
        Utils.getShareText('123', ShareType.feed, title: title)
            .split('\n')
            .first,
        '${List.filled(100, '👨‍👩‍👧‍👦').join()}…');
  });

  test('untitled feeds use plain text with a safe empty fallback', () {
    expect(
        Utils.getShareText('123', ShareType.feed,
                message: '<p>第一行<br>第二行 &amp; 内容</p>')
            .split('\n')
            .first,
        '第一行 第二行 & 内容');
    expect(Utils.getShareText('123', ShareType.feed).split('\n').first, '动态');
  });

  for (final link in [
    'coolmarket://www.coolapk.com/feed/123?s=x#reply',
    'coolmarket://com.coolapk.market/feed/123',
    'https://m.coolapk.com/feed/123?s=x',
    'https://www.coolapk1s.com/feed/123',
  ]) {
    testWidgets('external link $link opens the normalized feed',
        (tester) async {
      await tester.pumpWidget(GetMaterialApp(initialRoute: '/', getPages: [
        GetPage(name: '/', page: () => const Scaffold(body: Text('主页'))),
        GetPage(
            name: '/feed/:id',
            page: () => Scaffold(body: Text('动态 ${Get.parameters['id']}'))),
      ]));
      await tester.pumpAndSettle();
      Utils.onOpenLink(link);
      await tester.pumpAndSettle();
      expect(find.text('动态 123'), findsOneWidget);
      expect(tester.takeException(), isNull);
      Get.back();
      await tester.pumpAndSettle();
      expect(find.text('主页'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final example in [
    ('https://m.coolapk.com/u/123?s=x#profile', '/u/:value', '123'),
    (
      'coolmarket://www.coolapk.com/apk/com.tencent.mm?s=x',
      '/apk/:value',
      'com.tencent.mm'
    ),
    (
      'https://www.coolapk.com/t/%E6%91%84%E5%BD%B1%20%26%20%E6%97%A5%E5%B8%B8?s=x#reply',
      '/t/:value',
      '摄影 & 日常'
    ),
    ('coolmarket://product/123?s=x', '/product/:value', '123'),
  ]) {
    testWidgets('non-feed link ${example.$1} strips metadata and decodes once',
        (tester) async {
      await tester.pumpWidget(GetMaterialApp(initialRoute: '/', getPages: [
        GetPage(name: '/', page: () => const Scaffold(body: Text('主页'))),
        GetPage(
            name: example.$2,
            page: () => Scaffold(body: Text('目标 ${Get.parameters['value']}'))),
      ]));
      await tester.pumpAndSettle();
      Utils.onOpenLink(example.$1);
      await tester.pumpAndSettle();
      expect(find.text('目标 ${example.$3}'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final link in [
    'https://coolapk.com.evil.example/feed/123',
    'https://evil-coolapk.com/feed/123',
    'https://www.coolapk.com:8443/feed/123',
  ]) {
    testWidgets('lookalike or explicit-port URL remains external: $link',
        (tester) async {
      final opened = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'), (call) async {
        if (call.method == 'launch') {
          opened.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/url_launcher'), null));
      await tester.pumpWidget(GetMaterialApp(initialRoute: '/', getPages: [
        GetPage(name: '/', page: () => const Scaffold(body: Text('主页'))),
        GetPage(name: '/feed/:id', page: () => const Text('internal feed')),
      ]));
      await tester.pumpAndSettle();
      Utils.onOpenLink(link);
      await tester.pumpAndSettle();
      expect(opened, [link]);
      expect(find.text('internal feed'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final link in [
    'https://www.coolapk.com/feed/%ZZ',
    'https://www.coolapk.com/t/%FF',
    'https://www.coolapk.com/t/%2Fescape',
    'https://www.coolapk.com/t/%5Cescape',
    'https://www.coolapk.com/t/a/b',
    'https://www.coolapk.com/u/',
    'https://user@www.coolapk.com/feed/123',
    'coolmarket://com.coolapk.market/feed/',
    'http://[invalid',
    'javascript:alert(1)',
    'https://www.coolapk.com/t/%00',
    'https://www.coolapk.com/t/topic?type=%FF',
  ]) {
    testWidgets('malformed or ambiguous link is safely rejected: $link',
        (tester) async {
      await tester.pumpWidget(GetMaterialApp(
          builder: FlutterSmartDialog.init(),
          initialRoute: '/',
          getPages: [
            GetPage(name: '/', page: () => const Scaffold(body: Text('主页'))),
            GetPage(
                name: '/feed/:id', page: () => const Text('bad navigation')),
            GetPage(name: '/t/:id', page: () => const Text('bad navigation')),
            GetPage(name: '/u/:id', page: () => const Text('bad navigation')),
          ]));
      await tester.pumpAndSettle();
      Utils.onOpenLink(link);
      await tester.pumpAndSettle();
      expect(find.text('主页'), findsOneWidget);
      expect(find.text('bad navigation'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
