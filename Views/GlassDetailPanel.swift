import SwiftUI

// MARK: - Glass Detail Panel

struct GlassDetailPanel: View {
    let asset: ImageAsset?

    @Environment(MetadataActor.self) private var metadataActor
    @State private var isEditing = false

    var body: some View {
        Group {
            if let asset {
                detailContent(for: asset)
            } else {
                placeholderView
            }
        }
        .glassBackgroundEffect()
    }

    // MARK: - Detail Content

    @ViewBuilder
    private func detailContent(for asset: ImageAsset) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                thumbnailHeader(for: asset)
                metadataSection(for: asset)
                exifSection(for: asset)
                iptcSection(for: asset)
                actionButtons(for: asset)
            }
            .padding(20)
        }
        .navigationTitle(asset.fileName)
    }

    // MARK: - Thumbnail Header

    private func thumbnailHeader(for asset: ImageAsset) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
            if let thumbnail = asset.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(8)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 240)
        .glassEffect(in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Metadata Section

    private func metadataSection(for asset: ImageAsset) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("File Info")
            metadataRow("File Name", value: asset.fileName)
            metadataRow("File Size", value: asset.formattedFileSize)
            metadataRow("Dimensions", value: asset.formattedDimensions)
            metadataRow("Date Modified", value: asset.formattedDate)
        }
    }

    // MARK: - EXIF Section

    private func exifSection(for asset: ImageAsset) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("EXIF Data")
            if let metadata = asset.metadata {
                metadataRow("Camera", value: metadata.cameraModel ?? "—")
                metadataRow("Lens", value: metadata.lensModel ?? "—")
                metadataRow("ISO", value: metadata.iso.map { "\($0)" } ?? "—")
                metadataRow("Aperture", value: metadata.formattedAperture)
                metadataRow("Shutter Speed", value: metadata.formattedShutterSpeed)
                metadataRow("Focal Length", value: metadata.formattedFocalLength)
                metadataRow("White Balance", value: metadata.whiteBalance ?? "—")
                metadataRow("Flash", value: metadata.flash ?? "—")
            } else {
                Text("No EXIF data available.")
                    .foregroundStyle(.tertiary)
                    .font(.callout)
            }
        }
    }

    // MARK: - IPTC Section

    private func iptcSection(for asset: ImageAsset) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("IPTC / XMP")
            if let metadata = asset.metadata {
                metadataRow("Title", value: metadata.title ?? "—")
                metadataRow("Description", value: metadata.imageDescription ?? "—")
                metadataRow("Copyright", value: metadata.copyright ?? "—")
                metadataRow("Creator", value: metadata.creator ?? "—")
                metadataRow("Keywords", value: metadata.keywords?.joined(separator: ", ") ?? "—")
            } else {
                Text("No IPTC/XMP data available.")
                    .foregroundStyle(.tertiary)
                    .font(.callout)
            }
        }
    }

    // MARK: - Action Buttons

    private func actionButtons(for asset: ImageAsset) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await metadataActor.toggleFavorite(asset) }
            } label: {
                Label(
                    asset.isFavorite ? "Remove Favorite" : "Add Favorite",
                    systemImage: asset.isFavorite ? "star.fill" : "star"
                )
            }
            .buttonStyle(.glass)

            Button {
                Task { await metadataActor.addToExportQueue(asset) }
            } label: {
                Label("Export", systemImage: "arrow.up.circle")
            }
            .buttonStyle(.glass)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .padding(.bottom, 2)
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
        }
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Select an Image")
                .font(.title2.bold())
                .foregroundStyle(.secondary)
            Text("Choose an image from the grid to view its metadata.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
