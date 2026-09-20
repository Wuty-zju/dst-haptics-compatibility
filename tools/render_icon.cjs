// Reproducible vector artwork. Install sharp in your development environment,
// or set NODE_PATH to the shared runtime's node_modules directory.
const path = require('node:path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
async function main() {
  const source = path.join(root, 'assets', 'icon.svg');
  await sharp(source).flatten({background: '#f5f5f0'}).jpeg({quality: 94}).toFile(path.join(root, 'preview.jpg'));
  await sharp(source).resize(128, 128).png().toFile(path.join(root, 'assets', 'modicon.png'));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
