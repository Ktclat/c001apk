import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../utils/global_data.dart';
import '../../utils/storage_util.dart';

typedef ApiSessionContext = ({int generation, String identity, int revision});

/// Retain only the API's session cookie in the existing private settings store.
/// Account cookies remain owned by AccountStore. Never log stored values.
class ApiSessionStore {
  static const storageKey = 'apiSessionV1';
  static const validationKey = 'apiValidationV1';
  static int _revision = 0;
  static final _processId = '$pid:${DateTime.now().microsecondsSinceEpoch}';
  static const _maxAge = Duration(days: 7);

  static bool allows(Uri uri) =>
      uri.scheme == 'https' &&
      uri.port == 443 &&
      ['api.coolapk.com', 'api2.coolapk.com'].contains(uri.host);

  String get _identity {
    final global = GlobalData();
    return sha256
        .convert(utf8.encode(jsonEncode([
          GStorage.xAppDevice,
          global.isLogin,
          global.isLogin ? global.uid : '',
          global.isLogin ? global.token : '',
        ])))
        .toString();
  }

  Map? get _record {
    final record = GStorage.settings.get(storageKey);
    if (record is! Map ||
        record['identity'] != _identity ||
        record['expiresAt'] is! int ||
        record['expiresAt'] <= DateTime.now().millisecondsSinceEpoch ||
        record['value'] is! String ||
        record['domain'] is! String ||
        record['path'] is! String) return null;
    return record;
  }

  String cookieFor(Uri uri) {
    if (!allows(uri)) return '';
    final record = _record;
    if (record == null) return '';
    final domain = record['domain'] as String;
    final path = record['path'] as String;
    if (domain != 'coolapk.com' && domain != uri.host) return '';
    if (uri.path != path &&
        !uri.path.startsWith(path.endsWith('/') ? path : '$path/')) return '';
    return 'SESSID=${record['value']}';
  }

  ApiSessionContext capture() => (
        generation: GlobalData().sessionGeneration,
        identity: _identity,
        revision: _revision,
      );

  Future<String?> save(
      Uri uri, List<String> headers, ApiSessionContext context) async {
    if (!allows(uri) || context != capture()) return null;
    for (final header in headers) {
      Cookie cookie;
      try {
        cookie = Cookie.fromSetCookieValue(header);
      } on FormatException {
        continue;
      }
      if (cookie.name != 'SESSID') continue;
      final domain =
          (cookie.domain ?? uri.host).replaceFirst(RegExp(r'^\.'), '');
      final lastSlash = uri.path.lastIndexOf('/');
      final path = cookie.path ??
          (lastSlash <= 0 ? '/' : uri.path.substring(0, lastSlash));
      if ((domain != 'coolapk.com' && domain != uri.host) ||
          !path.startsWith('/') ||
          path.length > 256) continue;
      final now = DateTime.now();
      var expires = now.add(_maxAge);
      if (cookie.maxAge != null) {
        final maxAge = now.add(Duration(seconds: cookie.maxAge!));
        if (maxAge.isBefore(expires)) expires = maxAge;
      } else if (cookie.expires != null && cookie.expires!.isBefore(expires)) {
        expires = cookie.expires!;
      }
      if (cookie.value.isEmpty || !expires.isAfter(now)) {
        await clear();
        return null;
      }
      if (!RegExp(r'^[A-Za-z0-9,._~%+/-]{1,512}$').hasMatch(cookie.value)) {
        continue;
      }
      final revision = ++_revision;
      await GStorage.settings.put(storageKey, {
        'identity': context.identity,
        'value': cookie.value,
        'domain': domain,
        'path': path,
        'expiresAt': expires.millisecondsSinceEpoch,
      });
      return revision == _revision &&
              context.identity == _identity &&
              context.generation == GlobalData().sessionGeneration
          ? sessionHash
          : null;
    }
    return context == capture() ? sessionHash : null;
  }

  static Future<void> clear() async {
    _revision++;
    GlobalData().SESSID = '';
    await GStorage.settings.delete(storageKey);
    await clearValidation();
  }

  String get sessionHash => sha256
      .convert(utf8.encode(_record?['value'] as String? ?? ''))
      .toString();

  String? get validation {
    final record = GStorage.settings.get(validationKey);
    if (record is! Map ||
        record['identity'] != _identity ||
        record['session'] != sessionHash ||
        (record['process'] == _processId &&
            record['generation'] != GlobalData().sessionGeneration) ||
        record['expiresAt'] is! int ||
        record['expiresAt'] <= DateTime.now().millisecondsSinceEpoch ||
        record['value'] is! String) return null;
    return record['value'] as String;
  }

  Future<void> saveValidation(String value, ApiSessionContext context,
      {required String acceptedSession}) async {
    if (context.generation != GlobalData().sessionGeneration ||
        context.identity != _identity ||
        acceptedSession != sessionHash) return;
    await GStorage.settings.put(validationKey, {
      'identity': context.identity,
      'session': acceptedSession,
      'process': _processId,
      'generation': context.generation,
      'value': value,
      'expiresAt':
          DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
    });
    await GStorage.settings.flush();
  }

  static Future<void> clearValidation() =>
      GStorage.settings.delete(validationKey);
}
