import 'package:c001apk_flutter/pages/settings/about_page.dart';
import 'package:c001apk_flutter/utils/bundled_font_licenses.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

const _fontPackage = 'Noto Sans CJK SC';
const _copyright = 'Copyright © 2014, 2015 Adobe Systems Incorporated '
    '(http://www.adobe.com/).';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Keep the framework's collectors intact. This file never resets the registry
  // independently of the production once-only registration guard.
  setUpAll(() {
    registerBundledFontLicenses();
    registerBundledFontLicenses();
  });

  test('real asset bundle includes the complete unchanged OFL', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(manifest.listAssets(), contains('assets/fonts/OFL.txt'));
    final bytes = await rootBundle.load('assets/fonts/OFL.txt');
    expect(
      sha256
          .convert(bytes.buffer.asUint8List(
            bytes.offsetInBytes,
            bytes.lengthInBytes,
          ))
          .toString(),
      '6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2',
    );
  });

  test('registry has one complete font license with the actual attribution',
      () async {
    final entries = await LicenseRegistry.licenses
        .where((entry) => entry.packages.contains(_fontPackage))
        .toList();
    expect(entries, hasLength(1));
    final entry = entries.single as LicenseEntryWithLineBreaks;
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    expect(entry.text, startsWith(_copyright));
    expect(entry.text, endsWith(license));
    expect(entry.text, contains('NotoSansCJKsc-Regular.otf'));
    expect(entry.text, contains('NotoSansCJKsc-Medium.otf'));
    expect(entry.text, contains('NotoSansCJKsc-Bold.otf'));
    expect(entry.text, contains('7af038d32866b387c64ef8e644abf5c303e48db6'));
    final paragraphs = entry.paragraphs.map((p) => p.text).join('\n');
    expect(paragraphs,
        contains('SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007'));
    expect(paragraphs, contains('PERMISSION & CONDITIONS'));
    expect(paragraphs, contains('OTHER DEALINGS IN THE FONT SOFTWARE.'));
  });

  testWidgets('existing About license route exposes the font and full terms',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(Get.reset);

    await tester.pumpWidget(const GetMaterialApp(home: AboutPage()));
    final licenseLink = find.text('Flutter 及依赖许可证');
    await tester.scrollUntilVisible(licenseLink, 250);
    await tester.tap(licenseLink);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LicensePage), findsOneWidget);

    // Use the real framework registry and LicensePage, including its normal
    // asynchronous asset loading. No replacement license widget or collector.
    for (var attempt = 0;
        attempt < 100 &&
            find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
    final font = find.text(_fontPackage);
    await tester.scrollUntilVisible(font, 300, maxScrolls: 100);
    expect(font.hitTestable(), findsOneWidget);
    await tester.tap(font);
    await tester.pumpAndSettle();
    final copyright = find.text(_copyright);
    await tester.scrollUntilVisible(copyright, 200);
    expect(copyright.hitTestable(), findsOneWidget);
    final title = find
        .textContaining('SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007');
    await tester.scrollUntilVisible(title, 250);
    expect(title.hitTestable(), findsOneWidget);
    final disclaimer =
        find.textContaining('OTHER DEALINGS IN THE FONT SOFTWARE.');
    await tester.scrollUntilVisible(disclaimer, 300, maxScrolls: 40);
    // scrollUntilVisible finishes with ensureVisible, which changes the scroll
    // position without pumping the final layout frame.
    await tester.pumpAndSettle();
    final disclaimerRect = tester.getRect(disclaimer);
    final viewport = tester.getRect(find.byType(Scrollable));
    final scrollOffset =
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
    expect(disclaimer.hitTestable(), findsOneWidget,
        reason: 'Disclaimer $disclaimerRect; viewport $viewport; '
            'scroll offset $scrollOffset');
    expect(disclaimerRect.top, greaterThanOrEqualTo(viewport.top));
    expect(disclaimerRect.bottom, lessThanOrEqualTo(viewport.bottom));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
