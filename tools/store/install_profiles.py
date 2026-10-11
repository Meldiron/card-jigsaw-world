#!/usr/bin/env python3
"""Download the App Store provisioning profiles for the app and its widget
from App Store Connect and install them for xcodebuild (manual signing).

Usage: ASC_ISSUER_ID=... ASC_KEY_ID=... ASC_KEY_PATH=... python3 install_profiles.py
Defaults: key id 9QC72A5QMN, key at secrets/AuthKey_9QC72A5QMN.p8,
issuer id from secrets/app-store-connect-issuer-id.txt.
Requires: pip install pyjwt cryptography
"""
import base64, json, os, sys, time, urllib.request
import jwt

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
KEY_ID = os.environ.get('ASC_KEY_ID', '9QC72A5QMN')
KEY_PATH = os.environ.get('ASC_KEY_PATH', os.path.join(ROOT, 'secrets', f'AuthKey_{KEY_ID}.p8'))
ISSUER = os.environ.get('ASC_ISSUER_ID') or open(os.path.join(ROOT, 'secrets', 'app-store-connect-issuer-id.txt')).read().strip()
PROFILES = ['CJW AppStore cardjigsawworld', 'CJW AppStore DailyWidget']
DEST = os.path.expanduser('~/Library/MobileDevice/Provisioning Profiles')

now = int(time.time())
token = jwt.encode({'iss': ISSUER, 'iat': now, 'exp': now + 900, 'aud': 'appstoreconnect-v1'}, open(KEY_PATH).read(), algorithm='ES256', headers={'kid': KEY_ID, 'typ': 'JWT'})
req = urllib.request.Request('https://api.appstoreconnect.apple.com/v1/profiles?limit=200&filter[profileType]=IOS_APP_STORE', headers={'Authorization': 'Bearer ' + token})
data = json.loads(urllib.request.urlopen(req).read())['data']
os.makedirs(DEST, exist_ok=True)
found = 0
for p in data:
    a = p['attributes']
    if a['name'] in PROFILES and a['profileState'] == 'ACTIVE':
        path = os.path.join(DEST, a['uuid'] + '.mobileprovision')
        open(path, 'wb').write(base64.b64decode(a['profileContent']))
        print('installed', a['name'], '->', path)
        found += 1
if found != len(PROFILES):
    print('ERROR: expected', len(PROFILES), 'profiles, installed', found, file=sys.stderr)
    sys.exit(1)
