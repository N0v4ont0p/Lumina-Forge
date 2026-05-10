import Foundation
import AppKit
import QuickLookThumbnailing
import SwiftData

// MARK: - ThumbnailActor

/// Background actor that generates, caches, and serves image thumbnails.
///
/// ## Cache hierarchy (fastest → slowest)
///
/// 1. **In-memory LRU** – O(1) lookup, capped at `lruCapacity` entries.
///    Evicts the least-recently-used entry when full.
///
/// 2. **SwiftData disk cache** – PNG data persisted in the app's Caches
///    directory.  Survives app restarts; stale entries are invalidated by
///    comparing the source file's modification date.
///
/// 3. **QLThumbnailGenerator** – Apple's Quick Look thumbnail engine.
///    Handles JPEG, PNG, HEIC, TIFF and all major RAW formats (CR3, NEF,
///    ARW, RAF, DNG, …) out of the box, including correct orientation.
///
/// ## Thread safety
///
/// All methods are actor-isolated.  The underlying SwiftData `ModelContext`
/// is created and used exclusively within this actor, so it is never shared
/// across threads.  `nonisolated(unsafe)` is used on the container / context
/// properties to satisfy the Swift 6 `Sendable` checker – access is safe
/// because it is serialised by the actor executor.
actor ThumbnailActor {

    // MARK: - Configuration

    /// Max pixel dimension (width or height) of generated thumbnails.
    static let maxPixelSize: Int = 320

    /// Maximum number of thumbnails retained in the hot in-memory LRU cache.
    private let lruCapacity: Int = 500

    // MARK: - In-Memory LRU

    /// Ordered list of URLs, front = most-recently accessed.
    private var lruOrder: [URL] = []

    /// URL → image mapping.
    private var lruCache: [URL: NSImage] = [:]

    // MARK: - SwiftData Persistence
    //
    // These properties are only ever touched from within actor-isolated methods,
    // so access is serialised by the actor executor.  `nonisolated(unsafe)` opts
    // out of the Swift 6 Sendability check while remaining correct at runtime.

    nonisolated(unsafe) private let modelContainer: ModelContainer
    nonisolated(unsafe) private let modelContext: ModelContext

    // MARK: - Init

    /// Creates the actor and establishes the SwiftData thumbnail cache.
    ///
    /// Falls back to an in-memory-only SwiftData store if the persistent
    /// store cannot be created (e.g. during unit tests or sandboxing issues).
    init() {
        let schema = Schema([CachedThumbnail.self])
        let persistConfig = ModelConfiguration(
            "LuminaThumbCache",
            schema: schema,
            isStoredInMemoryOnly: false
        )

        if let container = try? ModelContainer(for: schema, configurations: persistConfig) {
            self.modelContainer = container
        } else {
            // Graceful fallback: use an in-memory store so the app still works.
            let memConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // Force-try is safe here: an in-memory store always succeeds.
            self.modelContainer = try! ModelContainer(for: schema, configurations: memConfig)
        }
        self.modelContext = ModelContext(self.modelContainer)
    }

    // MARK: - Public API

    /// Return a thumbnail for `url`, populating `asset.thumbnail` as a side-effect.
    ///
    /// Cache lookup order: LRU → SwiftData → QLThumbnailGenerator.
    func thumbnail(for url: URL, asset: ImageAsset) async -> NSImage? {

        // 1. Hot LRU cache
        if let hit = lruGet(url) {
            return hit
        }

        // 2. SwiftData disk cache (check for staleness via file mod-date)
        if let cached = persistedThumbnail(for: url),
           !isStale(cached, url: url),
           let image = NSImage(data: cached.pngData) {
            lruPut(url, image: image)
            asset.thumbnail         = image
            asset.isThumbnailLoaded = true
            return image
        }

        // 3. Generate via QLThumbnailGenerator
        guard let image = await generateThumbnail(for: url) else { return nil }

        lruPut(url, image: image)
        persistThumbnail(image, for: url)

        asset.thumbnail         = image
        asset.isThumbnailLoaded = true
        return image
    }

    /// Pre-warm the cache for a batch of assets using a concurrent TaskGroup.
    ///
    /// Call this after loading a new folder to front-load generation work
    /// before the user scrolls to those items.
    func prewarm(assets: [ImageAsset]) async {
        await withTaskGroup(of: Void.self) { group in
            for asset in assets {
                let url = asset.url
                group.addTask { _ = await self.thumbnail(for: url, asset: asset) }
            }
        }
    }

    /// Remove a URL from both the LRU and SwiftData caches.
    func evict(url: URL) {
        lruRemove(url)
        if let cached = persistedThumbnail(for: url) {
            modelContext.delete(cached)
            try? modelContext.save()
        }
    }

    /// Flush the in-memory LRU without touching the SwiftData disk cache.
    func clearMemoryCache() {
        lruOrder.removeAll()
        lruCache.removeAll()
    }

    /// Purge all cached entries older than `days` days from the SwiftData store.
    func pruneOldEntries(olderThanDays days: Int = 30) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let predicate = #Predicate<CachedThumbnail> { $0.cachedAt < cutoff }
        let descriptor = FetchDescriptor<CachedThumbnail>(predicate: predicate)
        if let stale = try? modelContext.fetch(descriptor) {
            stale.forEach { modelContext.delete($0) }
            try? modelContext.save()
        }
    }

    // MARK: - QL Generation

    private func generateThumbnail(for url: URL) async -> NSImage? {
        let size = CGSize(
            width:  Self.maxPixelSize,
            height: Self.maxPixelSize
        )
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: 1.0,
            representationTypes: .thumbnail
        )

        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateRepresentations(for: request) { rep, _, error in
                guard error == nil, let cgImage = rep?.cgImage else {
                    // Fallback: try CGImageSource for formats QL may not handle
                    let fallback = Self.cgImageSourceThumbnail(for: url)
                    continuation.resume(returning: fallback)
                    return
                }
                let image = NSImage(
                    cgImage: cgImage,
                    size: NSSize(width: cgImage.width, height: cgImage.height)
                )
                continuation.resume(returning: image)
            }
        }
    }

    /// Secondary fallback thumbnail generator using `CGImageSource`.
    private static func cgImageSourceThumbnail(for url: URL) -> NSImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard
            let src = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cg  = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    // MARK: - LRU Helpers

    private func lruGet(_ url: URL) -> NSImage? {
        guard let image = lruCache[url] else { return nil }
        // Move to front (mark as most-recently used).
        lruOrder.removeAll { $0 == url }
        lruOrder.insert(url, at: 0)
        return image
    }

    private func lruPut(_ url: URL, image: NSImage) {
        if lruCache[url] != nil {
            lruOrder.removeAll { $0 == url }
        }
        lruOrder.insert(url, at: 0)
        lruCache[url] = image

        // Evict tail entries when over capacity.
        while lruOrder.count > lruCapacity {
            if let evicted = lruOrder.popLast() {
                lruCache.removeValue(forKey: evicted)
            }
        }
    }

    private func lruRemove(_ url: URL) {
        lruOrder.removeAll { $0 == url }
        lruCache.removeValue(forKey: url)
    }

    // MARK: - SwiftData Helpers

    private func persistedThumbnail(for url: URL) -> CachedThumbnail? {
        let path = url.path(percentEncoded: false)
        let descriptor = FetchDescriptor<CachedThumbnail>(
            predicate: #Predicate { $0.filePath == path }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func isStale(_ entry: CachedThumbnail, url: URL) -> Bool {
        guard
            let cachedMod = entry.fileModificationDate,
            let diskMod   = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                                .contentModificationDate
        else { return false }
        return diskMod > cachedMod
    }

    private func persistThumbnail(_ image: NSImage, for url: URL) {
        guard
            let tiff   = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png    = bitmap.representation(using: .png, properties: [:])
        else { return }

        let path    = url.path(percentEncoded: false)
        let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                          .contentModificationDate

        if let existing = persistedThumbnail(for: url) {
            existing.pngData              = png
            existing.cachedAt             = .now
            existing.fileModificationDate = modDate
        } else {
            modelContext.insert(
                CachedThumbnail(filePath: path, pngData: png, fileModificationDate: modDate)
            )
        }
        try? modelContext.save()
    }
}
