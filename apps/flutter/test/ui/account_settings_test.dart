import 'dart:io';

import 'package:c001apk_flutter/logic/accounts/account_store.dart';
import 'package:c001apk_flutter/pages/accounts/accounts_page.dart';
import 'package:c001apk_flutter/pages/settings/settings_page.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:c001apk_flutter/utils/app_theme.dart';
import 'package:c001apk_flutter/pages/home/app/app_list_page.dart';
import 'package:c001apk_flutter/pages/home/return_top_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<void> finishAccountAction(WidgetTester tester) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail(
      'Account action did not finish while advancing real IO and widget frames');
}

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('account-settings-ui-');
    Hive.init(directory.path);
    GStorage.settings = await Hive.openBox('settings');
    PackageInfo.setMockInitialValues(
        appName: 'c001apk',
        packageName: 'app.awavenue.c001apk',
        version: '1.1.0',
        buildNumber: '20261014',
        buildSignature: '');
  });
  setUp(() async {
    await GStorage.settings.clear();
    GStorage.setIsLogin(false);
    GStorage.setUid('');
    GStorage.setToken('');
    await AccountStore().initialize();
  });
  tearDown(() async {
    Get.reset();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
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
  test('font setting uses native Android family and persists', () {
    final base = ThemeData(platform: TargetPlatform.android, useMaterial3: true);
    final system = applyAppTypography(base, fontChoice: AppFontChoice.system);
    final material =
        applyAppTypography(base, fontChoice: AppFontChoice.material);
    expect(system.textTheme.bodyMedium!.fontFamily, 'sans-serif');
    expect(system.appBarTheme.titleTextStyle!.fontFamily, 'sans-serif');
    expect(material.textTheme.bodyMedium!.fontFamily, isNot('sans-serif'));
    expect(AppFontChoice.fromStorage(100), AppFontChoice.system);
    expect(AppFontChoice.fromStorage('invalid'), AppFontChoice.system);
    GStorage.setFontChoice(AppFontChoice.material);
    expect(GStorage.fontChoice, AppFontChoice.material);
  });
  testWidgets('the font picker changes its saved choice', (tester) async {
    tester.view.physicalSize = const Size(400, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const GetMaterialApp(
        home: SettingsDetailPage(section: SettingsSection.appearance)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('界面字体'));
    await tester.pumpAndSettle();
    expect(find.text('跟随系统（推荐）'), findsOneWidget);
    await tester.tap(find.text('Material 默认'));
    await tester.pumpAndSettle();
    expect(GStorage.fontChoice, AppFontChoice.material);
    expect(find.text('当前：Material 默认'), findsOneWidget);
  });
  testWidgets('account manager marks current account and confirms removal',
      (tester) async {
    await tester.runAsync(() async {
      await AccountStore()
          .saveLogin(uid: '1', username: '合成账号一', token: 'synthetic-one');
      await AccountStore()
          .saveLogin(uid: '2', username: '合成账号二', token: 'synthetic-two');
    });
    await tester.pumpWidget(const GetMaterialApp(home: AccountsPage()));
    await tester.pumpAndSettle();
    expect(find.text('当前使用'), findsOneWidget);
    expect(find.text('添加账号'), findsOneWidget);
    await tester.tap(find.byTooltip('移除合成账号一'));
    await tester.pumpAndSettle();
    expect(find.text('移除本机登录？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(AccountStore().accounts.length, 2);
    // UI gestures belong to WidgetTester’s fake-async zone. Running a tap
    // inside runAsync while waiting for Hive IO can deadlock this test.
    await tester.tap(find.text('合成账号一'));
    await finishAccountAction(tester);
    expect(GStorage.uid, '1');
    await tester.tap(find.text('使用游客模式'));
    await finishAccountAction(tester);
    expect(GStorage.isLogin, isFalse);
    expect(AccountStore().accounts.length, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
