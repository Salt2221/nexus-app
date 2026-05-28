import re
import os

filepath = r"C:\Users\roman\.openclaw\workspace\nexus\tools\TgWsProxy_window.exe"
with open(filepath, "rb") as f:
    data = f.read()

print(f"File size: {len(data)} bytes")

# Extract ASCII strings (minimum 6 chars)
pattern = rb'[\x20-\x7E]{6,}'
matches = re.findall(pattern, data)
strings = [m.decode('ascii') for m in matches]
print(f"Total strings: {len(strings)}")

# Filter for MTProto/proxy/key related
keywords = ['mtproto', 'proxy', 'secret', 'fake', 'obfuscated', 'cipher', 'aes', 'key', 'nonce', 
            'random', 'dc1', 'dc2', 'dc3', 'dc4', 'dc5', 'telegram', 'conn', 'addr', 'port']
filtered = [s for s in strings if any(k in s.lower() for k in keywords)]
print(f"\n=== MTProto/Proxy related ({len(filtered)}) ===")
for s in sorted(set(filtered)):
    print(s)

# Look for Python files
py_files = [s for s in strings if s.endswith('.py') and not s.startswith('_') and not any(x in s.lower() for x in ['hook', 'test', 'site', 'ctypes', 'importlib', 'setuptools', 'pytz', 'dill', 'certifi', 'charset', 'requests', 'urllib', 'idna', 'pathlib', 'asyncio', 'json', 'logging', 'socket', 'ssl', 'hashlib', 'base64', 'threading', 'time', 'os', 'sys', 're', 'math', 'random', 'string', 'typing', 'collections', 'abc', 'functools', 'operator', 'inspect', 'itertools', 'copy', 'configparser', 'argparse', 'textwrap', 'enum', 'decimal', 'datetime', 'io', 'struct', 'binascii'])]
print(f"\n=== Custom Python files ===")
for s in sorted(set(py_files)):
    print(s)

# Look for JSON/YAML configs
configs = [s for s in strings if s.endswith(('.json', '.yaml', '.yml', '.conf')) and 'site-packages' not in s and 'lib' not in s]
print(f"\n=== Config files ===")
for s in sorted(set(configs)):
    print(s)
