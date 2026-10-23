import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:c001apk_flutter/logic/network/request.dart';
import 'package:c001apk_flutter/utils/global_data.dart';
import 'package:c001apk_flutter/pages/feed/reply/emoji_panel.dart';
import 'package:c001apk_flutter/pages/feed/reply/reply_dialog.dart';
import 'package:c001apk_flutter/pages/feed/reply/reply_page.dart';
import 'package:c001apk_flutter/utils/app_theme.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:c001apk_flutter/utils/utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide FormData, Response;
import 'package:get/get_navigation/src/dialog/dialog_route.dart';
import 'package:hive/hive.dart';

const emoteToken = '[哈哈哈]';
const isEmoteBaseline = bool.fromEnvironment('EMOTICON_BASELINE');
final emoteCaptureKey = GlobalKey();

/// All API requests terminate here; no socket/network adapter is constructed.
class EmoteOfflineAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Completer<void>? gate;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    await gate?.future;
    return ResponseBody.fromString(
        jsonEncode({'status': -1, 'message': '离线测试未发布'}), 200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

class EmoteEnvironment {
  late Directory temp;
  late bool oldDesktop;
  late (bool, String, String, int, String, String, String) oldSession;
  late HttpClientAdapter oldAdapter;
  Future<void> setUp() async {
    oldDesktop = Utils.isDesktop;
    final global = GlobalData();
    oldSession = (
      global.isLogin,
      global.uid,
      global.token,
      global.sessionGeneration,
      global.SESSID,
      global.loginSession,
      global.username
    );
    Request();
    oldAdapter = Request.dio.httpClientAdapter;
    Utils.isDesktop = false;
    temp = await Directory.systemTemp.createTemp('emote-offline-');
    Hive.init(temp.path);
    GStorage.settings = await Hive.openBox('settings');
    await GStorage.settings.putAll({
      SettingsBoxKey.xAppDevice: 'synthetic-device',
      SettingsBoxKey.userAgent: 'SyntheticTest/1.0',
      SettingsBoxKey.versionName: '16.2.0',
      SettingsBoxKey.versionCode: '2604201',
      SettingsBoxKey.apiVersion: '16',
      SettingsBoxKey.sdkInt: '33',
    });
    final font = FontLoader(AppFontChoice.bundledFontFamily);
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      font.addFont(File('assets/fonts/NotoSansCJKsc-$weight.otf')
          .readAsBytes()
          .then(ByteData.sublistView));
    }
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/'
              'artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then(ByteData.sublistView));
    await icons.load();
  }

  Future<void> tearDown() async {
    Utils.isDesktop = oldDesktop;
    final global = GlobalData();
    global.isLogin = oldSession.$1;
    global.uid = oldSession.$2;
    global.token = oldSession.$3;
    global.sessionGeneration = oldSession.$4;
    global.SESSID = oldSession.$5;
    global.loginSession = oldSession.$6;
    global.username = oldSession.$7;
    Request.dio.httpClientAdapter = oldAdapter;
    await Hive.close();
    await temp.delete(recursive: true);
  }
}

/// Builds the genuine legacy State/handlers without claiming its broken,
/// unbounded panel can render. The surrounding app and toast overlay still
/// receive normal layout. This boundary is never used for screenshots or taps.
class LegacyHandlerOnlyHost extends SingleChildRenderObjectWidget {
  const LegacyHandlerOnlyHost({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLegacyHandlerOnlyHost();
}

class _RenderLegacyHandlerOnlyHost extends RenderProxyBox {
  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.smallest;

  @override
  void performLayout() {
    // Deliberately do not layout or read the child's size.
    size = constraints.smallest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {}

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {}
}

TextEditingController emoteEditor(WidgetTester tester) => tester
    .widget<TextField>(find.byType(TextField, skipOffstage: false).first)
    .controller!;

Future<void> openEmotePage(WidgetTester tester, {double scale = 1}) async {
  await tester.pumpWidget(RepaintBoundary(
      key: emoteCaptureKey,
      child: GetMaterialApp(
          debugShowCheckedModeBanner: false,
          theme: applyAppTypography(
              ThemeData(useMaterial3: true, platform: TargetPlatform.android)),
          navigatorObservers: [FlutterSmartDialog.observer],
          builder: (context, child) => FlutterSmartDialog.init()(
              context,
              MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!)),
          home: const Scaffold(body: Center(child: Text('离线生产回复组件'))))));
  Get.key.currentState!.push(GetDialogRoute(
      pageBuilder: (_, __, ___) =>
          const ReplyPage(type: ReplyType.feed, id: 7001, username: '离线联系人')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.byIcon(Icons.emoji_emotions));
  await tester.pump();
  await tester.pumpAndSettle();
  expect(find.byType(EmotePanel), findsOneWidget);
  expect(find.byTooltip(emoteToken).hitTestable(), findsOneWidget);
}

Future<void> captureEmote(WidgetTester tester, String name) async {
  final output = Platform.environment['EMOTICON_EVIDENCE'];
  if (output == null) return;
  // Let the size and input-hint animations finish before capturing pixels.
  await tester.pumpAndSettle();
  expect(find.byTooltip(emoteToken).hitTestable(), findsOneWidget);
  // Original bundled art must be both decoded and visibly hit-testable.
  final images = find
      .descendant(of: find.byType(EmotePanel), matching: find.byType(RawImage))
      .hitTestable();
  for (var i = 0;
      i < 40 &&
          !images.evaluate().any((e) => (e.widget as RawImage).image != null);
      i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(images.evaluate().any((e) => (e.widget as RawImage).image != null),
      isTrue,
      reason: 'Original bundled emoji art must decode');
  await tester.runAsync(() async {
    final boundary = emoteCaptureKey.currentContext!.findRenderObject()!
        as RenderRepaintBoundary;
    final image =
        await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(png!.buffer.asUint8List());
    List<double> ltrb(EdgeInsets value) =>
        [value.left, value.top, value.right, value.bottom];
    Map<String, Object> metrics(MediaQueryData data) => {
          'sizeLogical': [data.size.width, data.size.height],
          'devicePixelRatio': data.devicePixelRatio,
          'paddingLTRB': ltrb(data.padding),
          'viewPaddingLTRB': ltrb(data.viewPadding),
          'systemGestureInsetsLTRB': ltrb(data.systemGestureInsets),
          'viewInsetsLTRB': ltrb(data.viewInsets),
          'scaled14pt': data.textScaler.scale(14),
        };
    List<double> bounds(Rect value) =>
        [value.left, value.top, value.right, value.bottom];
    Map<String, Object?> labelMetrics(String label) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      final fontSize = paragraph.text.style?.fontSize;
      expect(fontSize, isNotNull, reason: 'Actual label must resolve its font');
      return {
        'label': paragraph.text.toPlainText(),
        'spanFontSize': fontSize,
        'scaledFontSize': paragraph.textScaler.scale(fontSize!),
        'size': [paragraph.size.width, paragraph.size.height],
        'paintBoundsLTRB': bounds(paragraph.paintBounds),
        'semanticsBoundsLTRB': bounds(paragraph.semanticBounds),
      };
    }

    final value = emoteEditor(tester).value;
    final metadata = {
      'scope':
          'Offline real ReplyPage GetDialogRoute, not full Home app or device',
      'baseline': isEmoteBaseline,
      'physicalSize': [
        tester.view.physicalSize.width,
        tester.view.physicalSize.height
      ],
      'devicePixelRatio': tester.view.devicePixelRatio,
      'routeMediaQuery':
          metrics(MediaQuery.of(tester.element(find.byType(ReplyPage)))),
      'editorMediaQuery':
          metrics(MediaQuery.of(tester.element(find.byType(TextField).first))),
      'actualLabels': [labelMetrics('回复并转发'), labelMetrics('发布')],
      'editorText': value.text,
      'selection': [value.selection.baseOffset, value.selection.extentOffset],
      'composing': [value.composing.start, value.composing.end],
      'decodedBundledEmojiCount': images
          .evaluate()
          .where((e) => (e.widget as RawImage).image != null)
          .length,
    };
    await File('$output/$name.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(metadata));
    image.dispose();
  });
}
