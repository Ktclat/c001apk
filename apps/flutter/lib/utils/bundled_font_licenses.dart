import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

/// Adds the bundled fonts to the existing About page's license list.
///
/// Only registration happens at startup. The complete, unchanged OFL asset is
/// loaded locally when LicenseRegistry is read; no font or license is fetched.
void registerBundledFontLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(
      const ['Noto Sans CJK SC'],
      // Copyright from name ID 0 of all three pinned, bundled OTF files.
      'Copyright © 2014, 2015 Adobe Systems Incorporated '
      '(http://www.adobe.com/).\n\n'
      'Bundled files: NotoSansCJKsc-Regular.otf, NotoSansCJKsc-Medium.otf, '
      'NotoSansCJKsc-Bold.otf (C001NotoSans).\n\n'
      'Source: https://github.com/CodePlayer/webfont-noto/tree/'
      '7af038d32866b387c64ef8e644abf5c303e48db6/'
      'dist/NotoSans/NotoSansCJKsc-hinted/subset/'
      'NotoSansCJKsc-hinted-standard\n\n'
      '$license',
    );
  });
}
