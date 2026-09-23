import Foundation

/// The recording area behind the lens: a digital back's sensor or a film format's image area.
public struct CaptureFormat: Identifiable, Codable, Hashable, Sendable {
    public enum Category: String, Codable, CaseIterable, Sendable {
        case digitalBack
        case mediumFormatFilm
        case largeFormatFilm
        case smallFormat
        case custom

        public var title: String {
            switch self {
            case .digitalBack: "Digital Backs"
            case .mediumFormatFilm: "Medium Format Film"
            case .largeFormatFilm: "Large Format Film"
            case .smallFormat: "Small Format"
            case .custom: "Custom"
            }
        }
    }

    public var id: String
    public var name: String
    /// Long side of the image area in millimetres.
    public private(set) var longSide: Double
    /// Short side of the image area in millimetres.
    public private(set) var shortSide: Double
    public var category: Category

    /// Width and height may be given in either order; they are stored as long and short side.
    public init(id: String, name: String, width: Double, height: Double, category: Category) {
        self.id = id
        self.name = name
        self.longSide = max(width, height)
        self.shortSide = min(width, height)
        self.category = category
    }

    public static func custom(name: String, width: Double, height: Double) -> CaptureFormat {
        CaptureFormat(id: "custom-\(UUID().uuidString)", name: name, width: width, height: height, category: .custom)
    }

    public var isCustom: Bool { category == .custom }

    public static let sideRange: ClosedRange<Double> = 1...600

    public var isValid: Bool {
        Self.sideRange.contains(longSide) && Self.sideRange.contains(shortSide)
    }

    public var diagonal: Double { (longSide * longSide + shortSide * shortSide).squareRoot() }

    /// Long side divided by short side, e.g. 1.335 for 53.4 × 40.0.
    public var aspectRatio: Double { longSide / shortSide }

    /// "53.4 × 40 mm"
    public var dimensionsLabel: String {
        "\(Millimetres.label(longSide)) × \(Millimetres.label(shortSide)) mm"
    }

    /// Updates both sides, keeping the long/short invariant.
    public mutating func setDimensions(width: Double, height: Double) {
        longSide = max(width, height)
        shortSide = min(width, height)
    }
}
