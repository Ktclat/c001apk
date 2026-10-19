import 'package:c001apk_flutter/utils/official_device_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = 'synthetic_shuzlm_identity_0123456789';
  test('extracts only ShuzlmID from the official four-field clipboard text',
      () {
    expect(
        OfficialDeviceIdentity.parse('设备ID: unused-device\n'
            'ShuzlmID: $id\nAndroidID: unused-android\nUUID: unused-uuid'),
        id);
    expect(
        OfficialDeviceIdentity.parse('\uFEFF设备ID：unused\r\n'
            '  ShuzlmID ： $id \r\nAndroidID：unused\r\nUUID：unused'),
        id);
    expect(OfficialDeviceIdentity.parse('ShuzlmID: synthetic.id_+/=-012345'),
        'synthetic.id_+/=-012345');
  });
  for (final text in [
    '设备ID: unused\nAndroidID: abcdef0123456789\nUUID: unused',
    'oaid-only-value-01234567890123456789',
    'ShuzlmID: ',
    'ShuzlmID: null',
    'ShuzlmID: undefined',
    'ShuzlmID: $id\nShuzlmID: another_synthetic_identity_012345',
    'ShuzlmID: $id; injected-header',
    'ShuzlmID: contains whitespace',
    'ShuzlmID: <redacted>',
  ]) {
    test('rejects incomplete or ambiguous input ${text.hashCode}', () {
      expect(() => OfficialDeviceIdentity.parse(text), throwsFormatException);
    });
  }
  test('validation errors never include clipboard identifiers', () {
    try {
      OfficialDeviceIdentity.parse('AndroidID: private-example');
      fail('Expected rejection');
    } on FormatException catch (error) {
      expect(error.toString(), isNot(contains('private-example')));
      expect(error.source, isNull);
    }
  });
}
