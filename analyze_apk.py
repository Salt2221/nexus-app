import zipfile, os, struct
from xml.parsers.expat import ParserCreate

apk_path = r'C:\Users\roman\.openclaw\workspace\nexus\build\app\outputs\flutter-apk\app-debug.apk'

z = zipfile.ZipFile(apk_path)
names = z.namelist()

print("=== APK Contents ===")
for n in names:
    print(f"  {n} ({z.getinfo(n).file_size} bytes)")

# Find classes.dex and classes2.dex
print("\n=== DEX files ===")
for n in names:
    if n.startswith("classes") and n.endswith(".dex"):
        info = z.getinfo(n)
        print(f"  {n}: {info.file_size} bytes")

# Check lib directory
print("\n=== Native libraries ===")
for n in names:
    if 'lib/' in n and n.endswith('.so'):
        print(f"  {n}")

print("\n=== Manifest (binary -> text) ===")
with z.open('AndroidManifest.xml') as f:
    raw = f.read()
# Quick check: extract android:name
idx = raw.find(b'android:name')
if idx >= 0:
    print(f"  'android:name' found at offset {idx}")
    
# Check FlutterEngineGroup / FlutterRenderer presence
seen_classes = set()
# Let's just check for classes.dex first
with z.open('classes.dex') as f:
    dex_data = f.read()

# Check for specific strings in DEX
import re
# Look for ProcessLifecycleOwner
if b'ProcessLifecycleOwner' in dex_data:
    print("\n  ProcessLifecycleOwner FOUND in classes.dex")
else:
    print("\n  ProcessLifecycleOwner NOT in classes.dex")

if b'ReLinker' in dex_data:
    print("  ReLinker FOUND in classes.dex")
else:
    print("  ReLinker NOT in classes.dex")

# Check classes2.dex if exists
if 'classes2.dex' in names:
    with z.open('classes2.dex') as f:
        dex2_data = f.read()
    if b'ProcessLifecycleOwner' in dex2_data:
        print("  ProcessLifecycleOwner FOUND in classes2.dex")
    else:
        print("  ProcessLifecycleOwner NOT in classes2.dex")
    
    if b'ReLinker' in dex2_data:
        print("  ReLinker FOUND in classes2.dex")
    else:
        print("  ReLinker NOT in classes2.dex")

z.close()
