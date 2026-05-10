<div align="center">

# ✨ Lumina Forge (Electron Premium)

### _Mac-only Liquid Glass metadata editor — no Xcode required_

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

```bash
npm install
npm run build:mac
```

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
