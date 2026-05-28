#!/usr/bin/env python3
import os, requests

t = os.environ['GH_TOKEN']
api = 'https://api.github.com/repos/Salt2221/nexus-app'
h = {'Authorization': f'Bearer {t}', 'User-Agent': 'nexus', 'Accept': 'application/vnd.github+json'}
tag = 'v1.0.3'
apk = r'C:\Users\roman\.openclaw\workspace\nexus\build\app\outputs\flutter-apk\app-debug.apk'

print(f'Using token: {t[:10]}...{t[-4:]}')

# Delete old release/tag
r = requests.get(f'{api}/releases/tags/{tag}', headers=h)
if r.status_code == 200:
    rid = r.json()['id']
    print(f'Delete release {rid}')
    requests.delete(f'{api}/releases/{rid}', headers=h)

r = requests.get(f'{api}/git/refs/tags/{tag}', headers=h)
if r.status_code == 200:
    print('Delete tag')
    requests.delete(f'{api}/git/refs/tags/{tag}', headers=h)

print('Create release...')
r = requests.post(f'{api}/releases', json={
    'tag_name': tag,
    'name': 'NEXUS v1.0.3',
    'body': '## NEXUS v1.0.3\n\n- DeepSeek chat (AI tab)\n- New icon (user-supplied)\n- Fixed auto-update (no update loops)\n- 4-tab navigation: Home/AI/VPN/Profile',
    'draft': False,
}, headers=h)
print(f'Status: {r.status_code}')
if r.status_code != 201:
    print(f'Error: {r.text[:300]}')
    r.raise_for_status()
rel = r.json()
print(f'Release: {rel["html_url"]}')

print('Upload APK...')
with open(apk, 'rb') as f:
    up = rel['upload_url'].replace('{?name,label}', '?name=NEXUS-v1.0.3-debug.apk')
    r2 = requests.post(up, data=f, headers={**h, 'Content-Type': 'application/vnd.android.package-archive'})
    r2.raise_for_status()
    print(f'APK: {r2.json()["browser_download_url"]}')
print('DONE')
