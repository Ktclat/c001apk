import 'dart:io';

import 'package:c001apk_flutter/pages/settings/settings_page.dart';
import 'package:c001apk_flutter/components/html_text.dart';
import 'package:c001apk_flutter/components/settings/font_choice_tile.dart';
import 'package:c001apk_flutter/components/settings/reading_preset_tile.dart';
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
    expect(theme.textTheme.bodyMedium!.height, 1.46);
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
    expect(find.text('悬浮 Tab 导航'), findsOneWidget);
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
  test('floating tab setting defaults off, persists, and does not affect fonts',
      () async {
    expect(GStorage.floatingTabBar, isFalse);
    final originalFont = GStorage.fontChoice;
    await GStorage.setFloatingTabBar(true);
    await GStorage.settings.flush();
    expect(GStorage.settings.get(SettingsBoxKey.floatingTabBar), isTrue);
    expect(GStorage.floatingTabBar, isTrue);
    expect(GStorage.fontChoice, originalFont);
    await GStorage.setFloatingTabBar(false);
    await GStorage.settings.flush();
    expect(GStorage.floatingTabBar, isFalse);
  });

  test('font setting uses native Android family and persists', () async {
    final base = ThemeData(platform: TargetPlatform.android, useMaterial3: true);
    final system = applyAppTypography(base, fontChoice: AppFontChoice.system);
    final material =
        applyAppTypography(base, fontChoice: AppFontChoice.material);
    expect(system.textTheme.bodyMedium!.fontFamily, 'sans-serif');
    expect(system.appBarTheme.titleTextStyle!.fontFamily, 'sans-serif');
    expect(material.textTheme.bodyMedium!.fontFamily, isNot('sans-serif'));
    expect(AppFontChoice.fromStorage(null), AppFontChoice.notoSans);
    expect(AppFontChoice.notoSans.familyForPlatform(TargetPlatform.android),
        AppFontChoice.bundledFontFamily);
    expect(AppFontChoice.fromStorage(100), AppFontChoice.system);
    expect(AppFontChoice.fromStorage('invalid'), AppFontChoice.system);
    await GStorage.setFontChoice(AppFontChoice.material);
    // Real database IO is tested outside WidgetTester's fake async zone.
    await GStorage.settings.flush();
    expect(GStorage.fontChoice, AppFontChoice.material);
  });
  test('existing installations adopt new typography only once', () async {
    await GStorage.settings.put(SettingsBoxKey.fontChoice, 0);
    await GStorage.settings.put(SettingsBoxKey.readingPreset, 1);
    await GStorage.settings.put('unrelated-setting', 'keep');
    await GStorage.migrateTypographyV2();
    expect(GStorage.fontChoice, AppFontChoice.notoSans);
    expect(GStorage.readingPreset, ReadingPreset.comfortable);
    expect(GStorage.settings.get('unrelated-setting'), 'keep');
    await GStorage.setFontChoice(AppFontChoice.system);
    await GStorage.migrateTypographyV2();
    expect(GStorage.fontChoice, AppFontChoice.system);
  });

  test('reading preset adjusts only feed typography and persists', () async {
    expect(GStorage.readingPreset, ReadingPreset.comfortable);
    var body = htmlText('中文帖子', role: HtmlTextRole.feedBody) as HtmlWidget;
    var title = htmlText('帖子标题', role: HtmlTextRole.feedTitle) as HtmlWidget;
    expect(body.textStyle!.fontSize, 14.5);
    expect(body.textStyle!.fontWeight, FontWeight.w400);
    expect(body.textStyle!.height, 1.52);
    expect(title.textStyle!.fontWeight, FontWeight.w500);
    expect(
        (htmlText('评论', role: HtmlTextRole.replyBody) as HtmlWidget)
            .textStyle!.fontSize,
        14);
    expect(
        (htmlText('长文章标题', role: HtmlTextRole.articleTitle) as HtmlWidget)
            .textStyle!.fontSize,
        16.5);
    await GStorage.setReadingPreset(ReadingPreset.original);
    expect(GStorage.readingPreset, ReadingPreset.original);
    body = htmlText('中文帖子', role: HtmlTextRole.feedBody) as HtmlWidget;
    title = htmlText('帖子标题', role: HtmlTextRole.feedTitle) as HtmlWidget;
    expect(body.textStyle!.fontSize, 16);
    expect(body.textStyle!.height, 1.5);
    expect(title.textStyle!.fontWeight, FontWeight.bold);
    expect(
        (htmlText('评论', role: HtmlTextRole.replyBody) as HtmlWidget)
            .textStyle!.fontSize,
        15);
    expect((htmlText('普通控件') as HtmlWidget).textStyle!.fontSize, 15);
    await GStorage.settings.flush();
    expect(ReadingPreset.fromStorage('invalid'), ReadingPreset.comfortable);
  });

  test('post markup and article typography match readable design', () {
    expect(normalizePostMarkup('**周五新鲜事**\n\n\n欢迎'),
        '<strong>周五新鲜事</strong><br/><br/>欢迎');
    expect(normalizePostMarkup('前文\n下一行'),
        '前文<br/>下一行');
    expect(normalizePostMarkup('<a href="/u/1">用户</a>'),
        '<a href="/u/1">用户</a>');
    final article =
        htmlText('中文文章', role: HtmlTextRole.articleBody) as HtmlWidget;
    expect(article.textStyle!.fontSize, 15);
    expect(article.textStyle!.fontWeight, FontWeight.w400);
    expect(article.textStyle!.locale, const Locale('zh', 'CN'));
  });

  test('feed HTML text follows the chosen Android font', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect((htmlText('中文动态') as HtmlWidget).textStyle?.fontFamily,
        AppFontChoice.bundledFontFamily);
    await GStorage.setFontChoice(AppFontChoice.material);
    expect((htmlText('中文动态') as HtmlWidget).textStyle?.fontFamily, isNull);
  });
  testWidgets('reading style can be selected without filesystem IO',
      (tester) async {
    ReadingPreset? selected;
    await tester.pumpWidget(GetMaterialApp(
      home: Scaffold(body: ReadingPresetTile(onSelected: (value) {
        selected = value;
      })),
    ));
    await tester.tap(find.text('正文排版'));
    await tester.pumpAndSettle();
    expect(find.text('舒适阅读（推荐）'), findsOneWidget);
    await tester.tap(find.text('原版排版'));
    await tester.pumpAndSettle();
    expect(selected, ReadingPreset.original);
    expect(GStorage.readingPreset, ReadingPreset.comfortable);
    await tester.pumpWidget(const SizedBox.shrink());
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
    expect(find.text('思源黑体 · 清爽（推荐）'), findsOneWidget);
    await tester.tap(find.text('Material 原版'));
    await tester.pumpAndSettle();
    // The sheet must close without running Hive's asynchronous filesystem
    // writer in a simulated async zone. Persistence is tested above.
    expect(chosen, AppFontChoice.material);
    expect(GStorage.fontChoice, AppFontChoice.notoSans);
    expect(find.text('Material 原版'), findsNothing);
    // Release any ValueListenableBuilder subscriptions before teardown.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
