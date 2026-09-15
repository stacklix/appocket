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

# The launcher is a PWA itself. Its worker caches only the launcher allowlist,
# and lets requests to unvisited sub-apps reach the network unchanged.
launcher_files = ['index.html', 'manifest.json', 'icons/icon-192.png', 'icons/icon-512.png']
for name in launcher_files:
    target = ROOT / 'dist' / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / name, target)
launcher_template = template.replace('`sentra:${ROOT}:`', '`appocket:${ROOT}:`')
launcher_template = launcher_template.replace(
    "const target = request.mode === 'navigate'",
    "const target = request.mode === 'navigate' && (url.pathname === '/' || url.pathname === '/index.html')")
launcher_digest = hashlib.sha256(launcher_template.encode())
for name in launcher_files:
    launcher_digest.update((ROOT / name).read_bytes())
launcher_worker = launcher_template.replace('__VERSION__', json.dumps(launcher_digest.hexdigest()[:16]))
launcher_worker = launcher_worker.replace('__FILES__', json.dumps(launcher_files))
(ROOT / 'dist' / 'sw.js').write_text(launcher_worker)
print('Built Appocket launcher PWA.')
