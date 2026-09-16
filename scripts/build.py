#!/usr/bin/env python3
"""Build independently scoped PWA sub-apps into a single static site."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'sentra'
subprocess.run([
    'flutter', 'build', 'web', '--release', '--base-href=/sentra/',
    '--no-web-resources-cdn', '--pwa-strategy=none',
], cwd=APP, check=True)
output = ROOT / 'dist' / 'sentra'
if output.exists():
    shutil.rmtree(output)
shutil.copytree(APP / 'build' / 'web', output)
# The project owns its service worker rather than Flutter's deprecated generator.
(output / 'flutter_service_worker.js').unlink(missing_ok=True)
paths = sorted(p for p in output.rglob('*') if p.is_file() and p.name != 'sw.js')
files = [p.relative_to(output).as_posix() for p in paths]
template = (ROOT / 'scripts' / 'sw.js').read_text()
digest = hashlib.sha256(template.encode())
for path, name in zip(paths, files):
    digest.update(name.encode())
    digest.update(path.read_bytes())
worker = template.replace('__VERSION__', json.dumps(digest.hexdigest()[:16]))
worker = worker.replace('__FILES__', json.dumps(files))
(output / 'sw.js').write_text(worker)
shutil.copyfile(ROOT / 'index.html', ROOT / 'dist' / 'index.html')
print(f'Built {output}; precached {len(files)} files.')

# Appocket is a directory; keep a retirement worker for existing installations.
shutil.copytree(ROOT / 'icons', ROOT / 'dist' / 'icons', dirs_exist_ok=True)
(ROOT / 'dist' / 'manifest.json').unlink(missing_ok=True)
shutil.copyfile(ROOT / 'scripts' / 'retire-root-sw.js', ROOT / 'dist' / 'sw.js')
print('Built Appocket app directory.')
