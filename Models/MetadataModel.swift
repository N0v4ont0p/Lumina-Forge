import Foundation
import CoreLocation

// MARK: - Metadata Model

/// Value type holding the complete read/write metadata for a single image.
///
/// `MetadataModel` covers three metadata standards:
/// - **EXIF** – camera hardware, exposure, GPS, dates
/// - **IPTC** – editorial fields (title, caption, keywords, copyright, creator,
///              location), written by Lightroom / Photoshop / news agencies
/// - **XMP**  – XML sidecar extension of IPTC; preferred by modern tools
///
/// All properties are `var` so a view can make a local copy, let the user
/// edit it, and pass the mutated value back to `MetadataActor.writeMetadata(_:to:)`.
///
/// `hasUnsavedChanges` must be set to `true` by callers whenever a field is
/// modified, so the UI can show a "modified" indicator and gate the Save button.
struct MetadataModel: Sendable, Equatable {

    // MARK: - Source Tracking

    /// The file URL this metadata was originally read from.
    var sourceURL: URL?

    // MARK: - Camera & Lens

    var cameraMake: String?            // EXIF Make
    var cameraModel: String?           // EXIF Model
    var lensModel: String?             // EXIF LensModel
    var software: String?              // EXIF Software (processing app)

    // MARK: - Exposure

    var iso: Int?                      // EXIF ISOSpeedRatings
    var aperture: Double?              // EXIF FNumber  (f-number, e.g. 2.8)
    var shutterSpeed: Double?          // EXIF ExposureTime (seconds, e.g. 0.004)
    var focalLength: Double?           // EXIF FocalLength (mm)
    var focalLengthIn35mm: Int?        // EXIF FocalLengthIn35mmFilm
    var exposureCompensation: Double?  // EXIF ExposureBiasValue (EV)
    var whiteBalance: String?          // EXIF WhiteBalance
    var flash: String?                 // EXIF Flash
    var exposureMode: String?          // EXIF ExposureMode (human-readable)
    var meteringMode: String?          // EXIF MeteringMode (human-readable)
    var exposureProgram: String?       // EXIF ExposureProgram
    var sceneCaptureType: String?      // EXIF SceneCaptureType

    // MARK: - Image Geometry

    var imageWidth: Int?               // EXIF PixelXDimension
    var imageHeight: Int?              // EXIF PixelYDimension
    var orientation: Int?              // EXIF Orientation (1–8)
    var colorSpace: String?            // EXIF ColorSpace
    var bitsPerSample: Int?            // TIFF BitsPerSample
    var colorProfile: String?          // ICC profile name

    // MARK: - Dates

    var dateTimeOriginal: Date?        // EXIF DateTimeOriginal  (shutter release)
    var dateTimeDigitized: Date?       // EXIF DateTimeDigitized (scan/conversion)
    var dateTimeModified: Date?        // TIFF DateTime          (last file write)

    // MARK: - GPS

    /// Decimal degrees, positive = North.
    var gpsLatitude: Double?
    /// Decimal degrees, positive = East.
    var gpsLongitude: Double?
    /// Metres above (positive) or below (negative) sea level.
    var gpsAltitude: Double?
    var gpsSpeed: Double?              // km/h
    var gpsDirection: Double?          // True bearing 0 – 359.99°
    var gpsTimestamp: Date?            // UTC time embedded in GPS IFD

    // MARK: - IPTC / XMP — Editable by the user

    var title: String?                 // XMP dc:title / IPTC ObjectName
    var headline: String?              // IPTC Headline
    var caption: String?               // XMP dc:description / IPTC Caption-Abstract
    var imageDescription: String?      // EXIF ImageDescription (ASCII, legacy)
    var credit: String?                // IPTC Credit
    var source: String?                // IPTC Source
    var copyright: String?             // XMP dc:rights / IPTC CopyrightNotice
    var copyrightStatus: String?       // XMP xmpRights:Marked ("True" / "False")
    var creator: String?               // XMP dc:creator / IPTC By-line
    var creatorTitle: String?          // IPTC By-lineTitle (job title)
    var keywords: [String]?            // XMP dc:subject / IPTC Keywords
    var subject: [String]?             // XMP dc:subject (alias for keywords in XMP)
    var instructions: String?          // IPTC SpecialInstructions
    var rating: Int?                   // XMP xmp:Rating (0 = no rating, 1–5 stars)
    var label: String?                 // XMP xmp:Label (colour label name)

    // MARK: - Location (IPTC)

    var city: String?
    var state: String?                 // IPTC Province-State
    var country: String?               // IPTC Country-PrimaryLocationName
    var countryCode: String?           // ISO 3166-1 alpha-2 / alpha-3
    var location: String?              // IPTC Sub-location

    // MARK: - Change Tracking

    /// Set to `true` by callers when any editable field is modified.
    /// Reset to `false` after a successful `MetadataActor.writeMetadata` call.
    var hasUnsavedChanges: Bool = false

    // MARK: - GPS Convenience

    /// `CoreLocation` coordinate synthesised from `gpsLatitude`/`gpsLongitude`.
    var coordinate: CLLocationCoordinate2D? {
        get {
            guard let lat = gpsLatitude, let lon = gpsLongitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        set {
            gpsLatitude  = newValue?.latitude
            gpsLongitude = newValue?.longitude
        }
    }

    // MARK: - Formatted Display Helpers

    var formattedAperture: String {
        aperture.map { String(format: "f/%.1f", $0) } ?? "—"
    }

    var formattedShutterSpeed: String {
        guard let s = shutterSpeed else { return "—" }
        if s >= 1 { return String(format: "%.1fs", s) }
        let denominator = Int((1.0 / s).rounded())
        return "1/\(denominator)s"
    }

    var formattedFocalLength: String {
        guard let mm = focalLength else { return "—" }
        if let eq = focalLengthIn35mm {
            return String(format: "%.0fmm (%.0fmm eq.)", mm, Double(eq))
        }
        return String(format: "%.0fmm", mm)
    }

    var formattedISO: String {
        iso.map { "ISO \($0)" } ?? "—"
    }

    var formattedGPS: String {
        guard let lat = gpsLatitude, let lon = gpsLongitude else { return "—" }
        let latDir = lat >= 0 ? "N" : "S"
        let lonDir = lon >= 0 ? "E" : "W"
        return String(format: "%.6f°%@ %.6f°%@", abs(lat), latDir, abs(lon), lonDir)
    }

    // MARK: - Export Dictionary

    /// Flat dictionary for JSON / CSV export.  `nil` values are omitted.
    func asDictionary() -> [String: Any] {
        var d: [String: Any] = [:]
        d["CameraMake"]           = cameraMake
        d["CameraModel"]          = cameraModel
        d["LensModel"]            = lensModel
        d["Software"]             = software
        d["ISO"]                  = iso
        d["Aperture"]             = aperture
        d["ShutterSpeed"]         = shutterSpeed
        d["FocalLength"]          = focalLength
        d["FocalLengthIn35mm"]    = focalLengthIn35mm
        d["ExposureCompensation"] = exposureCompensation
        d["WhiteBalance"]         = whiteBalance
        d["Flash"]                = flash
        d["ExposureMode"]         = exposureMode
        d["MeteringMode"]         = meteringMode
        d["ImageWidth"]           = imageWidth
        d["ImageHeight"]          = imageHeight
        d["ColorSpace"]           = colorSpace
        d["BitsPerSample"]        = bitsPerSample
        d["DateTimeOriginal"]     = dateTimeOriginal?.ISO8601Format()
        d["DateTimeModified"]     = dateTimeModified?.ISO8601Format()
        d["GPSLatitude"]          = gpsLatitude
        d["GPSLongitude"]         = gpsLongitude
        d["GPSAltitude"]          = gpsAltitude
        d["Title"]                = title
        d["Headline"]             = headline
        d["Caption"]              = caption
        d["Credit"]               = credit
        d["Source"]               = source
        d["Copyright"]            = copyright
        d["Creator"]              = creator
        d["Keywords"]             = keywords?.joined(separator: "; ")
        d["Rating"]               = rating
        d["City"]                 = city
        d["State"]                = state
        d["Country"]              = country
        d["CountryCode"]          = countryCode
        d["Location"]             = location
        return d.compactMapValues { $0 }
    }
}
