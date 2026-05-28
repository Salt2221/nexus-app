import os, base64, requests

b64 = os.environ.get('GH_TOKEN_B64', '')
if not b64:
    b64 = 'Z2hwX0dQM25PTlppQ1BxRnRyTzhUWHJYQ1kwUXZzWE44MWNjbFEz'

token = base64.b64decode(b64).decode()
h = {'Authorization': f'Bearer {token}', 'User-Agent': 'nexus'}
r = requests.get('https://api.github.com/user', headers=h)
print(f'Status: {r.status_code}')
if r.status_code == 200:
    print(f'Login: {r.json()["login"]}')
else:
    print(f'Error: {r.text[:200]}')

# Try releases
api = 'https://api.github.com/repos/Salt2221/nexus-app'
r = requests.get(f'{api}/releases/tags/v1.0.3', headers=h)
print(f'Release check: {r.status_code}')
