<div align="center">

<img src="Assets.xcassets/AppIcon.appiconset/AppIcon.png" alt="Lumina Forge Logo" width="128" height="128" />

# ✨ Lumina Forge

### _Professional Image Metadata Editor — Built with Liquid Glass_

[![macOS](https://img.shields.io/badge/macOS-26%20Tahoe%2B-black?style=for-the-badge&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-6-blue?style=for-the-badge&logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Xcode](https://img.shields.io/badge/Xcode-17%2B-147EFB?style=for-the-badge&logo=xcode&logoColor=white)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

</div>

---

## 🌊 Liquid Glass — The Future of macOS UI

Lumina Forge is crafted from the ground up for **macOS 26 Tahoe**, embracing Apple's revolutionary **Liquid Glass** design language. Every surface breathes, refracts, and responds to light — delivering an interface that feels alive.

```
┌─────────────────────────────────────────────────────────────┐
│  🔮 Lumina Forge  ·  Liquid Glass · Native macOS 26 Tahoe   │
│─────────────────────────────────────────────────────────────│
│  ▓▓▓ GlassSidebar   │    ◈◈◈◈◈◈ GlassGridView ◈◈◈◈◈◈      │
│  ─────────────────  │  ┌──────┐ ┌──────┐ ┌──────┐         │
│  📁 All Images      │  │ IMG1 │ │ IMG2 │ │ IMG3 │         │
│  ⭐ Favorites       │  │      │ │      │ │      │         │
│  🏷 Tagged          │  └──────┘ └──────┘ └──────┘         │
│  📤 Export Queue    │                                       │
│                     │  ┌──────────────────────────────┐    │
│  ▓▓▓ Metadata       │  │    GlassDetailPanel          │    │
│  ─────────────────  │  │  Camera: Canon EOS R5         │    │
│  Camera: Canon R5   │  │  Lens:   24-70mm f/2.8        │    │
│  ISO: 400           │  │  ISO:    400                  │    │
│  f/2.8              │  │  Shutter: 1/250s              │    │
│                     │  └──────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

---

## ✨ Features

| Feature | Description |
|---|---|
| 🔮 **Liquid Glass UI** | Native `.glassBackgroundEffect` & `.glassEffect` throughout |
| 📸 **EXIF / IPTC / XMP** | Read and write all major metadata standards via ExifTool |
| ⚡ **Swift 6 Actors** | Thread-safe async metadata and thumbnail processing |
| 🎨 **Glass Grid** | Gorgeous thumbnail grid with real-time metadata overlays |
| 📋 **Batch Operations** | Process hundreds of images simultaneously with progress tracking |
| 🔍 **Smart Sidebar** | Filter and navigate collections with glass-morphic sidebar |
| 💾 **Non-Destructive** | All edits are sidecar-based, original files remain untouched |
| 🔐 **Full Disk Access** | Sandboxed with Full Disk Access entitlement for broad file access |
| 📤 **Flexible Export** | Export metadata to JSON, CSV, sidecar XMP |

---

## 🚀 Getting Started

### Requirements

- macOS 26 Tahoe or later
- Xcode 17 or later
- Swift 6
- **No Apple Developer account required** — the project builds unsigned (arm64)

### One-Command Build

```bash
git clone https://github.com/N0v4ont0p/lumina-forge.git
cd lumina-forge
bash build.sh
```

After the build completes, **Lumina Forge.app is automatically copied to `~/Downloads/Lumina Forge/`** and is ready to run — no manual steps needed.

```bash
# Open the app immediately after building:
open ~/Downloads/Lumina\ Forge/Lumina\ Forge.app
```

### Build Options

| Command | Description |
|---|---|
| `bash build.sh` | Debug build → `~/Downloads/Lumina Forge/` |
| `bash build.sh release` | Optimised Release build → same destination |
| `bash build.sh clean` | Clean the build folder |
| `bash build.sh clean release` | Clean + Release build |

### Open in Xcode (optional)

```bash
open "Lumina Forge.xcodeproj"
```

Press **⌘R** to build and run; the built `.app` is automatically copied to `~/Downloads/Lumina Forge/` by the **Copy to Downloads** Run Script build phase.

### Build Settings

| Setting | Value | Effect |
|---|---|---|
| `ARCHS` | `arm64` | Apple Silicon only — smallest, fastest binary |
| `CODE_SIGNING_REQUIRED` | `NO` | No certificate or developer account needed |
| `CODE_SIGN_IDENTITY` | `-` | Ad-hoc / unsigned |
| `ENABLE_USER_SCRIPT_SANDBOXING` | `NO` | Allows the post-build copy to `~/Downloads` |

---

## 🗂 Project Structure

```
lumina-forge/
├── LuminaForgeApp.swift          # App entry point, SwiftUI lifecycle
├── Views/
│   ├── GlassSidebar.swift        # Navigation sidebar with glass morphism
│   ├── GlassGridView.swift       # Image thumbnail grid
│   ├── GlassDetailPanel.swift    # Metadata detail panel
│   ├── BatchProgressView.swift   # Batch operation progress UI
│   └── components/
│       └── GlassCard.swift       # Reusable glass card component
├── Models/
│   ├── ImageAsset.swift          # Image asset data model
│   └── MetadataModel.swift       # EXIF/IPTC/XMP metadata model
├── Actors/
│   ├── MetadataActor.swift       # Thread-safe metadata I/O actor
│   └── ThumbnailActor.swift      # Async thumbnail generation actor
├── Resources/
│   └── ExifTool/                 # ExifTool binary (add manually)
├── Assets.xcassets               # App icons & color assets
├── ExportOptions.plist           # Export configuration
├── Lumina Forge.xcodeproj        # Xcode project
└── README.md
```

---

## 🧱 Tech Stack

| Layer | Technology |
|---|---|
| **Language** | Swift 6 |
| **UI Framework** | SwiftUI 6 |
| **Design Language** | Liquid Glass (macOS 26 Tahoe) |
| **Concurrency** | Swift Actors + async/await |
| **Metadata Engine** | ExifTool (bundled binary) |
| **Minimum OS** | macOS 26 Tahoe |
| **IDE** | Xcode 17+ |

---

## 🔮 Roadmap

- [ ] ExifTool binary integration
- [ ] iCloud sync support
- [ ] AI-powered metadata suggestions
- [ ] Batch rename with metadata tokens
- [ ] Plugin architecture for custom exporters
- [ ] Shortcuts app integration

---

## 🤝 Contributing

Contributions are welcome! Please open an issue first to discuss what you would like to change.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<div align="center">

**Built with ❤️ and Liquid Glass for macOS 26 Tahoe**

[GitHub](https://github.com/N0v4ont0p) · [Issues](https://github.com/N0v4ont0p/lumina-forge/issues) · [Discussions](https://github.com/N0v4ont0p/lumina-forge/discussions)

</div>