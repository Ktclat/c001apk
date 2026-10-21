import 'dart:io';

import 'package:c001apk_flutter/pages/settings/device_identity_page.dart';
import 'package:c001apk_flutter/pages/settings/manual_device_info_page.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:c001apk_flutter/utils/token_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('identity-import-ui-');
    Hive.init(directory.path);
    GStorage.settings = await Hive.openBox('settings');
  });
  setUp(() async {
    await GStorage.settings.clear();
    await GStorage.settings.put(
        SettingsBoxKey.xAppDevice,
        await TokenUtils.encodeDevice(
            'old-install-id; ; ; ; A; B; C; D; null'));
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  testWidgets(
      'pasting recognizes one ID, hides copied fields, and saves on tap',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var clipboardReads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        clipboardReads++;
        return {
          'text': '设备ID: private-device\n'
              'ShuzlmID: synthetic_official_identity_0123456789\n'
              'AndroidID: private-android\nUUID: private-uuid'
        };
      }
      return null;
    });
    await tester.pumpWidget(const MaterialApp(home: DeviceIdentityPage()));
    await tester.pumpAndSettle();
    expect(clipboardReads, 0);
    await tester.tap(find.text('粘贴并识别'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已识别数盟 ID'), findsOneWidget);
    expect(find.textContaining('private-android'), findsNothing);
    expect(GStorage.szlmId, isEmpty);
    await tester.runAsync(() async {
      await tester.tap(find.text('保存并应用'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(GStorage.szlmId, 'synthetic_official_identity_0123456789');
    expect(find.textContaining('已保存'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('incomplete pasted text cannot overwrite an existing identity',
      (tester) async {
    await tester.runAsync(
        () => GStorage.settings.put(SettingsBoxKey.szlmId, 'keep-existing'));
    await tester.pumpWidget(const MaterialApp(home: DeviceIdentityPage()));
    await tester.enterText(find.byType(TextField), 'AndroidID: wrong-field');
    await tester.pumpAndSettle();
    expect(GStorage.szlmId, 'keep-existing');
    final save =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '保存并应用'));
    expect(save.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('manual editor saves a changed profile without clipboard access',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => GStorage.settings.putAll({
          SettingsBoxKey.manufacturer: 'Maker',
          SettingsBoxKey.brand: 'Brand',
          SettingsBoxKey.model: 'Model',
          SettingsBoxKey.buildNumber: 'Build',
          SettingsBoxKey.sdkInt: '33',
          SettingsBoxKey.androidVersion: '13'
        }));
    await tester.pumpWidget(const MaterialApp(home: ManualDeviceInfoPage()));
    expect(find.text('手动填写设备信息'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('manual-shuzlm-id')),
        'synthetic_custom_identity_123456');
    await tester.enterText(find.byKey(const Key('manual-model')), 'CustomPhone');
    await tester.ensureVisible(find.text('保存并应用'));
    await tester.runAsync(() async {
      await tester.tap(find.text('保存并应用'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(GStorage.model, 'CustomPhone');
    expect(GStorage.szlmId, 'synthetic_custom_identity_123456');
    expect(
        tester.widget<TextField>(find.byKey(const Key('manual-shuzlm-id')))
            .controller!.text,
        isEmpty);
    expect(find.textContaining('已保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('missing official client gives an immediate installation prompt',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('samples.flutter.dev/channel'), (call) async {
        if (call.method == 'openOfficialIdSettings') {
          throw PlatformException(code: 'official_client_not_installed');
        }
        throw MissingPluginException();
      });
      await tester.pumpWidget(const MaterialApp(home: DeviceIdentityPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('酷安 OAID 界面'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('尚未安装官方酷安'), findsOneWidget);
      expect(GStorage.szlmId, isEmpty);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
