import Foundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Image Asset Model

@Observable
final class ImageAsset: Identifiable, Sendable {
    let id: UUID
    let url: URL
    var metadata: MetadataModel?
    var thumbnail: NSImage?
    var isFavorite: Bool
    var isInExportQueue: Bool
    var tags: [String]

    init(
        id: UUID = UUID(),
        url: URL,
        metadata: MetadataModel? = nil,
        thumbnail: NSImage? = nil,
        isFavorite: Bool = false,
        isInExportQueue: Bool = false,
        tags: [String] = []
    ) {
        self.id = id
        self.url = url
        self.metadata = metadata
        self.thumbnail = thumbnail
        self.isFavorite = isFavorite
        self.isInExportQueue = isInExportQueue
        self.tags = tags
    }

    // MARK: - Computed Properties

    var fileName: String {
        url.lastPathComponent
    }

    var formattedFileSize: String {
        guard let size = fileSize else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var formattedDimensions: String {
        guard let metadata else { return "—" }
        if let width = metadata.imageWidth, let height = metadata.imageHeight {
            return "\(width) × \(height) px"
        }
        return "—"
    }

    var formattedDate: String {
        guard let metadata, let date = metadata.dateTimeOriginal else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - Private Helpers

    private var fileSize: Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map { Int64($0) }
    }
}
