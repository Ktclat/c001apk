import 'dart:async';
import 'dart:io';

import 'package:c001apk_flutter/logic/network/request.dart';
import 'package:c001apk_flutter/pages/feed/reply/emoji_panel.dart';
import 'package:c001apk_flutter/pages/feed/reply/reply_dialog.dart';
import 'package:c001apk_flutter/utils/global_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'emote_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final environment = EmoteEnvironment();
  late EmoteOfflineAdapter adapter;
  setUpAll(environment.setUp);
  tearDownAll(environment.tearDown);
  setUp(() {
    adapter = EmoteOfflineAdapter();
    Request();
    Request.dio.httpClientAdapter = adapter;
    GlobalData().sessionGeneration++;
    GlobalData().isLogin = true;
    GlobalData().uid = 'offline-emote-owner';
    GlobalData().token = 'synthetic-token';
  });

  void pageTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetSystemGestureInsets);
      try {
        await body(tester);
      } finally {
        adapter.gate?.complete();
        adapter.gate = null;
        // Default dismiss does not cancel queued toast timers.
        SmartDialog.dismiss(status: SmartStatus.allToast);
        SmartDialog.dismiss();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        Get.reset();
      }
    });
  }

  pageTest('production page replaces forward and reverse range by real art tap',
      (tester) async {
    await openEmotePage(tester);
    final controller = emoteEditor(tester);
    for (final offsets in [(1, 3), (3, 1)]) {
      controller.value = TextEditingValue(
          text: '甲乙丙丁',
          selection:
              TextSelection(baseOffset: offsets.$1, extentOffset: offsets.$2),
          composing: const TextRange(start: 0, end: 4));
      await tester.pump();
      await tester.tap(find.byTooltip(emoteToken).hitTestable());
      await tester.pump();
      if (isEmoteBaseline) {
        expect(controller.text, offsets.$1 == 1 ? '甲[哈哈哈]乙丙丁' : '甲乙丙[哈哈哈]丁');
      } else {
        expect(controller.text, '甲[哈哈哈]丁');
        expect(controller.selection, const TextSelection.collapsed(offset: 6));
        expect(controller.value.composing, TextRange.empty);
      }
    }
    expect(adapter.requests, isEmpty);
  });

  pageTest('production page invalid selection baseline and safe insertion',
      (tester) async {
    await openEmotePage(tester);
    final controller = emoteEditor(tester);
    final onClick = tester.widget<EmotePanel>(find.byType(EmotePanel)).onClick;
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    controller.value = const TextEditingValue(text: '中文');
    if (isEmoteBaseline) {
      expect(() => onClick(emoteToken), throwsRangeError);
      expect(controller.text, '中文');
    } else {
      onClick(emoteToken);
      expect(controller.text, '中文[哈哈哈]');
      expect(controller.selection.baseOffset, 7);
      onClick(emoteToken);
      expect(controller.text, '中文[哈哈哈][哈哈哈]');
    }
    expect(adapter.requests, isEmpty);
  });

  if (!isEmoteBaseline) {
    pageTest('production page respects grapheme boundary and 500 atomic limit',
        (tester) async {
      await openEmotePage(tester);
      final controller = emoteEditor(tester);
      final onClick =
          tester.widget<EmotePanel>(find.byType(EmotePanel)).onClick;
      controller.value = const TextEditingValue(
          text: '甲👩🏽‍💻乙', selection: TextSelection.collapsed(offset: 2));
      onClick(emoteToken);
      expect(controller.text, '甲👩🏽‍💻[哈哈哈]乙');
      final before = TextEditingValue(
          text: '中' * 500,
          selection: const TextSelection.collapsed(offset: 200),
          composing: const TextRange(start: 0, end: 3));
      controller.value = before;
      await tester.pump();
      final publishBefore =
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed;
      onClick(emoteToken);
      await tester.pump();
      expect(controller.value, before);
      expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed !=
              null,
          publishBefore != null);
      // SmartDialog makes its debug overlay visible across post-frame awaits.
      final limitToast = find.text('最多输入500个字，无法插入完整表情');
      for (var i = 0; i < 20 && limitToast.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(limitToast, findsOneWidget);
      controller.value = before.copyWith(
          selection: const TextSelection(baseOffset: 10, extentOffset: 15));
      onClick(emoteToken);
      expect(controller.text.characters.length, 500);
      expect(controller.text.substring(10, 15), emoteToken);
      expect(controller.value.composing, TextRange.empty);
      controller.value = TextEditingValue(
          text: '中' * 510,
          selection: const TextSelection.collapsed(offset: 510));
      final oversized = controller.value;
      onClick(emoteToken);
      expect(controller.value, oversized);
      expect(adapter.requests, isEmpty);
    });

    pageTest(
        'retained page callback ignores covered route, account switch and disposal',
        (tester) async {
      await openEmotePage(tester);
      final controller = emoteEditor(tester);
      controller.value = const TextEditingValue(
          text: '原稿', selection: TextSelection.collapsed(offset: 2));
      final onClick =
          tester.widget<EmotePanel>(find.byType(EmotePanel)).onClick;
      final before = controller.value;
      showDialog<void>(
          context: tester.element(find.byType(EmotePanel)),
          builder: (_) => const AlertDialog(title: Text('离线确认覆盖层')));
      await tester.pumpAndSettle();
      onClick(emoteToken);
      expect(controller.value, before);
      Get.back();
      await tester.pumpAndSettle();
      onClick(emoteToken);
      expect(controller.text, '原稿[哈哈哈]');
      final oldAccountValue = controller.value;
      GlobalData().sessionGeneration++;
      onClick(emoteToken);
      expect(controller.value, oldAccountValue);
      Get.back();
      await tester.pumpAndSettle();
      expect(() => onClick(emoteToken), returnsNormally);
      expect(adapter.requests, isEmpty);
    });

    pageTest('keyboard return and selected local image preserve the draft',
        (tester) async {
      await openEmotePage(tester);
      final controller = emoteEditor(tester);
      await tester.tap(find.byIcon(Icons.keyboard));
      await tester.pump();
      controller.value = const TextEditingValue(
          text: '甲乙丙丁',
          selection: TextSelection(baseOffset: 1, extentOffset: 3));
      await tester.tap(find.byIcon(Icons.emoji_emotions));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip(emoteToken).hitTestable());
      await tester.pump();
      expect(controller.text, '甲[哈哈哈]丁');
      final afterInsertion = controller.value;
      await tester.tap(find.byIcon(Icons.keyboard));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.value, afterInsertion);
      await tester.tap(find.byIcon(Icons.emoji_emotions));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.value, afterInsertion);
      final fixture = File('test/fixtures/gallery/portrait.png').absolute.path;
      const channel = MethodChannel('plugins.flutter.io/image_picker');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => [fixture]);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.tap(find.byIcon(Icons.image));
      final preview =
          find.byWidgetPredicate((w) => w is Image && w.image is FileImage);
      for (var i = 0; i < 40 && preview.evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(preview, findsOneWidget);
      expect((tester.widget<Image>(preview).image as FileImage).file.path,
          fixture);
      expect(controller.text, '甲[哈哈哈]丁');
      final onClick =
          tester.widget<EmotePanel>(find.byType(EmotePanel)).onClick;
      onClick(emoteToken);
      await tester.pump();
      expect(controller.text, '甲[哈哈哈][哈哈哈]丁');
      expect(preview, findsOneWidget);
      expect((tester.widget<Image>(preview).image as FileImage).file.path,
          fixture);
      expect(adapter.requests, isEmpty);
    });

    pageTest(
        'active toolbar uses distinct 48dp hit regions without shrinking icons',
        (tester) async {
      await openEmotePage(tester);
      final regions = <Rect>[];
      for (final icon in [Icons.keyboard, Icons.emoji_emotions, Icons.image]) {
        final target = find.ancestor(
            of: find.byIcon(icon), matching: find.byType(IconButton));
        final rect = tester.getRect(target);
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.height, greaterThanOrEqualTo(48));
        expect(tester.widget<Icon>(find.byIcon(icon)).size, 22);
        for (final previous in regions) {
          expect(previous.overlaps(rect), isFalse);
        }
        regions.add(rect);
      }
      for (final target in [
        find.widgetWithText(TextButton, '回复并转发'),
        find.byType(FilledButton),
      ]) {
        final rect = tester.getRect(target);
        expect(rect.width, greaterThanOrEqualTo(48));
        expect(rect.height, greaterThanOrEqualTo(48));
        for (final previous in regions) {
          expect(previous.overlaps(rect), isFalse);
        }
        regions.add(rect);
      }
      await tester
          .tapAt(Offset(regions.first.left + 2, regions.first.center.dy));
      await tester.pumpAndSettle();
      expect(
          tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);
      // Closing the panel moves the toolbar; use the current hit region.
      final emojiRegion = tester.getRect(find.ancestor(
          of: find.byIcon(Icons.emoji_emotions),
          matching: find.byType(IconButton)));
      expect(emojiRegion.size, const Size(48, 48));
      await tester.tapAt(Offset(emojiRegion.left + 2, emojiRegion.center.dy));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      expect(adapter.requests, isEmpty);
    });

    pageTest('landscape long draft keeps editor and full panel scrollable',
        (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      await openEmotePage(tester);
      await tester.tap(find.byIcon(Icons.keyboard));
      await tester.pumpAndSettle();
      final draft = List.generate(24, (i) => '第${i + 1}行中文草稿').join('\n');
      await tester.enterText(find.byType(TextField), draft);
      await tester.tap(find.byIcon(Icons.emoji_emotions));
      await tester.pumpAndSettle();
      final editorScroll = find.byKey(const ValueKey('reply-editor-scroll'));
      final rect = tester.getRect(editorScroll);
      expect(rect.height, greaterThanOrEqualTo(48));
      final position = tester
          .state<ScrollableState>(find
              .descendant(of: editorScroll, matching: find.byType(Scrollable))
              .first)
          .position;
      expect(position.maxScrollExtent, greaterThan(0));
      // Drag the editor padding, not TextField's keyboard-switch listener.
      await tester.dragFrom(
          Offset(rect.right - 2, rect.bottom - 10), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(find.byTooltip(emoteToken).hitTestable(), findsOneWidget);
      expect(find.byType(TabBar).hitTestable(), findsOneWidget);
      final grid = find.descendant(
          of: find.byType(EmotePanel), matching: find.byType(GridView));
      final gridScroll = tester
          .state<ScrollableState>(find
              .descendant(of: grid, matching: find.byType(Scrollable))
              .first)
          .position;
      expect(gridScroll.maxScrollExtent, greaterThan(0));
      final controller = emoteEditor(tester);
      controller.selection = TextSelection.collapsed(offset: draft.length);
      await tester.tap(find.byTooltip(emoteToken).hitTestable());
      await tester.pumpAndSettle();
      expect(controller.text, '$draft$emoteToken');
      expect(controller.selection.baseOffset, controller.text.length);
      expect(tester.getRect(editorScroll).height, greaterThanOrEqualTo(48));
      await captureEmote(tester, 'landscape-long-draft-after');
      expect(adapter.requests, isEmpty);
      expect(tester.takeException(), isNull);
    });

    pageTest('pending offline publish cannot be edited or resent by emoji',
        (tester) async {
      await openEmotePage(tester);
      final controller = emoteEditor(tester);
      final onClick =
          tester.widget<EmotePanel>(find.byType(EmotePanel)).onClick;
      onClick(emoteToken);
      await tester.pump();
      adapter.gate = Completer<void>();
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed!();
      for (var i = 0; i < 40 && adapter.requests.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(adapter.requests, hasLength(1));
      final before = controller.value;
      onClick(emoteToken);
      onClick(emoteToken);
      expect(controller.value, before);
      expect(adapter.requests, hasLength(1));
      adapter.gate!.complete();
      adapter.gate = null;
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.text, emoteToken);
    });
  }

  // The legacy ReplyDialog has no live caller and an existing unbounded panel
  // layout. The explicit non-rendering child boundary exercises its real
  // State/TextField/EmotePanel handlers while the app/toast overlay lays out.
  // This is not a renderable legacy dialog, full app or screenshot proof.
  void legacyTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      await tester.pumpWidget(GetMaterialApp(
          navigatorObservers: [FlutterSmartDialog.observer],
          builder: FlutterSmartDialog.init(),
          home: const Scaffold(
              body: LegacyHandlerOnlyHost(child: ReplyDialog()))));
      // Only the legacy child has no layout. Suppress its fixture focus request
      // so the 300ms autofocus cannot open an unlaid input.
      tester
          .widget<TextField>(find.byType(TextField, skipOffstage: false).first)
          .focusNode!
          .canRequestFocus = false;
      // Flush initial focus notifications before tests install composing text.
      await tester.pump(null);
      try {
        await body(tester);
      } finally {
        adapter.gate?.complete();
        adapter.gate = null;
        SmartDialog.dismiss(status: SmartStatus.allToast);
        SmartDialog.dismiss();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        Get.reset();
      }
    });
  }

  legacyTest('legacy handler selection, invalid, graphemes and lifetime',
      (tester) async {
    final controller = emoteEditor(tester);
    final onClick = tester
        .widget<EmotePanel>(find.byType(EmotePanel, skipOffstage: false))
        .onClick;
    for (final offsets in [(1, 3), (3, 1)]) {
      controller.value = TextEditingValue(
          text: '甲乙丙丁',
          selection:
              TextSelection(baseOffset: offsets.$1, extentOffset: offsets.$2),
          composing: const TextRange(start: 0, end: 4));
      onClick(emoteToken);
      expect(
          controller.text,
          isEmoteBaseline
              ? (offsets.$1 == 1 ? '甲[哈哈哈]乙丙丁' : '甲乙丙[哈哈哈]丁')
              : '甲[哈哈哈]丁');
      expect(controller.value.composing, TextRange.empty);
    }
    controller.value = const TextEditingValue(text: '中文');
    if (isEmoteBaseline) {
      expect(() => onClick(emoteToken), throwsRangeError);
    } else {
      onClick(emoteToken);
      expect(controller.text, '中文[哈哈哈]');
      controller.value = const TextEditingValue(
          text: '甲👩🏽‍💻乙', selection: TextSelection.collapsed(offset: 2));
      onClick(emoteToken);
      expect(controller.text, '甲👩🏽‍💻[哈哈哈]乙');
      onClick(emoteToken);
      expect(controller.text, '甲👩🏽‍💻[哈哈哈][哈哈哈]乙');
      final before = controller.value;
      GlobalData().sessionGeneration++;
      onClick(emoteToken);
      expect(controller.value, before);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
    if (!isEmoteBaseline) expect(() => onClick(emoteToken), returnsNormally);
    expect(adapter.requests, isEmpty);
  });

  if (!isEmoteBaseline) {
    legacyTest('legacy handler atomic 500 rejection preserves disabled publish',
        (tester) async {
      final controller = emoteEditor(tester);
      final onClick = tester
          .widget<EmotePanel>(find.byType(EmotePanel, skipOffstage: false))
          .onClick;
      final before = TextEditingValue(
          text: '中' * 500,
          selection: const TextSelection.collapsed(offset: 200),
          composing: const TextRange(start: 0, end: 3));
      controller.value = before;
      expect(
          tester
              .widget<FilledButton>(
                  find.byType(FilledButton, skipOffstage: false))
              .onPressed,
          isNull);
      onClick(emoteToken);
      expect(controller.value, before);
      await tester.pump(null);
      expect(controller.value, before);
      expect(
          tester
              .widget<FilledButton>(
                  find.byType(FilledButton, skipOffstage: false))
              .onPressed,
          isNull);
      controller.value = before.copyWith(
          selection: const TextSelection(baseOffset: 15, extentOffset: 10));
      onClick(emoteToken);
      await tester.pump(null);
      expect(controller.text.characters.length, 500);
      expect(controller.text.substring(10, 15), emoteToken);
      expect(controller.value.composing, TextRange.empty);
      expect(
          tester
              .widget<FilledButton>(
                  find.byType(FilledButton, skipOffstage: false))
              .onPressed,
          isNotNull);
      expect(adapter.requests, isEmpty);
    });

    legacyTest('legacy pending publish rejects token without a second request',
        (tester) async {
      final controller = emoteEditor(tester);
      final onClick = tester
          .widget<EmotePanel>(find.byType(EmotePanel, skipOffstage: false))
          .onClick;
      onClick(emoteToken);
      await tester.pump(null);
      adapter.gate = Completer<void>();
      tester
          .widget<FilledButton>(find.byType(FilledButton, skipOffstage: false))
          .onPressed!();
      for (var i = 0; i < 40 && adapter.requests.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(adapter.requests, hasLength(1));
      final before = controller.value;
      onClick(emoteToken);
      expect(controller.value, before);
      expect(adapter.requests, hasLength(1));
      adapter.gate!.complete();
      adapter.gate = null;
      await tester.pump(const Duration(milliseconds: 500));
    });
  }

  for (final config in [
    ('observed', const Size(1200, 2670), 3.25, 1.0),
    ('narrow', const Size(360, 780), 1.0, 1.0),
    ('landscape', const Size(844, 390), 1.0, 1.0),
    ('large-text-1_6', const Size(390, 844), 1.0, 1.6),
    ('large-text-2', const Size(390, 844), 1.0, 2.0),
  ]) {
    pageTest('production page ${config.$1} art-to-editor capture',
        (tester) async {
      tester.view.physicalSize = config.$2;
      tester.view.devicePixelRatio = config.$3;
      if (config.$1 == 'observed') {
        tester.view.padding = const FakeViewPadding(top: 140);
        tester.view.viewPadding = const FakeViewPadding(top: 140);
        tester.view.systemGestureInsets = const FakeViewPadding(top: 179);
      }
      await openEmotePage(tester, scale: config.$4);
      final controller = emoteEditor(tester);
      controller.value = const TextEditingValue(
          text: '中文原稿，选择替换后继续写。',
          selection: TextSelection(baseOffset: 2, extentOffset: 4));
      await tester.pump();
      await captureEmote(tester, '${config.$1}-before');
      await tester.tap(find.byTooltip(emoteToken).hitTestable());
      await tester.pump();
      expect(controller.text,
          isEmoteBaseline ? '中文[哈哈哈]原稿，选择替换后继续写。' : '中文[哈哈哈]，选择替换后继续写。');
      await captureEmote(tester, '${config.$1}-after');
      expect(adapter.requests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
