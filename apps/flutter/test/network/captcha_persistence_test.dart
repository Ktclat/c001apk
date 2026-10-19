import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:c001apk_flutter/logic/network/request.dart';
import 'package:c001apk_flutter/utils/global_data.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _Server implements HttpClientAdapter {
  _Server({this.reject = false});
  final bool reject;
  int requests = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    requests++;
    final verified = !reject &&
        (options.headers['Cookie'] ?? '')
            .toString()
            .contains('validate=NEC%3A01234567%3Asynthetic-proof');
    return ResponseBody.fromString(
        jsonEncode(verified
            ? {'data': []}
            : {
                'code': 403,
                'messageStatus': 'err_request_captcha_v2',
                'messageExtra': {
                  'captchaId': '0123456789abcdef0123456789abcdef',
                  'captchaField': ''
                },
              }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

Future<Map<String, dynamic>> _launch(String path,
    {required bool first,
    bool reject = false,
    bool expire = false,
    bool restoreDevice = false,
    bool otherDevice = false,
    bool otherAccount = false}) async {
  Hive.init(path);
  GStorage.settings = await Hive.openBox('settings');
  if (first) {
    await GStorage.settings.putAll({
      SettingsBoxKey.xAppDevice: 'synthetic-device',
      SettingsBoxKey.versionCode: '2604201',
      SettingsBoxKey.versionName: '16.2.0',
      SettingsBoxKey.apiVersion: '16',
      SettingsBoxKey.sdkInt: '33',
      SettingsBoxKey.userAgent: 'SyntheticTest/1.0',
    });
  }
  if (expire) {
    final record = Map<String, dynamic>.from(
        GStorage.settings.get('apiValidationV1') as Map);
    record['expiresAt'] = 1;
    await GStorage.settings.put('apiValidationV1', record);
  }
  if (otherDevice) {
    await GStorage.settings.put(SettingsBoxKey.xAppDevice, 'changed-device');
  }
  if (restoreDevice) {
    await GStorage.settings.put(SettingsBoxKey.xAppDevice, 'synthetic-device');
  }
  if (otherAccount) {
    GlobalData().isLogin = true;
    GlobalData().uid = '123';
    GlobalData().token = 'synthetic-account-token';
  }
  Request();
  final server = _Server(reject: reject);
  Request.dio.httpClientAdapter = server;
  var prompts = 0;
  Request().captchaVerifier = (challenge) async {
    prompts++;
    return first ? challenge.proof('synthetic-proof') : null;
  };
  final response =
      await Request().get('https://api.coolapk.com/v6/feed/replyList');
  final result = <String, dynamic>{
    'accepted': response.data['data'] is List,
    'prompts': prompts,
    'requests': server.requests,
  };
  await Hive.close();
  return result;
}

void main() {
  test('accepted verification survives a fresh process without another prompt',
      () async {
    final directory = await Directory.systemTemp.createTemp('captcha-restart-');
    final path = directory.path;
    try {
      expect(await Isolate.run(() => _launch(path, first: true)),
          {'accepted': true, 'prompts': 1, 'requests': 2});
      expect(await Isolate.run(() => _launch(path, first: false)),
          {'accepted': true, 'prompts': 0, 'requests': 1});
    } finally {
      await directory.delete(recursive: true);
    }
  });
  for (final reason in ['expired', 'device', 'account', 'server-rejected']) {
    test('$reason verification is discarded before another cold start',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('captcha-invalid-');
      final path = directory.path;
      try {
        await Isolate.run(() => _launch(path, first: true));
        expect(
            await Isolate.run(() => _launch(path,
                first: false,
                expire: reason == 'expired',
                otherDevice: reason == 'device',
                otherAccount: reason == 'account',
                reject: reason == 'server-rejected')),
            {'accepted': false, 'prompts': 1, 'requests': 1});
        // Returning to the original identity must not resurrect rejected proof.
        expect(
            await Isolate.run(
                () => _launch(path, first: false, restoreDevice: true)),
            {'accepted': false, 'prompts': 1, 'requests': 1});
      } finally {
        await directory.delete(recursive: true);
      }
    });
  }
  test('a server-rejected verification is never persisted', () async {
    final directory = await Directory.systemTemp.createTemp('captcha-reject-');
    final path = directory.path;
    try {
      expect(await Isolate.run(() => _launch(path, first: true, reject: true)),
          {'accepted': false, 'prompts': 1, 'requests': 2});
      expect(await Isolate.run(() => _launch(path, first: false)),
          {'accepted': false, 'prompts': 1, 'requests': 1});
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
