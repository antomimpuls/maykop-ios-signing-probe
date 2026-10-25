"""Fail CI if the free-account app acquires extensions or capability entitlements."""
import json
from pathlib import Path
import plistlib
import subprocess
import sys

app = Path(sys.argv[1])
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.antomimpuls.vpnapp.d78a43e1'
assert not list(app.rglob('*.appex')), 'Extensions are prohibited'
assert not list(app.rglob('embedded.mobileprovision')), 'Unsigned build must not contain a profile'
binary = app / info['CFBundleExecutable']
signature = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(binary)], capture_output=True)
entitlements = plistlib.loads(signature.stdout) if signature.stdout.strip().startswith(b'<?xml') else {}
assert not entitlements, 'Unsigned build must have no requested entitlements'
libraries = subprocess.check_output(['otool', '-L', str(binary)], text=True)
assert 'NetworkExtension.framework' not in libraries
print(json.dumps({'bundle_id': info['CFBundleIdentifier'], 'app_count': 1,
    'extension_count': 0, 'requested_entitlements': entitlements,
    'network_extension_linked': False, 'signature': 'unsigned; not yet installable'}))
