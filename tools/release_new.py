import requests

token = "ghp_GP3nONZiCPqFtrO8TXrXCY0QvsXN81cclQ3"
h = {'Authorization': f'Bearer {token}', 'User-Agent': 'nexus'}
print(f'Token length: {len(token)}')
print(f'Token: {token[:10]}...{token[-4:]}')

r = requests.get('https://api.github.com/user', headers=h)
print(f'User: {r.status_code}')
if r.status_code == 200:
    print(f'Login: {r.json()["login"]}')
    print('Token works!')
else:
    print(r.text[:300])

# Try releases
api = 'https://api.github.com/repos/Salt2221/nexus-app'
r = requests.get(f'{api}/releases/tags/v1.0.3', headers=h)
print(f'Release check: {r.status_code}')
if r.status_code == 200:
    print(f'Release exists, deleting...')
    rid = r.json()['id']
    requests.delete(f'{api}/releases/{rid}', headers=h)

# Delete tag too
r = requests.get(f'{api}/git/refs/tags/v1.0.3', headers=h)
if r.status_code == 200:
    print('Delete tag')
    requests.delete(f'{api}/git/refs/tags/v1.0.3', headers=h)

print('Create release...')
r = requests.post(f'{api}/releases', json={
    'tag_name': 'v1.0.3',
    'name': 'NEXUS v1.0.3',
    'body': '## NEXUS v1.0.3\n\n- Real VpnService TCP tunnel\n- Built-in MTProto proxy (127.0.0.1:1443)\n- New icon\n- DeepSeek AI chat tab\n- Fixed auto-update',
    'draft': False,
}, headers=h)
print(f'Release status: {r.status_code}')
if r.status_code != 201:
    print(r.text[:400])
    exit(1)
rel = r.json()
print(f'Release: {rel["html_url"]}')

print('Upload APK...')
apk = r'C:\Users\roman\.openclaw\workspace\nexus\build\app\outputs\flutter-apk\app-debug.apk'
with open(apk, 'rb') as f:
    up = rel['upload_url'].replace('{?name,label}', '?name=NEXUS-v1.0.3-debug.apk')
    r2 = requests.post(up, data=f, headers={**h, 'Content-Type': 'application/vnd.android.package-archive'})
    r2.raise_for_status()
    print(f'APK: {r2.json()["browser_download_url"]}')
print('DONE')
