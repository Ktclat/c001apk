import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// Supplement mock-network/widget coverage with explicit integration boundaries.
// These checks do not replace behavioral tests or imply full upstream parity.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('partial sync preserves fork toolchain and session boundaries', () {
    final workflow = read('../../.github/workflows/android-font-build.yml');
    expect(workflow, contains('3.47.7'));
    expect(read('lib/logic/network/interceptor.dart'),
        contains("options.extra['apiSessionContext'] = _sessions.capture()"));
    expect(read('lib/pages/common/common_controller.dart'),
        contains('generation != GlobalData().sessionGeneration'));
    expect(
        read('android/app/build.gradle'), contains('io.github.ktclat.c001apk'));
    expect(read('../../docs/UPSTREAM_SYNC.md'), contains('部分同步'));
  });

  test('share call sites use payloads but copy actions remain URL-only', () {
    for (final page in ['feed/feed', 'app/app', 'topic/topic', 'user/user']) {
      final source =
          read('lib/pages/${page}_page.dart').replaceAll(RegExp(r'\s+'), '');
      expect(source, contains('Share.share(Utils.getShareText('), reason: page);
      expect(source, contains('Utils.copyText(Utils.getShareUrl('),
          reason: page);
    }
  });

  test('verification and deferred-comments actions remain explicit in feed UI',
      () {
    final source = read('lib/pages/feed/feed_page.dart');
    expect(source, contains('if (feedState.canVerify)'));
    expect(source, contains('导入官方设备标识'));
    expect(source, contains('加载评论并验证'));
    expect(source, contains('!_feedController.repliesDeferred.value'));
    expect(source, isNot(contains('ExpressiveLoadingIndicator')));
    expect(source, isNot(contains('FeedNavigation.open')));
  });
}
