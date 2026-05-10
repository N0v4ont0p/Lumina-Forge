import SwiftUI
import SwiftData

@main
struct LuminaForgeApp: App {
    // MARK: - Actors

    /// Owns the library asset list and all metadata I/O.
    @State private var metadataActor = MetadataActor()

    /// Owns the thumbnail LRU + SwiftData cache (creates its own ModelContainer).
    @State private var thumbnailActor = ThumbnailActor()

    // MARK: - Scene

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(metadataActor)
                .environment(thumbnailActor)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)

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
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480, height: 360)
    }
}
