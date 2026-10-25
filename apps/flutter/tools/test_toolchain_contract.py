"""Offline guard for the bounded SDK migration; does not invoke any build tools."""
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[3]
APP = ROOT / 'apps/flutter'


class AndroidToolchainContractTests(unittest.TestCase):
    def test_ci_and_pubspec_use_the_same_pinned_flutter_baseline(self):
        workflow = (ROOT / '.github/workflows/android-font-build.yml').read_text()
        self.assertEqual(re.findall(r"flutter-version: '([^']+)'", workflow), ['3.47.7', '3.47.7'])
        pubspec = (APP / 'pubspec.yaml').read_text()
        self.assertIn("flutter: '>=3.47.7'", pubspec)
        self.assertIn('intl: ^0.20.3', pubspec)
        self.assertIn('dynamic_color: 1.8.1', pubspec)
        self.assertIn('flutter_native_splash: 2.4.6', pubspec)
        self.assertIn('flutter_widget_from_html_core: ^0.15.2', pubspec)
        self.assertNotIn('dependency_overrides:', pubspec)
        self.assertEqual(workflow.count('flutter pub get --enforce-lockfile'), 2)

    def test_android_toolchain_is_compatible_without_agp9_or_bypasses(self):
        settings = (APP / 'android/settings.gradle').read_text()
        self.assertIn('id "com.android.application" version "8.13.2" apply false', settings)
        self.assertIn('id "org.jetbrains.kotlin.android" version "2.3.10" apply false', settings)
        wrapper = (APP / 'android/gradle/wrapper/gradle-wrapper.properties').read_text()
        self.assertIn('gradle-8.14.3-bin.zip', wrapper)
        self.assertIn('distributionSha256Sum=bd71102213493060956ec229d946beee57158dbd89d0e62b91bca0fa2c5f3531', wrapper)
        workflow = (ROOT / '.github/workflows/android-font-build.yml').read_text()
        self.assertIn("java-version: '17'", workflow)
        self.assertIn("'platforms;android-35'", workflow)
        self.assertIn("'platforms;android-36' 'build-tools;35.0.0' 'ndk;28.2.13676358'", workflow)
        properties = (APP / 'android/gradle.properties').read_text()
        # Official Flutter migration preserves the existing Kotlin plugin/DSL.
        self.assertIn('android.builtInKotlin=false', properties)
        self.assertIn('android.newDsl=false', properties)
        for path in [ROOT / '.github/workflows/android-font-build.yml',
                     APP / 'android/gradle.properties', APP / 'android/app/build.gradle']:
            source = path.read_text()
            for bypass in ('android-skip-build-dependency-validation',
                           'skipDependencyChecks', 'android.suppressUnsupportedCompileSdk'):
                self.assertNotIn(bypass, source, str(path))

    def test_sdk_scaffolding_exclusions_cannot_hide_tracked_dart(self):
        # Flutter 3.47.7 adds these exclusions during pub get. They are safe only
        # while the platform scaffolds contain no tracked Dart source/tests.
        options = (APP / 'analysis_options.yaml').read_text()
        excluded = ('build', 'android', 'ios', 'web', 'windows', 'macos', 'linux')
        for directory in excluded:
            self.assertIn(f'    - {directory}/**', options)
        self.assertNotIn('    - lib/', options)
        self.assertNotIn('    - test/', options)
        tracked = subprocess.check_output(
            ['git', 'ls-files', '-z', '--', 'apps/flutter'], cwd=ROOT
        ).decode().split('\0')
        hidden_dart = [path for path in tracked if path.endswith('.dart')
                       and path.split('/')[2] in excluded]
        self.assertEqual(hidden_dart, [], 'Review analyzer coverage before adding platform Dart sources')

    def test_minimum_support_and_target_behavior_are_explicit(self):
        gradle = (APP / 'android/app/build.gradle').read_text()
        for setting in ('compileSdk = 36', 'minSdk = 24', 'targetSdk = 34',
                        'ndkVersion = flutter.ndkVersion'):
            self.assertIn(setting, gradle)
        self.assertNotIn('targetSdk = flutter.targetSdkVersion', gradle)
        self.assertIn('namespace = "app.awavenue.c001apk"', gradle)
        self.assertIn('"io.github.ktclat.c001apk.diagnostic.motion" : "io.github.ktclat.c001apk"', gradle)
        self.assertIn('manifestPlaceholders.applicationLabel = _diagnosticBuild ? "c001apk 动效验证" : "c001apk"', gradle)
        self.assertIn('versionName = flutter.versionName + (_diagnosticBuild ? "-diag" : "")', gradle)
        self.assertIn('version: 0.1.0+1', (APP / 'pubspec.yaml').read_text())


if __name__ == '__main__':
    unittest.main()
