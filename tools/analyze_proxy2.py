"""Extract all useful strings from the proxy module and windows.pyc"""
import os, re

pyz_path = r"C:\Users\roman\.openclaw\workspace\pyinstxtractor\TgWsProxy_window.exe_extracted\PYZ-00.pyz"
windows_pyc = r"C:\Users\roman\.openclaw\workspace\nexus\tools\windows.pyc"

with open(pyz_path, 'rb') as f:
    data = f.read()

# Extract readable strings from PYZ (compressed but readable via raw bytes)
text = data.decode('latin-1')

print("=" * 60)
print("PROXY MODULE ANALYSIS")
print("=" * 60)

# Find proxy-related Python code patterns
patterns = [
    (r'class \w+', 'Classes'),
    (r'def \w+', 'Functions'),
    (r'import \w+', 'Imports'), 
    (r'from \w+', 'From imports'),
    (r'\.connect\(|\.bind\(', 'Connection calls'),
    (r'websocket|WebSocket', 'WebSocket refs'),
    (r'secret|SECRET', 'Secret refs'),
    (r'fake_tls|fake\.tls', 'Fake TLS'),
    (r'obfuscat', 'Obfuscation'),
    (r'DC[0-9]', 'DC refs'),
    (r'tg://|web\.telegram|api\.telegram', 'Telegram URLs'),
    (r'aes|AES', 'AES refs'),
    (r'cipher', 'Cipher'),
]

for pat, label in patterns:
    matches = set(re.findall(pat, text, re.IGNORECASE))
    if matches:
        print(f"\n--- {label} ({len(matches)}) ---")
        for m in sorted(list(matches))[:15]:
            print(f"  {m}")

# Look at the proxy config/defaults
print("\n\n=== PROXY CONFIG DEFAULTS ===")
# Find DEFAULT_CONFIG or similar
config_matches = re.findall(r'[\x20-\x7E]{10,}', text)
for s in config_matches:
    if any(k in s for k in ['_config', 'secret', 'port', 'proxy_url', 'DEFAULT', 'localhost', '127.0.0.1', 'bridge_url', 'balancer']):
        if len(s) > 10 and len(s) < 200:
            print(f"  {s}")

print("\n\n=== PROXY FILES FROM PYZ ===")
# Find file names in TOC
pyc_files = re.findall(r'proxy/[a-zA-Z_]+\.pyc', text)
for f in sorted(set(pyc_files)):
    print(f"  {f}")

print("\n\n=== WINDOWS.PYC - function signatures ===")
with open(windows_pyc, 'rb') as f:
    wdata = f.read()
wtext = wdata.decode('latin-1')
funcs = set(re.findall(r'[a-z_]+\(', wtext))
proxy_funcs = [f for f in sorted(funcs) if any(k in f for k in ['proxy', 'start', 'stop', 'config', 'load', 'save', 'restart', 'tg', 'tray', 'bootstrap'])]
for f in proxy_funcs:
    print(f"  {f}")
