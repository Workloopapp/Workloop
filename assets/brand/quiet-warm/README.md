# Workloop — Quiet + Warm brand kit

Original Workloop window mark and lowercase Manrope wordmark. Use the cream/powder-blue artwork as supplied; keep clear space around the logo and let the platform apply app-icon masks. Do not add gradients, rounded-square masks, or shadows to the exported app icon.

## Ready-to-use files

| Use | File / size |
| --- | --- |
| Scalable wordmark | `wordmark-{ink,cream,black,white}.svg` |
| Transparent wordmark PNG | ink/cream at 512, 1024 and 2048 px wide |
| Compact symbol | `symbol-colour.svg`, four single-colour variants;512×448 |
| Horizontal / stacked logo | `lockup-horizontal-*`1400×350, `lockup-stacked-*`1080×1080 |
| App-store master | `app-icon-blue.png`,1024×1024, opaque; cream/dark alternatives included |
| Small icons / favicons | `icon-{16,24,32,48,64,128,180,192,256,384,512,1024,2048}.png` |
| Windows icon | `workloop-windows.ico`,16/24/32/48/64/128/256px PNG frames,32-bit directory entries |
| Social avatars | `avatar-{cream,blue,dark}.png`,1080×1080, circle-safe central mark |
| Social square / portrait / story |1080×1080 /1080×1350 /1080×1920 |
| Social preview / banner |1200×630 /1500×500 |
| Facebook / YouTube cover |1640×924 /2560×1440; preview the destination crop before uploading |
| Light / dark splash | `splash-lockup.svg`, `splash-lockup-dark.svg`,840×840 transparent; dark uses cream lettering |
| Android adaptive foreground | `android-adaptive-foreground.svg`,1080×1080 transparent |
| Android themed icon | `android-adaptive-monochrome.xml` native108dp vector; SVG/PNG alpha-mask previews included |

The adaptive monochrome drawing is centred inside a 48×42 dp footprint on a 108 dp canvas, fitting within the 66 dp safe region. Android supplies its final colour. It is separate from the 24 dp notification status icon. Native splash exports are 280/560/840 px for iOS and 280/420/560/840/1120 px for Android density variants, including both light and dark appearances.

## Colour and typography

Cream `#F5EDD9`; paper `#FBF7ED`; powder blue `#C3D7E4`; control blue `#91B4C8`; brown ink `#443C32`; selected blue `#286280`; yellow `#F0D18B`; dark canvas `#24231F`.

Manrope is used for the outlined brand lettering (weight650) and reading. IBM Plex Mono is reserved for small labels/dates. SVG lettering is converted to paths so exported artwork does not depend on installed fonts. Editable Canva HTML retains actual text. The distributable includes the original font files and their SIL Open Font License notices under `assets/fonts`; the WorkloopMono filename is the local family alias for IBM Plex Mono.

## Existing editable Canva master

[Open the existing eight-page Canva brand master](https://www.canva.com/d/ELT2-o4qmvAV8rN).

`canva-links.json` preserves its design ID and link. `canva-brand-masters.html` is a local editable source; running these scripts does not upload or replace the Canva design. Refresh that design separately when changing the source palette or artwork.

## Regenerate

Run from the Workloop repository root (or the extracted kit root for exports only). Build tooling only: Python3 + `fonttools==4.64.0`; Node.js + `sharp==0.35.4` (verified with bundled libvips 8.18.6). Install these in a tooling environment; no Flutter dependency changes are needed.

```sh
python3 scripts/brand/generate_quiet_warm.py
node scripts/brand/render_quiet_warm.cjs --exports-only
```

To regenerate AND install the platform icon/splash assets in the real Flutter repository, omit `--exports-only`. The renderer follows the iOS/macOS asset-catalog sizes and iOS dark appearance entries. It writes both Android splash density sets, Android 13 monochrome XML references, web icons and WindowsICO. It deliberately never rewrites the notification status icon, native colour/style XML, or splash storyboards.

Sharp is resolved in this order: explicit `WORKLOOP_SHARP_MODULE`, normal local Node resolution, a module next to the active bundled Node executable, then the current user's Codex bundled runtime. An explicit invalid override fails rather than silently switching versions. Example for a separate tooling install:

```sh
WORKLOOP_SHARP_MODULE=/absolute/tooling/node_modules/sharp node scripts/brand/render_quiet_warm.cjs --exports-only
```

If fontTools is installed in a separate target directory, set `PYTHONPATH` to that directory when running the Python generator. The current workstation uses `/tmp/workloop-brand-tools`; that temporary path is not needed by recipients who install the pinned tool normally.

Build the distributable with:

```sh
python3 scripts/brand/package_quiet_warm.py --output /absolute/output/workloop-quiet-warm-brand.zip
```

The ZIP contains all masters/rasters, this guide, generator scripts, fonts/licenses, selected native exports and a SHA-256 file inventory. It excludes the generated concept screenshot: that image is approval context, not shipped UI evidence. Repeated packaging with unchanged inputs produces identical ZIP bytes. Native app build/device checks and public uploads are separate release steps.

Platform references: [Android adaptive icons](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive), [Windows icon guidance](https://learn.microsoft.com/en-us/windows/win32/uxguide/vis-icons).
