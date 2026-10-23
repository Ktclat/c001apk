import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:c001apk_flutter/components/cards/feed_card.dart';
import 'package:c001apk_flutter/components/cards/feed_reply_card.dart';
import 'package:c001apk_flutter/logic/model/feed/datum.dart';
import 'package:c001apk_flutter/pages/others/imageview_page.dart';
import 'package:c001apk_flutter/utils/app_theme.dart';
import 'package:c001apk_flutter/utils/global_data.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:c001apk_flutter/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

const galleryFixtureRoot = 'test/fixtures/gallery';
const galleryA = 'https://fixture.invalid/gallery-a@160x100.png';
const galleryB = 'https://fixture.invalid/gallery-b@100x160.png';
const galleryC = 'https://fixture.invalid/gallery-c@160x100.png';
final captureKey = GlobalKey();
final localFixtureFiles = <String, FileInfo>{};

class CacheRequest {
  CacheRequest(this.url, this.key, this.headers);
  final String url;
  final String? key;
  final Map<String, String>? headers;
  final events = StreamController<FileResponse>();
  final failure = StateError('Synthetic offline image failure');
  void progress(int received, int? total) =>
      events.add(DownloadProgress(url, total, received));
  void fail() {
    events.addError(failure);
    events.close();
  }

  void image([String name = 'landscape.png']) {
    frame(name);
    events.close();
  }

  void frame([String name = 'landscape.png']) {
    events.add(FileInfo(localFixtureFiles[name]!.file, FileSource.Cache,
        DateTime.utc(2100), url));
  }
}

/// No HTTP client exists in this backend. Production CachedNetworkImageProvider
/// consumes real progress, failure and local-file decode events through it.
class ControlledCache extends BaseCacheManager {
  final requests = <CacheRequest>[];
  final removed = <String>[];
  Completer<void>? removalGate;
  bool failRemoval = false;
  @override
  Stream<FileResponse> getFileStream(String url,
      {String? key, Map<String, String>? headers, bool withProgress = false}) {
    final request = CacheRequest(url, key, headers);
    requests.add(request);
    return request.events.stream;
  }

  List<CacheRequest> forUrl(String url) =>
      requests.where((r) => r.url == url).toList();
  CacheRequest latest(String url) => forUrl(url).last;
  @override
  Future<void> removeFile(String key) async {
    removed.add(key);
    await removalGate?.future;
    if (failRemoval) {
      throw const FileSystemException('Synthetic removal failure');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> settleRoute(WidgetTester tester) async {
  // One pump starts a newly scheduled route transition; the next advances it.
  // Do not pumpAndSettle while intentionally pending images animate spinners.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

Future<void> settlePager(WidgetTester tester, int expectedPage) async {
  final controller = tester.widget<PageView>(find.byType(PageView)).controller!;
  await tester.pump();
  for (var frame = 0;
      frame < 240 && controller.position.isScrollingNotifier.value;
      frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  final allRetry = find.ancestor(
      of: find.text('重试本图'),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton));
  final state = 'page=${controller.page}, '
      'scrolling=${controller.position.isScrollingNotifier.value}, '
      'retryCount=${allRetry.evaluate().length}, '
      'retryHitCount=${allRetry.hitTestable().evaluate().length}, '
      'retryBounds=${allRetry.evaluate().map((e) => tester.getRect(find.byWidget(e.widget))).toList()}';
  debugPrint('Settled pager: $state');
  expect(controller.position.isScrollingNotifier.value, isFalse, reason: state);
  expect(controller.page, closeTo(expectedPage, .001), reason: state);
}

Future<void> flushImages(WidgetTester tester) async {
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 60 && !ready(); i++) {
    await flushImages(tester);
  }
  expect(ready(), isTrue, reason: 'Offline image event did not complete');
}

Future<void> assertDecoded(WidgetTester tester,
    {Finder? inside, int width = 160, int height = 100}) async {
  final raw = inside == null
      ? find.byType(RawImage).hitTestable()
      : find
          .descendant(of: inside, matching: find.byType(RawImage))
          .hitTestable();
  await until(
      tester,
      () => raw.evaluate().any((e) {
            final image = (e.widget as RawImage).image;
            return image?.width == width && image?.height == height;
          }));
  expect(
      raw.evaluate().any((e) {
        final image = (e.widget as RawImage).image;
        return image?.width == width && image?.height == height;
      }),
      isTrue,
      reason: 'Success requires decoded original PNG pixels');
}

Future<void> captureGallery(WidgetTester tester, String name,
    {bool success = false,
    int width = 160,
    int height = 100,
    double pixelRatio = 2}) async {
  if (success) await assertDecoded(tester, width: width, height: height);
  final destination = Platform.environment['GALLERY_EVIDENCE'];
  if (destination == null) return;
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(destination).create(recursive: true);
    await File('$destination/$name.png')
        .writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
}

Datum galleryDatum(List<String> images) => Datum.fromJson({
      'id': 7001,
      'entityType': 'feed',
      'fetchType': 'feed_reply',
      'feedTypeName': '动态',
      'uid': 700,
      'dateline': 1760000000,
      'userInfo': {'uid': 700, 'username': '离线图库测试'},
      'message': '原始离线图片，验证查看与返回位置。',
      'message_raw_output': '[]',
      'likenum': 0,
      'replynum': 0,
      'picArr': images,
    });

Widget galleryHarness({
  Widget Function()? page,
  List<String> images = const [galleryA, galleryB, galleryA],
  bool reply = false,
  double scale = 1,
  ScrollController? scrollController,
}) =>
    RepaintBoundary(
      key: captureKey,
      child: GetMaterialApp(
        debugShowCheckedModeBanner: false,
        theme: applyAppTypography(ThemeData(
          useMaterial3: true,
          platform: TargetPlatform.android,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6650A4)),
        )),
        navigatorObservers: [FlutterSmartDialog.observer],
        builder: (context, child) => FlutterSmartDialog.init()(
            context,
            MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            )),
        getPages: [
          GetPage(name: '/imageview', page: page ?? () => const ImageViewPage())
        ],
        home: Scaffold(
          appBar: AppBar(title: Text(reply ? '离线评论入口' : '离线动态入口')),
          body: ListView(
            controller: scrollController,
            children: [
              if (scrollController != null) const SizedBox(height: 360),
              if (reply)
                FeedReplyCard(data: galleryDatum(images))
              else
                FeedCard(data: galleryDatum(images), isFeedContent: true),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      ),
    );

Future<void> openGallery(WidgetTester tester, List<String> images,
    {int initial = 0}) async {
  Get.toNamed('/imageview',
      arguments: {'imgList': images, 'initialPage': initial});
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

class GalleryEnvironment {
  late Directory temp;
  late bool originalDesktop;
  Future<void> setUp() async {
    originalDesktop = Utils.isDesktop;
    Utils.isDesktop = false;
    temp = await Directory.systemTemp.createTemp('gallery-offline-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
    GStorage.blackList = await Hive.openBox('blackList');
    GlobalData().isLogin = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => temp.path);
    final fileSystem = IOFileSystem('gallery-local-fixtures');
    for (final name in [
      'landscape.png',
      'portrait.png',
      'extreme-wide.png',
      'corrupt.png'
    ]) {
      final file = await fileSystem.createFile(name);
      await file
          .writeAsBytes(await File('$galleryFixtureRoot/$name').readAsBytes());
      localFixtureFiles[name] =
          FileInfo(file, FileSource.Cache, DateTime.utc(2100), name);
    }
    final font = FontLoader(AppFontChoice.bundledFontFamily);
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(File('assets/fonts/NotoSansCJKsc-$weight.otf')
          .readAsBytes()
          .then(ByteData.sublistView));
    }
    await font.load();
    final root = Platform.environment['FLUTTER_ROOT']!;
    final icons = FontLoader('MaterialIcons')
      ..addFont(File(
              '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then(ByteData.sublistView));
    await icons.load();
  }

  Future<void> tearDown() async {
    Utils.isDesktop = originalDesktop;
    localFixtureFiles.clear();
    await Hive.close();
    await temp.delete(recursive: true);
  }
}
