import Foundation
import AppKit

// MARK: - Thumbnail Actor

/// Thread-safe actor responsible for generating and caching
/// image thumbnails asynchronously.
actor ThumbnailActor {

    // MARK: - Cache

    private var cache: [URL: NSImage] = [:]
    private let thumbnailSize = CGSize(width: 320, height: 320)

    // MARK: - Public Interface

    /// Returns a cached thumbnail or generates one on the fly.
    func thumbnail(for url: URL) async -> NSImage? {
        if let cached = cache[url] {
            return cached
        }
        return await generateThumbnail(for: url)
    }

    /// Pre-warm the thumbnail cache for an array of URLs.
    func prewarm(urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    _ = await self.thumbnail(for: url)
                }
            }
        }
    }

    /// Evict a specific URL from the cache.
    func evict(url: URL) {
        cache.removeValue(forKey: url)
    }

    /// Clear the entire thumbnail cache.
    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Private Generation

    private func generateThumbnail(for url: URL) async -> NSImage? {
        // Use CGImageSource for efficient thumbnail generation
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(thumbnailSize.width, thumbnailSize.height)
        ]

        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return nil
        }

        let nsImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )

        cache[url] = nsImage
        return nsImage
    }
}
