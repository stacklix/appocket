import { readFile, writeFile, mkdir, cp, rm } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '..');
const base = (process.env.MODULE_BASE_URL || 'https://appocket.stackli.me').replace(/\/$/, '');
if (new URL(base).protocol !== 'https:') throw new Error('MODULE_BASE_URL must use HTTPS');
const names = JSON.parse(await readFile(path.join(root, 'modules.json'), 'utf8'));
const retire = `self.addEventListener('install',()=>self.skipWaiting());self.addEventListener('activate',event=>event.waitUntil((async()=>{await self.registration.unregister();await self.clients.claim();})()));`;
const modules = [];
await rm(path.join(root, 'ios/Appocket/Resources/BuiltinModules'), {
  recursive: true,
  force: true,
});
await mkdir(path.join(root, 'dist/packages'), { recursive: true });
for (const name of names) {
  const manifest = JSON.parse(await readFile(path.join(root, name, 'manifest.json'), 'utf8'));
  if (!/^[a-z0-9][a-z0-9-]{0,63}$/.test(manifest.id) || !/^\d+\.\d+\.\d+$/.test(manifest.version))
    throw new Error('Invalid module identity');
  if (manifest.id !== name) throw new Error('Module ID must match its directory name');
  const output = path.join(root, 'dist', name);
  await writeFile(path.join(output, 'sw.js'), retire);
  await writeFile(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2));
  const archive = `${manifest.id}-${manifest.version}.zip`;
  const zipPath = path.join(root, 'dist/packages', archive);
  const result = spawnSync('python3', [path.join(root, 'scripts/stored-zip.py'), output, zipPath], {
    stdio: 'inherit',
  });
  if (result.status !== 0) throw new Error('ZIP packaging failed');
  const data = await readFile(zipPath);
  modules.push({
    ...manifest,
    webUrl: `${base}/${name}/`,
    downloadUrl: `${base}/packages/${archive}`,
    size: data.length,
    sha256: createHash('sha256').update(data).digest('hex'),
  });
  const builtin = path.join(root, 'ios/Appocket/Resources/BuiltinModules', manifest.id);
  await rm(builtin, { recursive: true, force: true });
  await mkdir(path.dirname(builtin), { recursive: true });
  await cp(output, builtin, { recursive: true });
}
await writeFile(path.join(root, 'dist/catalog.json'), JSON.stringify({ modules }, null, 2));
// Remove obsolete generated artifacts from builds using the old catalog format.
await rm(path.join(root, 'dist/public-key.txt'), { force: true });
await rm(path.join(root, 'dist/catalog.preview.json'), { force: true });
await cp(path.join(root, 'index.html'), path.join(root, 'dist/index.html'));
await writeFile(path.join(root, 'dist/sw.js'), retire);
await writeFile(path.join(root, 'dist/.nojekyll'), '');
// GitHub project domains use their default hostname; custom domains need CNAME.
const hostname = new URL(base).hostname;
if (!hostname.endsWith('.github.io'))
  await writeFile(path.join(root, 'dist/CNAME'), hostname + '\n');
console.log(
  `Built ${modules.length} module(s), static catalog, archives and native bundled resources.`,
);
