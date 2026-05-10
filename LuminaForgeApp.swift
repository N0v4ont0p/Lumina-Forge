import SwiftUI

@main
struct LuminaForgeApp: App {
    @State private var metadataActor = MetadataActor()
    @State private var thumbnailActor = ThumbnailActor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(metadataActor)
                .environment(thumbnailActor)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)

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

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            GlassSidebar(selection: $selectedSidebarItem)
        } content: {
            GlassGridView(
                sidebarItem: selectedSidebarItem,
                selectedAsset: $selectedAsset
            )
        } detail: {
            GlassDetailPanel(asset: selectedAsset)
        }
        .glassBackgroundEffect()
    }
}

// MARK: - Settings View

struct SettingsView: View {
    var body: some View {
        Form {
            Section("ExifTool") {
                Text("ExifTool binary path will be configured here.")
                    .foregroundStyle(.secondary)
            }
            Section("Export") {
                Text("Default export options will appear here.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480, height: 320)
    }
}
