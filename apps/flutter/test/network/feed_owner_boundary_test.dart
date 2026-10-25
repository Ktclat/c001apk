import 'dart:async';
import 'dart:io';

import 'package:c001apk_flutter/components/markdown_body.dart';
import 'package:c001apk_flutter/logic/accounts/account_store.dart';
import 'package:c001apk_flutter/logic/network/request.dart';
import 'package:c001apk_flutter/pages/feed/feed_page.dart';
import 'package:c001apk_flutter/pages/feed/feed_controller.dart';
import 'package:c001apk_flutter/logic/state/loading_state.dart';
import 'package:dio/dio.dart';
import 'package:c001apk_flutter/pages/feed/reply/reply_page.dart';
import 'package:c001apk_flutter/utils/global_data.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import 'guest_detail_test.dart' show GuestDetailAdapter, showFeed;

class DelayedLikeAdapter extends GuestDetailAdapter {
  final likeStarted = Completer<void>();
  final likeResponse = Completer<ResponseBody>();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    if (options.uri.path == '/v6/feed/like') {
      requests.add(options);
      likeStarted.complete();
      return likeResponse.future;
    }
    return super.fetch(options, requestStream, cancelFuture);
  }
}

void main() {
  late Directory temporary;
  late GuestDetailAdapter adapter;
  final externalCalls = <MethodCall>[];
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp('feed-owner-boundary-');
    Hive.init(temporary.path);
    GStorage.settings = await Hive.openBox('owner-settings');
    GStorage.blackList = await Hive.openBox('owner-blacklist');
    GStorage.favFeed = await Hive.openBox('owner-favorites');
    Request();
  });
  setUp(() async {
    await GStorage.settings.clear();
    await GStorage.blackList.clear();
    await GStorage.favFeed.clear();
    await GStorage.settings.putAll({
      SettingsBoxKey.xAppDevice: 'synthetic-owner-device',
      SettingsBoxKey.versionCode: '2604201',
      SettingsBoxKey.versionName: '16.2.0',
      SettingsBoxKey.apiVersion: '16',
      SettingsBoxKey.sdkInt: '33',
      SettingsBoxKey.userAgent: 'SyntheticOwner/1.0',
      SettingsBoxKey.recordHistory: false,
    });
    GlobalData().isLogin = true;
    GlobalData().uid = 'synthetic-owner-a';
    GlobalData().sessionGeneration++;
    GlobalData().SESSID = 'SESSID=synthetic-session';
    adapter = GuestDetailAdapter();
    adapter.apiBody = {
      'data': {
        ...adapter.webBody['data'],
        'feedTypeName': '旧账号类型',
        'message': '# 旧账号正文\n\n${'原始正文。' * 350}',
      }
    };
    Request.dio.httpClientAdapter = adapter;
    externalCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
      externalCalls.add(call);
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method.startsWith('Clipboard.') &&
          call.method != 'Clipboard.hasStrings') {
        externalCalls.add(call);
      }
      return null;
    });
  });
  tearDown(() {
    Get.reset();
    Request().captchaVerifier = null;
    GlobalData().isLogin = false;
    GlobalData().uid = '';
    GlobalData().SESSID = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  tearDownAll(() async {
    await Hive.close();
    await temporary.delete(recursive: true);
  });

  Future<void> prepared(WidgetTester tester) async {
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      final texts = tester.widgetList<FeedText>(find.byType(FeedText));
      if (texts.isNotEmpty &&
          texts.every((value) => value.content != null) &&
          find
              .descendant(
                  of: find.byType(FeedText), matching: find.byType(RichText))
              .evaluate()
              .isNotEmpty) {
        return;
      }
    }
    fail('Bounded detail preparation did not publish');
  }

  void changeOwnerBeforeNotifier() {
    // This is the actual AccountStore ordering: mutate globals, await storage,
    // and only later emit changes. Do not collapse the interval in this test.
    GlobalData().sessionGeneration++;
    GlobalData().uid = 'synthetic-owner-b';
  }

  Future<void> forceDetailRebuild(WidgetTester tester) async {
    tester.element(find.byType(FeedPage)).markNeedsBuild();
    await tester.pumpAndSettle();
  }

  void expectNoOldDetail(WidgetTester tester) {
    expect(find.byType(FeedText), findsNothing);
    expect(find.byType(RawSourceText), findsNothing);
    expect(find.text('合成作者'), findsNothing);
    expect(find.text('旧账号类型'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(PopupMenuButton<FeedMenuItem>), findsNothing);
    expect(find.text('账号已切换，请重新打开详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  testWidgets(
      'pre-notifier owner gap hides body sticky author and retained FAB action',
      (tester) async {
    await showFeed(tester, adapter);
    await prepared(tester);
    final oldFab =
        tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
    final scroll = tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    scroll.jumpTo(100);
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(50));
    final requestCount = adapter.requests.length;
    changeOwnerBeforeNotifier();
    oldFab.onPressed!();
    await forceDetailRebuild(tester);
    expectNoOldDetail(tester);
    expect(find.byType(ReplyPage), findsNothing);
    expect(adapter.requests, hasLength(requestCount));
    // Explicit retry, not the owner change, is what loads the new account.
    adapter.apiBody = {
      'data': {...adapter.webBody['data'], 'message': '# 新账号正文'}
    };
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await prepared(tester);
    expect(tester.widget<FeedText>(find.byType(FeedText)).source, '# 新账号正文');
    expect(tester.takeException(), isNull);
  });

  for (final notify in [false, true]) {
    for (final item in FeedMenuItem.values) {
      testWidgets(
          'open ${item.name} menu action is inert after owner change notify=$notify',
          (tester) async {
        await showFeed(tester, adapter);
        await prepared(tester);
        final oldMenu = tester.widget<PopupMenuButton<FeedMenuItem>>(
            find.byType(PopupMenuButton<FeedMenuItem>));
        await tester.tap(find.byType(PopupMenuButton<FeedMenuItem>));
        await tester.pumpAndSettle();
        expect(find.text(item.label), findsOneWidget);
        final requests = adapter.requests.length;
        changeOwnerBeforeNotifier();
        if (notify) AccountStore.changes.value++;
        // Exercise both a real outstanding popup and the exact retained action
        // ticket. Neither may silently rebind to the newly current owner.
        await tester.tap(find.text(item.label));
        oldMenu.onSelected!(item);
        await tester.pumpAndSettle();
        await forceDetailRebuild(tester);
        expectNoOldDetail(tester);
        expect(GStorage.favFeed.isEmpty, isTrue);
        expect(GStorage.blackList.isEmpty, isTrue);
        expect(externalCalls, isEmpty);
        expect(adapter.requests, hasLength(requests));
        expect(Get.currentRoute, '/feed/123');
      });
    }
  }

  for (final raw in [
    '[  {"type":"text","message":"普通结构化正文"}  ]',
    '[  {"type":"image","url":"invalid-image-source"}  ]',
    '[  {"type":"unknown","custom":"保留原始字段"}  ]',
  ]) {
    testWidgets(
        'retained structured source is available without Markdown: $raw',
        (tester) async {
      adapter.apiBody = {
        'data': {
          ...adapter.webBody['data'],
          'title': '原始标题 &amp;',
          'message_raw_output': raw,
        }
      };
      await showFeed(tester, adapter);
      // Image-only and unknown-block articles have no formatted text worker to
      // await; availability comes from retained raw JSON, not parser output.
      await tester.tap(find.byType(PopupMenuButton<FeedMenuItem>));
      await tester.pumpAndSettle();
      expect(find.text('查看原文'), findsOneWidget);
      await tester.tap(find.text('查看原文'));
      await tester.pumpAndSettle();
      expect(find.text('原始结构化正文（JSON）'), findsOneWidget);
      final texts = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((value) => value.data);
      expect(texts, contains(raw));
      expect(texts, contains('原始标题 &amp;'));
      expect(tester.takeException(), isNull);
    });
  }

  for (final dispose in [false, true]) {
    testWidgets(
        'pending raw Next page cannot survive owner invalidation dispose=$dispose',
        (tester) async {
      adapter.apiBody = {
        'data': {
          ...adapter.webBody['data'],
          'message': '# 旧账号\n\n${'原文段落。\n\n' * 1200}'
        }
      };
      await showFeed(tester, adapter);
      await prepared(tester);
      await tester.tap(find.byType(PopupMenuButton<FeedMenuItem>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看原文'));
      await tester.pump();
      for (var i = 0;
          i < 100 && find.byType(SelectableText).evaluate().isEmpty;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(find.byType(SelectableText), findsOneWidget);
      final next =
          tester.widget<TextButton>(find.widgetWithText(TextButton, '下一段'));
      expect(next.onPressed, isNotNull);
      next.onPressed!();
      // Let the real worker complete and queue its post-frame navigation,
      // without letting a frame execute that callback yet.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)));
      changeOwnerBeforeNotifier();
      if (dispose) {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump();
        expect(find.byType(FeedPage), findsNothing);
      } else {
        await forceDetailRebuild(tester);
        expectNoOldDetail(tester);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final fail in [false, true]) {
    test('old in-flight like cannot publish into replacement body fail=$fail',
        () async {
      final delayed = DelayedLikeAdapter();
      delayed.apiBody = {
        'data': {...delayed.webBody['data'], 'message': '# 旧正文', 'likenum': 1}
      };
      Request.dio.httpClientAdapter = delayed;
      final controller = FeedController(id: '123', recordHistory: false);
      try {
        await controller.getFeedData();
        final pending = controller.onLike(123, 0, isFeed: true);
        await delayed.likeStarted.future;
        changeOwnerBeforeNotifier();
        delayed.apiBody = {
          'data': {
            ...delayed.webBody['data'],
            'message': '# 新正文',
            'likenum': 42
          }
        };
        await controller.getFeedData();
        final replacement = controller.feedState.value;
        expect((replacement as Success).response.likenum, 42);
        if (fail) {
          delayed.likeResponse
              .completeError(StateError('synthetic stale failure'));
        } else {
          delayed.likeResponse.complete(
              ResponseBody.fromString('{"data":{"count":99}}', 200, headers: {
            Headers.contentTypeHeader: ['application/json']
          }));
        }
        await pending;
        expect(controller.feedState.value, same(replacement));
        expect((controller.feedState.value as Success).response.likenum, 42);
      } finally {
        controller.onClose();
      }
    });
  }

  test(
      'structured snapshot retains each display metadata source with literal mode keys',
      () async {
    const raw = '[{"type":"text","message":"正文"},'
        '{"type":"shareUrl","title":"<b>**literal share**</b>","url":"https://example.com"},'
        '{"type":"image","url":"invalid-image-source","description":"&amp; **literal description**"}]';
    adapter.apiBody = {
      'data': {
        ...adapter.webBody['data'],
        'title': '<b>原始标题</b>',
        'message_raw_output': raw,
      }
    };
    final controller = FeedController(id: '123', recordHistory: false);
    try {
      await controller.getFeedData();
      final snapshot = controller.bodySnapshot.value!;
      expect(snapshot.sources, {
        'article:0:title': '<b>原始标题</b>',
        'article:1': '正文',
        'article:2:label': '<b>**literal share**</b>',
        'article:3:description': '&amp; **literal description**',
      });
      expect(snapshot.rawFields['message_raw_output'], raw);
    } finally {
      controller.onClose();
    }
  });
}
