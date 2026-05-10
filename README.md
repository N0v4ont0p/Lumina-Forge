<div align="center">

# ✨ Lumina Forge (Electron Premium)

### _Currently macOS-only by design: Liquid Glass metadata editor — no Xcode required_

</div>

## Stack

- Electron Forge + Vite
- React 19 + TypeScript
- TailwindCSS + shadcn/ui-style components
- Framer Motion (high-refresh spring animations)
- `exiftool-vendored` + `sharp` for metadata + thumbnails

## Features

- Frameless macOS window with native traffic lights + vibrant glass chrome
- Liquid Glass UI shell (sidebar + masonry/grid + metadata detail panel)
- Hover lifts, spring transitions, matched-geometry-style image transitions
- Batch export flow with animated circular progress + confetti completion burst
- Supports directory + file ingestion across common and RAW image formats
- Metadata extraction via ExifTool and fast thumbnail generation via Sharp

## Requirements

- macOS (Apple Silicon recommended)
- Node.js 20+
- npm 10+

## One-command build (no Xcode)

Before building, place your Canva-designed logo as `logo.icns` in the repository root (already included in this repo).

```bash
npm install
npm run build:mac
```

> `npm install` triggers the `postinstall` hook (`electron-rebuild -f`),
> which compiles native modules — notably
> [`sharp`](https://sharp.pixelplumbing.com/) (`@img/sharp-darwin-arm64` +
> `@img/sharp-libvips-darwin-arm64`) and `batch-cluster` — against the
> Electron ABI. All three modules (`sharp`, `exiftool-vendored`,
> `batch-cluster`) are explicit direct dependencies and are automatically
> extracted from the asar archive via `packagerConfig.asarUnpack` in
> `forge.config.ts`, so they are available as real files at runtime.
>
> If you ever see a runtime error such as
> `Could not load the "sharp" module using the darwin-arm64 runtime` or
> `Cannot find module 'batch-cluster'`, rebuild native modules:
>
> ```bash
> npm install --include=optional
> npx electron-rebuild -f
> ```

The packaged `Lumina Forge.app` ships with the custom Canva-designed
Lumina Forge logo (`logo.icns`) as its macOS application icon, wired up
through `forge.config.ts` (`packagerConfig.icon: './logo.icns'` +
`packagerConfig.extraResource`). Native runtime modules are extracted
from the asar archive via `packagerConfig.asarUnpack`.

After the build completes, `Lumina Forge.app` is automatically copied to:

```bash
~/Downloads/Lumina Forge/Lumina Forge.app
```

You can launch it with:

```bash
open ~/Downloads/Lumina\ Forge/Lumina\ Forge.app
```

## Dev

```bash
npm start
```

## Lint

```bash
npm run lint
```
