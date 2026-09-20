# Workloop websites dependency audit — 4 September 2026

## Applied patch update — 4 September 2026

Both deployed sites now use React/React DOM/RSC 19.2.8 and Vite 8.0.16. Marketing additionally uses Next/eslint-config-next 16.2.11 with targeted PostCSS 8.5.23 resolutions in synchronized npm/pnpm lockfiles. Production builds and typechecks passed; marketing 19 tests and OS adapter/runner checks passed. Marketing v28 and private OS v15 are deployed and verified at their actual domains. The exposed React parser dependency is patched.

Residual marketing npm audit reports 19 affected entries (13 high, five moderate, one low), predominantly toolchain/development dependencies discussed below. The Cloudflare/Miniflare major toolchain change, unpublished image-size fix and incompatible automatic downgrades were not forced. Optional Undici peer hygiene in OS remains a documented residual; no affected transport implementation was found in the deployed worker. This is not a zero-vulnerability claim. Read the sections below as the initial audit and rationale for reviewed exceptions, not as current installed direct versions.

---

Read-only audit. Neither Sites checkout was changed by this subagent. Raw snapshots:
- `/tmp/workloop-website-audit-20260904.json`: npm audit, 23 affected package entries, 17 high / 5 moderate / 1 low.
- `/tmp/workloop-os-audit-20260904.json`: pnpm audit, 10 high / 9 moderate / 3 low advisory findings. Different counting conventions; do not compare as package counts.

## Launch priority

Both sites currently install React, React DOM and react-server-dom-webpack 19.2.6. Pin **all three to 19.2.8**. The patched RSC package requires React/DOM ^19.2.8; both installed Vinext versions and plugin-rsc permit these peers. React's own advisory GHSA-wx67-qw84-cm4g identifies crafted Server Function requests causing CPU/memory exhaustion and recommends immediate update. Both current worker bundles include decodeAction/decodeReply. Neither app source declares `use server`; header-based actions load/check the target before decoding, but the progressive multipart path calls decodeAction directly. Therefore this is a relevant exposed parser dependency to patch, without claiming a demonstrated exploit. No malicious payload was sent.
Primary source: https://github.com/react/react/security/advisories/GHSA-wx67-qw84-cm4g
Registry: https://registry.npmjs.org/react-server-dom-webpack/19.2.8

Pin **Vite 8.0.16** in both sites: the first patched 8.0 version, compatible with the existing ^8 Vinext peers. The current Vite 8.0.13 advisories concern Windows network-exposed development servers, not the deployed Cloudflare worker or current macOS environment. A small patch is still sensible.
Primary source: https://github.com/vitejs/vite/security/advisories/GHSA-fx2h-pf6j-xcff
Registry: https://registry.npmjs.org/vite/8.0.16

## Marketing Next dependency

The manifest installs Next 16.2.6, but scripts launch/build **Vinext** and the worker imports `vinext/server/app-router-entry`. Next imports in app source are resolved through Vinext shims. No Next custom server, Turbopack middleware, Server Actions, rewrite proxy or Next image optimizer is running in the inspected worker. The custom image endpoint delegates to Cloudflare IMAGES, not local Sharp.

The smallest Next patch that fixes its direct advisories is **next 16.2.11**, with matching **eslint-config-next 16.2.11**. However, that Next patch still pins vulnerable PostCSS 8.4.31. Two concrete choices:
- Minimal Next-line change: next/eslint-config-next 16.2.11 plus a targeted `next>postcss` resolution/override to **8.5.23**, followed by lint/type/build checks.
- Cleaner parent dependency update without a forced transitive override: next/eslint-config-next **16.3.4**; its manifest already pins PostCSS **8.5.23**. Same major but a larger minor release, requiring tests.

Do not mistake npm's 17 high count for 17 proven public website attack paths. For example the Next Server Action DoS advisory explicitly requires at least one action and a Next App Router server.
Primary source: https://github.com/vercel/next.js/security/advisories/GHSA-m99w-x7hq-7vfj
Manifests: https://registry.npmjs.org/next/16.2.11 and https://registry.npmjs.org/next/16.3.4

## Cloudflare development toolchain

Miniflare/Wrangler transitively pin older Sharp, Undici, ws and esbuild. These emulate Workers locally; they are not uploaded as production application request handlers. Current installed Sharp is 0.34.5; its advisory affects processing untrusted images using vulnerable libvips.

Coherent current package set (verify preview/build before publishing):
- **@cloudflare/vite-plugin 1.54.4**
- **wrangler 4.129.0**
- **@cloudflare/workers-types 5.20260903.1** (Wrangler peer minimum for that release)

This pair pins ws8.21.0, Undici7.29.0, esbuild0.28.1 and Sharp0.35.2. Sharp's CVE package range is fixed in0.35.0, while its maintainer recommends0.35.3/libvips8.18.3 as latest hardening; a deliberate Sharp0.35.3 override can follow if strict current patch hygiene is desired. Do not override native packages without rebuilding local preview.

Important compatibility tradeoff: current Cloudflare releases internally depend on Miniflare5-alpha. Earlier plugin1.47.0 + Wrangler4.114.0 avoids that internal major change but still pins Undici7.28.0, which has newer advisories. This is why upgrading only to the first plugin audit fix does not remove every later warning. Registry package manifests were read directly; no automatic audit fix was run.
Primary Sharp source: https://github.com/lovell/sharp/security/advisories/GHSA-f88m-g3jw-g9cj
Manifests: https://registry.npmjs.org/@cloudflare/vite-plugin/1.54.4 and https://registry.npmjs.org/wrangler/4.129.0

## OS runtime optional transport

OS imports @openai/agents in lib/orchestration.ts. Its OpenAI7.8.0 optional Undici peer is resolved to7.24.8; a compatible explicit peer pin **undici7.29.0** addresses its current advisory ranges. The OpenAI peer allows >=5 <9. The inspected orchestration uses normal Responses requests and Worker global fetch; no SOCKS proxy, Undici cache, custom dispatcher or realtime WebSocket is configured. Current built worker has only an Undici mention in an explanatory timeout message, not an Undici implementation import. Thus no affected transport usage was demonstrated, but resolving the peer to a patched version is low-impact hygiene.
Primary advisories: https://github.com/nodejs/undici/security/advisories (exact individual IDs retained in raw audit JSON)

## Known audit traps / remaining build dependencies

**image-size2.0.2:** advisory feed says fixed >=2.0.3, but the npm registry contains NO published2.0.3; latest remains2.0.2. Do not pin a nonexistent package. Vinext0.0.50 (marketing) and1.0.0-beta.5(OS) use this package to inspect repository static image metadata at build time. No image-size parser appears in the current deployed worker bundles. The risk is malicious repository images blocking a build, not an identified public upload endpoint. Vinext1.0.0-beta.6+ removes image-size; beta.9 is current, but jumping the marketing framework across its beta boundary solely to silence a build warning is not a minimal launch patch. Beta.9 also needs plugin-rsc^0.5.34 (current0.5.26). Treat that as a separately tested framework upgrade.
Primary researcher disclosure linked by advisory: https://joshua.hu/image-size-infinite-loop-dos-vulnerabilities
Maintainer release history: https://github.com/cloudflare/vinext/releases

**drizzle-kit0.31.10:** old @esbuild-kit loader contains esbuild0.18.20 and its cross-origin development-server disclosure issue. No esbuild serve usage exists in the site's runtime. npm suggests downgrading drizzle-kit to0.18.1; DO NOT do that. It is a major API/schema-tool regression, not a sensible security fix. 0.31.11 is not published. Keep this explicit development-only exception until the maintained loader chain changes; do not force a major esbuild replacement beneath its old loader without testing the migration tool.
Primary advisory: https://github.com/evanw/esbuild/security/advisories/GHSA-67mh-4wv8-2f99

Other marketing lock transitive findings are build/lint parsers/config consumers. Published first safe versions include browserslist4.28.7, fast-uri3.1.6, fflate0.7.5, js-yaml4.3.1, nanoid3.3.18 and PostCSS8.5.23. Existing compatible ranges can usually be refreshed without app-code changes. brace-expansion needs matching major-line fixes (1.1.18 or5.0.9), not a blanket cross-major override. Babel7.29.1 is NOT published; do not invent that patch or force Babel8 under the existing React plugin just to clear a low build-source-map advisory. These are not public application input parsers in the inspected source/bundles.

## Verification boundary / next execution

Registry peer/version checks and source/bundle reachability inspection completed; no build/test rerun here because no site files changed. Root should apply chosen direct pins in its existing Sites workflow, regenerate BOTH relevant lockfiles, install, run full site tests/typecheck/lint/build, then re-audit. Review residual warnings by actual use, not by count. Deployment must be rebuilt from patched packages and the live domain checked; package.json changes alone do not update an already deployed Worker.
