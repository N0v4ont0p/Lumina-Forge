import Foundation
import SwiftData

// MARK: - CachedThumbnail

/// SwiftData persistent model for the thumbnail disk cache.
///
/// `ThumbnailActor` writes PNG-encoded thumbnail data here so thumbnails
/// survive app restarts.  The `filePath` property (absolute POSIX path) is the
/// primary lookup key.  `fileModificationDate` is stored alongside so the actor
/// can detect when the source image has been updated and invalidate the entry.
///
/// The schema lives in its own lightweight `ModelContainer` owned by
/// `ThumbnailActor`, keeping it fully isolated from any other SwiftData
/// container in the app.
@Model
final class CachedThumbnail {

    // MARK: - Stored Properties

    /// Absolute POSIX path of the source image file.
    var filePath: String

    /// PNG-encoded thumbnail data (max 320 × 320 px).
    var pngData: Data

    /// When this cache entry was created or last refreshed.
    var cachedAt: Date

    /// Last-modified date of the source file at the time of caching.
    /// Used to detect stale cache entries when the source image changes.
    var fileModificationDate: Date?

    // MARK: - Init

    init(
        filePath: String,
        pngData: Data,
        fileModificationDate: Date? = nil
    ) {
        self.filePath             = filePath
        self.pngData              = pngData
        self.cachedAt             = .now
        self.fileModificationDate = fileModificationDate
    }
}
