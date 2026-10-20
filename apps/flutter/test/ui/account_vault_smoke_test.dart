import 'dart:io';

import 'package:c001apk_flutter/logic/accounts/account_store.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('c001apk-account-vault-');
    Hive.init(directory.path);
    GStorage.settings = await Hive.openBox<dynamic>('account-vault');
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('account vault can save, select and enter guest mode', () async {
    await GStorage.settings.clear();
    await AccountStore().initialize();
    await AccountStore()
        .saveLogin(uid: '1', username: '本地测试一', token: 'test-only-1')
        .timeout(const Duration(seconds: 8));
    expect(GStorage.uid, '1');
    await AccountStore()
        .saveLogin(uid: '2', username: '本地测试二', token: 'test-only-2')
        .timeout(const Duration(seconds: 8));
    expect(GStorage.uid, '2');
    await AccountStore().switchTo('1').timeout(const Duration(seconds: 8));
    expect(GStorage.uid, '1');
    await AccountStore().useGuest().timeout(const Duration(seconds: 8));
    expect(GStorage.isLogin, isFalse);
    expect(AccountStore().accounts.length, 2);
  });
}
