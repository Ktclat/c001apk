"""Offline normal-APK guard regressions using mocked aapt and synthetic ZIPs."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import verify_normal_profile_apk as verifier

BADGING = """package: name='io.github.ktclat.c001apk' versionName='0.1.0'
application-label:'c001apk'
native-code: 'arm64-v8a'
"""
MANIFEST = 'E: manifest\n  E: application\n'
LIBRARIES = {'lib/arm64-v8a/libapp.so': b'aot', 'lib/arm64-v8a/libflutter.so': b'engine'}
ROOT = Path(__file__).resolve().parents[3]


class NormalProfileApkTests(unittest.TestCase):
    def check_apk(self, badging=BADGING, manifest=MANIFEST, libraries=None, limit=None):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / 'app-arm64-v8a-profile.apk'
            with zipfile.ZipFile(apk, 'w') as archive:
                for name, content in (LIBRARIES if libraries is None else libraries).items():
                    archive.writestr(name, content)
            with patch.object(verifier.subprocess, 'check_output', side_effect=[badging, manifest]) as aapt:
                with patch.object(verifier, 'MAX_APK_BYTES', apk.stat().st_size + limit if limit is not None else 50_000_000):
                    verifier.verify('/mock/aapt', apk)
                self.assertEqual(aapt.call_args_list[0].args[0], ['/mock/aapt', 'dump', 'badging', str(apk)])
                self.assertEqual(aapt.call_args_list[1].args[0], ['/mock/aapt', 'dump', 'xmltree', str(apk), 'AndroidManifest.xml'])

    def test_accepts_normal_non_debug_aot(self):
        self.check_apk()
        self.check_apk(manifest=MANIFEST + '    A: android:debuggable(0x0101000f)=(type 0x12)0x0\n')

    def test_rejects_wrong_identity_label_or_diagnostic_version(self):
        for badge in (BADGING.replace("c001apk' version", "c001apk.diagnostic.motion' version"),
                      BADGING.replace("c001apk' version", "c001apk.other' version"),
                      BADGING.replace("application-label:'c001apk'", "application-label:'c001apk 动效验证'"),
                      BADGING.replace("0.1.0'", "0.1.0-diag'")):
            with self.subTest(badging=badge), self.assertRaises(ValueError):
                self.check_apk(badging=badge)

    def test_rejects_wrong_or_missing_badging_abi(self):
        for abi in ('', "native-code: 'x86_64'", "native-code: 'arm64-v8a' 'armeabi-v7a'"):
            with self.subTest(abi=abi), self.assertRaises(ValueError):
                self.check_apk(badging=BADGING.replace("native-code: 'arm64-v8a'", abi))

    def test_rejects_debug_builds(self):
        with self.assertRaises(ValueError):
            self.check_apk(badging=BADGING + 'application-debuggable\n')
        with self.assertRaises(ValueError):
            self.check_apk(manifest=MANIFEST + '    A: android:debuggable(0x0101000f)=(type 0x12)0xffffffff\n')

    def test_rejects_wrong_zip_abi_missing_aot_and_kernels(self):
        variants = [{}, {'lib/arm64-v8a/libflutter.so': b'engine'},
                    dict(LIBRARIES, **{'lib/arm64-v8a/libapp.so': b''})]
        variants += [dict(LIBRARIES, **{name: b'bad'}) for name in (
            'lib/x86_64/libapp.so', 'assets/flutter_assets/kernel_blob.bin', 'assets/app.dill')]
        for libraries in variants:
            with self.subTest(libraries=libraries), self.assertRaises(ValueError):
                self.check_apk(libraries=libraries)

    def test_size_limit_is_strict(self):
        self.check_apk(limit=1)
        for limit in (0, -1):
            with self.subTest(limit=limit), self.assertRaises(ValueError):
                self.check_apk(limit=limit)

    def test_aapt_failure_is_not_swallowed(self):
        with patch.object(verifier.subprocess, 'check_output', side_effect=subprocess.CalledProcessError(1, 'aapt')):
            with tempfile.NamedTemporaryFile() as apk:
                apk.write(b'not empty')
                apk.flush()
                with self.assertRaises(subprocess.CalledProcessError):
                    verifier.verify('/mock/aapt', apk.name)

    def test_ci_normal_arm64_is_verified_and_uploaded_before_diagnostics(self):
        workflow = (ROOT / '.github/workflows/android-font-build.yml').read_text()
        section = workflow.split('      - name: Compile normal arm64 profile APK\n', 1)[1].split(
            '      - name: Compile standalone diagnostic profile APK\n', 1)[0]
        self.assertIn('--profile --no-pub --split-per-abi --target-platform android-arm64', section)
        for define in ('APP_BUILD_SHA', 'APP_SOURCE_SHA', 'APP_BUILD_RUN'):
            self.assertIn('--dart-define=' + define + '=', section)
        self.assertNotIn('APP_DIAGNOSTIC', section)
        self.assertNotIn('diagnosticBuild', section)
        self.assertIn('python3 tools/verify_normal_profile_apk.py', section)
        self.assertIn('name: c001apk-android-profile-arm64', section)
        self.assertIn('path: apps/flutter/build/normal-arm64/app-normal-arm64-profile.apk', section)


if __name__ == '__main__':
    unittest.main()
