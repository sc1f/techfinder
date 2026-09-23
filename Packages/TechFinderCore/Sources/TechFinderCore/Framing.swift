import Foundation

/// Optical description of the phone camera feeding the viewfinder.
///
/// Everything is expressed as tangents of half-angles: for a rectilinear lens the image extent on the
/// sensor is proportional to tan(θ/2), so frames can be compared by simple ratios. Digital zoom
/// divides the tangent by the zoom factor.
public struct CameraOptics: Equatable, Sendable {
    /// tan(horizontal field of view / 2) along the image's long side, at zoom factor 1.
    public var tanHalfLong: Double
    /// Long side / short side of the camera image, e.g. 4:3 → 1.333.
    public var aspectRatio: Double
    public var minZoom: Double
    public var maxZoom: Double

    public init(horizontalFieldOfView degrees: Double, aspectRatio: Double, minZoom: Double = 1, maxZoom: Double = 10) {
        self.tanHalfLong = tan(degrees * .pi / 360)
        self.aspectRatio = max(aspectRatio, 1 / aspectRatio)
        self.minZoom = max(minZoom, 1)
        self.maxZoom = max(maxZoom, self.minZoom)
    }

    public var tanHalfShort: Double { tanHalfLong / aspectRatio }

    public var horizontalFieldOfView: Double { atan(tanHalfLong) * 360 / .pi }

    /// A stand-in for devices without a camera (Simulator): an iPhone ultra-wide at 4:3.
    public static let simulated = CameraOptics(horizontalFieldOfView: 108.3, aspectRatio: 4.0 / 3.0, minZoom: 1, maxZoom: 15)
}

/// Where the taking frame sits inside the phone's camera image.
public struct FramingSolution: Equatable, Sendable {
    /// Zoom factor to apply to the phone camera.
    public var zoom: Double
    /// Frame size as a fraction of the camera image along the image's long axis.
    public var longFraction: Double
    /// Frame size as a fraction of the camera image along the image's short axis.
    public var shortFraction: Double

    /// The frame is wider than the phone can see even fully zoomed out, so its edges are cut off.
    public var isClipped: Bool { longFraction > 1.0001 || shortFraction > 1.0001 }
}

public enum Framing {
    public static let defaultFill = 0.85
    public static let fillRange: ClosedRange<Double> = 0.4...1.0

    /// Chooses the phone zoom so the taking frame fills `fill` of the camera image in its tighter
    /// dimension, then reports the frame's size in that zoomed image.
    ///
    /// The format's long side is laid along the camera image's long side: holding the phone in landscape
    /// frames a landscape picture, holding it upright frames a portrait one.
    public static func solve(focalLength: Double, format: CaptureFormat, optics: CameraOptics, fill: Double = defaultFill) -> FramingSolution {
        let fill = min(max(fill, fillRange.lowerBound), fillRange.upperBound)
        let targetLong = format.longSide / (2 * focalLength)
        let targetShort = format.shortSide / (2 * focalLength)

        let idealZoom = min(fill * optics.tanHalfLong / targetLong,
                            fill * optics.tanHalfShort / targetShort)
        let zoom = min(max(idealZoom, optics.minZoom), optics.maxZoom)

        return FramingSolution(
            zoom: zoom,
            longFraction: targetLong / (optics.tanHalfLong / zoom),
            shortFraction: targetShort / (optics.tanHalfShort / zoom)
        )
    }

    /// Angle of view in degrees across `extent` millimetres of the format.
    public static func angleOfView(focalLength: Double, extent: Double) -> Double {
        2 * atan(extent / (2 * focalLength)) * 180 / .pi
    }

    /// The 35mm-format focal length with the same diagonal angle of view.
    public static func equivalentFocalLength(focalLength: Double, format: CaptureFormat) -> Double {
        let fullFrameDiagonal = (36.0 * 36.0 + 24.0 * 24.0).squareRoot()
        return focalLength * fullFrameDiagonal / format.diagonal
    }
}

/// Human-readable angles of view for a lens on a format.
public struct FieldOfView: Equatable, Sendable {
    public var long: Double
    public var short: Double
    public var diagonal: Double
    public var equivalentFocalLength: Double

    public init(focalLength: Double, format: CaptureFormat) {
        long = Framing.angleOfView(focalLength: focalLength, extent: format.longSide)
        short = Framing.angleOfView(focalLength: focalLength, extent: format.shortSide)
        diagonal = Framing.angleOfView(focalLength: focalLength, extent: format.diagonal)
        equivalentFocalLength = Framing.equivalentFocalLength(focalLength: focalLength, format: format)
    }

    /// "72.4° × 58.2°"
    public var anglesLabel: String {
        String(format: "%.1f° × %.1f°", long, short)
    }

    /// "≈ 15 mm FF"
    public var equivalentLabel: String {
        "≈ \(Int(equivalentFocalLength.rounded())) mm FF"
    }
}
