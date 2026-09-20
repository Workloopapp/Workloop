/** Rasterize brand masters; by default also install the native app exports. */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

function loadSharp() {
  // An explicit override is authoritative: report a typo instead of silently
  // switching renderer versions, which would hide export reproducibility drift.
  if (process.env.WORKLOOP_SHARP_MODULE) return require(process.env.WORKLOOP_SHARP_MODULE);
  const candidates = [
    'sharp',
    path.resolve(path.dirname(process.execPath), '../node_modules/sharp'),
    path.join(os.homedir(), '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp'),
  ];
  for (const candidate of candidates) {
    try { return require(candidate); }
    catch (error) { if (error.code !== 'MODULE_NOT_FOUND') throw error; }
  }
  throw new Error('Sharp is unavailable. Install it in a tooling environment and set WORKLOOP_SHARP_MODULE to its module directory. See assets/brand/quiet-warm/README.md.');
}
const sharp = loadSharp();
const root = path.resolve(__dirname, '../..');
const out = path.join(root, 'assets/brand/quiet-warm');
const exportsOnly = process.argv.includes('--exports-only');
if (process.argv.slice(2).some(arg => arg !== '--exports-only')) {
  throw new Error('Usage: node scripts/brand/render_quiet_warm.cjs [--exports-only]');
}
async function png(src, dest, w, h, opaque = false) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  let image = sharp(src).resize(w, h, { fit: 'contain' });
  if (opaque) image = image.flatten({ background: '#C3D7E4' });
  await image.png().toFile(dest);
}
async function windowsIco(source, destination) {
  // Modern Windows accepts PNG frames in an ICO directory. Keep real small
  // frames so taskbars/file lists need not downsample a lone 256px image.
  const sizes = [16, 24, 32, 48, 64, 128, 256];
  const frames = await Promise.all(sizes.map(size => sharp(source)
    .resize(size, size).flatten({ background: '#C3D7E4' }).png().toBuffer()));
  const directory = Buffer.alloc(6 + sizes.length * 16);
  directory.writeUInt16LE(1, 2);
  directory.writeUInt16LE(sizes.length, 4);
  let offset = directory.length;
  frames.forEach((frame, index) => {
    const entry = 6 + index * 16;
    directory[entry] = directory[entry + 1] = sizes[index] === 256 ? 0 : sizes[index];
    directory.writeUInt16LE(1, entry + 4);
    directory.writeUInt16LE(32, entry + 6);
    directory.writeUInt32LE(frame.length, entry + 8);
    directory.writeUInt32LE(offset, entry + 12);
    offset += frame.length;
  });
  fs.writeFileSync(destination, Buffer.concat([directory, ...frames]));
}
async function installCatalog(directory, source) {
  const contents = JSON.parse(fs.readFileSync(path.join(directory, 'Contents.json')));
  for (const asset of contents.images) {
    if (!asset.filename) continue;
    const n = Math.round(parseFloat(asset.size) * parseFloat(asset.scale));
    await png(source, path.join(directory, asset.filename), n, n, true);
  }
}
async function main() {
  const manifest = JSON.parse(fs.readFileSync(path.join(out, 'manifest.json')));
  for (const required of ['splash-lockup-dark.svg', 'android-adaptive-monochrome.xml']) {
    if (!fs.existsSync(path.join(out, required))) {
      throw new Error(`Missing ${required}. Run generate_quiet_warm.py successfully before rendering.`);
    }
  }
  for (const asset of manifest.masters) {
    await png(path.join(out, asset.source), path.join(out, asset.name + '.png'), asset.width, asset.height);
  }
  const appIcon = path.join(out, 'app-icon-blue.svg');
  for (const size of [16, 24, 32, 48, 64, 128, 180, 192, 256, 384, 512, 1024, 2048]) {
    await png(appIcon, path.join(out, `icon-${size}.png`), size, size, true);
  }
  for (const name of ['wordmark-ink', 'wordmark-cream', 'lockup-horizontal-ink', 'lockup-horizontal-cream']) {
    const asset = manifest.masters.find(item => item.name === name);
    for (const width of [512, 1024, 2048]) {
      await png(path.join(out, asset.source), path.join(out, `${name}-${width}.png`), width, Math.round(width * asset.height / asset.width));
    }
  }
  // Preserve the already-approved colour foreground geometry.
  const symbol = fs.readFileSync(path.join(out, 'symbol-colour.svg'), 'utf8')
    .replace(/^<svg[^>]*>/, '').replace(/<\/svg>$/, '');
  const adaptive = `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1080" viewBox="0 0 1080 1080"><g transform="translate(250 285) scale(1.1328125)">${symbol}</g></svg>`;
  fs.writeFileSync(path.join(out, 'android-adaptive-foreground.svg'), adaptive);
  await png(Buffer.from(adaptive), path.join(out, 'android-adaptive-foreground.png'), 1080, 1080);
  const ico = path.join(out, 'workloop-windows.ico');
  await windowsIco(appIcon, ico);
  if (!exportsOnly) {
    await installCatalog(path.join(root, 'ios/Runner/Assets.xcassets/AppIcon.appiconset'), appIcon);
    const launch = path.join(root, 'ios/Runner/Assets.xcassets/LaunchImage.imageset');
    const catalog = JSON.parse(fs.readFileSync(path.join(launch, 'Contents.json')));
    for (const asset of catalog.images) {
      if (!asset.filename) continue;
      const dark = asset.appearances?.some(item => item.appearance === 'luminosity' && item.value === 'dark');
      const size = 280 * parseFloat(asset.scale);
      await png(path.join(out, dark ? 'splash-lockup-dark.svg' : 'splash-lockup.svg'), path.join(launch, asset.filename), size, size);
    }
    const res = path.join(root, 'android/app/src/main/res');
    for (const [density, scale] of [['mdpi', 1], ['hdpi', 1.5], ['xhdpi', 2], ['xxhdpi', 3], ['xxxhdpi', 4]]) {
      const directory = path.join(res, 'mipmap-' + density);
      await png(appIcon, path.join(directory, 'ic_launcher.png'), 48 * scale, 48 * scale, true);
      await png(Buffer.from(adaptive), path.join(directory, 'ic_launcher_foreground.png'), 108 * scale, 108 * scale);
      for (const dark of [false, true]) {
        await png(path.join(out, dark ? 'splash-lockup-dark.svg' : 'splash-lockup.svg'),
          path.join(res, `drawable-${dark ? 'night-' : ''}${density}`, 'launch_image.png'), 280 * scale, 280 * scale);
      }
    }
    fs.copyFileSync(path.join(out, 'android-adaptive-monochrome.xml'), path.join(res, 'drawable/ic_launcher_monochrome.xml'));
    for (const name of ['ic_launcher', 'ic_launcher_round']) {
      const destination = path.join(res, 'mipmap-anydpi-v33', name + '.xml');
      fs.mkdirSync(path.dirname(destination), { recursive: true });
      fs.writeFileSync(destination, `<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n    <background android:drawable="@color/workloop_icon_background" />\n    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />\n</adaptive-icon>\n`);
    }
    const web = path.join(root, 'web');
    await png(appIcon, path.join(web, 'favicon.png'), 32, 32, true);
    for (const size of [192, 512]) {
      for (const prefix of ['Icon', 'Icon-maskable']) await png(appIcon, path.join(web, `icons/${prefix}-${size}.png`), size, size, true);
    }
    const mac = path.join(root, 'macos/Runner/Assets.xcassets/AppIcon.appiconset');
    if (fs.existsSync(mac)) await installCatalog(mac, appIcon);
    fs.copyFileSync(ico, path.join(root, 'windows/runner/resources/app_icon.ico'));
  }
  console.log(`Rendered Quiet + Warm exports${exportsOnly ? '' : ' and native icons/light+dark splash'} with Sharp ${sharp.versions.sharp}, libvips ${sharp.versions.vips}.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
