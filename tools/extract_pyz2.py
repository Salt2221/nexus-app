"""Extract proxy module files from PYZ"""
import struct, zlib, marshal, os

pyz_path = r"C:\Users\roman\.openclaw\workspace\pyinstxtractor\TgWsProxy_window.exe_extracted\PYZ-00.pyz"
out_dir = r"C:\Users\roman\.openclaw\workspace\nexus\tools\proxy_sources"
windows_pyc_path = r"C:\Users\roman\.openclaw\workspace\pyinstxtractor\TgWsProxy_window.exe_extracted\windows.pyc"
os.makedirs(out_dir, exist_ok=True)

with open(pyz_path, 'rb') as f:
    data = f.read()

# Parse PYZ v2 format (PyInstaller 5+)
# PYZ format: b'PYZ\x00' + 4 bytes TOC uncompressed size + zlib compressed data
# The zlib data contains: marshalled TOC dict + file data
assert data[:3] == b'PYZ', f"Bad magic"
toc_uncompressed_size = struct.unpack('<I', data[4:8])[0]
print(f"PYZ header OK. TOC uncompressed size: {toc_uncompressed_size}")

# The zlib data starts at offset 8
zlib_data = data[8:]
print(f"Zlib data size: {len(zlib_data)}")

# Decompress
try:
    decompressed = zlib.decompress(zlib_data)
except zlib.error as e:
    print(f"Zlib decompress failed: {e}")
    # Maybe raw deflate
    try:
        decompressed = zlib.decompress(zlib_data, -zlib.MAX_WBITS)
        print("Used raw deflate")
    except:
        # Try without header
        import subprocess
        result = subprocess.run(['python', '-c', f"""
import zlib, sys
with open(r'{pyz_path}', 'rb') as f:
    data = f.read()
# Skip PYZ header
rest = data[8:]
# Find zlib header (0x78)
for i in range(len(rest)):
    if rest[i] == 0x78:
        try:
            d = zlib.decompress(rest[i:])
            with open(r'{out_dir}\\__toc_raw.bin', 'wb') as of:
                of.write(d)
            print(f'Decompressed from offset {{i}}, size: {{len(d)}}')
            break
        except:
            pass
"""], capture_output=True, text=True)
        print(result.stdout)
        print(result.stderr)
        sys.exit(0)

print(f"Decompressed size: {len(decompressed)}")

# Parse marshalled TOC
# PyInstaller 5+ stores TOC as a dict with module_path -> {typecode, data_offset, compressed_len, uncompressed_len, is_pkg}
# The file data follows the TOC

toc_end = 0
# TOC is a dict marshalled
toc_raw = decompressed[:200000]  # assume TOC is within first 200KB
# Actually just search for the dict markers
import io
stream = io.BytesIO(decompressed)
# Skip the first entry which is a zlib-compressed dict
# Actually the whole decompressed data is a marshal stream
# Marshal format: type byte + data
# type 'd' (100) = dict, type 'l' (108) = list, 'c' (99) = code object

# Find proxy entries by scanning the decompressed text
print("\nSearching for proxy module names...")
for i, b in enumerate(decompressed):
    if i % 10000 == 0:
        pass
    
text = decompressed.decode('latin-1')
for name in ['proxy/tg_ws_proxy', 'proxy/fake_tls', 'proxy/config', 'proxy/balancer', 'proxy/bridge', 'proxy/raw_websocket', 'proxy/stats', 'proxy/utils']:
    idx = text.find(name)
    if idx >= 0:
        print(f"  Found '{name}' at offset {idx}")
        # Read surrounding context (200 bytes)
        start = max(0, idx - 20)
        end = min(len(text), idx + len(name) + 4)
        ctx = text[start:end].encode('latin-1')
        print(f"    Context: {ctx[:80]}")
    else:
        print(f"  NOT FOUND: '{name}'")

# Actually the TOC is marshal'd, let's try to unmarshal it
try:
    import io
    stream = io.BytesIO(decompressed)
    toc = marshal.load(stream)
    print(f"\nTOC type: {type(toc)}")
    if isinstance(toc, dict):
        print(f"TOC entries: {len(toc)}")
        for k, v in list(toc.items())[:5]:
            print(f"  {k}: {type(v)} {v if not isinstance(v, (bytes, bytearray)) else v[:20]}")
        proxy_items = {k: v for k, v in toc.items() if 'proxy' in k.lower()}
        print(f"Proxy entries: {len(proxy_items)}")
        for k, v in proxy_items.items():
            print(f"  {k}: {v}")
    elif isinstance(toc, list):
        print(f"TOC list entries: {len(toc)}")
        for item in toc[:5]:
            print(f"  {item}")
except Exception as e:
    print(f"Marshalling failed: {e}")

print("\nDone")
