#!/usr/bin/env python3
"""Real LaunchServices broker probes. Executes only our synthetic local application."""
import json
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

# Direct invocation also gets an owned workspace and automatic cleanup.
import os as _artifact_os, sys as _artifact_sys
from pathlib import Path as _ArtifactPath
if not _artifact_os.environ.get('EXERUNNER_ARTIFACT_SESSION'):
    _artifact_os.execv(_artifact_sys.executable, [_artifact_sys.executable, '-I',
        str(_ArtifactPath(__file__).resolve().parents[1] / 'tools/artifacts.py'),
        'run', '--label', 'test-isolation-broker-test', '--', _artifact_sys.executable, __file__, *_artifact_sys.argv[1:]])

ROOT = pathlib.Path(__file__).resolve().parents[1]
ENGINE = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '/Applications/ExeRunner.app/Contents/Resources/engine')
WORK = pathlib.Path(tempfile.mkdtemp(prefix='exerunner-broker.', dir=os.environ.get('TMPDIR', '/private/tmp')))
PREFIX = WORK / 'isolated-broker'
APP = PREFIX / 'Canary.app'
MARKER = WORK / 'outside-marker.txt'
EXPECTED = 'Synthetic LaunchServices canary\n'
KEEP = os.environ.get('EXERUNNER_KEEP_BROKER_EVIDENCE') == '1'

def run(command, **kwargs):
    return subprocess.run([str(x) for x in command], check=True, timeout=60, **kwargs)

def remove_marker():
    if MARKER.exists():
        assert MARKER.read_text() == EXPECTED, 'Diagnostic marker changed; preserving it'
        MARKER.unlink()

try:
    for part in ['drive_c', '.isolation/home', '.isolation/tmp', 'Canary.app/Contents/MacOS']:
        (PREFIX / part).mkdir(parents=True, exist_ok=True)
    (PREFIX / '.exerunner-isolated-v1').write_text('offline prototype\n')
    (APP / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'local.exerunner.synthetic.canary.' + uuid.uuid4().hex,
        'CFBundleExecutable': 'canary', 'CFBundleName': 'Canary',
        'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1', 'LSBackgroundOnly': True,
    }))
    native = PREFIX / 'ls-probe'
    run(['clang', '-Wno-deprecated-declarations', '-DCANARY_MARKER=' + json.dumps(str(MARKER)),
         ROOT / 'tests/isolation-launchservices.c', '-framework', 'CoreServices', '-o', native])
    shutil.copy2(native, APP / 'Contents/MacOS/canary')
    run(['/usr/bin/codesign', '--force', '--sign', '-', APP], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    workspace = PREFIX / 'workspace-probe'
    run(['swiftc', ROOT / 'tests/isolation-launchservices.swift', '-o', workspace])
    shutil.copy2(ROOT / 'tests/isolation-test.swift', WORK / 'main.swift')
    core = ROOT / 'app/Sources/ExeRunner/Core'
    files = ['IsolatedWine', 'Basics', 'Engine', 'Library', 'Bottles', 'Settings',
             'Processes', 'VDF', 'Recipe', 'Localization', 'English', 'PrefixLaunchGate']
    harness = WORK / 'harness'
    run(['swiftc', '-o', harness, WORK / 'main.swift'] + [core / (x + '.swift') for x in files])
    profile = WORK / 'profile.sb'
    run([harness, 'profile', PREFIX, ENGINE, profile])
    environment = {'HOME': str(PREFIX / '.isolation/home'), 'TMPDIR': str(PREFIX / '.isolation/tmp'),
                   'PATH': '/usr/bin:/bin', 'USER': 'isolated', 'LOGNAME': 'isolated'}
    modes = {'direct': [APP / 'Contents/MacOS/canary'],
             'workspace': [workspace, APP], 'spec': [native, 'spec', APP], 'url': [native, 'url', APP]}
    evidence = []
    for mode, command in modes.items():
        for protected in [False, True]:
            remove_marker()
            launch = ['/usr/bin/sandbox-exec', '-f', profile] + command if protected else command
            result = subprocess.run([str(x) for x in launch], env=environment,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=15)
            until = time.monotonic() + (2 if protected else 5)
            while time.monotonic() < until and not MARKER.exists():
                time.sleep(0.05)
            created = MARKER.exists()
            evidence.append({'mode': mode, 'protected': protected, 'status': result.returncode,
                             'outside_marker_created': created, 'output': result.stdout})
            print(f'{mode}: protected={protected} status={result.returncode} outside_marker={created}', flush=True)
            (WORK / 'results.json').write_text(json.dumps(evidence, indent=2))
            if protected:
                assert result.returncode != 0 and not created, f'{mode}: application escaped isolation'
            else:
                assert result.returncode == 0 and created, f'{mode}: positive control failed'
    # A broker might reuse an existing app without starting a new process. Test that path too.
    existing = PREFIX / 'ExistingCanary.app'
    (existing / 'Contents/MacOS').mkdir(parents=True)
    ready = PREFIX / 'existing-ready.txt'
    scheme = 'exerunnercanary' + uuid.uuid4().hex
    (existing / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'local.exerunner.synthetic.existing.' + uuid.uuid4().hex,
        'CFBundleExecutable': 'canary', 'CFBundleName': 'ExeRunner Existing Canary',
        'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1', 'LSBackgroundOnly': True,
        'CFBundleURLTypes': [{'CFBundleURLName': 'ExeRunner synthetic test', 'CFBundleURLSchemes': [scheme]}],
    }))
    binary = existing / 'Contents/MacOS/canary'
    run(['clang', '-DMARKER=' + json.dumps(str(MARKER)), '-DREADY=' + json.dumps(str(ready)),
         ROOT / 'tests/isolation-existing-canary.m', '-framework', 'AppKit', '-o', binary])
    run(['/usr/bin/codesign', '--force', '--sign', '-', existing], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    existing_probe = PREFIX / 'existing-url-probe'
    run(['swiftc', ROOT / 'tests/isolation-existing-launchservices.swift', '-o', existing_probe])
    lsregister = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
    run([lsregister, '-f', existing])
    with (WORK / 'existing-canary.log').open('w') as output:
        process = subprocess.Popen([str(binary)], stdout=output, stderr=subprocess.STDOUT)
        try:
            until = time.monotonic() + 10
            while time.monotonic() < until and not ready.exists():
                time.sleep(0.05)
            assert ready.exists(), 'Existing native canary failed to start'
            for protected in [False, True]:
                remove_marker()
                command = [existing_probe, existing, scheme + '://own-test']
                launch = ['/usr/bin/sandbox-exec', '-f', profile] + command if protected else command
                result = subprocess.run([str(x) for x in launch], env=environment, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, text=True, timeout=15)
                until = time.monotonic() + 2
                while time.monotonic() < until and not MARKER.exists():
                    time.sleep(0.05)
                created = MARKER.exists()
                evidence.append({'mode': 'existing-url', 'protected': protected, 'status': result.returncode,
                                 'outside_marker_created': created, 'output': result.stdout})
                (WORK / 'results.json').write_text(json.dumps(evidence, indent=2))
                print(f'existing-url: protected={protected} status={result.returncode} outside_marker={created}', flush=True)
                assert created != protected, 'Existing-app URL broker boundary failed'
                assert result.returncode != 0 if protected else result.returncode == 0
        finally:
            process.terminate()
            process.wait(timeout=5)
    print('PASS: direct execution, three launch APIs and URL delivery to an existing native app blocked; positive controls passed')
finally:
    remove_marker()
    lsregister = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
    try:
        for application in [APP, PREFIX / 'ExistingCanary.app']:
            subprocess.run([lsregister, '-u', str(application)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
    except subprocess.TimeoutExpired:
        KEEP = True
    if KEEP:
        print('Test workspace (automatic cleanup):', WORK)
    else:
        shutil.rmtree(WORK)
