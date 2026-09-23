import Foundation

/// A taking lens on the technical camera.
public struct Lens: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// Focal length in millimetres.
    public var focalLength: Double

    public init(id: UUID = UUID(), name: String, focalLength: Double) {
        self.id = id
        self.name = name
        self.focalLength = focalLength
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
