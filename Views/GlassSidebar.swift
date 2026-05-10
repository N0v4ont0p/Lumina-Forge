import SwiftUI

// MARK: - Sidebar Navigation Items

enum SidebarItem: String, CaseIterable, Identifiable {
    case allImages = "All Images"
    case favorites = "Favorites"
    case tagged = "Tagged"
    case exportQueue = "Export Queue"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .allImages:   return "photo.on.rectangle.angled"
        case .favorites:   return "star.fill"
        case .tagged:      return "tag.fill"
        case .exportQueue: return "arrow.up.circle.fill"
        }
    }
}

// MARK: - Glass Sidebar View

struct GlassSidebar: View {
    @Binding var selection: SidebarItem
    @Environment(MetadataActor.self) private var metadataActor

    var body: some View {
        List(SidebarItem.allCases, selection: $selection) { item in
            Label(item.rawValue, systemImage: item.systemImage)
                .tag(item)
        }
        .listStyle(.sidebar)
        .navigationTitle("Lumina Forge")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: openImages) {
                    Label("Add Images", systemImage: "plus")
                }
                .help("Add images to library")
            }
        }
        .glassBackgroundEffect()
        .safeAreaInset(edge: .bottom) {
            metadataSummary
        }
    }

    // MARK: - Metadata Summary Footer

    private var metadataSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Text("Library")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text("\(metadataActor.assetCount) images")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Actions

    private func openImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .rawImage]
        panel.begin { response in
            guard response == .OK else { return }
            Task {
                await metadataActor.loadAssets(from: panel.urls)
            }
        }
    }
}
