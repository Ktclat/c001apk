import 'dart:io';

import 'package:c001apk_flutter/logic/accounts/account_store.dart';
import 'package:c001apk_flutter/pages/accounts/accounts_page.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

Future<void> waitForAccountAction(WidgetTester tester) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Account operation failed to complete while pumping frames and IO');
}

void main() {
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('c001apk-accounts-ui-');
    Hive.init(directory.path);
    GStorage.settings = await Hive.openBox<dynamic>('settings');
  });

  setUp(() async {
    await GStorage.settings.clear();
    GStorage.setIsLogin(false);
    GStorage.setUid('');
    GStorage.setToken('');
    await AccountStore().initialize();
  });

  tearDown(() => Get.reset());

  tearDownAll(() async {
    // Scope cleanup to this suite's private box instead of closing any other
    // boxes opened by widgets during tests. Fail promptly if IO stalls.
    await GStorage.settings.flush().timeout(const Duration(seconds: 8));
    await GStorage.settings.close().timeout(const Duration(seconds: 8));
    await directory.delete(recursive: true).timeout(const Duration(seconds: 8));
  });

  Future<void> seedTwoAccounts() async {
    await AccountStore()
        .saveLogin(uid: '1', username: '合成账号一', token: 'synthetic-one');
    await AccountStore()
        .saveLogin(uid: '2', username: '合成账号二', token: 'synthetic-two');
  }

  testWidgets('account manager lists accounts and cancels removal',
      (tester) async {
    await tester.runAsync(seedTwoAccounts);
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
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('account manager switches account and enters guest mode',
      (tester) async {
    await tester.runAsync(seedTwoAccounts);
    await tester.pumpWidget(const GetMaterialApp(home: AccountsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('合成账号一'));
    await waitForAccountAction(tester);
    expect(GStorage.uid, '1');

    await tester.tap(find.text('使用游客模式'));
    await waitForAccountAction(tester);
    expect(GStorage.isLogin, isFalse);
    expect(AccountStore().accounts.length, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
