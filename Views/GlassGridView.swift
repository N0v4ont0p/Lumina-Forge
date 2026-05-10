import SwiftUI

// MARK: - Glass Grid View

struct GlassGridView: View {
    let sidebarItem: SidebarItem
    @Binding var selectedAsset: ImageAsset?

    @Environment(MetadataActor.self) private var metadataActor
    @Environment(ThumbnailActor.self) private var thumbnailActor

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)
    ]

    var body: some View {
        Group {
            if filteredAssets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredAssets) { asset in
                            GlassCard(asset: asset, isSelected: selectedAsset?.id == asset.id) {
                                selectedAsset = asset
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(sidebarItem.rawValue)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                batchExportButton
                sortMenu
            }
        }
        .glassBackgroundEffect()
    }

    // MARK: - Filtered Assets

    private var filteredAssets: [ImageAsset] {
        switch sidebarItem {
        case .allImages:
            return metadataActor.assets
        case .favorites:
            return metadataActor.assets.filter(\.isFavorite)
        case .tagged:
            return metadataActor.assets.filter { !$0.tags.isEmpty }
        case .exportQueue:
            return metadataActor.assets.filter(\.isInExportQueue)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("No Images")
                .font(.title2.bold())
                .foregroundStyle(.secondary)
            Text("Click the + button to add images to your library.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar Items

    private var batchExportButton: some View {
        Button(action: startBatchExport) {
            Label("Batch Export", systemImage: "arrow.up.circle")
        }
        .disabled(filteredAssets.isEmpty)
        .help("Export metadata for all visible images")
    }

    private var sortMenu: some View {
        Menu {
            Button("Date (Newest First)") {}
            Button("Date (Oldest First)") {}
            Divider()
            Button("File Name (A–Z)") {}
            Button("File Name (Z–A)") {}
            Divider()
            Button("File Size") {}
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort images")
    }

    // MARK: - Actions

    private func startBatchExport() {
        // Batch export logic handled by MetadataActor
    }
}
