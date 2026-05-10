import SwiftUI

// MARK: - Asset Sort Order

/// Available sort orderings for the image grid.
enum AssetSortOrder: String, CaseIterable, Identifiable {
    case dateNewest = "Date (Newest First)"
    case dateOldest = "Date (Oldest First)"
    case nameAZ     = "Name (A–Z)"
    case nameZA     = "Name (Z–A)"
    case fileSize   = "File Size"

    var id: String { rawValue }
}

// MARK: - Glass Grid View

/// The central image grid displayed in the NavigationSplitView content column.
///
/// ## Layout modes
/// - **Grid**:    Adaptive `LazyVGrid` with uniform 160 px cards.  Fully lazy —
///               handles 20 k+ images with no stutter.
/// - **Masonry**: 3-column `LazyVGrid` where card heights are derived from each
///               image's natural aspect ratio (clamped 120 – 300 px).
///
/// ## Animations
/// - Cards stagger in with `spring(response: 0.28, dampingFraction: 0.82)` and
///   a 22 ms per-card delay (capped at 24 cards so large libraries don't wait).
/// - Filter / sort changes clear the stagger counter so cards replay the entrance.
/// - The empty state shows an animated gradient orb (rotating `AngularGradient`
///   + pulsing halo rings) using continuous `withAnimation(.repeatForever)`.
struct GlassGridView: View {
    let sidebarItem: SidebarItem
    @Binding var selectedAsset: ImageAsset?
    /// Namespace shared with `GlassDetailPanel` for thumbnail hero transitions.
    var heroNamespace: Namespace.ID

    @Environment(MetadataActor.self) private var metadataActor
    @Environment(ThumbnailActor.self) private var thumbnailActor

    // MARK: - Layout state
    @State private var isMasonry = false
    @State private var sortOrder: AssetSortOrder = .dateNewest
    @State private var showBatchProgress = false

    // MARK: - Stagger animation state

    /// Asset IDs that have already completed their entrance animation.
    /// Cards already in this set appear instantly (no stagger) — important when
    /// the user switches filters and comes back.
    @State private var appearedIDs: Set<UUID> = []

    /// Increments on every filter / sort change to re-trigger staggered entrances
    /// by making the `.task(id:)` ID unique again for each card.
    @State private var staggerGeneration = 0

    // MARK: - Empty-state animation
    @State private var orbRotation: Double = 0
    @State private var haloPulse = false

    // MARK: - Grid column definitions
    private let gridColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12),
    ]
    private let masonryColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    // Unified spring per master plan
    private let spring = Animation.spring(response: 0.28, dampingFraction: 0.82)

    // MARK: - Body

    var body: some View {
        Group {
            if filteredAssets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: isMasonry ? masonryColumns : gridColumns,
                        spacing: 12
                    ) {
                        ForEach(
                            Array(filteredAssets.enumerated()),
                            id: \.element.id
                        ) { index, asset in
                            GlassCard(
                                asset: asset,
                                isSelected: selectedAsset?.id == asset.id,
                                namespace: heroNamespace,
                                cardHeight: isMasonry ? masonryHeight(for: asset) : 160
                            ) {
                                withAnimation(spring) { selectedAsset = asset }
                            }
                            // ── Staggered entrance ──────────────────────
                            .opacity(appearedIDs.contains(asset.id) ? 1 : 0)
                            .offset(y: appearedIDs.contains(asset.id) ? 0 : 14)
                            .scaleEffect(appearedIDs.contains(asset.id) ? 1 : 0.90)
                            // Task re-runs whenever staggerGeneration changes,
                            // which happens on every filter / sort switch.
                            .task(id: "\(asset.id)-\(staggerGeneration)") {
                                guard !appearedIDs.contains(asset.id) else { return }
                                // Stagger up to 24 cards; the rest appear together.
                                let delay = Double(min(index, 24)) * 0.022
                                try? await Task.sleep(for: .seconds(delay))
                                withAnimation(spring) { appearedIDs.insert(asset.id) }
                            }
                        }
                    }
                    .padding(16)
                    // Animate the column change when toggling grid ↔ masonry
                    .animation(spring, value: isMasonry)
                }
            }
        }
        .navigationTitle(sidebarItem.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Grid / Masonry toggle button
                Button {
                    withAnimation(spring) { isMasonry.toggle() }
                } label: {
                    Image(systemName: isMasonry ? "square.grid.2x2" : "rectangle.3.group")
                        .contentTransition(.symbolEffect(.replace))
                }
                .help(isMasonry ? "Switch to Grid" : "Switch to Masonry")

                batchExportButton
                sortMenu
            }
        }
        .glassBackgroundEffect()
        // Re-stagger when the active collection or sort order changes
        .onChange(of: sidebarItem) { _, _ in resetStagger() }
        .onChange(of: sortOrder)   { _, _ in resetStagger() }
    }

    // MARK: - Filtered & Sorted Assets

    private var filteredAssets: [ImageAsset] {
        let base: [ImageAsset]
        switch sidebarItem {
        case .allImages:
            base = metadataActor.assets
        case .favorites:
            base = metadataActor.assets.filter(\.isFavorite)
        case .tagged:
            base = metadataActor.assets.filter { !$0.tags.isEmpty }
        case .exportQueue:
            base = metadataActor.assets.filter(\.isInExportQueue)
        case .folder(let url):
            base = metadataActor.assets.filter {
                $0.url.deletingLastPathComponent() == url
            }
        }
        return base.sorted { a, b in
            switch sortOrder {
            case .dateNewest:
                return (a.metadata?.dateTimeOriginal ?? .distantPast)
                    > (b.metadata?.dateTimeOriginal ?? .distantPast)
            case .dateOldest:
                return (a.metadata?.dateTimeOriginal ?? .distantPast)
                    < (b.metadata?.dateTimeOriginal ?? .distantPast)
            case .nameAZ:
                return a.fileName.localizedStandardCompare(b.fileName) == .orderedAscending
            case .nameZA:
                return a.fileName.localizedStandardCompare(b.fileName) == .orderedDescending
            case .fileSize:
                return (a.cachedFileSize ?? 0) > (b.cachedFileSize ?? 0)
            }
        }
    }

    // MARK: - Masonry Height

    /// Returns a card height proportional to the image's natural aspect ratio,
    /// clamped between 120 and 300 px to prevent extreme tall / wide cards.
    ///
    /// Falls back to 180 px when metadata has not yet been loaded.
    private func masonryHeight(for asset: ImageAsset) -> CGFloat {
        guard
            let w = asset.metadata?.imageWidth, w > 0,
            let h = asset.metadata?.imageHeight, h > 0
        else { return 180 }
        // Assume ~180 px column width for 3-column masonry
        return min(max(180 * CGFloat(h) / CGFloat(w), 120), 300)
    }

    // MARK: - Empty State

    /// Full-screen placeholder shown when `filteredAssets` is empty.
    ///
    /// Features an animated gradient orb:
    /// - A rotating `AngularGradient` circle (7 s rotation, `repeatForever`)
    /// - Two pulsing halo rings with different radii and phases
    /// - A specular highlight overlay for depth
    private var emptyState: some View {
        VStack(spacing: 28) {

            // ── Animated Gradient Orb ──────────────────────────────────────
            ZStack {
                // Primary pulsing halo
                Circle()
                    .fill(Color.accentColor.opacity(haloPulse ? 0.18 : 0.05))
                    .frame(
                        width:  haloPulse ? 150 : 110,
                        height: haloPulse ? 150 : 110
                    )
                    .blur(radius: 28)
                    .animation(
                        .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                        value: haloPulse
                    )

                // Secondary purple halo (offset phase for a liquid-breathing feel)
                Circle()
                    .fill(Color.purple.opacity(haloPulse ? 0.12 : 0.03))
                    .frame(
                        width:  haloPulse ? 120 : 85,
                        height: haloPulse ? 120 : 85
                    )
                    .blur(radius: 20)
                    .animation(
                        .easeInOut(duration: 2.4).delay(0.55).repeatForever(autoreverses: true),
                        value: haloPulse
                    )

                // Rotating AngularGradient orb
                Circle()
                    .fill(AngularGradient(
                        stops: [
                            .init(color: .accentColor, location: 0.00),
                            .init(color: .purple,      location: 0.33),
                            .init(color: .pink,        location: 0.58),
                            .init(color: .blue,        location: 0.80),
                            .init(color: .accentColor, location: 1.00),
                        ],
                        center: .center
                    ))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(orbRotation))

                // Specular highlight — gives the orb a glossy, liquid feel
                Circle()
                    .fill(RadialGradient(
                        colors: [.white.opacity(0.55), .clear],
                        center: UnitPoint(x: 0.35, y: 0.28),
                        startRadius: 2,
                        endRadius: 28
                    ))
                    .frame(width: 80, height: 80)

                // SF Symbol icon centred on the orb
                Image(systemName: sidebarItem.systemImage)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    // Bounce in when the empty state first appears
                    .symbolEffect(.bounce)
            }
            .onAppear {
                // Start the continuous rotation
                withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) {
                    orbRotation = 360
                }
                // Trigger the halo pulse
                haloPulse = true
            }

            // ── Text ──────────────────────────────────────────────────────
            VStack(spacing: 8) {
                Text(emptyTitle)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text(emptySubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 270)
            }

            // CTA button — only for the full library, not smart collections
            if case .allImages = sidebarItem {
                Button("Add Images", action: openImagePanel)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var emptyTitle: String {
        switch sidebarItem {
        case .allImages:    return "No Images Yet"
        case .favorites:    return "No Favorites"
        case .tagged:       return "No Tagged Images"
        case .exportQueue:  return "Export Queue is Empty"
        case .folder:       return "Empty Folder"
        }
    }

    private var emptySubtitle: String {
        switch sidebarItem {
        case .allImages:
            return "Click the + button or drop images into the sidebar to start building your library."
        case .favorites:
            return "Star an image in the detail panel to add it here."
        case .tagged:
            return "Apply tags to images in the detail panel."
        case .exportQueue:
            return "Use the Export button in the detail panel to queue images."
        case .folder:
            return "No images from this folder are currently loaded."
        }
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
            ForEach(AssetSortOrder.allCases) { order in
                Button {
                    withAnimation(spring) { sortOrder = order }
                } label: {
                    HStack {
                        Text(order.rawValue)
                        if sortOrder == order {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort images")
    }

    // MARK: - Actions

    private func startBatchExport() {
        showBatchProgress = true
    }

    private func openImagePanel() {
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

    /// Clears the `appearedIDs` set and bumps `staggerGeneration` so that
    /// every `.task(id:)` on the card cells fires again, replaying the
    /// staggered entrance animation for the new filter / sort.
    private func resetStagger() {
        withAnimation(.easeOut(duration: 0.10)) { appearedIDs = [] }
        staggerGeneration += 1
    }
}
