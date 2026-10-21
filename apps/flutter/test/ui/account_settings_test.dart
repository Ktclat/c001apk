import 'dart:io';

import 'package:c001apk_flutter/pages/settings/settings_page.dart';
import 'package:c001apk_flutter/components/html_text.dart';
import 'package:c001apk_flutter/components/settings/font_choice_tile.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:c001apk_flutter/utils/app_theme.dart';
import 'package:c001apk_flutter/utils/reading_preset.dart';
import 'package:c001apk_flutter/pages/home/app/app_list_page.dart';
import 'package:c001apk_flutter/pages/home/return_top_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('account-settings-ui-');
    Hive.init(directory.path);
    GStorage.settings = await Hive.openBox('settings');
    PackageInfo.setMockInitialValues(
        appName: 'c001apk',
        packageName: 'io.github.ktclat.c001apk',
        version: '1.1.0',
        buildNumber: '20261014',
        buildSignature: '');
  });
  setUp(() async {
    // This suite only checks typography and appearance widgets. Initializing
    // the serialized account vault here can leave unrelated async work behind
    // during widget teardown and cause spurious suite timeouts.
    await GStorage.settings.clear();
  });
  tearDown(() async {
    Get.reset();
  });
  tearDownAll(() async {
    // Scope cleanup to this suite's private box instead of closing any other
    // boxes opened by widgets during tests. Fail promptly if IO stalls.
    await GStorage.settings.flush().timeout(const Duration(seconds: 8));
    await GStorage.settings.close().timeout(const Duration(seconds: 8));
    await directory.delete(recursive: true).timeout(const Duration(seconds: 8));
  });
  test('reference typography composes app and system text scales', () {
    final theme = applyAppTypography(ThemeData(useMaterial3: true));
    expect(theme.appBarTheme.titleTextStyle!.fontSize, 18);
    expect(theme.listTileTheme.titleTextStyle!.fontSize, 16);
    expect(theme.listTileTheme.subtitleTextStyle!.fontSize, 13);
    expect(theme.textTheme.bodyMedium!.height, 1.45);
    expect(const AppTextScaler(TextScaler.linear(1.5), 1.2).scale(14), 25.2);
  });
  testWidgets(
      'recreating the Android apps page releases old return-to-top listeners',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('samples.flutter.dev/channel'),
            (_) async => []);
    final controller = Get.put(ReturnTopController(), tag: 'home');
    await tester.pumpWidget(const GetMaterialApp(home: AppListPage()));
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.index.subject.length, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(controller.index.subject.length, 0);
  });
  testWidgets('wide settings show categories and selected content together',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const GetMaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();
    expect(find.text('动态取色'), findsOneWidget);
    await tester.tap(find.text('浏览与隐私'));
    await tester.pumpAndSettle();
    expect(find.text('用户黑名单'), findsOneWidget);
    expect(find.text('外观与字体'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('settings categories open independent pages on narrow windows',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const GetMaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();
    expect(find.text('外观与字体'), findsOneWidget);
    expect(find.text('协议与设备'), findsOneWidget);
    expect(find.text('动态取色'), findsNothing);
    await tester.tap(find.text('外观与字体'));
    await tester.pumpAndSettle();
    expect(find.text('动态取色'), findsOneWidget);
    expect(find.text('字体大小'), findsOneWidget);
    expect(find.text('界面字体'), findsOneWidget);
    expect(find.text('正文排版'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('settings fit narrow windows with enlarged text', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const GetMaterialApp(
        home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: SettingsDetailPage(section: SettingsSection.appearance))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('font setting uses native Android family and persists', () async {
    final base = ThemeData(platform: TargetPlatform.android, useMaterial3: true);
    final system = applyAppTypography(base, fontChoice: AppFontChoice.system);
    final material =
        applyAppTypography(base, fontChoice: AppFontChoice.material);
    expect(system.textTheme.bodyMedium!.fontFamily, 'sans-serif');
    expect(system.appBarTheme.titleTextStyle!.fontFamily, 'sans-serif');
    expect(material.textTheme.bodyMedium!.fontFamily, isNot('sans-serif'));
    expect(AppFontChoice.fromStorage(100), AppFontChoice.system);
    expect(AppFontChoice.fromStorage('invalid'), AppFontChoice.system);
    await GStorage.setFontChoice(AppFontChoice.material);
    // Real database IO is tested outside WidgetTester's fake async zone.
    await GStorage.settings.flush();
    expect(GStorage.fontChoice, AppFontChoice.material);
  });
  test('reading preset adjusts only feed typography and persists', () async {
    expect(GStorage.readingPreset, ReadingPreset.comfortable);
    var body = htmlText('中文帖子', role: HtmlTextRole.feedBody) as HtmlWidget;
    var title = htmlText('帖子标题', role: HtmlTextRole.feedTitle) as HtmlWidget;
    expect(body.textStyle!.fontSize, 15);
    expect(body.textStyle!.fontWeight, FontWeight.w400);
    expect(body.textStyle!.height, 1.42);
    expect(title.textStyle!.fontWeight, FontWeight.w500);
    await GStorage.setReadingPreset(ReadingPreset.original);
    expect(GStorage.readingPreset, ReadingPreset.original);
    body = htmlText('中文帖子', role: HtmlTextRole.feedBody) as HtmlWidget;
    title = htmlText('帖子标题', role: HtmlTextRole.feedTitle) as HtmlWidget;
    expect(body.textStyle!.fontSize, 16);
    expect(body.textStyle!.height, 1.5);
    expect(title.textStyle!.fontWeight, FontWeight.bold);
    expect((htmlText('普通控件') as HtmlWidget).textStyle!.fontSize, 15);
    await GStorage.settings.flush();
    expect(ReadingPreset.fromStorage('invalid'), ReadingPreset.comfortable);
  });

  test('feed HTML text follows the chosen Android font', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect((htmlText('中文动态') as HtmlWidget).textStyle?.fontFamily,
        'sans-serif');
    await GStorage.setFontChoice(AppFontChoice.material);
    expect((htmlText('中文动态') as HtmlWidget).textStyle?.fontFamily, isNull);
  });
  testWidgets('the font picker reports a selection without disk IO',
      (tester) async {
    tester.view.physicalSize = const Size(400, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppFontChoice? chosen;
    await tester.pumpWidget(GetMaterialApp(
        home: Scaffold(
            body: FontChoiceTile(onChoiceSelected: (value) {
      chosen = value;
    }))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('界面字体'));
    await tester.pumpAndSettle();
    expect(find.text('跟随系统（推荐）'), findsOneWidget);
    await tester.tap(find.text('Material 默认'));
    await tester.pumpAndSettle();
    // The sheet must close without running Hive's asynchronous filesystem
    // writer in a simulated async zone. Persistence is tested above.
    expect(chosen, AppFontChoice.material);
    expect(GStorage.fontChoice, AppFontChoice.system);
    expect(find.text('Material 默认'), findsNothing);
    // Release any ValueListenableBuilder subscriptions before teardown.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
