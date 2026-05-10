import SwiftUI

// MARK: - Glass Card

/// A glass-styled thumbnail card displayed in the image grid.
///
/// ## Visual design (Liquid Glass & Animation Bible)
/// - **Hover lift**:       `scaleEffect(1.04)` via `spring(response: 0.28, dampingFraction: 0.82)`
/// - **Selection bloom**:  gradient `strokeBorder` + accent `shadow` glow
/// - **Tap ripple**:       expanding translucent circle that fades on every tap
/// - **Shadow bloom**:     radius and opacity grow on hover / selection
/// - **Matched geometry**: `"thumb_<id>"` ID is wired to the hero namespace so
///                         `GlassDetailPanel` can participate in hero transitions.
struct GlassCard: View {
    let asset: ImageAsset
    let isSelected: Bool
    /// Namespace shared with `GlassDetailPanel` for thumbnail hero transitions.
    let namespace: Namespace.ID
    /// Fixed card height.  Grid mode uses 160 px; masonry mode passes a value
    /// derived from the image's aspect ratio.
    var cardHeight: CGFloat = 160
    /// `true` for assets discovered via FSEvents folder watching (shows a brief
    /// pulsing green border to draw the user's attention to the new arrival).
    var isNewlyAdded: Bool = false
    let action: () -> Void

    @Environment(ThumbnailActor.self) private var thumbnailActor

    // Interaction state
    @State private var isHovered = false
    @State private var rippleRadius: CGFloat = 0
    @State private var rippleOpacity: Double = 0
    @State private var newlyAddedPulse = false

    // Unified spring per master plan
    private let spring = Animation.spring(response: 0.28, dampingFraction: 0.82)

    // MARK: - Body

    var body: some View {
        Button {
            triggerRipple()
            action()
        } label: {
            ZStack(alignment: .bottomLeading) {
                // Thumbnail — carries the matched-geometry ID for hero transitions
                thumbnailView
                    .matchedGeometryEffect(id: "thumb_\(asset.id)", in: namespace)

                rippleOverlay
                metadataOverlay
            }
        }
        .buttonStyle(.plain)
        // Hover lift (1.04) with a gentle selection nudge (1.01)
        .scaleEffect(isHovered ? 1.04 : (isSelected ? 1.01 : 1.0))
        // Shadow bloom — colour, radius and Y-offset all grow on hover/selection
        .shadow(
            color: isSelected
                ? .accentColor.opacity(isHovered ? 0.55 : 0.42)
                : .black.opacity(isHovered ? 0.22 : 0.12),
            radius: isSelected ? (isHovered ? 22 : 14) : (isHovered ? 12 : 5),
            x: 0,
            y: isHovered ? 9 : 4
        )
        // Gradient bloom ring rendered on top of the glass surface
        .overlay(selectionBloom)
        // FSEvents "newly added" pulse ring
        .overlay(newlyAddedRing)
        .glassEffect(in: RoundedRectangle(cornerRadius: 14))
        .animation(spring, value: isHovered)
        .animation(spring, value: isSelected)
        .onHover { isHovered = $0 }
        // Kick off thumbnail generation the first time the card becomes visible
        .task(id: asset.id) {
            guard !asset.isThumbnailLoaded else { return }
            _ = await thumbnailActor.thumbnail(for: asset.url, asset: asset)
        }
        // Pulse the green ring when newly added
        .onAppear {
            guard isNewlyAdded else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                newlyAddedPulse = true
            }
        }
    }

    // MARK: - Selection Bloom

    /// A gradient-stroked ring with an inner glow shadow that appears when
    /// the card is selected.  Uses a spring transition so it pops on smoothly.
    @ViewBuilder
    private var selectionBloom: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.accentColor,
                            Color.accentColor.opacity(0.55),
                            Color.accentColor,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                // Inner glow drawn behind the stroke via a shadow
                .shadow(color: .accentColor.opacity(0.65), radius: 7)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    // MARK: - Newly Added Ring

    /// Pulsing green ring shown briefly for assets discovered via FSEvents.
    @ViewBuilder
    private var newlyAddedRing: some View {
        if isNewlyAdded {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    Color.green.opacity(newlyAddedPulse ? 0.9 : 0.25),
                    lineWidth: 2.5
                )
                .shadow(color: .green.opacity(0.5), radius: newlyAddedPulse ? 8 : 2)
                .transition(.opacity)
        }
    }

    // MARK: - Tap Ripple

    /// A translucent circle that starts at ~8 px, expands to fill the card
    /// and fades to transparent, simulating a Material-style ripple.
    private var rippleOverlay: some View {
        Circle()
            .fill(Color.white.opacity(rippleOpacity))
            .frame(width: rippleRadius * 2, height: rippleRadius * 2)
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Clip so the ripple never bleeds outside the card shape
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func triggerRipple() {
        rippleRadius = 8
        rippleOpacity = 0.38
        withAnimation(.easeOut(duration: 0.58)) {
            rippleRadius = 160
            rippleOpacity = 0
        }
    }

    // MARK: - Thumbnail View

    @ViewBuilder
    private var thumbnailView: some View {
        Group {
            if let thumbnail = asset.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity.animation(.easeIn(duration: 0.22)))
            } else {
                ZStack {
                    Color(.controlBackgroundColor)
                    if asset.isThumbnailLoaded {
                        // Generation finished but the format is unsupported
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .symbolEffect(.pulse)
                    }
                }
            }
        }
        // Fill the grid column width; height is controlled by the caller
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Metadata Overlay

    /// Glass-material label strip that slides in from the card bottom on hover
    /// and stays fully opaque when the card is selected.
    private var metadataOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(asset.displayTitle)
                .font(.caption.bold())
                .lineLimit(1)
                .truncationMode(.middle)
            Text(asset.formattedFileSize)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(6)
        .opacity(isHovered || isSelected ? 1.0 : 0.82)
        .animation(spring, value: isHovered)
        .animation(spring, value: isSelected)
    }
}
