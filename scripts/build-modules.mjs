import { readFile, rm } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
const root = path.resolve(import.meta.dirname, '..');
const modules = JSON.parse(await readFile(path.join(root, 'modules.json'), 'utf8'));
if (
  !Array.isArray(modules) ||
  !modules.length ||
  new Set(modules).size !== modules.length ||
  modules.some((name) => typeof name !== 'string' || !/^[a-z0-9][a-z0-9-]{0,63}$/.test(name))
) {
  throw new Error('modules.json must contain unique module directory names');
}
// Build from a clean directory so retired modules/assets cannot leak into a release.
await rm(path.join(root, 'dist'), { recursive: true, force: true });
for (const module of modules) {
  const result = spawnSync('npm', ['run', 'build', '--workspace', module], {
    cwd: root,
    stdio: 'inherit',
  });
  if (result.status !== 0) throw new Error(`Build failed: ${module}`);
}
await import('./package-modules.mjs');
