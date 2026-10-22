"""Validate the actual side-by-side APK before CI publishes it. No signing I/O."""
import re
import subprocess
import sys

DIAGNOSTIC_ID = 'io.github.ktclat.c001apk.diagnostic'


def application_tree(manifest):
    lines = manifest.splitlines()
    for index, line in enumerate(lines):
        match = re.match(r'^(\s*)E: application(?:\s|$)', line)
        if match:
            indent = len(match.group(1))
            end = index + 1
            while end < len(lines):
                following = lines[end]
                if following.strip() and len(following) - len(following.lstrip()) <= indent:
                    break
                end += 1
            return '\n'.join(lines[index:end])
    raise AssertionError('Missing merged application manifest')


def validate(badging, manifest):
    package = re.search(r"^package: name='([^']+)'", badging, re.M)
    assert package and package.group(1) == DIAGNOSTIC_ID, 'Wrong diagnostic package'
    assert "application-label:'c001apk 诊断'" in badging, 'Missing diagnostic launcher label'
    assert re.search(r"versionName='[^']+-diag'", badging), 'Missing diagnostic version suffix'
    assert 'sharedUserId' not in manifest, 'Shared app identity is forbidden'
    app = application_tree(manifest)
    assert re.search(r'android:allowBackup[^\n]*0x0\s*$', app, re.M), 'Backup must be disabled'
    for forbidden in ('android.intent.action.VIEW', 'android.intent.category.BROWSABLE', 'android:autoVerify'):
        assert forbidden not in app, 'Diagnostic APK must not intercept external links'
    for authority in re.findall(r'android:authorities[^\n]*?="([^"]+)"', app):
        assert all(part.startswith(DIAGNOSTIC_ID + '.') for part in authority.split(';')), 'Provider authority escapes diagnostic package'


if __name__ == '__main__':
    aapt, apk = sys.argv[1:]
    badging = subprocess.check_output([aapt, 'dump', 'badging', apk], text=True)
    manifest = subprocess.check_output([aapt, 'dump', 'xmltree', apk, 'AndroidManifest.xml'], text=True)
    validate(badging, manifest)
    print('Verified standalone diagnostic package, label, version suffix and sandbox settings.')
