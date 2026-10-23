import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:c001apk_flutter/components/retryable_media_image.dart';
import 'package:c001apk_flutter/components/nine_grid_view.dart';
import 'package:c001apk_flutter/components/imageview.dart' as media;
import 'package:c001apk_flutter/pages/others/imageview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:photo_view/photo_view.dart';

import 'gallery_test_support.dart';

Finder get viewer => find.byType(ImageViewPage);
Finder get retry => find
    .ancestor(
        of: find.text('重试本图'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton))
    .hitTestable();
Finder thumbnails() => find.byWidgetPredicate(
    (widget) => widget is RetryableMediaImage && !widget.isGallery);

class LocalFileResponse implements FileServiceResponse {
  LocalFileResponse(this.bytes);
  final List<int> bytes;
  @override
  Stream<List<int>> get content => Stream.value(bytes);
  @override
  int get contentLength => bytes.length;
  @override
  int get statusCode => 200;
  @override
  DateTime get validTill => DateTime.utc(2100);
  @override
  String? get eTag => null;
  @override
  String get fileExtension => '.png';
}

class OfflineFileService extends FileService {
  final calls = <String>[];
  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    calls.add(url);
    final name = calls.length == 1 ? 'corrupt.png' : 'landscape.png';
    return LocalFileResponse(
        await File('$galleryFixtureRoot/$name').readAsBytes());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final environment = GalleryEnvironment();
  late ControlledCache cache;
  setUpAll(environment.setUp);
  tearDownAll(environment.tearDown);
  setUp(() {
    cache = ControlledCache();
    CachedNetworkImageProvider.defaultCacheManager = cache;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  void galleryTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        Get.reset();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      }
    });
  }

  Future<void> start(WidgetTester tester,
      {List<String> images = const [galleryA],
      int initial = 0,
      double scale = 1}) async {
    await tester.pumpWidget(galleryHarness(images: const [], scale: scale));
    await openGallery(tester, images, initial: initial);
    if (images.isNotEmpty) {
      await until(
          tester,
          () => cache
              .forUrl(images[initial.clamp(0, images.length - 1)])
              .isNotEmpty);
    }
  }

  galleryTest('unknown zero normal and over-total progress are safe',
      (tester) async {
    await start(tester);
    final progress = find.descendant(
        of: viewer, matching: find.byType(CircularProgressIndicator));
    expect(tester.widget<CircularProgressIndicator>(progress).value, isNull);
    for (final sample in [
      (20, null, null),
      (0, 0, null),
      (50, 100, .5),
      (150, 100, 1.0)
    ]) {
      cache.latest(galleryA).progress(sample.$1, sample.$2);
      await flushImages(tester);
      expect(
          tester.widget<CircularProgressIndicator>(progress).value, sample.$3);
      expect(tester.takeException(), isNull);
      await captureGallery(tester, 'progress-${sample.$2}-${sample.$1}');
    }
    cache.latest(galleryA).image();
    await assertDecoded(tester, inside: viewer);
    expect(progress, findsNothing);
    await captureGallery(tester, 'viewer-ready', success: true);
  });

  galleryTest('explicit retry is single-flight and decodes the original PNG',
      (tester) async {
    await start(tester);
    cache.latest(galleryA).fail();
    await until(tester, () => retry.evaluate().isNotEmpty);
    expect(find.text('图片加载失败'), findsOneWidget);
    await captureGallery(tester, 'viewer-error');
    final button = tester.widget<FilledButton>(retry);
    cache.removalGate = Completer<void>();
    button.onPressed!();
    button.onPressed!();
    await tester.pump();
    expect(cache.removed, [galleryA]);
    expect(cache.forUrl(galleryA), hasLength(1));
    expect(retry, findsNothing);
    cache.removalGate!.complete();
    await until(tester, () => cache.forUrl(galleryA).length == 2);
    cache.latest(galleryA).image();
    await assertDecoded(tester, inside: viewer);
    expect(find.text('图片加载失败'), findsNothing);
    expect(cache.forUrl(galleryA), hasLength(2));
    await captureGallery(tester, 'viewer-retry-ready', success: true);
  });

  galleryTest('repeated failure has no automatic retry including page revisit',
      (tester) async {
    await start(tester, images: [galleryA, galleryB]);
    cache.latest(galleryA).fail();
    await until(tester, () => retry.evaluate().isNotEmpty);
    await tester.tap(retry);
    await until(tester, () => cache.forUrl(galleryA).length == 2);
    cache.latest(galleryA).fail();
    await until(tester, () => retry.evaluate().isNotEmpty);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 5));
      await flushImages(tester);
    }
    expect(cache.forUrl(galleryA), hasLength(2));
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await settlePager(tester, 1);
    await until(tester, () => cache.forUrl(galleryB).isNotEmpty);
    cache.latest(galleryB).image('portrait.png');
    await assertDecoded(tester, inside: viewer, width: 100, height: 160);
    await tester.drag(find.byType(PageView), const Offset(350, 0));
    await settlePager(tester, 0);
    expect(find.text('1/2'), findsOneWidget);
    expect(retry.hitTestable(), findsOneWidget);
    expect(cache.forUrl(galleryA), hasLength(2));
    expect(cache.removed, [galleryA]);
    await tester.tap(retry);
    await until(tester, () => cache.forUrl(galleryA).length == 3);
    cache.latest(galleryA).fail();
    await until(tester, () => retry.evaluate().isNotEmpty);
    expect(cache.removed, [galleryA, galleryA]);
    expect(tester.takeException(), isNull);
  });

  galleryTest('late previous page completion cannot replace current image',
      (tester) async {
    await start(tester, images: [galleryA, galleryB, galleryC]);
    final old = cache.latest(galleryA);
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await settleRoute(tester);
    await until(tester, () => cache.forUrl(galleryB).isNotEmpty);
    cache.latest(galleryB).image('portrait.png');
    await assertDecoded(tester, inside: viewer, width: 100, height: 160);
    old.image();
    await flushImages(tester);
    expect(find.text('2/3'), findsOneWidget);
    await assertDecoded(tester, inside: viewer, width: 100, height: 160);
    await captureGallery(tester, 'late-page-stays-second',
        success: true, width: 100, height: 160);
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await settleRoute(tester);
    await until(tester, () => cache.forUrl(galleryC).isNotEmpty);
    final pending = cache.latest(galleryC);
    await tester.pageBack();
    await settleRoute(tester);
    pending.image();
    await flushImages(tester);
    expect(viewer, findsNothing);
    expect(tester.takeException(), isNull);
  });

  galleryTest(
      'successful disposed page resolves fresh loading error and explicit retry',
      (tester) async {
    await start(tester, images: [
      galleryA,
      galleryB,
      galleryC,
      'https://fixture.invalid/fourth.png'
    ]);
    cache.latest(galleryA).image();
    await assertDecoded(tester, inside: viewer);
    final previousProvider = tester
        .widget<PhotoView>(find.byType(PhotoView).hitTestable())
        .imageProvider!;
    final pager = tester.widget<PageView>(find.byType(PageView)).controller!;
    pager.jumpToPage(3);
    await tester.pump();
    await settleRoute(tester);
    expect(
        find.byWidgetPredicate(
            (w) => w is RetryableMediaImage && w.isGallery && w.index == 0),
        findsNothing);
    await tester.runAsync(previousProvider.evict);
    pager.jumpToPage(0);
    await tester.pump();
    await until(tester, () => cache.forUrl(galleryA).length == 2);
    expect(
        find
            .descendant(
                of: viewer, matching: find.byType(CircularProgressIndicator))
            .hitTestable(),
        findsOneWidget);
    cache.latest(galleryA).fail();
    await until(tester, () => retry.hitTestable().evaluate().isNotEmpty);
    await tester.tap(retry);
    await until(tester, () => cache.forUrl(galleryA).length == 3);
    cache.latest(galleryA).image();
    await assertDecoded(tester, inside: viewer);
    expect(find.text('1/4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  galleryTest(
      'failed cache eviction remains visible and closing cancels late retry',
      (tester) async {
    await start(tester);
    cache.latest(galleryA).fail();
    await until(tester, () => retry.evaluate().isNotEmpty);
    cache.failRemoval = true;
    await tester.tap(retry);
    await until(tester, () => find.text('重试准备失败，请再试一次').evaluate().isNotEmpty);
    expect(retry, findsOneWidget);
    expect(cache.forUrl(galleryA), hasLength(1));
    cache.failRemoval = false;
    cache.removalGate = Completer<void>();
    await tester.tap(retry);
    await tester.pump();
    await tester.pageBack();
    await settleRoute(tester);
    cache.removalGate!.complete();
    await flushImages(tester);
    expect(cache.forUrl(galleryA), hasLength(1));
    expect(viewer, findsNothing);
    expect(tester.takeException(), isNull);
  });

  galleryTest('same URL ordinals retry only the selected failed page',
      (tester) async {
    await start(tester, images: [galleryA, galleryA, galleryB]);
    cache.latest(galleryA).fail();
    await until(tester, () => retry.evaluate().isNotEmpty);
    final pager = tester.widget<PageView>(find.byType(PageView)).controller!;
    pager.jumpToPage(1);
    await tester.pump();
    await until(tester, () => cache.forUrl(galleryA).length == 2);
    cache.latest(galleryA).fail();
    await until(tester, () => retry.hitTestable().evaluate().isNotEmpty);
    await tester.tap(retry.hitTestable());
    await until(tester, () => cache.forUrl(galleryA).length == 3);
    cache.latest(galleryA).image();
    await assertDecoded(tester, inside: viewer);
    expect(find.text('2/3'), findsOneWidget);
    expect(cache.removed, [galleryA]);
    final current = tester.widget<RetryableMediaImage>(find.byWidgetPredicate(
        (w) => w is RetryableMediaImage && w.isGallery && w.index == 1));
    expect(current.attempt!.generation, 1);
    pager.jumpToPage(0);
    await tester.pump();
    expect(retry.hitTestable(), findsOneWidget);
    expect(cache.forUrl(galleryA), hasLength(3));
    final previous = tester.widget<RetryableMediaImage>(find.byWidgetPredicate(
        (w) => w is RetryableMediaImage && w.isGallery && w.index == 0));
    expect(previous.attempt!.generation, 0);
    expect(tester.takeException(), isNull);
  });

  galleryTest('closed retry cleanup cannot evict a reopened route request',
      (tester) async {
    await start(tester);
    cache.latest(galleryA).fail();
    await until(tester, () => retry.evaluate().isNotEmpty);
    cache.removalGate = Completer<void>();
    await tester.tap(retry);
    await tester.pump();
    await tester.pageBack();
    await settleRoute(tester);
    expect(viewer, findsNothing);
    await openGallery(tester, [galleryA]);
    await until(tester, () => cache.forUrl(galleryA).length == 2);
    final provider = tester
        .widget<PhotoView>(find.byType(PhotoView).hitTestable())
        .imageProvider!;
    final key = await tester
        .runAsync(() => provider.obtainKey(ImageConfiguration.empty));
    expect(
        PaintingBinding.instance.imageCache.statusForKey(key!).pending, isTrue);
    cache.removalGate!.complete();
    await flushImages(tester);
    expect(
        PaintingBinding.instance.imageCache.statusForKey(key).pending, isTrue);
    cache.latest(galleryA).image();
    await assertDecoded(tester, inside: viewer);
    expect(cache.forUrl(galleryA), hasLength(2));
    expect(Get.currentRoute, '/imageview');
    expect(tester.takeException(), isNull);
  });

  galleryTest('late retry cleanup cannot evict another ordinal pending image',
      (tester) async {
    await start(tester, images: [galleryA, galleryA, galleryB]);
    cache.latest(galleryA).fail();
    await until(tester, () => retry.evaluate().isNotEmpty);
    cache.removalGate = Completer<void>();
    await tester.tap(retry);
    await tester.pump();
    final pager = tester.widget<PageView>(find.byType(PageView)).controller!;
    pager.jumpToPage(1);
    await settleRoute(tester);
    await until(tester, () => cache.forUrl(galleryA).length == 2);
    final provider = tester
        .widget<PhotoView>(find.byType(PhotoView).hitTestable())
        .imageProvider!;
    final key = await tester
        .runAsync(() => provider.obtainKey(ImageConfiguration.empty));
    expect(
        PaintingBinding.instance.imageCache.statusForKey(key!).pending, isTrue);
    cache.removalGate!.complete();
    await flushImages(tester);
    expect(
        PaintingBinding.instance.imageCache.statusForKey(key).pending, isTrue);
    expect(retry, findsNothing);
    cache.latest(galleryA).image();
    await assertDecoded(tester, inside: viewer);
    expect(find.text('2/3'), findsOneWidget);
    expect(cache.forUrl(galleryA), hasLength(2));
    pager.jumpToPage(0);
    await settleRoute(tester);
    await assertDecoded(tester, inside: viewer);
    expect(cache.forUrl(galleryA), hasLength(2));
    expect(tester.takeException(), isNull);
  });

  galleryTest('error after a cached first frame still needs one explicit retry',
      (tester) async {
    await start(tester);
    final request = cache.latest(galleryA);
    request.frame();
    await assertDecoded(tester, inside: viewer);
    final provider = tester
        .widget<PhotoView>(find.byType(PhotoView).hitTestable())
        .imageProvider!;
    final key = await tester
        .runAsync(() => provider.obtainKey(ImageConfiguration.empty));
    expect(PaintingBinding.instance.imageCache.statusForKey(key!).keepAlive,
        isTrue);
    request.fail();
    await until(tester, () => retry.evaluate().isNotEmpty);
    expect(PaintingBinding.instance.imageCache.statusForKey(key).untracked,
        isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(cache.forUrl(galleryA), hasLength(1));
    await tester.tap(retry);
    await until(tester, () => cache.forUrl(galleryA).length == 2);
    cache.latest(galleryA).image();
    await assertDecoded(tester, inside: viewer);
    expect(cache.forUrl(galleryA), hasLength(2));
    expect(tester.takeException(), isNull);
  });

  galleryTest('old disposed mount error cannot poison a fresh pending stream',
      (tester) async {
    await start(tester, images: [
      galleryA,
      galleryB,
      galleryC,
      'https://fixture.invalid/fourth.png'
    ]);
    final old = cache.latest(galleryA);
    // Observe this intentionally abandoned stream's expected error, without
    // suppressing other Flutter errors or holding a production image alive.
    final previousProvider = tester
        .widget<PhotoView>(find.byType(PhotoView).hitTestable())
        .imageProvider!;
    final oldStream = previousProvider.resolve(ImageConfiguration.empty);
    Object? observedOldError;
    final observer = ImageStreamListener((info, _) => info.dispose(),
        onError: (Object error, StackTrace? stack) => observedOldError = error);
    oldStream.addListener(observer);
    addTearDown(() => oldStream.removeListener(observer));
    final pager = tester.widget<PageView>(find.byType(PageView)).controller!;
    pager.jumpToPage(3);
    await tester.pump();
    await settleRoute(tester);
    await tester.runAsync(previousProvider.evict);
    pager.jumpToPage(0);
    await tester.pump();
    await until(tester, () => cache.forUrl(galleryA).length == 2);
    final currentProvider = tester
        .widget<PhotoView>(find.byType(PhotoView).hitTestable())
        .imageProvider!;
    final currentKey = await tester
        .runAsync(() => currentProvider.obtainKey(ImageConfiguration.empty));
    expect(currentProvider, previousProvider,
        reason: 'Normal revisits keep a stable memory cache key');
    expect(currentProvider.resolve(ImageConfiguration.empty).completer,
        isNot(same(oldStream.completer)));
    expect(cache.forUrl(galleryA), hasLength(2));
    expect(
        PaintingBinding.instance.imageCache.statusForKey(currentKey!).pending,
        isTrue);
    old.fail();
    await flushImages(tester);
    expect(observedOldError, same(old.failure));
    expect(PaintingBinding.instance.imageCache.statusForKey(currentKey).pending,
        isTrue,
        reason:
            'An old URL failure must not evict the current mount cache entry');
    expect(retry.hitTestable(), findsNothing);
    expect(
        find
            .descendant(
                of: viewer, matching: find.byType(CircularProgressIndicator))
            .hitTestable(),
        findsOneWidget);
    cache.latest(galleryA).image();
    await assertDecoded(tester, inside: viewer);
    expect(find.text('1/4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  galleryTest('media cache cleans failure and reuses success without listeners',
      (tester) async {
    const diskKey = 'ordinary-media-exact-key';
    const headers = {'X-Offline-Fixture': 'unchanged'};
    MediaImageAttempt newAttempt() => MediaImageAttempt(galleryA, 0,
        providerBuilder: (_, __, ___) => const CachedNetworkImageProvider(
            galleryA,
            cacheKey: diskKey,
            headers: headers));
    final first = newAttempt();
    final second = newAttempt();
    final sentinel = MediaImageAttempt(galleryB, 1);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(sentinel.dispose);
    final streams = <ImageStream>[];
    final errors = <Object>[];
    final listener = ImageStreamListener((info, _) => info.dispose(),
        onError: (error, stack) => errors.add(error));
    ImageStream observe(ImageProvider provider) {
      final stream = provider.resolve(ImageConfiguration.empty);
      stream.addListener(listener);
      streams.add(stream);
      return stream;
    }

    addTearDown(() {
      for (final stream in streams) {
        stream.removeListener(listener);
      }
    });
    observe(first.provider);
    final unrelated = observe(sentinel.provider);
    await until(tester, () => cache.requests.length == 2);
    final failed = cache.latest(galleryA);
    expect(failed.key, diskKey);
    expect(failed.headers, headers);
    cache.latest(galleryB).image('portrait.png');
    failed.fail();
    await flushImages(tester);
    expect(errors, [same(failed.failure)]);
    final key = await tester
        .runAsync(() => first.provider.obtainKey(ImageConfiguration.empty));
    final sentinelKey = await tester
        .runAsync(() => sentinel.provider.obtainKey(ImageConfiguration.empty));
    final imageCache = PaintingBinding.instance.imageCache;
    expect(imageCache.statusForKey(key!).untracked, isTrue);
    await until(tester, () => imageCache.statusForKey(sentinelKey!).keepAlive);
    expect(second.provider, first.provider);
    final recovered = observe(second.provider);
    await until(tester, () => cache.forUrl(galleryA).length == 2);
    expect(cache.latest(galleryA).key, diskKey);
    expect(cache.latest(galleryA).headers, headers);
    cache.latest(galleryA).image();
    await until(tester, () => imageCache.statusForKey(key).keepAlive);
    expect(imageCache.statusForKey(sentinelKey!).keepAlive, isTrue);
    expect(cache.forUrl(galleryB), hasLength(1));
    recovered.removeListener(listener);
    streams.remove(recovered);
    expect(recovered.completer!.hasListeners, isFalse,
        reason: 'Cache cleanup must not retain a permanent image listener');
    final reopened = observe(first.provider);
    expect(reopened.completer, same(recovered.completer));
    expect(cache.forUrl(galleryA), hasLength(2));
    expect(unrelated.completer!.hasListeners, isTrue);
    expect(tester.takeException(), isNull);
  });

  galleryTest('extremely wide single image keeps a stable 48dp viewing target',
      (tester) async {
    const url = 'https://fixture.invalid/wide@1000x1.png';
    await tester.pumpWidget(GetMaterialApp(
      getPages: [
        GetPage(name: '/imageview', page: () => const ImageViewPage())
      ],
      home: Scaffold(body: Center(child: media.image(310, [url]))),
    ));
    await flushImages(tester);
    final tile = thumbnails().first;
    final loading = tester.getRect(tile);
    expect(loading.height, 48);
    expect(loading.width, 310);
    cache.requests.single.fail();
    await flushImages(tester);
    expect(tester.getRect(tile), loading);
    await tester.tapAt(loading.topLeft + const Offset(20, 10));
    await settleRoute(tester);
    expect(find.text('1/1'), findsOneWidget);
    await tester.pageBack();
    await settleRoute(tester);
    expect(tester.getRect(tile), loading);
    // A separate successful mount exercises the identical geometry with pixels.
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: media.image(310, [url])))));
    await flushImages(tester);
    final request = cache.requests.last;
    request.image('extreme-wide.png');
    await assertDecoded(tester, inside: thumbnails(), width: 1000, height: 1);
    expect(tester.getRect(thumbnails()), loading);
    final rawSource = tester.widget<Image>(
        find.descendant(of: thumbnails(), matching: find.byType(Image)));
    expect(rawSource.fit, BoxFit.contain);
    expect(tester.takeException(), isNull);
  });

  galleryTest('corrupt real disk cache is removed only by explicit retry',
      (tester) async {
    final service = OfflineFileService();
    late CacheManager disk;
    await tester.runAsync(() async {
      disk = CacheManager(Config('gallery-real-cache',
          repo: JsonCacheInfoRepository(
              path: '${environment.temp.path}/real-cache.json'),
          fileService: service));
    });
    CachedNetworkImageProvider.defaultCacheManager = disk;
    await tester.runAsync(() => disk.putFile(
        galleryB, File('$galleryFixtureRoot/portrait.png').readAsBytesSync(),
        maxAge: const Duration(days: 365), fileExtension: 'png'));
    final sentinel =
        await tester.runAsync(() => disk.getFileFromCache(galleryB));
    try {
      await tester.pumpWidget(galleryHarness(images: const []));
      await openGallery(tester, [galleryA]);
      await until(tester, () => retry.evaluate().isNotEmpty);
      expect(service.calls, [galleryA]);
      final cached =
          await tester.runAsync(() => disk.getFileFromCache(galleryA));
      expect(cached, isNotNull);
      expect(await tester.runAsync(() => cached!.file.readAsBytes()),
          File('$galleryFixtureRoot/corrupt.png').readAsBytesSync());
      await tester.pump(const Duration(seconds: 3));
      expect(service.calls, [galleryA]);
      await tester.tap(retry);
      await assertDecoded(tester, inside: viewer);
      expect(service.calls, [galleryA, galleryA]);
      final unchanged =
          await tester.runAsync(() => disk.getFileFromCache(galleryB));
      expect(unchanged!.file.path, sentinel!.file.path);
      expect(await tester.runAsync(() => unchanged.file.readAsBytes()),
          File('$galleryFixtureRoot/portrait.png').readAsBytesSync());
      final fresh =
          await tester.runAsync(() => disk.getFileFromCache(galleryA));
      expect(await tester.runAsync(() => fresh!.file.readAsBytes()),
          File('$galleryFixtureRoot/landscape.png').readAsBytesSync());
      await captureGallery(tester, 'corrupt-disk-retry-ready', success: true);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(disk.dispose);
      CachedNetworkImageProvider.defaultCacheManager = cache;
    }
  });

  for (final reply in [false, true]) {
    galleryTest(
        '${reply ? 'reply' : 'feed'} duplicate third image and Back retain real entry position',
        (tester) async {
      final scroll = ScrollController(initialScrollOffset: 280);
      addTearDown(scroll.dispose);
      await tester
          .pumpWidget(galleryHarness(reply: reply, scrollController: scroll));
      await flushImages(tester);
      for (final request in List<CacheRequest>.from(cache.requests)) {
        request.image();
      }
      await assertDecoded(tester, inside: thumbnails().first);
      final before = scroll.offset;
      final third = thumbnails().at(2);
      expect(tester.getSize(third).shortestSide, greaterThanOrEqualTo(48));
      await captureGallery(tester, '${reply ? 'reply' : 'feed'}-entry-ready',
          success: true);
      await tester.tap(third);
      await settleRoute(tester);
      expect(Get.currentRoute, '/imageview');
      expect(Get.arguments['initialPage'], 2);
      expect(find.text('3/3'), findsOneWidget);
      await until(tester, () => cache.forUrl(galleryA).isNotEmpty);
      cache.latest(galleryA).image();
      await assertDecoded(tester, inside: viewer);
      await captureGallery(
          tester, '${reply ? 'reply' : 'feed'}-third-duplicate',
          success: true);
      await tester.pageBack();
      await settleRoute(tester);
      expect(before, greaterThan(0));
      expect(scroll.offset, before);
      expect(viewer, findsNothing);
      expect(Get.currentRoute, '/');
      expect(thumbnails(), findsNWidgets(3));
      final requestsBeforeReopen = cache.requests.length;
      await tester.tap(thumbnails().at(2));
      await settleRoute(tester);
      expect(find.text('3/3'), findsOneWidget);
      await assertDecoded(tester, inside: viewer);
      expect(cache.requests.length, requestsBeforeReopen);
      await tester.pageBack();
      await settleRoute(tester);
      expect(scroll.offset, before);
      expect(tester.takeException(), isNull);
    });
  }

  galleryTest('more than nine keeps count and ninth opens its actual ordinal',
      (tester) async {
    final images = List.generate(
        10, (index) => 'https://fixture.invalid/grid-$index@160x100.png');
    await tester.pumpWidget(galleryHarness(images: images));
    await flushImages(tester);
    expect(find.byType(NineGridView), findsOneWidget);
    expect(thumbnails(), findsNWidgets(9));
    expect(find.text('+1'), findsOneWidget);
    for (final request in List<CacheRequest>.from(cache.requests)) {
      request.image();
    }
    await assertDecoded(tester, inside: thumbnails().last);
    await tester.tap(thumbnails().last);
    await settleRoute(tester);
    expect(find.text('9/10'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await settleRoute(tester);
    expect(find.text('10/10'), findsOneWidget);
    expect(Get.arguments['initialPage'], 8);
  });

  for (final spec in [
    (240.0, 640.0, 2.0),
    (320.0, 640.0, 2.0),
    (800.0, 360.0, 1.6)
  ]) {
    galleryTest('responsive ${spec.$1} grid failure and viewer controls',
        (tester) async {
      tester.view.physicalSize = Size(spec.$1, spec.$2);
      final semantics = tester.ensureSemantics();
      try {
        for (final count in [4, 9]) {
          final images = List.generate(
              count,
              (i) =>
                  'https://fixture.invalid/responsive-$count-$i@160x100.png');
          await tester.pumpWidget(
              galleryHarness(images: images, reply: true, scale: spec.$3));
          await flushImages(tester);
          final activeUrls = thumbnails()
              .evaluate()
              .map((e) => (e.widget as RetryableMediaImage).url)
              .toSet();
          final activeRequests = cache.requests
              .where((request) =>
                  activeUrls.contains(request.url) && !request.events.isClosed)
              .toList();
          expect(activeRequests, hasLength(count));
          for (final request in activeRequests) {
            request.fail();
          }
          await flushImages(tester);
          final thumbnailRequests = cache.requests
              .where((request) => activeUrls.contains(request.url))
              .length;
          for (final tile in thumbnails().evaluate()) {
            final rect = tester.getRect(find.byWidget(tile.widget));
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.height, greaterThanOrEqualTo(48));
          }
          expect(find.byTooltip('图片加载失败，重试缩略图'), findsNothing);
          await captureGallery(
              tester, 'grid-$count-error-width-${spec.$1.toInt()}');
          await tester.tap(thumbnails().first);
          await settleRoute(tester);
          expect(
              cache.requests
                  .where((request) => activeUrls.contains(request.url)),
              hasLength(thumbnailRequests));
          await until(tester, () => cache.forUrl(images.first).isNotEmpty);
          cache.latest(images.first).fail();
          await until(tester, () => retry.evaluate().isNotEmpty);
          expect(tester.getSize(retry).shortestSide, greaterThanOrEqualTo(48));
          expect(tester.getSize(find.byType(BackButton)).shortestSide,
              greaterThanOrEqualTo(48));
          await captureGallery(
              tester, 'viewer-error-width-${spec.$1.toInt()}-from-$count');
          expect(tester.takeException(), isNull);
          await tester.pageBack();
          await settleRoute(tester);
          expect(
              cache.requests
                  .where((request) => activeUrls.contains(request.url)),
              hasLength(thumbnailRequests));
          await tester.pumpWidget(const SizedBox.shrink());
          Get.reset();
        }
      } finally {
        semantics.dispose();
      }
    });
  }

  galleryTest('failed thumbnail route transition preserves request ownership',
      (tester) async {
    final images = List.generate(
        4, (i) => 'https://fixture.invalid/ownership-$i@160x100.png');
    await tester.pumpWidget(galleryHarness(images: images, reply: true));
    await until(tester, () => cache.requests.length == 4);
    for (final request in List<CacheRequest>.from(cache.requests)) {
      request.fail();
    }
    await flushImages(tester);
    await tester.pump();
    final grid = find.byWidgetPredicate(
        (w) => w is RetryableMediaImage && !w.isGallery,
        skipOffstage: false);
    expect(
        find.descendant(of: grid, matching: find.byType(Image)), findsNothing,
        reason: 'A terminal thumbnail error must remove the image resolver');
    final identities = <String, State>{};
    final keys = <String, Object>{};
    Future<void> trace(String phase) async {
      for (final element in grid.evaluate()) {
        final widget = element.widget as RetryableMediaImage;
        final state = (element as StatefulElement).state;
        final innerImages = find.descendant(
            of: find.byWidget(widget, skipOffstage: false),
            matching: find.byType(Image, skipOffstage: false));
        final provider = innerImages.evaluate().isEmpty
            ? null
            : (innerImages.evaluate().single.widget as Image).image;
        final key = provider == null
            ? keys[widget.url]
            : await tester
                .runAsync(() => provider.obtainKey(ImageConfiguration.empty));
        if (phase == 'before') {
          identities[widget.url] = state;
          if (key != null) keys[widget.url] = key;
        } else {
          expect(state, same(identities[widget.url]));
          if (key != null) expect(key, keys[widget.url]);
        }
        debugPrint('Thumbnail $phase: url=${widget.url}, '
            'state=${identityHashCode(state)}, innerImages=${innerImages.evaluate().length}, '
            'providerType=${provider.runtimeType}, keyHash=${key.hashCode}, '
            'cache=${key == null ? null : PaintingBinding.instance.imageCache.statusForKey(key)}');
      }
    }

    await trace('before');
    final thumbnailUrls = identities.keys.toSet();
    expect(thumbnailUrls, hasLength(4));
    expect(thumbnailUrls.intersection(images.toSet()), isEmpty,
        reason: 'Viewer and thumbnail URLs are counted separately');
    await tester.tap(thumbnails().first);
    await settleRoute(tester);
    expect(Get.currentRoute, '/imageview');
    await trace('after');
    debugPrint('Request URLs: ${cache.requests.map((r) => r.url).toList()}');
    expect(cache.forUrl(images.first), hasLength(1));
    expect(cache.requests.where((r) => thumbnailUrls.contains(r.url)),
        hasLength(4));
  });

  for (final reply in [false, true]) {
    galleryTest(
        'observed Android window ${reply ? 'reply' : 'feed'} retry and Back',
        (tester) async {
      // Reproduce the observed window geometry, not a device-model code path.
      tester.view.physicalSize = const Size(1200, 2670);
      tester.view.devicePixelRatio = 3.25;
      tester.view.padding = const FakeViewPadding(top: 140);
      tester.view.viewPadding = const FakeViewPadding(top: 140);
      tester.view.systemGestureInsets = const FakeViewPadding(top: 179);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetSystemGestureInsets);
      final scroll = ScrollController(initialScrollOffset: 280);
      addTearDown(scroll.dispose);
      final images = [
        galleryA,
        galleryB,
        galleryA,
        ...List.generate(
            6, (i) => 'https://fixture.invalid/observed-$i@160x100.png')
      ];
      await tester.pumpWidget(galleryHarness(
          images: images, reply: reply, scrollController: scroll));
      await flushImages(tester);
      final query = MediaQuery.of(tester.element(find.byType(Scaffold).first));
      expect(query.size.width, closeTo(369.230769, .000001));
      expect(query.size.height, closeTo(821.538462, .000001));
      expect(query.padding.top, closeTo(43.076923, .000001));
      expect(query.systemGestureInsets.top, closeTo(55.076923, .000001));
      expect(query.padding.bottom, 0);
      for (final request in List<CacheRequest>.from(cache.requests)) {
        request.fail();
      }
      await flushImages(tester);
      for (final tile in thumbnails().evaluate()) {
        expect(tester.getSize(find.byWidget(tile.widget)).shortestSide,
            greaterThanOrEqualTo(48));
      }
      final thumbnailUrls = thumbnails()
          .evaluate()
          .map((e) => (e.widget as RetryableMediaImage).url)
          .toSet();
      final thumbnailRequests = cache.requests
          .where((request) => thumbnailUrls.contains(request.url))
          .length;
      final before = scroll.offset;
      expect(before, greaterThan(0));
      await captureGallery(
          tester, 'observed-${reply ? 'reply' : 'feed'}-grid-error',
          pixelRatio: 3.25);
      await tester.tap(thumbnails().at(2));
      await settleRoute(tester);
      expect(Get.currentRoute, '/imageview');
      expect(find.text('3/9'), findsOneWidget);
      await until(tester, () => cache.forUrl(galleryA).isNotEmpty);
      cache.latest(galleryA).fail();
      await until(tester, () => retry.hitTestable().evaluate().isNotEmpty);
      expect(tester.getSize(retry).shortestSide, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.byType(BackButton)).shortestSide,
          greaterThanOrEqualTo(48));
      await captureGallery(
          tester, 'observed-${reply ? 'reply' : 'feed'}-viewer-error',
          pixelRatio: 3.25);
      await tester.tap(retry);
      await until(tester, () => cache.forUrl(galleryA).length == 2);
      cache.latest(galleryA).image();
      await assertDecoded(tester, inside: viewer);
      await captureGallery(
          tester, 'observed-${reply ? 'reply' : 'feed'}-viewer-ready',
          success: true, pixelRatio: 3.25);
      await tester.pageBack();
      await settleRoute(tester);
      expect(scroll.offset, before);
      expect(viewer, findsNothing);
      expect(Get.currentRoute, '/');
      expect(thumbnails().at(2).hitTestable(), findsOneWidget);
      expect(cache.forUrl(galleryA), hasLength(2));
      expect(
          cache.requests
              .where((request) => thumbnailUrls.contains(request.url)),
          hasLength(thumbnailRequests));
      await captureGallery(tester, 'observed-${reply ? 'reply' : 'feed'}-back',
          pixelRatio: 3.25);
      expect(tester.takeException(), isNull);
    });
  }

  galleryTest(
      'empty and out-of-range page arguments do not index invalid images',
      (tester) async {
    await start(tester, images: []);
    expect(find.text('0/0'), findsOneWidget);
    expect(find.text('没有可查看的图片'), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    await tester.pageBack();
    await settleRoute(tester);
    await openGallery(tester, [galleryA, galleryB], initial: 99);
    expect(find.text('2/2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  galleryTest('zoom pan and original action menu survive the pager replacement',
      (tester) async {
    await start(tester, images: [galleryA, galleryB], initial: 1);
    cache.latest(galleryB).image('portrait.png');
    await assertDecoded(tester, inside: viewer, width: 100, height: 160);
    final image = find
        .descendant(of: viewer, matching: find.byType(RawImage))
        .hitTestable();
    List<String> transforms() => find
        .ancestor(of: image, matching: find.byType(Transform))
        .evaluate()
        .map((e) => (e.widget as Transform).transform.toString())
        .toList();
    final initialTransforms = transforms();
    await tester.tap(image);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(image);
    await settleRoute(tester);
    expect(transforms(), isNot(initialTransforms));
    await tester.drag(image, const Offset(30, 20));
    await settleRoute(tester);
    expect(find.text('2/2'), findsOneWidget);
    await tester.longPress(image);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('保存图片'), findsOneWidget);
    expect(find.text('保存全部图片'), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);
    Object? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = call.arguments;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.tap(find.text('复制'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(copied, {'text': galleryB});
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('2/2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
