import Foundation
import ImageIO

// MARK: - MetadataActor

/// Production-grade background actor responsible for all image-metadata I/O.
///
/// ## Architecture
///
/// ### Two-pass loading (optimised for 20 k+ libraries)
///
/// 1. **Fast pass – ImageIO (no subprocess).**
///    `readQuickMetadata(from:)` reads basic EXIF / TIFF / GPS / IPTC fields
///    straight from the file's embedded IFDs via `CGImageSourceCopyProperties`.
///    This runs synchronously and is called immediately for every asset so the
///    UI grid populates within milliseconds.
///
/// 2. **Full pass – ExifTool (batched subprocess).**
///    URLs are chunked into batches of up to 500 and submitted to the bundled
///    ExifTool binary in parallel TaskGroups.  ExifTool handles every vendor
///    extension (Canon CR3, Nikon NEF, Sony ARW, Fuji RAF, DJI XMP, …).
///    An `AsyncSemaphore` caps concurrent ExifTool processes to avoid
///    overwhelming the OS scheduler.
///
/// ### Non-blocking subprocesses
///
/// `Process.terminationHandler` is used instead of `waitUntilExit()` so no
/// thread from the cooperative pool is ever blocked.
///
/// ### Undo stack
///
/// Every successful `writeMetadata` call pushes a `MetadataEdit` onto a
/// per-asset ring buffer (capped at `maxUndoDepth`).  `undo(for:)` pops the
/// most recent edit and re-applies the previous state.
@Observable
actor MetadataActor {

    // MARK: - Published State

    /// All currently loaded image assets.
    private(set) var assets: [ImageAsset] = []

    /// `true` while a load operation is in progress.
    private(set) var isLoading = false

    /// Fractional progress of the current load (0.0 – 1.0).
    private(set) var loadProgress: Double = 0

    var assetCount: Int { assets.count }

    // MARK: - Batch Operation Progress

    /// Total assets in the current batch operation.
    private(set) var batchTotal: Int = 0

    /// Number of assets completed in the current batch operation.
    private(set) var batchCompleted: Int = 0

    /// Filename currently being processed during a batch operation.
    private(set) var currentProcessingFile: String = ""

    /// `true` while a batch export / write operation is active.
    private(set) var isBatchRunning: Bool = false

    /// Set to `true` to request cancellation of the current batch operation.
    private var isBatchCancelled: Bool = false

    /// Most-recent operation error, displayed in the UI as an alert.
    private(set) var lastError: String? = nil

    // MARK: - Recently Added (FSEvents)

    /// Asset IDs whose files were discovered via FSEvents folder-watching.
    /// Cleared 5 s after being populated so the highlight pulse fades out.
    private(set) var recentlyAddedAssetIDs: Set<UUID> = []

    // MARK: - Undo Stack
    // Maps asset.id → ring buffer of MetadataEdit records.

    private var undoStack: [UUID: [MetadataEdit]] = [:]
    private let maxUndoDepth = 100

    // MARK: - Concurrency Control

    /// Caps concurrent ExifTool processes to prevent scheduler saturation.
    private let semaphore = AsyncSemaphore(limit: 8)

    /// Number of files per ExifTool batch invocation.
    private let batchSize = 500

    // MARK: - ExifTool Binary

    private var exifToolURL: URL? {
        Bundle.main.url(
            forResource: "exiftool",
            withExtension: nil,
            subdirectory: "ExifTool"
        )
    }

    // MARK: ─── LOAD ─────────────────────────────────────────────────────────

    /// Load assets from an array of file / directory URLs.
    ///
    /// - Deduplicates against already-loaded assets.
    /// - Immediately creates `ImageAsset` stubs so the grid renders.
    /// - Runs a fast ImageIO pass synchronously on the actor.
    /// - Runs a full ExifTool pass in a concurrent `TaskGroup`.
    func loadAssets(from urls: [URL]) async {
        // Expand any directories to image files.
        let fileURLs = expandToImageFiles(urls)
        let newURLs  = fileURLs.filter { url in !assets.contains { $0.url == url } }
        guard !newURLs.isEmpty else { return }

        isLoading    = true
        loadProgress = 0
        defer { isLoading = false; loadProgress = 1 }

        let total = Double(newURLs.count)
        var completed = 0

        // ── Step 1: Create stubs immediately ──────────────────────────────
        var newAssets: [ImageAsset] = newURLs.map { url in
            let asset = ImageAsset(url: url)
            asset.cachedFileSize = ImageAsset.diskFileSize(for: url)
            return asset
        }
        assets.append(contentsOf: newAssets)

        // ── Step 2: Fast ImageIO pass ──────────────────────────────────────
        // Runs without a subprocess; safe to iterate sequentially on the actor.
        for asset in newAssets {
            if let quick = Self.readQuickMetadata(from: asset.url) {
                asset.metadata          = quick
                asset.isMetadataLoaded  = true
            }
        }

        // ── Step 3: Full ExifTool pass (batched, concurrent) ──────────────
        guard let _ = exifToolURL else { return }   // binary not bundled yet

        let batches = stride(from: 0, to: newAssets.count, by: batchSize).map {
            Array(newAssets[$0 ..< min($0 + batchSize, newAssets.count)])
        }

        await withTaskGroup(of: [(UUID, MetadataModel?)].self) { group in
            for batch in batches {
                let batchURLs = batch.map(\.url)
                let batchIDs  = batch.map(\.id)

                group.addTask { [weak self] in
                    guard let self else { return [] }

                    // Throttle: at most `semaphore.limit` batches at once.
                    await self.semaphore.wait()
                    defer { Task { await self.semaphore.signal() } }

                    let results = await self.readFullMetadataBatch(urls: batchURLs)
                    return zip(batchIDs, results).map { ($0.0, $0.1) }
                }
            }

            for await batchResults in group {
                for (assetID, meta) in batchResults {
                    if let meta,
                       let asset = newAssets.first(where: { $0.id == assetID }) {
                        asset.metadata         = meta
                        asset.isMetadataLoaded = true
                    }
                }
                completed  += batchSize
                loadProgress = min(Double(completed) / total, 1.0)
            }
        }
    }

    // MARK: ─── FOLDER-WATCH LOAD ─────────────────────────────────────────────

    /// Load assets discovered by `FolderWatcherActor` (FSEvents-triggered).
    ///
    /// Identical to `loadAssets(from:)` but marks newly created `ImageAsset`
    /// objects as recently-added so the grid card can display a highlight pulse.
    /// The recently-added marking is cleared automatically after 5 seconds.
    func loadAssetsWatched(from urls: [URL]) async {
        let fileURLs = expandToImageFiles(urls)
        let newURLs  = fileURLs.filter { url in !assets.contains { $0.url == url } }
        guard !newURLs.isEmpty else { return }

        let newAssets: [ImageAsset] = newURLs.map { url in
            let asset = ImageAsset(url: url)
            asset.cachedFileSize = ImageAsset.diskFileSize(for: url)
            return asset
        }
        assets.append(contentsOf: newAssets)

        // Mark as recently added for highlight pulse.
        let newIDs = Set(newAssets.map(\.id))
        recentlyAddedAssetIDs.formUnion(newIDs)

        // Fast ImageIO pass.
        for asset in newAssets {
            if let quick = Self.readQuickMetadata(from: asset.url) {
                asset.metadata         = quick
                asset.isMetadataLoaded = true
            }
        }

        // Clear the highlight after 5 seconds.
        Task {
            try? await Task.sleep(for: .seconds(5))
            recentlyAddedAssetIDs.subtract(newIDs)
        }
    }

    // MARK: ─── FAST READ – ImageIO ──────────────────────────────────────────

    /// Reads basic EXIF / GPS / IPTC data via `CGImageSource` – no subprocess.
    ///
    /// Returns `nil` when the file cannot be opened or has no readable metadata.
    /// Declared `static` and `nonisolated` so it can be called from TaskGroup
    /// child tasks without hopping to the actor executor.
    static func readQuickMetadata(from url: URL) -> MetadataModel? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props  = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                            as? [CFString: Any]
        else { return nil }

        var m = MetadataModel()
        m.sourceURL = url

        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps  = props[kCGImagePropertyGPSDictionary]  as? [CFString: Any] ?? [:]
        let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] ?? [:]

        // TIFF / hardware
        m.cameraMake        = tiff[kCGImagePropertyTIFFMake]  as? String
        m.cameraModel       = tiff[kCGImagePropertyTIFFModel] as? String
        m.software          = tiff[kCGImagePropertyTIFFSoftware] as? String
        m.imageDescription  = tiff[kCGImagePropertyTIFFImageDescription] as? String
        m.orientation       = (tiff[kCGImagePropertyTIFFOrientation] as? NSNumber)?.intValue

        // Pixel dimensions
        m.imageWidth  = (props[kCGImagePropertyPixelWidth]  as? NSNumber)?.intValue
        m.imageHeight = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue

        // Exposure
        m.iso                  = (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first?.intValue
        m.aperture             = (exif[kCGImagePropertyExifFNumber]         as? NSNumber)?.doubleValue
        m.shutterSpeed         = (exif[kCGImagePropertyExifExposureTime]    as? NSNumber)?.doubleValue
        m.focalLength          = (exif[kCGImagePropertyExifFocalLength]     as? NSNumber)?.doubleValue
        m.focalLengthIn35mm    = (exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? NSNumber)?.intValue
        m.exposureCompensation = (exif[kCGImagePropertyExifExposureBiasValue] as? NSNumber)?.doubleValue
        m.lensModel            = exif[kCGImagePropertyExifLensModel] as? String
        m.flash                = (exif[kCGImagePropertyExifFlash] as? NSNumber).map { "\($0)" }
        m.exposureMode         = (exif[kCGImagePropertyExifExposureMode] as? NSNumber)
                                    .map { Self.exposureModeName($0.intValue) }
        m.meteringMode         = (exif[kCGImagePropertyExifMeteringMode] as? NSNumber)
                                    .map { Self.meteringModeName($0.intValue) }

        // Dates
        let fmt = DateFormatter.exifFormat
        if let s = exif[kCGImagePropertyExifDateTimeOriginal]  as? String { m.dateTimeOriginal  = fmt.date(from: s) }
        if let s = exif[kCGImagePropertyExifDateTimeDigitized] as? String { m.dateTimeDigitized = fmt.date(from: s) }
        if let s = tiff[kCGImagePropertyTIFFDateTime]          as? String { m.dateTimeModified  = fmt.date(from: s) }

        // GPS
        if let lat = gps[kCGImagePropertyGPSLatitude]  as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            let latRef = gps[kCGImagePropertyGPSLatitudeRef]  as? String ?? "N"
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
            m.gpsLatitude  = latRef == "S" ? -lat : lat
            m.gpsLongitude = lonRef == "W" ? -lon : lon
        }
        m.gpsAltitude = (gps[kCGImagePropertyGPSAltitude] as? NSNumber)?.doubleValue

        // IPTC (basic fields that ImageIO exposes)
        m.copyright = iptc[kCGImagePropertyIPTCCopyrightNotice] as? String
        m.creator   = iptc[kCGImagePropertyIPTCByline] as? String
        m.caption   = iptc[kCGImagePropertyIPTCCaptionAbstract] as? String
        m.headline  = iptc[kCGImagePropertyIPTCHeadline] as? String
        m.keywords  = iptc[kCGImagePropertyIPTCKeywords] as? [String]
        m.city      = iptc[kCGImagePropertyIPTCCity] as? String
        m.state     = iptc[kCGImagePropertyIPTCProvinceState] as? String
        m.country   = iptc[kCGImagePropertyIPTCCountryPrimaryLocationName] as? String
        m.source    = iptc[kCGImagePropertyIPTCSource] as? String
        m.credit    = iptc[kCGImagePropertyIPTCCredit] as? String

        return m
    }

    // MARK: ─── FULL READ – ExifTool (batched) ───────────────────────────────

    /// Invoke ExifTool once for an entire batch of URLs and parse the JSON array.
    ///
    /// Returns one `MetadataModel?` per input URL (preserving order).
    /// `nil` entries indicate files ExifTool could not parse.
    private func readFullMetadataBatch(urls: [URL]) async -> [MetadataModel?] {
        guard let tool = exifToolURL else { return Array(repeating: nil, count: urls.count) }

        var args: [String] = [
            "-json", "-n", "-charset", "UTF8",
            "-EXIF:All", "-IPTC:All", "-XMP:All", "-GPS:All",
            "-d", "%Y:%m:%d %H:%M:%S",     // normalise date output
        ]
        args.append(contentsOf: urls.map { $0.path(percentEncoded: false) })

        guard let data = await runExifToolProcess(tool: tool, arguments: args),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return Array(repeating: nil, count: urls.count)
        }

        // ExifTool output preserves input order.
        return zip(urls, array).map { url, dict in
            parseExifToolDict(dict, sourceURL: url)
        }
    }

    // MARK: ─── WRITE METADATA ────────────────────────────────────────────────

    /// Write user-edited metadata fields to the file on disk.
    ///
    /// All IPTC and XMP namespaces are written simultaneously.  GPS coordinates
    /// are written with correct hemisphere reference tags.  Keywords replace
    /// the existing set (clear-then-add).
    ///
    /// **Safety:** before writing, a temp backup of the original file is created
    /// in the system temp directory.  If ExifTool fails, the backup is restored
    /// so the original file is never left in a corrupt state.  On success the
    /// backup is deleted.
    ///
    /// Before writing, the current metadata is saved to the undo stack.
    /// After writing succeeds, the in-memory model is updated.
    ///
    /// - Throws: `MetadataError.exifToolNotFound` / `MetadataError.writeFailed`.
    func writeMetadata(_ metadata: MetadataModel, to asset: ImageAsset) async throws {
        guard let tool = exifToolURL else { throw MetadataError.exifToolNotFound }

        // ── Safety backup ────────────────────────────────────────────────────
        let backupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "LuminaBackup_\(asset.id.uuidString)_\(asset.url.lastPathComponent)"
            )
        try? FileManager.default.removeItem(at: backupURL)          // clean stale backup
        try? FileManager.default.copyItem(at: asset.url, to: backupURL)

        // Push undo before modifying anything.
        pushUndo(assetID: asset.id, before: asset.metadata, after: metadata)

        var args: [String] = ["-overwrite_original", "-charset", "UTF8"]

        // Helper: set the same value in both IPTC and XMP namespaces.
        func set(iptc: String, xmp: String, value: String?) {
            guard let v = value else { return }
            args.append("-IPTC:\(iptc)=\(v)")
            args.append("-XMP:\(xmp)=\(v)")
        }

        set(iptc: "ObjectName",              xmp: "Title",       value: metadata.title)
        set(iptc: "Headline",                xmp: "Headline",    value: metadata.headline)
        set(iptc: "Caption-Abstract",        xmp: "Description", value: metadata.caption)
        set(iptc: "CopyrightNotice",         xmp: "Rights",      value: metadata.copyright)
        set(iptc: "By-line",                 xmp: "Creator",     value: metadata.creator)
        set(iptc: "By-lineTitle",            xmp: "CreatorTitle",value: metadata.creatorTitle)
        set(iptc: "Credit",                  xmp: "Credit",      value: metadata.credit)
        set(iptc: "Source",                  xmp: "Source",      value: metadata.source)
        set(iptc: "City",                    xmp: "City",        value: metadata.city)
        set(iptc: "Province-State",          xmp: "State",       value: metadata.state)
        set(iptc: "Country-PrimaryLocationName", xmp: "Country", value: metadata.country)
        set(iptc: "Country-PrimaryLocationCode", xmp: "CountryCode", value: metadata.countryCode)
        set(iptc: "Sub-location",            xmp: "Location",    value: metadata.location)
        set(iptc: "SpecialInstructions",     xmp: "Instructions",value: metadata.instructions)

        if let label = metadata.label { args.append("-XMP:Label=\(label)") }

        // EXIF ImageDescription (ASCII legacy field, separate from IPTC)
        if let desc = metadata.imageDescription { args.append("-EXIF:ImageDescription=\(desc)") }

        // Keywords – clear existing set then re-add (atomic replace)
        args.append("-IPTC:Keywords=")
        args.append("-XMP:Subject=")
        for kw in (metadata.keywords ?? []) {
            args.append("-IPTC:Keywords+=\(kw)")
            args.append("-XMP:Subject+=\(kw)")
        }

        // Rating (XMP only; 0 = no star)
        if let r = metadata.rating { args.append("-XMP:Rating=\(r)") }

        // GPS – write decimal + hemisphere ref tags
        if let lat = metadata.gpsLatitude, let lon = metadata.gpsLongitude {
            args += [
                "-GPS:GPSLatitude=\(abs(lat))",
                "-GPS:GPSLatitudeRef=\(lat >= 0 ? "N" : "S")",
                "-GPS:GPSLongitude=\(abs(lon))",
                "-GPS:GPSLongitudeRef=\(lon >= 0 ? "E" : "W")",
            ]
            if let alt = metadata.gpsAltitude {
                args += [
                    "-GPS:GPSAltitude=\(abs(alt))",
                    "-GPS:GPSAltitudeRef=\(alt >= 0 ? 0 : 1)",
                ]
            }
        }

        args.append(asset.url.path(percentEncoded: false))

        guard let _ = await runExifToolProcess(tool: tool, arguments: args, expectOutput: false) else {
            // ── Restore from backup if write failed ──────────────────────────
            if FileManager.default.fileExists(atPath: backupURL.path(percentEncoded: false)) {
                try? FileManager.default.removeItem(at: asset.url)
                try? FileManager.default.copyItem(at: backupURL, to: asset.url)
            }
            try? FileManager.default.removeItem(at: backupURL)
            throw MetadataError.writeFailed(asset.url)
        }

        // ── Remove backup on success ─────────────────────────────────────────
        try? FileManager.default.removeItem(at: backupURL)

        // Update in-memory model and clear the dirty flag.
        var saved = metadata
        saved.hasUnsavedChanges = false
        asset.metadata = saved
    }

    // MARK: ─── STRIP ALL METADATA ────────────────────────────────────────────

    /// Remove ALL metadata from a file (privacy scrub / clean export).
    ///
    /// This is irreversible on disk but an undo record is pushed so the
    /// in-memory state can be restored within the session.
    func stripAllMetadata(from asset: ImageAsset) async throws {
        guard let tool = exifToolURL else { throw MetadataError.exifToolNotFound }

        pushUndo(assetID: asset.id, before: asset.metadata, after: MetadataModel())

        let args = ["-all=", "-overwrite_original", asset.url.path(percentEncoded: false)]
        guard let _ = await runExifToolProcess(tool: tool, arguments: args, expectOutput: false) else {
            throw MetadataError.writeFailed(asset.url)
        }

        var empty = MetadataModel()
        empty.sourceURL = asset.url
        asset.metadata = empty
    }

    // MARK: ─── SIDECAR XMP EXPORT ────────────────────────────────────────────

    /// Export all XMP metadata for an asset as a companion `.xmp` sidecar file.
    ///
    /// - Parameter directory: Output directory; defaults to the image's folder.
    /// - Returns: The URL of the created `.xmp` file.
    /// - Throws: `MetadataError.sidecarExportFailed` on ExifTool error.
    @discardableResult
    func exportSidecarXMP(for asset: ImageAsset, to directory: URL? = nil) async throws -> URL {
        guard let tool = exifToolURL else { throw MetadataError.exifToolNotFound }

        let baseDir = directory ?? asset.url.deletingLastPathComponent()
        let sidecarURL = baseDir
            .appendingPathComponent(asset.url.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("xmp")

        let args: [String] = [
            "-TagsFromFile", asset.url.path(percentEncoded: false),
            "-XMP:All",
            "-o", sidecarURL.path(percentEncoded: false),
        ]
        guard let _ = await runExifToolProcess(tool: tool, arguments: args, expectOutput: false) else {
            throw MetadataError.sidecarExportFailed(asset.url)
        }
        return sidecarURL
    }

    // MARK: ─── BATCH HELPERS ─────────────────────────────────────────────────

    /// Export metadata for all assets in the export queue, writing JSON files
    /// alongside each image.  Updates `batchCompleted`, `batchTotal`, and
    /// `currentProcessingFile` so `BatchProgressView` can observe live progress.
    func batchExportJSON(to directory: URL) async throws {
        let queue = assets.filter(\.isInExportQueue)
        guard !queue.isEmpty else { return }

        batchTotal     = queue.count
        batchCompleted = 0
        isBatchRunning = true
        isBatchCancelled = false
        defer {
            isBatchRunning        = false
            currentProcessingFile = ""
        }

        for asset in queue {
            if isBatchCancelled { break }

            currentProcessingFile = asset.fileName

            guard let meta = asset.metadata else {
                batchCompleted += 1
                continue
            }
            let dict   = meta.asDictionary()
            let data   = try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
            let outURL = directory
                .appendingPathComponent(asset.url.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("json")
            try data.write(to: outURL)

            batchCompleted += 1
        }
    }

    /// Request cancellation of the currently-running batch operation.
    func cancelBatch() {
        isBatchCancelled = true
    }

    // MARK: ─── UNDO / REDO ───────────────────────────────────────────────────

    /// `true` when there is at least one undo entry for the asset.
    func canUndo(for assetID: UUID) -> Bool {
        undoStack[assetID]?.isEmpty == false
    }

    /// Revert to the metadata state before the last write.
    /// Note: calling `undo` itself pushes a new undo entry (the undo action
    /// can also be undone for multi-level history).
    func undo(for asset: ImageAsset) async throws {
        guard let edit = undoStack[asset.id]?.popLast(),
              let previous = edit.beforeMetadata
        else { return }
        try await writeMetadata(previous, to: asset)
        // Remove the entry that `writeMetadata` just pushed (redo not yet supported).
        undoStack[asset.id]?.removeLast()
    }

    // MARK: ─── FAVORITES & EXPORT QUEUE ─────────────────────────────────────

    func toggleFavorite(_ asset: ImageAsset)         { asset.isFavorite.toggle() }
    func addToExportQueue(_ asset: ImageAsset)        { asset.isInExportQueue = true }
    func removeFromExportQueue(_ asset: ImageAsset)   { asset.isInExportQueue = false }

    func batchAddToExportQueue(_ assets: [ImageAsset]) {
        assets.forEach { $0.isInExportQueue = true }
    }

    // MARK: ─── PRIVATE: SUBPROCESS ───────────────────────────────────────────

    /// Run ExifTool as a non-blocking subprocess using `terminationHandler`.
    ///
    /// Stdout is collected via a `Pipe`.  The method suspends the calling
    /// Task (not an OS thread) until the process exits.
    ///
    /// - Parameters:
    ///   - tool:         URL to the ExifTool binary.
    ///   - arguments:    Command-line arguments.
    ///   - expectOutput: When `false`, returns an empty `Data` on success
    ///                   (avoids buffering large outputs when we only care
    ///                   about exit status).
    /// - Returns: Stdout data on success, `nil` on non-zero exit or launch error.
    private func runExifToolProcess(
        tool: URL,
        arguments: [String],
        expectOutput: Bool = true
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = tool
            process.arguments     = arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError  = errPipe

            // terminationHandler fires on a dispatch queue – never blocks a thread.
            process.terminationHandler = { proc in
                guard proc.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                let data = expectOutput
                    ? outPipe.fileHandleForReading.readDataToEndOfFile()
                    : Data()
                continuation.resume(returning: data)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: ─── PRIVATE: JSON PARSING ─────────────────────────────────────────

    /// Map a single ExifTool JSON dictionary to a `MetadataModel`.
    private func parseExifToolDict(_ dict: [String: Any], sourceURL: URL) -> MetadataModel? {
        var m = MetadataModel()
        m.sourceURL = sourceURL

        // Camera hardware
        m.cameraMake           = dict["Make"]       as? String
        m.cameraModel          = dict["Model"]      as? String
        m.lensModel            = dict["LensModel"]  as? String
        m.software             = dict["Software"]   as? String

        // Exposure
        m.iso                  = dict["ISO"]                as? Int
        m.aperture             = dict["FNumber"]            as? Double
        m.shutterSpeed         = dict["ExposureTime"]       as? Double
        m.focalLength          = dict["FocalLength"]        as? Double
        m.focalLengthIn35mm    = dict["FocalLengthIn35mmFormat"] as? Int
        m.exposureCompensation = dict["ExposureCompensation"] as? Double
        m.whiteBalance         = dict["WhiteBalance"]       as? String
        m.flash                = dict["Flash"]              as? String
        m.exposureMode         = dict["ExposureMode"]       as? String
        m.meteringMode         = dict["MeteringMode"]       as? String
        m.exposureProgram      = dict["ExposureProgram"]    as? String
        m.sceneCaptureType     = dict["SceneCaptureType"]   as? String

        // Geometry
        m.imageWidth           = dict["ImageWidth"]   as? Int
        m.imageHeight          = dict["ImageHeight"]  as? Int
        m.colorSpace           = dict["ColorSpace"]   as? String
        m.bitsPerSample        = dict["BitsPerSample"] as? Int
        m.orientation          = dict["Orientation"]  as? Int

        // Dates
        let fmt = DateFormatter.exifFormat
        if let s = dict["DateTimeOriginal"]  as? String { m.dateTimeOriginal  = fmt.date(from: s) }
        if let s = dict["DateTimeDigitized"] as? String { m.dateTimeDigitized = fmt.date(from: s) }
        if let s = dict["ModifyDate"]        as? String { m.dateTimeModified  = fmt.date(from: s) }

        // GPS (ExifTool with -n returns decimal degrees with sign)
        m.gpsLatitude          = dict["GPSLatitude"]    as? Double
        m.gpsLongitude         = dict["GPSLongitude"]   as? Double
        m.gpsAltitude          = dict["GPSAltitude"]    as? Double
        m.gpsSpeed             = dict["GPSSpeed"]       as? Double
        m.gpsDirection         = dict["GPSImgDirection"] as? Double

        // IPTC / XMP editorial
        m.title                = dict["Title"]                          as? String
        m.headline             = dict["Headline"]                       as? String
        m.caption              = (dict["Description"] as? String)
                                 ?? (dict["Caption-Abstract"] as? String)
        m.imageDescription     = dict["ImageDescription"]               as? String
        m.credit               = dict["Credit"]                         as? String
        m.source               = dict["Source"]                         as? String
        m.copyright            = dict["Copyright"]                      as? String
        m.copyrightStatus      = dict["CopyrightStatus"]                as? String
        if let creators = dict["Creator"] as? [String] { m.creator     = creators.first }
        else                                            { m.creator     = dict["Artist"] as? String }
        m.creatorTitle         = dict["By-lineTitle"]                   as? String
        m.keywords             = (dict["Keywords"]  as? [String])
                                 ?? (dict["Subject"] as? [String])
        m.instructions         = dict["SpecialInstructions"]            as? String
        m.rating               = dict["Rating"]                         as? Int
        m.label                = dict["Label"]                          as? String

        // Location
        m.city                 = dict["City"]                                   as? String
        m.state                = dict["Province-State"]                         as? String
        m.country              = dict["Country-PrimaryLocationName"]            as? String
        m.countryCode          = dict["Country-PrimaryLocationCode"]            as? String
        m.location             = dict["Sub-location"]                           as? String

        return m
    }

    // MARK: ─── PRIVATE: UNDO ────────────────────────────────────────────────

    private func pushUndo(assetID: UUID, before: MetadataModel?, after: MetadataModel) {
        var stack = undoStack[assetID] ?? []
        stack.append(MetadataEdit(beforeMetadata: before, afterMetadata: after))
        if stack.count > maxUndoDepth { stack.removeFirst() }
        undoStack[assetID] = stack
    }

    // MARK: ─── PRIVATE: DIRECTORY EXPANSION ─────────────────────────────────

    /// Recursively expand directory URLs to supported image file URLs.
    private func expandToImageFiles(_ urls: [URL]) -> [URL] {
        let supportedExtensions: Set<String> = [
            "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff",
            "gif", "bmp", "webp",
            // RAW formats
            "cr2", "cr3", "nef", "arw", "rw2", "raf", "orf",
            "dng", "pef", "srw", "x3f", "mrw",
        ]
        var result: [URL] = []
        let fm = FileManager.default

        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
                while let child = enumerator?.nextObject() as? URL {
                    if supportedExtensions.contains(child.pathExtension.lowercased()) {
                        result.append(child)
                    }
                }
            } else {
                if supportedExtensions.contains(url.pathExtension.lowercased()) {
                    result.append(url)
                }
            }
        }
        return result
    }

    // MARK: ─── PRIVATE: EXIF CODE → STRING ──────────────────────────────────

    private static func exposureModeName(_ value: Int) -> String {
        switch value {
        case 0: return "Auto"
        case 1: return "Manual"
        case 2: return "Auto bracket"
        default: return "Unknown (\(value))"
        }
    }

    private static func meteringModeName(_ value: Int) -> String {
        switch value {
        case 1: return "Average"
        case 2: return "Center-weighted"
        case 3: return "Spot"
        case 4: return "Multi-spot"
        case 5: return "Multi-segment"
        case 6: return "Partial"
        default: return "Unknown (\(value))"
        }
    }
}

// MARK: - Undo Record

/// Immutable snapshot of a metadata change for undo/redo support.
struct MetadataEdit: Sendable {
    let beforeMetadata: MetadataModel?
    let afterMetadata: MetadataModel
    let date: Date = .now
}

// MARK: - Errors

enum MetadataError: LocalizedError {
    case exifToolNotFound
    case writeFailed(URL)
    case sidecarExportFailed(URL)

    var errorDescription: String? {
        switch self {
        case .exifToolNotFound:
            return "ExifTool binary was not found in the app bundle. " +
                   "Place the binary at Resources/ExifTool/exiftool."
        case .writeFailed(let url):
            return "Failed to write metadata to "\(url.lastPathComponent)"."
        case .sidecarExportFailed(let url):
            return "Failed to export XMP sidecar for "\(url.lastPathComponent)"."
        }
    }
}

// MARK: - DateFormatter

extension DateFormatter {
    /// Shared formatter for EXIF date strings (`"yyyy:MM:dd HH:mm:ss"`).
    static let exifFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
