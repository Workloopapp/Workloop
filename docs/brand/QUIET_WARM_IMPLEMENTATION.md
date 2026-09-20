# Quiet + Warm — approved visual direction

User approved the A Quiet retro + B Warm desktop combined concept on 4 September 2026 and explicitly requested rollout across the whole app, website, emails, icons, splash, logo and social assets. The reference is quiet-warm-approved.png. This supersedes earlier Studio/indigo/rounded-dock visual rules; preserve workflows, routes, providers, data, existing accessibility and preferences.

## Shared contract

- Canvas/paper: #F5EDD9; lighter cream #FBF7ED; powder-blue header field #C3D7E4; control/header blue #91B4C8; muted yellow #F0D18B; primary ink/borders #443C32; blue selected ink #286280; small coral accent #D57958.
- Use dark text on blue/yellow fills. Secondary ink must retain readable contrast. Warm compatible dark mode remains supported, with light cream text on deep warm neutral surfaces and powder-blue accents.
- Fine 1px–1.5px visible brown outlines, 6–10px moderate corners, short 1–2px tactile offset shadows on primary controls only; avoid heavy cartoon shadows, giant pills and floating dock styling.
- Simple lowercase workloop wordmark using the existing humanist Manrope family; no chunky/outlined retro lettering. Main body/headings remain Manrope; small uppercase section captions/date may use a bundled licensed monospaced font. No pixel body typography.
- Five-destination bottom navigation Today / Clients / Work / Money / Business: cream full-width bar, delicate vertical separators, illustrated line icons, blue selected label/top edge, no large yellow tiles. Respect safe area and 44pt/48dp targets.
- Useful illustrated calendar, clock, folder, receipt, tools and storefront details, drawn natively or supplied as original vector artwork. No UI raster screenshots, fake desktop close/minimise controls, oversized hero illustrations, invented metrics or live-looking demo data.
- Framed panels with narrow blue or yellow title strips, comfortable lists and ruled sections; avoid nesting redundant cards. Tabs can use the clean folder-tab treatment.
- Today retains actual next booking, attention and schedule logic; Client retains actual tabs/actions; Money retains Made/Spent/Owed and actual totals/payment state. Screens must genuinely resemble the approved composition, not merely recolour old layouts.
- Root owns brand masters, native icon/splash, runtime font/assets declarations and overall release. Foundation agent owns theme/shared widgets/illustrated icon components. Screen agent owns lib/features presentation. Web/email agent owns marketing website and transactional email presentation. Coordinate shared API changes before use.

## Rollout evidence

Implementation is in progress. Do not describe generated concept imagery as app or deployment evidence. Record inspected screenshots, analysis/tests, signed builds, live website/email-template deployment and any provider-owned branding gates before declaring rollout complete.

### 5 September polish amendment

The earlier vertical navigation separators are superseded: bottom navigation is
one continuous cream surface through the safe area, with a blue top marker and
selected label. Paper-panel frames are 1.5 points and paint above header fills.
Every page has an opaque shared backdrop to prevent transition bleed-through.
See the dated amendment in `docs/UIDesignSystem.md` for the current contract.

### Final owner refinement — compact divided navigation

The owner subsequently chose to keep vertical dividers. Draw them through the
complete bottom safe area. The final button row is **52 points plus the device
bottom safe area**, with **26-point icons**, following the interim 64-point
revision. Navigation captions remain visible and their text scaling is capped
at 1.3×, with modest row growth; body text keeps the user's full scaling. This
supersedes the separator removal above; the rest of the polish amendment still
applies.

### 9 September refinement — dark charcoal and powder blue

The owner requested a better dark palette while preserving Light. Dark now uses
deep charcoal with a restrained blue cast: canvas `#171D22`, paper `#212A31`,
raised surfaces `#2B363F` and controls `#33404A`. Soft ivory `#F4F0E7` and neutral
secondary text replace the previous taupe ink. Frames are quieter blue-grey;
powder-blue actions and header strips carry the hierarchy. Amber, coral and
green remain restrained status accents.

Light colours, typography, layout, illustrations and workflows are unchanged.
This supersedes the earlier brown/ochre Dark palette only. The refinement is
local and held for the owner's next combined release.

### Final owner refinement — no cards inside boxes

Use one outer content frame for each grouped section, with flat rows, plain
empty-state copy and optional rules inside it. Never nest another rounded
content card in that frame. Standalone cards, form controls, buttons and small
icon fields keep their useful boundaries. This applies to linked screens and
import previews as well as the main workspaces.
