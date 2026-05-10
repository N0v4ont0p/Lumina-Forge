import SwiftUI
import SwiftData

@main
struct LuminaForgeApp: App {
    // MARK: - Actors

    /// Owns the library asset list and all metadata I/O.
    @State private var metadataActor = MetadataActor()

    /// Owns the thumbnail LRU + SwiftData cache (creates its own ModelContainer).
    @State private var thumbnailActor = ThumbnailActor()

    /// Watches loaded library folders for new image files via FSEvents.
    @State private var folderWatcher = FolderWatcherActor()

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(metadataActor)
                .environment(thumbnailActor)
                .environment(folderWatcher)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .commands {
            // Replace the system Undo/Redo menu items (real undo handled in detail panel)
            CommandGroup(replacing: .undoRedo) {}
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Root Content View

struct ContentView: View {
    @State private var selectedSidebarItem: SidebarItem = .allImages
    @State private var selectedAsset: ImageAsset?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// Error message to surface as an alert (populated by FSEvents load failures).
    @State private var globalErrorMessage: String? = nil

    @Environment(MetadataActor.self) private var metadataActor
    @Environment(FolderWatcherActor.self) private var folderWatcher

    /// Shared namespace for thumbnail hero transitions between `GlassGridView`
    /// (cards — `isSource: true`) and `GlassDetailPanel` (header — `isSource: false`).
    @Namespace private var heroNamespace

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            GlassSidebar(selection: $selectedSidebarItem)
        } content: {
            GlassGridView(
                sidebarItem: selectedSidebarItem,
                selectedAsset: $selectedAsset,
                heroNamespace: heroNamespace
            )
        } detail: {
            GlassDetailPanel(asset: selectedAsset, heroNamespace: heroNamespace)
        }
        .glassBackgroundEffect()
        // ── FSEvents: keep watches in sync with the loaded library ──────────
        .onChange(of: metadataActor.assets) { _, newAssets in
            let dirs = Set(newAssets.map { $0.url.deletingLastPathComponent() })
            Task { await folderWatcher.updateWatches(directories: dirs) }
        }
        // ── FSEvents: auto-load newly discovered image files ─────────────────
        .onChange(of: folderWatcher.newlyDiscoveredURLs) { _, urls in
            guard !urls.isEmpty else { return }
            Task {
                let fresh = await folderWatcher.consumeNewURLs()
                await metadataActor.loadAssetsWatched(from: fresh)
            }
        }
        // ── Global error alert ───────────────────────────────────────────────
        .alert("Error", isPresented: Binding(
            get: { globalErrorMessage != nil },
            set: { if !$0 { globalErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { globalErrorMessage = nil }
        } message: {
            Text(globalErrorMessage ?? "")
        }
        // ── Global keyboard shortcuts ────────────────────────────────────────
        // ⌘L: Toggle sidebar
        .background(
            Button("") { columnVisibility = columnVisibility == .all ? .detailOnly : .all }
                .keyboardShortcut("l", modifiers: .command)
                .hidden()
        )
    }
}

// MARK: - Settings View

struct SettingsView: View {
    var body: some View {
        Form {
            Section("ExifTool") {
                Text("Place the ExifTool binary at Resources/ExifTool/exiftool " +
                     "to enable full IPTC/XMP read-write support.")
                    .foregroundStyle(.secondary)
            }
            Section("Export") {
                Text("Default export options are configured in ExportOptions.plist.")
                    .foregroundStyle(.secondary)
            }
            Section("Cache") {
                Text("Thumbnail cache is managed automatically by ThumbnailActor " +
                     "and stored in ~/Library/Caches/LuminaThumbCache.store.")
                    .foregroundStyle(.secondary)
            }
            Section("Folder Watching") {
                Text("Lumina Forge monitors loaded library folders via FSEvents. " +
                     "New images copied into a watched folder appear automatically " +
                     "with a green highlight pulse.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480, height: 420)
    }
}
