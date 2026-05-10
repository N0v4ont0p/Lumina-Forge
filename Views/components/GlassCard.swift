import SwiftUI

// MARK: - Glass Card Component

struct GlassCard: View {
    let asset: ImageAsset
    let isSelected: Bool
    let action: () -> Void

    @Environment(ThumbnailActor.self) private var thumbnailActor
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                thumbnailView
                metadataOverlay
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isSelected ? Color.accentColor : Color.clear,
                    lineWidth: 2
                )
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: 14))
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(
            color: isSelected ? .accentColor.opacity(0.4) : .black.opacity(0.15),
            radius: isSelected ? 12 : 6,
            x: 0,
            y: 4
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        // Kick off thumbnail generation when the card first appears.
        .task(id: asset.id) {
            guard !asset.isThumbnailLoaded else { return }
            _ = await thumbnailActor.thumbnail(for: asset.url, asset: asset)
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
            } else {
                ZStack {
                    Color(.controlBackgroundColor)
                    if asset.isThumbnailLoaded {
                        // Generation finished but returned nil (unsupported format)
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                    } else {
                        // Still loading
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
        .frame(width: 160, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Metadata Overlay

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
        .opacity(isHovered || isSelected ? 1.0 : 0.85)
    }
}
