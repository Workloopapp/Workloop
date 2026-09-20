"""Package generated Workloop brand deliverables without uploading anything."""
from pathlib import Path
import argparse
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=ROOT.parent / 'Workloop-Releases/brand-quiet-warm/workloop-quiet-warm-brand.zip')
args = parser.parse_args()
brand = ROOT / 'assets/brand/quiet-warm'
required = ['manifest.json', 'README.md', 'canva-links.json', 'splash-lockup-dark.png',
            'workloop-windows.ico', 'android-adaptive-monochrome.xml']
for name in required:
    if not (brand / name).is_file():
        parser.error(f'Missing {name}: generate and render the brand kit first.')
files = list(brand.glob('*')) + list((ROOT / 'scripts/brand').glob('*.py')) + list((ROOT / 'scripts/brand').glob('*.cjs'))
for name in ['Manrope-Variable.ttf', 'Manrope-OFL.txt', 'WorkloopMono-Regular.ttf', 'WorkloopMono-OFL.txt']:
    files.append(ROOT / 'assets/fonts' / name)
for folder in ['ios/Runner/Assets.xcassets/AppIcon.appiconset', 'ios/Runner/Assets.xcassets/LaunchImage.imageset',
               'macos/Runner/Assets.xcassets/AppIcon.appiconset', 'windows/runner/resources']:
    files.extend((ROOT / folder).glob('*'))
res = ROOT / 'android/app/src/main/res'
for pattern in ['mipmap-*/ic_launcher*', 'drawable-*/launch_image.png', 'drawable/ic_launcher_monochrome.xml']:
    files.extend(res.glob(pattern))
files.extend((ROOT / 'web/icons').glob('*.png'))
files.append(ROOT / 'web/favicon.png')
files = sorted({file for file in files if file.is_file()})
entries = {str(file.relative_to(ROOT)): file.read_bytes() for file in files}
inventory = {'format': 1, 'files': {name: {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
                                 for name, data in entries.items()}}
entries['PACKAGE_MANIFEST.json'] = (json.dumps(inventory, indent=2, sort_keys=True) + '\n').encode()
args.output.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(args.output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for name, data in sorted(entries.items()):
        info = zipfile.ZipInfo('workloop-quiet-warm/' + name, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o100644 << 16
        info.create_system = 3
        archive.writestr(info, data)
digest = hashlib.sha256(args.output.read_bytes()).hexdigest()
args.output.with_suffix('.zip.sha256').write_text(f'{digest}  {args.output.name}\n')
print(json.dumps({'zip': str(args.output), 'files': len(entries), 'bytes': args.output.stat().st_size, 'sha256': digest}))
