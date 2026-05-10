const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const repoRoot = process.cwd();
const outDir = path.join(repoRoot, 'out');
const destinationDir = path.join(os.homedir(), 'Downloads', 'Lumina Forge');
const destinationApp = path.join(destinationDir, 'Lumina Forge.app');

function findApp(startPath) {
  if (!fs.existsSync(startPath)) return null;
  const entries = fs.readdirSync(startPath, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(startPath, entry.name);
    if (entry.isDirectory() && entry.name === 'Lumina Forge.app') return full;
    if (entry.isDirectory()) {
      const nested = findApp(full);
      if (nested) return nested;
    }
  }
  return null;
}

const foundApp = findApp(outDir);
if (!foundApp) {
  console.log('No Lumina Forge.app found in out/; skipping copy.');
  process.exit(0);
}

fs.mkdirSync(destinationDir, { recursive: true });
fs.rmSync(destinationApp, { recursive: true, force: true });
fs.cpSync(foundApp, destinationApp, { recursive: true });

console.log(`Copied ${foundApp} -> ${destinationApp}`);
