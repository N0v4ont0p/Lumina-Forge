import Foundation

// MARK: - Metadata Model

/// Represents the full EXIF / IPTC / XMP metadata for a single image.
struct MetadataModel: Sendable {

    // MARK: - Camera / Capture Settings

    var cameraModel: String?
    var cameraMake: String?
    var lensModel: String?
    var iso: Int?
    var aperture: Double?          // f-number (e.g. 2.8)
    var shutterSpeed: Double?      // Exposure time in seconds (e.g. 0.004)
    var focalLength: Double?       // In millimetres
    var focalLengthIn35mm: Int?
    var whiteBalance: String?
    var flash: String?
    var exposureMode: String?
    var meteringMode: String?

    // MARK: - Image Geometry

    var imageWidth: Int?
    var imageHeight: Int?
    var orientation: Int?
    var colorSpace: String?
    var bitsPerSample: Int?

    // MARK: - Dates

    var dateTimeOriginal: Date?
    var dateTimeDigitized: Date?
    var dateTimeModified: Date?

    // MARK: - GPS

    var gpsLatitude: Double?
    var gpsLongitude: Double?
    var gpsAltitude: Double?

    // MARK: - IPTC / XMP

    var title: String?
    var imageDescription: String?
    var copyright: String?
    var creator: String?
    var keywords: [String]?
    var rating: Int?
    var subject: [String]?

    // MARK: - Formatted Helpers

    var formattedAperture: String {
        guard let aperture else { return "—" }
        return String(format: "f/%.1f", aperture)
    }

    var formattedShutterSpeed: String {
        guard let shutter = shutterSpeed else { return "—" }
        if shutter >= 1 {
            return String(format: "%.0fs", shutter)
        }
        let denominator = Int((1.0 / shutter).rounded())
        return "1/\(denominator)s"
    }

    var formattedFocalLength: String {
        guard let focal = focalLength else { return "—" }
        if let equiv = focalLengthIn35mm {
            return String(format: "%.0fmm (%.0fmm eq.)", focal, Double(equiv))
        }
        return String(format: "%.0fmm", focal)
    }

    // MARK: - Dictionary Representation (for export)

    func asDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["CameraModel"]      = cameraModel
        dict["CameraMake"]       = cameraMake
        dict["LensModel"]        = lensModel
        dict["ISO"]              = iso
        dict["Aperture"]         = aperture
        dict["ShutterSpeed"]     = shutterSpeed
        dict["FocalLength"]      = focalLength
        dict["WhiteBalance"]     = whiteBalance
        dict["Flash"]            = flash
        dict["ImageWidth"]       = imageWidth
        dict["ImageHeight"]      = imageHeight
        dict["DateTimeOriginal"] = dateTimeOriginal?.ISO8601Format()
        dict["GPSLatitude"]      = gpsLatitude
        dict["GPSLongitude"]     = gpsLongitude
        dict["Title"]            = title
        dict["Description"]      = imageDescription
        dict["Copyright"]        = copyright
        dict["Creator"]          = creator
        dict["Keywords"]         = keywords
        dict["Rating"]           = rating
        return dict.compactMapValues { $0 }
    }
}
