"""Source contract tests; actual APK identity is separately checked after build."""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET
from verify_apk_identity import validate

ROOT = Path(__file__).resolve().parents[1]
ANDROID = '{http://schemas.android.com/apk/res/android}'


class DiagnosticIdentityTests(unittest.TestCase):
    def test_separate_manifest_has_no_external_routes_or_shared_identity(self):
        manifest = ET.parse(ROOT / 'android/app/src/diagnostic/AndroidManifest.xml').getroot()
        self.assertNotIn(ANDROID + 'sharedUserId', manifest.attrib)
        app = manifest.find('application')
        self.assertEqual(app.get(ANDROID + 'allowBackup'), 'false')
        self.assertEqual(app.get(ANDROID + 'label'), '${applicationLabel}')
        actions = [n.get(ANDROID + 'name') for n in app.findall('.//intent-filter/action')]
        self.assertEqual(actions, ['android.intent.action.MAIN'])
        self.assertEqual([n.get(ANDROID + 'name') for n in manifest.findall('uses-permission')],
                         ['android.permission.INTERNET', 'android.permission.ACCESS_NETWORK_STATE'])

    def test_production_package_stays_default(self):
        gradle = (ROOT / 'android/app/build.gradle').read_text()
        self.assertIn("providers.gradleProperty('diagnosticBuild').orNull == 'true'", gradle)
        self.assertIn('applicationId = _diagnosticBuild ? "io.github.ktclat.c001apk.diagnostic.motion" : "io.github.ktclat.c001apk"', gradle)
        self.assertIn("sourceSets.main.manifest.srcFile 'src/diagnostic/AndroidManifest.xml'", gradle)

    def test_actual_apk_validator_accepts_only_diagnostic_identity(self):
        badge = "package: name='io.github.ktclat.c001apk.diagnostic.motion' versionName='0.1.0-diag'\napplication-label:'c001apk 动效验证'"
        xml = 'E: manifest\n  E: application\n    A: android:allowBackup(0x01010280)=(type 0x12)0x0\n'
        validate(badge, xml)
        for wrong in [badge.replace('.motion', ''), badge.replace('.motion', '.visibility'), badge.replace('.diagnostic', ''), badge.replace('-diag', ''), badge.replace('c001apk 动效验证', 'c001apk')]:
            with self.assertRaises(AssertionError):
                validate(wrong, xml)
        with self.assertRaises(AssertionError):
            validate(badge, xml + 'sharedUserId="other"')
        for forbidden in ['android.intent.action.VIEW', 'android.intent.category.BROWSABLE', 'android:autoVerify', 'android:authorities(0x0)="io.github.ktclat.c001apk.files"']:
            with self.assertRaises(AssertionError):
                validate(badge, xml + '    A: ' + forbidden)
        validate(badge, xml + '    A: android:authorities(0x0)="io.github.ktclat.c001apk.diagnostic.motion.files"')
        validate(badge + "\nnative-code: 'arm64-v8a'", xml, 'arm64-v8a')
        for wrong in [badge, badge + "\nnative-code: 'armeabi-v7a' 'arm64-v8a'"]:
            with self.assertRaises(AssertionError):
                validate(wrong, xml, 'arm64-v8a')
        validate(badge, xml + '  E: queries\n    A: android.intent.action.VIEW')


if __name__ == '__main__':
    unittest.main()
