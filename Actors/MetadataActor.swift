import Foundation

// MARK: - Metadata Actor

/// Thread-safe actor responsible for reading, writing, and caching
/// image metadata using ExifTool.
@Observable
actor MetadataActor {

    // MARK: - Published State

    private(set) var assets: [ImageAsset] = []
    private(set) var isLoading = false

    var assetCount: Int { assets.count }

    // MARK: - ExifTool Path

    private var exifToolURL: URL? {
        Bundle.main.url(
            forResource: "exiftool",
            withExtension: nil,
            subdirectory: "ExifTool"
        )
    }

    // MARK: - Load Assets

    func loadAssets(from urls: [URL]) async {
        isLoading = true
        defer { isLoading = false }

        for url in urls {
            guard !assets.contains(where: { $0.url == url }) else { continue }
            let asset = ImageAsset(url: url)
            assets.append(asset)
            asset.metadata = await readMetadata(for: url)
        }
    }

    // MARK: - Toggle Favorite

    func toggleFavorite(_ asset: ImageAsset) {
        asset.isFavorite.toggle()
    }

    // MARK: - Export Queue

    func addToExportQueue(_ asset: ImageAsset) {
        asset.isInExportQueue = true
    }

    func removeFromExportQueue(_ asset: ImageAsset) {
        asset.isInExportQueue = false
    }

    // MARK: - Read Metadata via ExifTool

    func readMetadata(for url: URL) async -> MetadataModel? {
        guard let exifTool = exifToolURL else {
            // ExifTool binary not bundled yet; return nil gracefully
            return nil
        }

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = exifTool
            process.arguments = [
                "-json",
                "-n",          // Numeric output for aperture, shutter, etc.
                "-EXIF:All",
                "-IPTC:All",
                "-XMP:All",
                url.path(percentEncoded: false)
            ]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let metadata = parseExifToolJSON(data)
                continuation.resume(returning: metadata)
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Write Metadata via ExifTool

    func writeMetadata(_ metadata: MetadataModel, to url: URL) async throws {
        guard let exifTool = exifToolURL else {
            throw MetadataError.exifToolNotFound
        }

        var arguments: [String] = ["-overwrite_original"]

        if let title = metadata.title {
            arguments += ["-Title=\(title)", "-XMP:Title=\(title)"]
        }
        if let description = metadata.imageDescription {
            arguments += ["-Description=\(description)", "-XMP:Description=\(description)"]
        }
        if let copyright = metadata.copyright {
            arguments += ["-Copyright=\(copyright)", "-XMP:Rights=\(copyright)"]
        }
        if let creator = metadata.creator {
            arguments += ["-Artist=\(creator)", "-XMP:Creator=\(creator)"]
        }
        if let keywords = metadata.keywords {
            for keyword in keywords {
                arguments += ["-Keywords+=\(keyword)"]
            }
        }

        arguments.append(url.path(percentEncoded: false))

        let process = Process()
        process.executableURL = exifTool
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw MetadataError.writeFailed(url)
        }
    }

    // MARK: - JSON Parsing

    private func parseExifToolJSON(_ data: Data) -> MetadataModel? {
        guard
            let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let dict = array.first
        else { return nil }

        var model = MetadataModel()

        model.cameraModel     = dict["Model"] as? String
        model.cameraMake      = dict["Make"] as? String
        model.lensModel       = dict["LensModel"] as? String
        model.iso             = dict["ISO"] as? Int
        model.aperture        = dict["FNumber"] as? Double
        model.shutterSpeed    = dict["ExposureTime"] as? Double
        model.focalLength     = dict["FocalLength"] as? Double
        model.focalLengthIn35mm = dict["FocalLengthIn35mmFormat"] as? Int
        model.whiteBalance    = dict["WhiteBalance"] as? String
        model.flash           = dict["Flash"] as? String
        model.imageWidth      = dict["ImageWidth"] as? Int
        model.imageHeight     = dict["ImageHeight"] as? Int
        model.colorSpace      = dict["ColorSpace"] as? String

        if let dateStr = dict["DateTimeOriginal"] as? String {
            model.dateTimeOriginal = parseExifDate(dateStr)
        }

        model.gpsLatitude     = dict["GPSLatitude"] as? Double
        model.gpsLongitude    = dict["GPSLongitude"] as? Double
        model.gpsAltitude     = dict["GPSAltitude"] as? Double

        model.title           = dict["Title"] as? String
        model.imageDescription = dict["Description"] as? String
        model.copyright       = dict["Copyright"] as? String
        if let creators = dict["Creator"] as? [String] {
            model.creator = creators.first
        } else {
            model.creator = dict["Artist"] as? String
        }
        model.keywords        = dict["Keywords"] as? [String]
        model.rating          = dict["Rating"] as? Int

        return model
    }

    private func parseExifDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: string)
    }
}

// MARK: - Metadata Errors

enum MetadataError: LocalizedError {
    case exifToolNotFound
    case writeFailed(URL)

    var errorDescription: String? {
        switch self {
        case .exifToolNotFound:
            return "ExifTool binary was not found in the app bundle."
        case .writeFailed(let url):
            return "Failed to write metadata to \(url.lastPathComponent)."
        }
    }
}
