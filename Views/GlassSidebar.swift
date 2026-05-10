import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sidebar Item

/// The selection type used throughout the sidebar + grid.
///
/// - `allImages`:      Full, unfiltered library.
/// - `favorites`:      Assets the user has starred.
/// - `tagged`:         Assets carrying at least one tag.
/// - `exportQueue`:    Assets queued for batch export.
/// - `folder(URL)`:    Assets whose parent directory matches the given URL.
enum SidebarItem: Hashable {
    case allImages
    case favorites
    case tagged
    case exportQueue
    case folder(URL)

    /// Human-readable navigation title shown in the grid's toolbar.
    var title: String {
        switch self {
        case .allImages:        return "All Images"
        case .favorites:        return "Favorites"
        case .tagged:           return "Tagged"
        case .exportQueue:      return "Export Queue"
        case .folder(let url):  return url.lastPathComponent
        }
    }

    var systemImage: String {
        switch self {
        case .allImages:    return "photo.on.rectangle.angled"
        case .favorites:    return "star.fill"
        case .tagged:       return "tag.fill"
        case .exportQueue:  return "arrow.up.circle.fill"
        case .folder:       return "folder.fill"
        }
    }
}

// MARK: - Folder Node

/// A single folder derived from the currently loaded asset list.
struct FolderNode: Identifiable, Equatable {
    /// The folder's file URL — used as a stable identity and filter key.
    let id: URL
    let name: String
    var imageCount: Int
}

// MARK: - Drop Pulse Rings

/// Three concentric rounded-rect rings that expand outward and fade,
/// producing a "liquid sonar" pulse while the user drags images over the
/// drop zone.
private struct DropPulseRings: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        Color.accentColor.opacity(animate ? 0 : 0.55 - Double(i) * 0.14),
                        lineWidth: 1.5
                    )
                    .scaleEffect(animate ? 1.30 + Double(i) * 0.12 : 1.0)
                    .animation(
                        .easeOut(duration: 1.4)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.40),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

// MARK: - Folder Row

private struct FolderRow: View {
    let node: FolderNode

    var body: some View {
        Label {
            HStack {
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text("\(node.imageCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        } icon: {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
        }
    }
}

// MARK: - Glass Sidebar

struct GlassSidebar: View {
    @Binding var selection: SidebarItem
    @Environment(MetadataActor.self) private var metadataActor

    // MARK: Disclosure state
    @State private var foldersExpanded = false

    // MARK: Folder tree (derived from loaded assets)
    @State private var folderNodes: [FolderNode] = []

    // MARK: Drop-zone
    @State private var isDropTargeted = false

    // Unified spring per master plan
    private let spring = Animation.spring(response: 0.28, dampingFraction: 0.82)

    // MARK: - Body

    var body: some View {
        List(selection: $selection) {

            // ── Library ──────────────────────────────────────────────────
            Section {
                Label("All Images", systemImage: "photo.on.rectangle.angled")
                    .tag(SidebarItem.allImages)
                    .badge(metadataActor.assetCount)

                // Folder tree — shown only when images are loaded
                if !folderNodes.isEmpty {
                    DisclosureGroup(isExpanded: $foldersExpanded) {
                        ForEach(folderNodes) { node in
                            FolderRow(node: node)
                                .tag(SidebarItem.folder(node.id))
                        }
                    } label: {
                        Label("Folders", systemImage: "folder")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Library").textCase(.uppercase)
            }

            // ── Smart Collections ─────────────────────────────────────────
            Section {
                Label("Favorites", systemImage: "star.fill")
                    .tag(SidebarItem.favorites)
                    .badge(metadataActor.assets.filter(\.isFavorite).count)

                Label("Tagged", systemImage: "tag.fill")
                    .tag(SidebarItem.tagged)
                    .badge(metadataActor.assets.filter { !$0.tags.isEmpty }.count)

                Label("Export Queue", systemImage: "arrow.up.circle.fill")
                    .tag(SidebarItem.exportQueue)
                    .badge(metadataActor.assets.filter(\.isInExportQueue).count)
            } header: {
                Text("Collections").textCase(.uppercase)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Lumina Forge")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: openImages) {
                    Image(systemName: "plus")
                        // Bounce when a drop is active to reinforce the gesture
                        .symbolEffect(.bounce, value: isDropTargeted)
                }
                .help("Add images to library (⌘N)")
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .glassBackgroundEffect()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                dropZone
                footer
            }
        }
        // Accept file drops anywhere on the sidebar
        .onDrop(of: [.fileURL, .image, .rawImage], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        // Rebuild folder tree whenever the asset list changes
        .onChange(of: metadataActor.assets) { _, newAssets in
            withAnimation(spring) {
                folderNodes = buildFolderTree(from: newAssets)
            }
        }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        ZStack {
            // Background fill
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    isDropTargeted
                        ? Color.accentColor.opacity(0.10)
                        : Color.secondary.opacity(0.05)
                )

            // Border — static at rest, solid accent when targeted
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isDropTargeted
                        ? Color.accentColor.opacity(0.72)
                        : Color.secondary.opacity(0.22),
                    lineWidth: isDropTargeted ? 2 : 1
                )

            // Expanding pulse rings (shown only while a drag is active)
            if isDropTargeted {
                DropPulseRings()
                    .transition(.opacity)
            }

            // Icon + label
            VStack(spacing: 7) {
                Image(
                    systemName: isDropTargeted
                        ? "photo.badge.plus.fill"
                        : "photo.badge.plus"
                )
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: isDropTargeted)

                Text(isDropTargeted ? "Release to Add" : "Drop Images Here")
                    .font(.caption.bold())
                    .foregroundStyle(isDropTargeted ? .primary : .tertiary)
                    .contentTransition(.opacity)
            }
            .padding(.vertical, 14)
        }
        .frame(height: 90)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .animation(spring, value: isDropTargeted)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "photo.stack")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Library")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text("\(metadataActor.assetCount) images")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        // Smooth number transitions as images load
                        .contentTransition(.numericText())
                        .animation(spring, value: metadataActor.assetCount)
                }
                Spacer()
                if metadataActor.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Helpers

    private func openImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .rawImage]
        panel.begin { response in
            guard response == .OK else { return }
            Task { await metadataActor.loadAssets(from: panel.urls) }
        }
    }

    /// Extracts file URLs from dropped `NSItemProvider` items and forwards
    /// them to `MetadataActor.loadAssets(from:)`.
    private func handleDrop(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            Task { await metadataActor.loadAssets(from: urls) }
        }
    }

    /// Groups assets by their parent directory and returns one `FolderNode`
    /// per unique directory, sorted alphabetically.
    private func buildFolderTree(from assets: [ImageAsset]) -> [FolderNode] {
        var map: [URL: Int] = [:]
        for asset in assets {
            map[asset.url.deletingLastPathComponent(), default: 0] += 1
        }
        return map
            .map { FolderNode(id: $0.key, name: $0.key.lastPathComponent, imageCount: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
