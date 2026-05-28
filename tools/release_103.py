#!/usr/bin/env python3
import os, requests

t = os.environ['GH_TOKEN']
api = 'https://api.github.com/repos/Salt2221/nexus-app'
h = {'Authorization': f'Bearer {t}', 'User-Agent': 'nexus', 'Accept': 'application/vnd.github+json'}
tag = 'v1.0.3'
apk = r'C:\Users\roman\.openclaw\workspace\nexus\build\app\outputs\flutter-apk\app-debug.apk'

print(f'Token: {t[:10]}...{t[-4:]}')
print(f'User check: ', end='')
r = requests.get('https://api.github.com/user', headers=h)
print(f'{r.status_code} {r.json().get("login","?")}')

# Delete old
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
    'body': '## NEXUS v1.0.3\n\n- Real VpnService TCP tunnel\n- Built-in MTProto proxy (127.0.0.1:1443)\n- New icon\n- DeepSeek AI chat tab\n- Fixed auto-update',
    'draft': False,
}, headers=h)
print(f'Status: {r.status_code} {r.json().get("message","")}')
if r.status_code != 201:
    exit(1)
rel = r.json()
print(f'Release: {rel["html_url"]}')

print('Upload APK...')
with open(apk, 'rb') as f:
    up = rel['upload_url'].replace('{?name,label}', '?name=NEXUS-v1.0.3-debug.apk')
    r2 = requests.post(up, data=f, headers={**h, 'Content-Type': 'application/vnd.android.package-archive'})
    r2.raise_for_status()
    print(f'APK: {r2.json()["browser_download_url"]}')
print('DONE')
