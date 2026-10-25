import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:c001apk_flutter/utils/app_theme.dart';

import 'package:c001apk_flutter/logic/network/request.dart';
import 'package:c001apk_flutter/logic/state/loading_state.dart';
import 'package:c001apk_flutter/pages/feed/feed_controller.dart';
import 'package:c001apk_flutter/components/markdown_body.dart';
import 'package:c001apk_flutter/logic/accounts/account_store.dart';
import 'package:c001apk_flutter/pages/feed/feed_page.dart';
import 'package:c001apk_flutter/utils/global_data.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

// Only the external transport is replaced; requests, headers, models and the
// controller all run normally. Content and device data are synthetic.
class GuestDetailAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final detailServed = Completer<void>();
  Future<void> Function()? beforeReply;
  Future<void> Function()? beforeDetail;
  dynamic replyBody = {'data': []};
  Map<String, dynamic> apiBody = {
    'code': 403,
    'messageStatus': 'err_request_captcha_v2',
    'message': '需要验证码',
  };
  dynamic webBody = {
    'status': 0,
    'error': 0,
    'messageStatus': 0,
    'data': {
      'id': 123,
      'entityType': 'feed',
      'uid': 10,
      'userInfo': {'uid': 10, 'username': '合成作者'},
      'message': '完整的合成动态正文',
      'message_raw_output': '[]',
      'replynum': 0,
    },
  };

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (options.uri.path == '/v6/feed/replyList') await beforeReply?.call();
    if (options.uri.path == '/v6/feed/detail') await beforeDetail?.call();
    if (options.uri.path == '/v6/feed/detail' && !detailServed.isCompleted) {
      detailServed.complete();
    }
    final isWeb = options.uri.host == 'www.coolapk.com';
    final body = isWeb
        ? webBody
        : options.uri.path == '/v6/feed/replyList'
            ? replyBody
            : apiBody;
    return ResponseBody.fromString(
        body is String ? body : jsonEncode(body), 200,
        headers: {
          Headers.contentTypeHeader: [isWeb ? 'text/html' : 'application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

final captureKey = GlobalKey();
final evidenceRoot = Platform.environment['UPSTREAM_SYNC_EVIDENCE'];
bool captureFontsLoaded = false;

Future<void> pumpUntil(
    WidgetTester tester, bool Function() ready, String description) async {
  // Dio schedules each interceptor with Future(), i.e. fake-zone timers.
  // runAsync cannot advance those timers and must not await this transport.
  for (var frame = 0; frame < 40 && !ready(); frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(ready(), isTrue, reason: description);
}

Future<void> showFeed(WidgetTester tester, GuestDetailAdapter adapter) async {
  if (evidenceRoot != null) {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (!captureFontsLoaded) {
      await tester.runAsync(() async {
        final font = FontLoader(AppFontChoice.bundledFontFamily);
        for (final weight in ['Regular', 'Medium', 'Bold']) {
          font.addFont(File('assets/fonts/NotoSansCJKsc-$weight.otf')
              .readAsBytes()
              .then(ByteData.sublistView));
        }
        await font.load();
        final root = Platform.environment['FLUTTER_ROOT'];
        if (root == null) {
          throw StateError('FLUTTER_ROOT is required for evidence icons');
        }
        final icons = FontLoader('MaterialIcons')
          ..addFont(File(
                  '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
              .readAsBytes()
              .then(ByteData.sublistView));
        await icons.load();
        captureFontsLoaded = true;
      });
    }
  }
  await tester.pumpWidget(RepaintBoundary(
    key: captureKey,
    child: GetMaterialApp(
      debugShowCheckedModeBanner: false,
      theme: applyAppTypography(ThemeData(useMaterial3: true)),
      builder: FlutterSmartDialog.init(),
      initialRoute: '/feed/123',
      getPages: [
        GetPage(name: '/feed/:id', page: () => const FeedPage()),
      ],
    ),
  ));
  await pumpUntil(
      tester,
      () =>
          adapter.detailServed.isCompleted &&
          (find.byType(CustomScrollView).evaluate().isNotEmpty ||
              find.text('重试').evaluate().isNotEmpty),
      'Mock detail must finish and render its success/error view');
  await tester.pumpAndSettle();
  expect(find.byType(FeedPage), findsOneWidget);
  expect(adapter.requests.where((r) => r.uri.path == '/v6/feed/detail'),
      hasLength(1));
}

Future<void> captureFeed(WidgetTester tester, String name) async {
  if (evidenceRoot == null) return;
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(evidenceRoot!).create(recursive: true);
    await File('$evidenceRoot/$name.png')
        .writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  late Directory temp;
  late GuestDetailAdapter adapter;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('c001apk-guest-detail-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
    GStorage.blackList = await Hive.openBox('blackList');
    GStorage.favFeed = await Hive.openBox('favFeed');
    await GStorage.settings.putAll({
      SettingsBoxKey.xAppDevice: 'synthetic-test-device',
      SettingsBoxKey.versionCode: '2604201',
      SettingsBoxKey.versionName: '16.2.0',
      SettingsBoxKey.apiVersion: '16',
      SettingsBoxKey.sdkInt: '33',
      SettingsBoxKey.userAgent: 'SyntheticTest/1.0',
      SettingsBoxKey.recordHistory: false,
    });
    Request();
  });
  setUp(() async {
    await GStorage.settings.delete(SettingsBoxKey.szlmId);
    GlobalData().isLogin = false;
    GlobalData().SESSID = 'SESSID=synthetic-session';
    adapter = GuestDetailAdapter();
    Request.dio.httpClientAdapter = adapter;
  });
  tearDown(() {
    Get.reset();
    Request().captchaVerifier = null;
    GlobalData().isLogin = false;
    GlobalData().SESSID = '';
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test('guest opens complete feed through public page when API needs captcha',
      () async {
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Success>());
    expect(
        (controller.feedState.value as Success).response.message, '完整的合成动态正文');
    final web = adapter.requests
        .singleWhere((request) => request.uri.host == 'www.coolapk.com');
    expect(web.uri.path, '/feed/123');
    expect(web.method, 'GET');
    expect(web.headers['X-App-Token'], startsWith('v3'));
    expect(web.headers, isNot(contains('Cookie')));
    expect(controller.articleList, isEmpty);
  });

  test('guest article renders all structured text and images', () async {
    final data = adapter.webBody['data'] as Map<String, dynamic>;
    data['title'] = '合成内核文章';
    data['message_raw_output'] = jsonEncode([
      {'type': 'text', 'message': '开头'},
      {'type': 'image', 'url': 'https://image.coolapk.com/synthetic.jpg'},
      {'type': 'text', 'message': '文章末尾'},
    ]);
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Success>());
    expect(controller.articleList!.map((block) => block.type),
        ['title', 'text', 'image', 'text']);
    expect(controller.articleList!.last.message, '文章末尾');
    expect(
        controller.articleImgList, ['https://image.coolapk.com/synthetic.jpg']);
  });

  test('public feed with a summary title keeps its full normal body and photos',
      () async {
    final data = adapter.webBody['data'] as Map<String, dynamic>;
    data['title'] = '分享页摘要标题';
    data['picArr'] = ['https://image.coolapk.com/synthetic-feed.jpg'];
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Success>());
    expect(controller.articleList, isEmpty);
    final feed = (controller.feedState.value as Success).response;
    expect(feed.message, '完整的合成动态正文');
    expect(feed.picArr, ['https://image.coolapk.com/synthetic-feed.jpg']);
  });

  test('successful API detail does not request the public page', () async {
    adapter.apiBody = {'data': adapter.webBody['data']};
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Success>());
    expect(adapter.requests.where((r) => r.uri.host == 'www.coolapk.com'),
        isEmpty);
  });

  test('without an imported identity detail and refresh never request replies',
      () async {
    adapter.apiBody = {'data': adapter.webBody['data']};
    var prompts = 0;
    Request().captchaVerifier = (_) async {
      prompts++;
      return null;
    };
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    while (controller.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    controller.onReset();
    await controller.onGetData();
    await controller.onGetData(false);
    expect(controller.feedState.value, isA<Success>());
    expect(adapter.requests.where((r) => r.uri.path.endsWith('/replyList')),
        isEmpty,
        reason: '${adapter.requests.map((r) => r.uri)}; '
            '${controller.loadingState.value}');
    expect(prompts, 0);
  });

  test('account switch during explicit comments leaves a retryable state',
      () async {
    adapter.apiBody = {'data': adapter.webBody['data']};
    final started = Completer<void>();
    final released = Completer<void>();
    adapter.beforeReply = () {
      started.complete();
      return released.future;
    };
    adapter.replyBody = {
      'data': [
        {
          'id': 456,
          'entityType': 'feed_reply',
          'message': 'old-session-comment'
        },
      ]
    };
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    final pending = controller.loadReplies();
    await started.future;
    GlobalData().sessionGeneration++;
    released.complete();
    await pending;
    expect(controller.loadingState.value, isA<Error>());
    expect((controller.loadingState.value as Error).errMsg, contains('已切换'));
    expect(controller.repliesDeferred.value, isTrue);
    expect(controller.isLoading, isFalse);
    adapter.beforeReply = null;
    adapter.replyBody = {'data': []};
    await controller.loadReplies();
    expect(controller.loadingState.value, isA<Empty>());
  });

  test('identity import on the existing controller resumes automatic comments',
      () async {
    adapter.apiBody = {'data': adapter.webBody['data']};
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.repliesDeferred.value, isTrue);
    await GStorage.settings.put(SettingsBoxKey.szlmId, 'synthetic-imported-id');
    controller.onReset();
    await controller.onGetData();
    expect(controller.repliesDeferred.value, isFalse);
    expect(controller.loadingState.value, isA<Empty>());
    expect(adapter.requests.where((r) => r.uri.path.endsWith('/replyList')),
        hasLength(1));
    await GStorage.settings.delete(SettingsBoxKey.szlmId);
    await controller.onGetData();
    expect(controller.repliesDeferred.value, isTrue);
    expect(adapter.requests.where((r) => r.uri.path.endsWith('/replyList')),
        hasLength(1));
  });

  test('imported identity keeps automatic comment loading', () async {
    await GStorage.settings.put(SettingsBoxKey.szlmId, 'synthetic-imported-id');
    adapter.apiBody = {'data': adapter.webBody['data']};
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    while (controller.isLoading) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(controller.loadingState.value, isA<Empty>());
    expect(adapter.requests.where((r) => r.uri.path.endsWith('/replyList')),
        hasLength(1));
  });

  test('explicit comment action verifies once and supports cancellation retry',
      () async {
    adapter.apiBody = {'data': adapter.webBody['data']};
    adapter.replyBody = {
      'messageStatus': 'err_request_captcha_v2',
      'messageExtra': {
        'captchaId': '0123456789abcdef0123456789abcdef',
        'captchaField': '_token',
      },
    };
    var prompts = 0;
    final started = Completer<void>();
    final cancelled = Completer<String?>();
    Request().captchaVerifier = (_) {
      prompts++;
      started.complete();
      return cancelled.future;
    };
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    final body = controller.feedState.value;
    final pending = controller.loadReplies();
    await started.future;
    await controller.loadReplies();
    expect(prompts, 1);
    cancelled.complete(null);
    await pending;
    expect(controller.loadingState.value, isA<Error>());
    expect(controller.feedState.value, same(body));
    controller.onReset();
    await controller.onGetData();
    expect(prompts, 1);
    Request().captchaVerifier = (challenge) async {
      prompts++;
      adapter.replyBody = {'data': []};
      return challenge.proof('synthetic-proof');
    };
    await controller.loadReplies();
    expect(controller.loadingState.value, isA<Empty>());
    expect(controller.feedState.value, same(body));
    expect(prompts, 2);
  });

  testWidgets('scrolling to comments shows an action without a request',
      (tester) async {
    adapter.apiBody = {
      'data': {
        ...(adapter.webBody['data'] as Map<String, dynamic>),
        'feedTypeName': '图文',
        'message_raw_output': jsonEncode(List.generate(
            12, (i) => {'type': 'text', 'message': '第 $i 段合成正文。' * 20})),
      }
    };
    await showFeed(tester, adapter);
    expect(find.byType(CustomScrollView), findsOneWidget);
    expect(find.textContaining('第 0 段合成正文。', findRichText: true), findsWidgets);
    // tonalIcon creates a private FilledButton subclass. byType(FilledButton)
    // is exact-type matching and can never find this actual production button.
    final action = find.text('加载评论并验证');
    final outerController = tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller;
    final scrollable = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byWidgetPredicate((widget) => widget is Scrollable && widget.controller == outerController));
    expect(scrollable, findsOneWidget);
    expect(action.hitTestable(), findsNothing);
    await tester.scrollUntilVisible(action, 400,
        scrollable: scrollable, maxScrolls: 50);
    await tester.pumpAndSettle();
    expect(action.hitTestable(), findsOneWidget);
    expect(
        find.ancestor(
            of: action,
            matching:
                find.byWidgetPredicate((widget) => widget is FilledButton)),
        findsOneWidget);
    await captureFeed(tester, 'comments-deferred');
    expect(adapter.requests.where((r) => r.uri.path.endsWith('/replyList')),
        isEmpty);
    final replyServed = Completer<void>();
    adapter.beforeReply = () async {
      replyServed.complete();
    };
    await tester.tap(action);
    await pumpUntil(
        tester,
        () =>
            replyServed.isCompleted && find.text('暂无内容').evaluate().isNotEmpty,
        'Explicit comment tap must finish and render the mock empty response');
    await tester.pumpAndSettle();
    expect(find.text('暂无内容'), findsOneWidget);
    await captureFeed(tester, 'comments-loaded-empty');
    expect(adapter.requests.where((r) => r.uri.path.endsWith('/replyList')),
        hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('app-only public page exposes verification and identity actions',
      (tester) async {
    adapter.webBody = '<html>请用酷安手机APP扫码查看详情</html>';
    await showFeed(tester, adapter);
    expect(find.textContaining('当前设备需要验证'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '导入官方设备标识'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);
    expect(find.byType(CustomScrollView), findsNothing);
    await captureFeed(tester, 'public-share-verification-required');
    final cancelled = Completer<void>();
    Request().captchaVerifier = (_) async {
      cancelled.complete();
      return null;
    };
    await tester.tap(find.text('重试'));
    await pumpUntil(
        tester,
        () =>
            cancelled.isCompleted &&
            find.textContaining('已取消验证').evaluate().isNotEmpty,
        'Cancelling verification must leave a visible retryable error');
    await tester.pumpAndSettle();
    expect(find.textContaining('已取消验证'), findsOneWidget);
    expect(find.text('导入官方设备标识'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(adapter.requests.where((r) => r.uri.path.endsWith('/replyList')),
        isEmpty);
    expect(tester.takeException(), isNull);
    await captureFeed(tester, 'public-share-verification-cancelled');
    await tester.pumpWidget(const SizedBox());
  });

  test('cancelled next-page verification preserves comments and pauses refresh',
      () async {
    adapter.apiBody = {'data': adapter.webBody['data']};
    adapter.replyBody = {
      'data': [
        {'id': 456, 'entityType': 'feed_reply', 'message': '已读评论'},
      ]
    };
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    await controller.loadReplies();
    final comments = controller.loadingState.value as Success;
    expect(comments.response.single.message, '已读评论');
    adapter.replyBody = {
      'messageStatus': 'err_request_captcha_v2',
      'messageExtra': {
        'captchaId': '0123456789abcdef0123456789abcdef',
        'captchaField': '_token',
      },
    };
    var prompts = 0;
    Request().captchaVerifier = (_) async {
      prompts++;
      return null;
    };
    await controller.onGetData(false);
    expect(controller.footerState.value, isA<Error>());
    expect(controller.loadingState.value, same(comments));
    controller.listType = 'dateline_desc';
    controller.onReset();
    await controller.onGetData();
    expect(prompts, 1);
    expect(controller.loadingState.value, same(comments));
    await controller.loadReplies();
    expect(prompts, 2);
    expect(controller.loadingState.value, same(comments));
    expect(controller.footerState.value, isA<Error>());
    expect(controller.repliesDeferred.value, isTrue);
    adapter.replyBody = {'data': []};
    await controller.loadReplies();
    expect(controller.loadingState.value, isA<Empty>());
    expect(adapter.requests.last.queryParameters['page'], 1);
    expect(adapter.requests.last.queryParameters['listType'], 'dateline_desc');
  });

  test('normal feed without structured article output remains readable',
      () async {
    (adapter.webBody['data'] as Map<String, dynamic>)
        .remove('message_raw_output');
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Success>());
    expect(controller.articleList, isEmpty);
  });

  test('malformed structured article reports an error without leaving loading',
      () async {
    (adapter.webBody['data'] as Map<String, dynamic>)['message_raw_output'] =
        '{broken';
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Error>());
    expect((controller.feedState.value as Error).errMsg, contains('解析'));
  });

  test('removed content is not retried as a public page', () async {
    adapter.apiBody = {'code': 404, 'message': '动态不存在'};
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Error>());
    expect(adapter.requests, hasLength(1));
  });

  test(
      'logged in captcha reads public body without changing login or like state',
      () async {
    GlobalData().isLogin = true;
    GlobalData().uid = 'synthetic-uid';
    GlobalData().token = 'synthetic-token';
    (adapter.webBody['data'] as Map<String, dynamic>)['userAction'] = {
      'like': 1
    };
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Success>());
    final result = controller.feedState.value as Success;
    expect(result.response.message, '完整的合成动态正文');
    expect(result.response.userAction, isNull);
    expect(GlobalData().isLogin, isTrue);
    expect(GlobalData().uid, 'synthetic-uid');
    expect(GlobalData().token, 'synthetic-token');
    final web =
        adapter.requests.singleWhere((r) => r.uri.host == 'www.coolapk.com');
    expect(web.headers, isNot(contains('Cookie')));
  });

  test('guest login requirement can read the official public representation',
      () async {
    adapter.apiBody = {'code': 401, 'messageStatus': 'err_not_login'};
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Success>());
    expect((controller.feedState.value as Success).response.id, 123);
  });

  test('rejected verified detail preserves public body and reports the failure',
      () async {
    GlobalData().isLogin = true;
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    final previous = controller.feedState.value;
    Request().captchaVerifier =
        (challenge) async => challenge.proof('synthetic-validate');
    await controller.getFeedData(verify: true);
    expect(controller.feedState.value, same(previous));
    expect((controller as dynamic).accountDetailNotice.value, contains('仍未'));
    expect(adapter.requests.where((r) => r.uri.host == 'www.coolapk.com'),
        hasLength(1));
  });

  test('cancelled verification keeps public body and explains cancellation',
      () async {
    GlobalData().isLogin = true;
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    final previous = controller.feedState.value;
    Request().captchaVerifier = (_) async => null;
    await controller.getFeedData(verify: true);
    expect(controller.feedState.value, same(previous));
    expect((controller as dynamic).accountDetailNotice.value, contains('取消'));
  });

  test('verified account detail replaces public body and clears the notice',
      () async {
    GlobalData().isLogin = true;
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    Request().captchaVerifier = (challenge) async {
      adapter.apiBody = {
        'data': {
          ...(adapter.webBody['data'] as Map<String, dynamic>),
          'userAction': {'like': 1},
        }
      };
      return challenge.proof('synthetic-validate');
    };
    await controller.getFeedData(verify: true);
    final result = controller.feedState.value as Success;
    expect(result.isPublic, isFalse);
    expect(result.response.userAction.like, 1);
    expect((controller as dynamic).accountDetailNotice.value, isEmpty);
  });

  test('invalid account article keeps previously readable public article',
      () async {
    (adapter.webBody['data'] as Map<String, dynamic>)['message_raw_output'] =
        jsonEncode([
      {'type': 'text', 'message': '公开文章完整正文'}
    ]);
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    final previous = controller.feedState.value;
    adapter.apiBody = {
      'data': {
        ...(adapter.webBody['data'] as Map<String, dynamic>),
        'message_raw_output': '{broken',
      }
    };
    await controller.getFeedData(verify: true);
    expect(controller.feedState.value, same(previous));
    expect(controller.articleList, hasLength(1));
    expect(controller.articleList!.single.message, '公开文章完整正文');
  });

  test('repeated detail retry taps open only one verification request',
      () async {
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    final started = Completer<void>();
    final proof = Completer<String?>();
    var prompts = 0;
    Request().captchaVerifier = (_) {
      prompts++;
      started.complete();
      return proof.future;
    };
    final pending = controller.getFeedData(verify: true);
    await started.future;
    await controller.getFeedData(verify: true);
    expect(prompts, 1);
    expect(adapter.requests.where((r) => r.uri.path == '/v6/feed/detail'),
        hasLength(2));
    proof.complete(null);
    await pending;
    expect((controller as dynamic).isLoadingDetail.value, isFalse);
  });

  test('invalid feed identifier never becomes an external request', () async {
    final controller = FeedController(id: '../account', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Error>());
    expect(adapter.requests, isEmpty);
  });

  test('public HTML landing page remains an error instead of fake content',
      () async {
    adapter.webBody = '<html>请下载客户端</html>';
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Error>());
    expect((controller.feedState.value as Error).errMsg, contains('响应'));
    expect(adapter.requests, hasLength(2));
  });

  test('official app-only landing page explains device verification', () async {
    adapter.webBody = '<html><title>动态分享 - 酷安</title>'
        '<div>您当前查看的是「动态分享」，请用酷安手机APP扫码查看详情</div></html>';
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    expect(controller.feedState.value, isA<Error>());
    final result = controller.feedState.value as Error;
    expect(result.errMsg, contains('设备需要验证'));
    expect(result.errMsg, isNot(contains('格式异常')));
    expect((result as dynamic).canVerify, isTrue);
    expect(adapter.requests, hasLength(2));
    expect(GlobalData().isLogin, isFalse);
  });

  test('unavailable public representation retains the original login reason',
      () async {
    adapter.apiBody = {'code': 401, 'messageStatus': 'err_not_login'};
    adapter.webBody = '<html><title>图文分享 - 酷安</title>'
        '<div>请用酷安手机APP扫码查看详情</div></html>';
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    final result = controller.feedState.value as Error;
    expect(result.errMsg, contains('登录'));
    expect((result as dynamic).canVerify, isTrue);
    expect(adapter.requests, hasLength(2));
  });

  for (final cancelled in [true, false]) {
    test(
        'failed verification keeps identity help without a readable body ($cancelled)',
        () async {
      adapter.webBody = '<html>请用酷安手机APP扫码查看详情</html>';
      final controller = FeedController(id: '123', recordHistory: false);
      await controller.getFeedData();
      Request().captchaVerifier = (challenge) async =>
          cancelled ? null : challenge.proof('synthetic-validation');
      await controller.getFeedData(verify: true);
      final result = controller.feedState.value as Error;
      expect(result.canVerify, isTrue);
      expect(result.errMsg, isNot(contains('正文仍可阅读')));
    });
  }

  Future<void> awaitMarkdown(WidgetTester tester) async {
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      final texts = tester.widgetList<FeedText>(find.byType(FeedText));
      if (texts.isNotEmpty && texts.every((text) => text.content != null) &&
          find.text('正在准备原文分段…').evaluate().isEmpty &&
          find.descendant(of: find.byType(FeedText),
              matching: find.byType(CircularProgressIndicator)).evaluate().isEmpty &&
          find.descendant(of: find.byType(FeedText), matching: find.byType(RichText)).evaluate().isNotEmpty) {
        return;
      }
    }
    fail('Detail parser did not publish within its bounded worker lifetime');
  }

  testWidgets(
    'actual detail overflow toggles exact source without fetching replies',
    (tester) async {
      const source = '# 合成标题\r\n\r\n**中文正文** 👩🏽‍💻 <!--break-->';
      adapter.apiBody = {
        'data': {...adapter.webBody['data'], 'message': source},
      };
      await showFeed(tester, adapter);
      await awaitMarkdown(tester);
      await tester.tap(find.byType(PopupMenuButton<FeedMenuItem>));
      await tester.pumpAndSettle();
      expect(find.text('查看原文'), findsOneWidget);
      await tester.tap(find.text('查看原文'));
      await tester.pumpAndSettle();
      expect(find.byType(FeedText), findsNothing);
      expect(find.text('原始正文'), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        source,
      );
      await tester.tap(find.byType(PopupMenuButton<FeedMenuItem>));
      await tester.pumpAndSettle();
      expect(find.text('格式化显示'), findsOneWidget);
      await tester.tap(find.text('格式化显示'));
      await awaitMarkdown(tester);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FeedText>(find.byType(FeedText)).forcePlain,
        isFalse,
      );
      expect(
        adapter.requests.where((r) => r.uri.path.endsWith('/replyList')),
        isEmpty,
      );
      expect(
        adapter.requests.where((r) => r.uri.path.endsWith('/detail')),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'account replacement clears raw source without an automatic reload',
    (tester) async {
      final source = '# 旧账号正文\n\n${List.filled(40, '合成正文。\n\n').join()}';
      adapter.apiBody = {
        'data': {...adapter.webBody['data'], 'message': source},
      };
      await showFeed(tester, adapter);
      await awaitMarkdown(tester);
      await tester.tap(find.byType(PopupMenuButton<FeedMenuItem>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看原文'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CustomScrollView>(find.byType(CustomScrollView))
            .controller!
            .offset,
        greaterThan(50),
      );
      final requests = adapter.requests.length;
      GlobalData().sessionGeneration++;
      GlobalData().uid = 'new-synthetic-account';
      GlobalData().isLogin = true;
      AccountStore.changes.value++;
      await tester.pumpAndSettle();
      expect(find.byType(FeedText), findsNothing);
      expect(find.text('账号已切换，请重新打开详情'), findsOneWidget);
      expect(adapter.requests, hasLength(requests));
      expect(find.byType(PopupMenuButton<FeedMenuItem>), findsNothing);
      expect(find.text('合成作者'), findsNothing);
      expect(tester.takeException(), isNull);
      adapter.apiBody = {
        'data': {...adapter.webBody['data'], 'message': '# 新账号正文'},
      };
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      await awaitMarkdown(tester);
      final body = tester.widget<FeedText>(find.byType(FeedText));
      expect(body.source, '# 新账号正文');
      expect(body.forcePlain, isFalse);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(tester.takeException(), isNull);
      GlobalData().sessionGeneration++;
      GlobalData().isLogin = false;
      GlobalData().uid = '';
      AccountStore.changes.value++;
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byType(FeedText), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ordinary detail does not offer an inapplicable source menu', (
    tester,
  ) async {
    adapter.apiBody = {'data': adapter.webBody['data']};
    await showFeed(tester, adapter);
    await awaitMarkdown(tester);
    await tester.tap(find.byType(PopupMenuButton<FeedMenuItem>));
    await tester.pumpAndSettle();
    expect(find.text('查看原文'), findsNothing);
    expect(find.text('复制'), findsOneWidget);
  });

  test(
    'stale detail response cannot publish source into a new account generation',
    () async {
      final original = adapter.apiBody;
      final started = Completer<void>(), released = Completer<void>();
      // The public fallback transport is held while the account owner changes.
      adapter.beforeDetail = () async {
        started.complete();
        await released.future;
      };
      adapter.apiBody = {'data': adapter.webBody['data']};
      final controller = FeedController(id: '123', recordHistory: false);
      final pending = controller.getFeedData();
      await started.future;
      GlobalData().sessionGeneration++;
      released.complete();
      await pending;
      expect(controller.feedState.value, isA<Error>());
      expect(controller.bodySnapshot.value, isNull);
      controller.onClose();
      adapter.apiBody = original;
    },
  );

  testWidgets(
    'structured article publishes formatting and raw fields remain exact/inert',
    (tester) async {
      const raw = '[  {"type":"text","message":"# 文章标题\\n\\n**正文**"}, '
          '{"type":"shareUrl","title":"资料","url":"https://example.com"}  ]';
      adapter.apiBody = {
        'data': {
          ...adapter.webBody['data'],
          'title': '原始标题 &amp; 👩🏽‍💻',
          'message_cover': null,
          'message_raw_output': raw,
        },
      };
      await showFeed(tester, adapter);
      // No menu opening or scrolling: the outer reactive subscription must
      // rebuild lazily-created article text when the worker publishes.
      await awaitMarkdown(tester);
      expect(tester.widgetList<FeedText>(find.byType(FeedText)), isNotEmpty);
      expect(tester.widgetList<FeedText>(find.byType(FeedText))
          .every((text) => text.content != null), isTrue);
      expect(find.text('正在准备排版，暂显示原文'), findsNothing);
      await tester.tap(find.byType(PopupMenuButton<FeedMenuItem>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看原文'));
      await tester.pumpAndSettle();
      expect(find.text('原始结构化正文（JSON）'), findsOneWidget);
      expect(find.text('服务端未提供此字段'), findsOneWidget);
      final rawTexts = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((w) => w.data);
      expect(rawTexts, contains(raw));
      expect(rawTexts, contains('原始标题 &amp; 👩🏽‍💻'));
      expect(find.text('资料'), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(
        adapter.requests.where((r) => r.uri.host == 'example.com'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'raw page two and its independent pixel offset survive format round trip',
    (tester) async {
      final source =
          '# 标题\n\n${List.filled(400, '中文正文连续内容。👩🏽‍💻\n\n').join()}';
      expect(source.length, greaterThan(4000));
      adapter.apiBody = {
        'data': {...adapter.webBody['data'], 'message': source},
      };
      await showFeed(tester, adapter);
      await awaitMarkdown(tester);
      await tester.pumpAndSettle();
      final scroll = tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!;
      scroll.jumpTo(80);
      await tester.pumpAndSettle();
      final formattedOffset = scroll.offset;
      expect(formattedOffset, greaterThan(50));
      await tester.tap(find.byType(PopupMenuButton<FeedMenuItem>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看原文'));
      await tester.pump();
      Future<void> waitForPage() async {
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
          if (find.byType(SelectableText).evaluate().isNotEmpty) return;
        }
        fail('Raw page did not prepare');
      }

      await waitForPage();
      await tester.ensureVisible(find.text('下一段'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一段'));
      await tester.pump();
      await waitForPage();
      final second =
          tester.widget<SelectableText>(find.byType(SelectableText)).data;
      await tester.pump();
      expect(
        tester.getTopLeft(find.byType(SelectableText)).dy,
        lessThan(150),
        reason:
            'Next raw page must reveal its beginning, not retain the previous page bottom',
      );
      scroll.jumpTo(120);
      await tester.pumpAndSettle();
      final offset = scroll.offset;
      expect(offset, greaterThan(50));
      await tester.tap(find.byType(PopupMenuButton<FeedMenuItem>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('格式化显示'));
      await awaitMarkdown(tester);
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(formattedOffset, 1));
      await tester.tap(find.byType(PopupMenuButton<FeedMenuItem>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看原文'));
      await tester.pump();
      await waitForPage();
      await tester.pumpAndSettle();
      expect(find.text('原文第 2 段'), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        second,
      );
      expect(scroll.offset, closeTo(offset, 1));
      expect(tester.takeException(), isNull);
    },
  );
  test('same-body metadata refresh retains raw position, changed body clears it', () async {
    adapter.apiBody = {'data': {...adapter.webBody['data'], 'message': '# 原始正文'}};
    final controller = FeedController(id: '123', recordHistory: false);
    await controller.getFeedData();
    final original = controller.bodySnapshot.value!;
    final position = controller.sourcePositionFor('@raw:message');
    position.offsets.add(20); position.splitEnds.add(0); position.index = 1;
    adapter.apiBody = {'data': {...adapter.webBody['data'], 'message': '# 原始正文', 'likenum': 12}};
    await controller.getFeedData();
    expect(controller.bodySnapshot.value!.sameBody(original), isTrue);
    expect(controller.sourcePositionFor('@raw:message'), same(position));
    expect(position.index, 1);
    adapter.apiBody = {'data': {...adapter.webBody['data'], 'message': '# 更新正文'}};
    await controller.getFeedData();
    expect(controller.bodySnapshot.value!.sameBody(original), isFalse);
    expect(controller.sourcePositionFor('@raw:message').index, 0);
    expect(controller.sourcePositionFor('@raw:message'), isNot(same(position)));
    controller.onClose();
  });

  testWidgets('account changes before a queued source-layout callback cannot restore old content', (tester) async {
    adapter.apiBody = {'data': {...adapter.webBody['data'], 'message': '# 原始正文'}};
    await showFeed(tester, adapter);
    await awaitMarkdown(tester);
    final menu = tester.widget<PopupMenuButton<FeedMenuItem>>(find.byType(PopupMenuButton<FeedMenuItem>));
    menu.onSelected!(FeedMenuItem.Source);
    GlobalData().sessionGeneration++;
    AccountStore.changes.value++;
    await tester.pumpAndSettle();
    expect(find.byType(RawSourceText), findsNothing);
    expect(find.byType(FeedText), findsNothing);
    expect(find.byType(PopupMenuButton<FeedMenuItem>), findsNothing);
    expect(tester.takeException(), isNull);
  });

}
