"""Fail closed before publishing the normal arm64 AOT profile APK. No signing I/O."""
from pathlib import Path
import re
import subprocess
import sys
import zipfile

NORMAL_ID = 'io.github.ktclat.c001apk'
MAX_APK_BYTES = 50_000_000


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(aapt, apk):
    apk = Path(apk)
    require(0 < apk.stat().st_size < MAX_APK_BYTES, 'APK must be smaller than 50,000,000 bytes')
    badging = subprocess.check_output([str(aapt), 'dump', 'badging', str(apk)], text=True)
    package = re.search(r"^package: name='([^']+)'", badging, re.M)
    require(package and package.group(1) == NORMAL_ID, 'Wrong normal app package')
    require("application-label:'c001apk'" in badging, 'Wrong normal launcher label')
    require(not re.search(r"versionName='[^']*-diag'", badging), 'Diagnostic version is forbidden')
    native = re.search(r'^native-code: (.+)$', badging, re.M)
    require(native and re.findall(r"'([^']+)'", native.group(1)) == ['arm64-v8a'],
            'Expected only arm64-v8a in APK badging')
    # Flutter 3.24.5 profile initWith(debug) retains Android debuggability.
    # buildModeFor selects profile by name before inspecting debuggable:
    # https://github.com/flutter/flutter/blob/3.24.5/packages/flutter_tools/gradle/src/main/groovy/flutter.groovy
    # Android's flag is not a JIT-mode discriminator. The --profile CI contract
    # plus nonempty AOT libraries and absence of JIT kernels establish this check.
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        abis = {name.split('/')[1] for name in names if name.startswith('lib/') and not name.endswith('/')}
        require(abis == {'arm64-v8a'}, 'Unexpected native ABI in ZIP')
        for name in ('lib/arm64-v8a/libapp.so', 'lib/arm64-v8a/libflutter.so'):
            require(name in names and archive.getinfo(name).file_size > 0, 'Missing AOT library: ' + name)
        require(not any(Path(name).name == 'kernel_blob.bin' or name.endswith('.dill') for name in names),
                'Dart JIT kernel is forbidden')
    print('Verified normal package, arm64-only native libraries, AOT/no-JIT-kernel layout and size limit.')


if __name__ == '__main__':
    verify(*sys.argv[1:3])
