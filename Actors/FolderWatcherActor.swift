import Foundation
import CoreServices    // FSEventStreamCreate, FSEventStreamRef, …

// MARK: - FSWatch Handle

/// Non-actor wrapper around a single `FSEventStreamRef`.
///
/// Kept alive as a value in `FolderWatcherActor.handles` so the actor's
/// reference count prevents premature deallocation while the stream is
/// running.  The handle is `@unchecked Sendable` because:
///
/// - `start()` is called once before the handle is inserted into the actor's
///   dictionary (no concurrent callers).
/// - `stop()` is called only after the handle is removed from the dictionary
///   (actor-serialised), then again from `deinit` which is a no-op after `stop()`.
/// - The C callback fires on a private `DispatchQueue` and only reads the
///   `onChange` constant — safe.
private final class FSWatchHandle: @unchecked Sendable {

    private var stream: FSEventStreamRef?
    private let directory: URL

    /// Called from a background dispatch queue with the set of changed paths.
    let onChange: @Sendable ([URL]) -> Void

    init(directory: URL, onChange: @escaping @Sendable ([URL]) -> Void) {
        self.directory = directory
        self.onChange  = onChange
    }

    func start() {
        // Wrap `self` as an unretained raw pointer for the C context.
        // Safety: the handle lives in `FolderWatcherActor.handles` for at
        // least as long as the stream is running.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        var context = FSEventStreamContext(
            version: 0, info: selfPtr, retain: nil, release: nil, copyDescription: nil
        )

        // Callback receives per-file paths because we request `FileEvents`.
        let eventCallback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            guard let info else { return }
            let handle = Unmanaged<FSWatchHandle>.fromOpaque(info).takeUnretainedValue()

            // eventPaths is a CFArray of CFStrings (kFSEventStreamCreateFlagUseCFTypes).
            guard let rawArray = Unmanaged<CFArray>.fromOpaque(eventPaths)
                .takeUnretainedValue() as? [String]
            else { return }

            let flagsBuf = UnsafeBufferPointer(start: eventFlags, count: numEvents)
            var urls: [URL] = []

            for i in 0 ..< numEvents {
                let flag = flagsBuf[i]
                // Only surface Created events to avoid double-loading modified files.
                let isCreated  = flag & UInt32(kFSEventStreamEventFlagItemCreated)  != 0
                let isRenamed  = flag & UInt32(kFSEventStreamEventFlagItemRenamed)  != 0
                if (isCreated || isRenamed), i < rawArray.count {
                    urls.append(URL(fileURLWithPath: rawArray[i]))
                }
            }

            guard !urls.isEmpty else { return }
            handle.onChange(urls)
        }

        let pathsToWatch = [directory.path(percentEncoded: false)] as CFArray

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            eventCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,    // coalesce window – wait 2 s for burst writes to settle
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagFileEvents  |
                kFSEventStreamCreateFlagNoDefer
            )
        )

        if let s = stream {
            let queue = DispatchQueue(
                label: "FolderWatcher.\(directory.lastPathComponent)",
                qos: .utility
            )
            FSEventStreamSetDispatchQueue(s, queue)
            FSEventStreamStart(s)
        }
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    deinit { stop() }
}

// MARK: - FolderWatcherActor

/// Monitors a set of directories with `FSEvents` and surfaces newly discovered
/// image file URLs through `newlyDiscoveredURLs`.
///
/// ## Typical usage (from `ContentView`)
///
/// ```swift
/// // Keep watches in sync with the loaded library:
/// .onChange(of: metadataActor.assets) { _, newAssets in
///     let dirs = Set(newAssets.map { $0.url.deletingLastPathComponent() })
///     Task { await folderWatcher.updateWatches(directories: dirs) }
/// }
///
/// // Auto-load any new files the user drops via Finder:
/// .onChange(of: folderWatcher.newlyDiscoveredURLs) { _, urls in
///     guard !urls.isEmpty else { return }
///     Task {
///         let fresh = await folderWatcher.consumeNewURLs()
///         await metadataActor.loadAssetsWatched(from: fresh)
///     }
/// }
/// ```
@Observable
actor FolderWatcherActor {

    // MARK: - Published

    /// Image file URLs detected since the last `consumeNewURLs()` call.
    /// Set to `[]` after `consumeNewURLs()` so the observer fires again
    /// next time new files appear.
    private(set) var newlyDiscoveredURLs: [URL] = []

    // MARK: - Private

    private var handles: [URL: FSWatchHandle] = [:]

    private let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp",
        "cr2", "cr3", "nef", "arw", "rw2", "raf", "orf", "dng", "pef", "srw", "x3f", "mrw",
    ]

    // MARK: - Public API

    /// Begin watching `directory`.  No-op if already watching that directory.
    func watch(directory: URL) {
        guard handles[directory] == nil else { return }
        let handle = FSWatchHandle(directory: directory) { [weak self] urls in
            Task { await self?.received(urls: urls) }
        }
        handle.start()
        handles[directory] = handle
    }

    /// Stop watching `directory`.
    func unwatch(directory: URL) {
        handles[directory]?.stop()
        handles.removeValue(forKey: directory)
    }

    /// Synchronise the active watches with the given directory set.
    ///
    /// Directories no longer in `directories` are unwatched; new ones are added.
    func updateWatches(directories: Set<URL>) {
        let current = Set(handles.keys)

        for removed in current.subtracting(directories) { unwatch(directory: removed) }
        for added   in directories.subtracting(current)  { watch(directory: added)    }
    }

    /// Stop all active watches.
    func unwatchAll() {
        handles.values.forEach { $0.stop() }
        handles.removeAll()
    }

    /// Return and clear the accumulated new-file URLs.
    func consumeNewURLs() -> [URL] {
        defer { newlyDiscoveredURLs = [] }
        return newlyDiscoveredURLs
    }

    // MARK: - Private

    private func received(urls: [URL]) {
        let images = urls.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
        guard !images.isEmpty else { return }
        newlyDiscoveredURLs.append(contentsOf: images)
    }
}
