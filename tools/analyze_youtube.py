import os, re, json, base64, sys
from pathlib import Path

inbound = Path(r"C:\Users\roman\.openclaw\media\inbound")
out_dir = Path(r"C:\Users\roman\.openclaw\workspace\nexus\tools\youtube_bypass")
out_dir.mkdir(parents=True, exist_ok=True)

files = list(inbound.glob("*general_ALT*")) + list(inbound.glob("*youtube*")) + list(inbound.glob("*bypass*"))
print(f"Found files related to bypass: {len(files)}")
for f in files:
    print(f"  {f.name} ({f.stat().st_size / 1024:.0f} KB)")

# Also find any recently added files (last 10 min)
import time
now = time.time()
recent = [f for f in inbound.iterdir() if f.is_file() and (now - f.stat().st_mtime) < 360]
if recent:
    print(f"\nRecently added files ({len(recent)}):")
    for f in sorted(recent, key=lambda x: x.stat().st_mtime, reverse=True)[:15]:
        print(f"  {f.name} ({f.stat().st_size / 1024:.0f} KB)")

# Try to extract readable content from each
for f in list(recent)[:5]:
    print(f"\n{'='*50}")
    print(f"FILE: {f.name}")
    ext = f.suffix.lower()
    data = f.read_bytes()
    
    # Check first bytes
    print(f"First 32 bytes: {data[:32].hex()}")
    print(f"Size: {len(data)} bytes")
    
    # Try extracting text
    text = data.decode('utf-8', errors='replace')
    readable = re.findall(r'[\x20-\x7E]{8,}', text)
    if readable:
        interesting = [s for s in readable if any(k in s.lower() for k in 
            ['youtube', 'google', 'proxy', 'vpn', 'dpi', 'bypass', 'zapret', 'mtproto', 
             'winhttp', 'hosts', 'dns', 'winsock', 'goodbye', 'discord', 'telegram'])]
        for s in interesting[:30]:
            print(f"  {s}")
    else:
        print("  (binary, no readable strings > 8 chars)")
