"""Extract PYZ-00.pyz from PyInstaller archive manually.
PYZ format: [4 bytes 'PYZ\x00'][4 bytes TOC length][zlib-compressed TOC][zlib-compressed files]"""
import struct
import zlib
import os
import sys

pyz_path = r"C:\Users\roman\.openclaw\workspace\pyinstxtractor\TgWsProxy_window.exe_extracted\PYZ-00.pyz"
out_dir = r"C:\Users\roman\.openclaw\workspace\nexus\tools\proxy_sources"

with open(pyz_path, 'rb') as f:
    data = f.read()

# PYZ header
assert data[:3] == b'PYZ', f"Bad magic: {data[:4]}"
toc_len = struct.unpack('<I', data[4:8])[0]
print(f"TOC length: {toc_len}")

# TOC is zlib compressed
toc_compressed = data[8:8+toc_len]
toc_raw = zlib.decompress(toc_compressed)
print(f"TOC decompressed: {len(toc_raw)} bytes")

# Parse TOC: (is_pkg, filename, uncompressed_len, compressed_len, flag_compressed)
# TOC format: struct of tuples - each entry: (name, type, data)
# Actually PyInstaller uses marshal for TOC
import types
# The TOC is a list of tuples: (name, type, uncompressed_len, compressed_len, compressed_flag)
# TOC is marshalled
import marshal
toc = marshal.loads(toc_raw)
print(f"TOC type: {type(toc)}")
if isinstance(toc, list):
    print(f"TOC entries: {len(toc)}")
if isinstance(toc, dict):
    print(f"TOC entries: {len(toc)}")

# PyInstaller stores as dict: filename -> (typecode, uncompressed_len, compressed_len, flag)
# or list of tuples depending on version
structure = toc
if isinstance(toc, dict):
    items = list(toc.items())
else:
    items = toc

# Offset after TOC
offset = 8 + toc_len
os.makedirs(out_dir, exist_ok=True)

extracted = []
for item in items:
    if isinstance(item, tuple) and len(item) >= 4:
        name = item[0]
        # Skip PYZ entries (PYSOURCE/PYCODE etc)
        if name == 'PYSOURCE' or name == 'PYCODE':
            continue
        typecode = item[1]
        if isinstance(typecode, int):
            # PyInstaller >= 6 typecode
            # 115='s' = SOURCE, 99='c' = CODE (PYC), 100='d' = DATA
            pass
        
        # Get length info
        if isinstance(item[2], int):
            compressed_len = item[2]
            flag_compressed = item[0] if isinstance(item[0], int) else 0
        else:
            continue
        
    elif isinstance(item, tuple) and len(item) == 3:
        name, typecode, pos_data = item
        compressed_len = getattr(pos_data, 'length', 0) if hasattr(pos_data, 'length') else 0
    else:
        continue

# Simpler approach: iterate TOC entries directly
# PyInstaller stores: (name, type, uncompressed_len, compressed_len, compressed_flag) as marshalled objects
pos = 0
file_data_start = 8 + toc_len
count = 0

# Try to parse TOC as marshalled data and find proxy entries
# The TOC is a marshal stream containing tuples
import io

print("\n--- Scanning for proxy-related entries ---")
# Use the unmarshalled TOC directly
if isinstance(toc, (list, tuple)):
    for idx, entry in enumerate(toc):
        if isinstance(entry, tuple) and len(entry) >= 3:
            name = entry[0] if isinstance(entry[0], str) else ''
            if 'proxy' in name.lower():
                print(f"  [{idx}] {name}: {entry}")
                # Try to extract
                if len(entry) >= 5:
                    # (name, typecode, uncompressed_len, compressed_len, compressed_flag)
                    uncompressed_len = entry[2] if isinstance(entry[2], int) else 0
                    compressed_len = entry[3] if isinstance(entry[3], int) else 0
                    compressed_flag = entry[4]
                    if compressed_flag and compressed_len > 0:
                        # Read from file data
                        raw = data[file_data_start:file_data_start+compressed_len]
                        try:
                            decompressed = zlib.decompress(raw)
                        except:
                            decompressed = raw
                    elif uncompressed_len > 0:
                        raw = data[file_data_start:file_data_start+uncompressed_len]
                        decompressed = raw
                    else:
                        continue
                    
                    # Save file
                    out_path = os.path.join(out_dir, name)
                    os.makedirs(os.path.dirname(out_path), exist_ok=True)
                    with open(out_path, 'wb') as f:
                        f.write(decompressed)
                    print(f"    -> Saved: {out_path} ({len(decompressed)} bytes)")
                    extracted.append(name)
                    
                    # Update file data start
                    if compressed_len > 0:
                        file_data_start += compressed_len
                    elif uncompressed_len > 0:
                        file_data_start += uncompressed_len
                    count += 1
        elif isinstance(entry, tuple):
            name = entry[0] if isinstance(entry[0], str) else ''
            if 'proxy' in name.lower():
                print(f"  [{idx}] {name}: {entry}")
elif isinstance(toc, dict):
    for name, entry in toc.items():
        if 'proxy' in name.lower():
            print(f"  {name}: {entry}")

print(f"\nExtracted {count} files to {out_dir}")
print(f"Files: {extracted}")
