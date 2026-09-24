import Foundation

/// A taking lens on the technical camera.
public struct Lens: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Focal length in millimetres.
    public var focalLength: Double
    /// Manufacturer image circle figures, e.g. 90 mm at f/11. Empty when unknown.
    public var imageCircle: [ImageCirclePoint]

    public init(id: UUID = UUID(), name: String, focalLength: Double, imageCircle: [ImageCirclePoint] = []) {
        self.id = id
        self.name = name
        self.focalLength = focalLength
        self.imageCircle = imageCircle
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, focalLength, imageCircle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        focalLength = try container.decode(Double.self, forKey: .focalLength)
        // Added later; missing in older libraries.
        imageCircle = try container.decodeIfPresent([ImageCirclePoint].self, forKey: .imageCircle) ?? []
    }

    /// The image circle diameter at an aperture, if the lens has image circle figures.
    public func imageCircle(at fNumber: Double) -> ImageCircleModel.Estimate? {
        ImageCircleModel.diameter(imageCircle, at: fNumber)
    }

    public static let focalLengthRange: ClosedRange<Double> = 1...2000

    public var isValid: Bool {
        Self.focalLengthRange.contains(focalLength)
    }

    /// The name to show, falling back to the focal length when the name is blank.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(focalLengthLabel) mm" : trimmed
    }

    /// Focal length without trailing zeros, e.g. "50" or "23.5".
    public var focalLengthLabel: String {
        Millimetres.label(focalLength)
    }
}

public enum Millimetres {
    /// Formats a millimetre value with at most one decimal and no trailing ".0".
    public static func label(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}
