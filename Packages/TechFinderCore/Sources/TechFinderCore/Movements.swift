import Foundation

// MARK: - Image circle

/// A manufacturer's image circle figure: the diameter covered at an aperture.
public struct ImageCirclePoint: Codable, Hashable, Sendable {
    /// Diameter of the image circle in millimetres.
    public var diameter: Double
    /// The f-number it is quoted at, e.g. 11 or 22.
    public var fNumber: Double

    public init(diameter: Double, fNumber: Double) {
        self.diameter = diameter
        self.fNumber = fNumber
    }
}

/// Works out a lens's image circle at any aperture from one or two manufacturer figures.
///
/// Coverage grows as the lens is stopped down (less mechanical vignetting) by an amount that depends on
/// the design, so there is no general formula:
/// - Two or more figures are interpolated in stops, and held at the nearest figure beyond them.
/// - One figure is used as-is at that aperture and smaller ones; at wider apertures it shrinks by
///   `shrinkPerStop` per stop, marked as an estimate.
public enum ImageCircleModel {
    /// Conservative loss of coverage per stop wider than the widest quoted aperture.
    public static let shrinkPerStop = 0.03
    /// Never shrink an estimate below this share of the quoted figure.
    static let smallestShare = 0.8

    public struct Estimate: Equatable, Sendable {
        public var diameter: Double
        /// True when the aperture is wider than any quoted figure, so the diameter is a guess.
        public var isEstimate: Bool
    }

    public static func diameter(_ points: [ImageCirclePoint], at fNumber: Double) -> Estimate? {
        let points = points.filter { $0.diameter > 0 && $0.fNumber > 0 }.sorted { $0.fNumber < $1.fNumber }
        guard let widest = points.first, let smallest = points.last, fNumber > 0 else { return nil }

        if fNumber < widest.fNumber {
            let stops = 2 * log2(widest.fNumber / fNumber)
            let share = max(1 - shrinkPerStop * stops, smallestShare)
            return Estimate(diameter: widest.diameter * share, isEstimate: true)
        }
        if fNumber >= smallest.fNumber {
            return Estimate(diameter: smallest.diameter, isEstimate: false)
        }
        for (lower, upper) in zip(points, points.dropFirst()) where fNumber <= upper.fNumber {
            let span = log2(upper.fNumber / lower.fNumber)
            let t = span > 0 ? log2(fNumber / lower.fNumber) / span : 0
            return Estimate(diameter: lower.diameter + (upper.diameter - lower.diameter) * t, isEstimate: false)
        }
        return Estimate(diameter: smallest.diameter, isEstimate: false)
    }
}

// MARK: - Movements

/// The two movements of a technical camera back, in the camera's own orientation.
public enum MovementAxis: String, Codable, CaseIterable, Sendable {
    /// Up and down. Positive rises: the frame moves up the scene.
    case rise
    /// Left and right. Positive moves the frame to the right in the scene.
    case shift

    public var title: String {
        switch self {
        case .rise: "Rise/Fall"
        case .shift: "Shift"
        }
    }
}

/// How far the back is moved from the lens axis, in millimetres.
public struct Movement: Codable, Equatable, Sendable {
    public var rise: Double
    public var shift: Double

    public init(rise: Double = 0, shift: Double = 0) {
        self.rise = rise
        self.shift = shift
    }

    public static let zero = Movement()

    public var isZero: Bool { rise == 0 && shift == 0 }

    public subscript(axis: MovementAxis) -> Double {
        get { axis == .rise ? rise : shift }
        set {
            if axis == .rise { rise = newValue } else { shift = newValue }
        }
    }
}

/// The camera's mechanical range of movement, in millimetres either side of centre.
public struct MovementLimits: Codable, Equatable, Sendable {
    public var rise: Double
    public var shift: Double

    public init(rise: Double, shift: Double) {
        self.rise = rise
        self.shift = shift
    }

    /// ±25 mm rise/fall and ±20 mm shift, typical of a technical camera.
    public static let `default` = MovementLimits(rise: 25, shift: 20)
    /// No mechanical limit: only the image circle applies.
    public static let unlimited = MovementLimits(rise: .infinity, shift: .infinity)

    public subscript(axis: MovementAxis) -> Double {
        get { axis == .rise ? rise : shift }
        set {
            if axis == .rise { rise = newValue } else { shift = newValue }
        }
    }
}

/// Where a moved format sits in the lens's image circle.
///
/// Rise/fall runs along the format's long side when the phone is held upright (a portrait frame), and
/// along its short side when held sideways (a landscape frame), because the frame's long side always
/// runs along the phone's long side.
public struct MovementGeometry: Equatable, Sendable {
    /// Half the format's extent along the rise/fall direction.
    public var halfAlongRise: Double
    /// Half the format's extent along the shift direction.
    public var halfAlongShift: Double

    public init(format: CaptureFormat, riseAlongLongSide: Bool) {
        halfAlongRise = (riseAlongLongSide ? format.longSide : format.shortSide) / 2
        halfAlongShift = (riseAlongLongSide ? format.shortSide : format.longSide) / 2
    }

    private func half(_ axis: MovementAxis) -> Double {
        axis == .rise ? halfAlongRise : halfAlongShift
    }

    /// Distance from the lens axis to the frame corner furthest from it.
    public func farthestCorner(_ movement: Movement) -> Double {
        hypot(abs(movement.rise) + halfAlongRise, abs(movement.shift) + halfAlongShift)
    }

    /// Room left between the furthest corner and the edge of an image circle of `diameter`; negative when
    /// a corner is outside it.
    public func margin(_ movement: Movement, imageCircle diameter: Double) -> Double {
        diameter / 2 - farthestCorner(movement)
    }

    /// The largest movement along `axis`, in either direction, that keeps every corner inside the image
    /// circle (if known) and within the camera's mechanical limit, given the other axis's position.
    public func maximum(_ axis: MovementAxis, other: Double, imageCircle diameter: Double?,
                        limits: MovementLimits) -> Double {
        var limit = limits[axis]
        if let diameter {
            let otherAxis: MovementAxis = axis == .rise ? .shift : .rise
            let radius = diameter / 2
            let across = abs(other) + half(otherAxis)
            let room = radius * radius - across * across
            let optical = room > 0 ? room.squareRoot() - half(axis) : 0
            limit = min(limit, max(optical, 0))
        }
        return max(limit, 0)
    }

    /// Sets one axis, stopping at the image circle and the mechanical limits. With an `increment`, the
    /// result lands on that grid (e.g. 0.5 mm), rounding towards zero so it never passes a limit.
    public func moving(_ movement: Movement, _ axis: MovementAxis, to value: Double, imageCircle diameter: Double?,
                       limits: MovementLimits, increment: Double? = nil) -> Movement {
        let other = axis == .rise ? movement.shift : movement.rise
        let maximum = maximum(axis, other: other, imageCircle: diameter, limits: limits)
        var position = min(max(value, -maximum), maximum)
        if let increment, increment > 0 {
            position = (position / increment).rounded(.towardZero) * increment
        }
        var moved = movement
        moved[axis] = position == 0 ? 0 : position // No negative zero.
        return moved
    }
}

// MARK: - Viewfinder layout for movements

/// Everything the viewfinder needs to draw movements, in tangent units on the portrait screen (x to the
/// right, y down, origin at the centre of the camera image). One tangent unit is a millimetre divided by
/// the focal length, so frames and the image circle scale together.
public struct MovementLayout: Equatable, Sendable {
    /// Phone camera zoom that fits the whole image circle (or the full movement range if the circle
    /// isn't known).
    public var zoom: Double
    /// Half the frame's width and height.
    public var frameHalfWidth: Double
    public var frameHalfHeight: Double
    /// Centre of the moved frame.
    public var frameCenterX: Double
    public var frameCenterY: Double
    /// Radius of the image circle, if known.
    public var circleRadius: Double?
    /// Half the width and height of the camera image at `zoom`.
    public var imageHalfWidth: Double
    public var imageHalfHeight: Double
}

public enum MovementPlanner {
    /// Unit screen directions for rise and shift, given how the phone is held. `sideways` is nil when
    /// upright, `true` when the phone's top points left and `false` when it points right.
    public static func screenDirections(sideways turnedLeft: Bool?) -> (rise: (x: Double, y: Double), shift: (x: Double, y: Double)) {
        switch turnedLeft {
        case nil: ((0, -1), (1, 0))
        case true?: ((1, 0), (0, 1))
        case false?: ((-1, 0), (0, -1))
        }
    }

    public static func layout(format: CaptureFormat, focalLength: Double, movement: Movement,
                              imageCircle diameter: Double?, limits: MovementLimits, turnedLeft: Bool?,
                              optics: CameraOptics, fill: Double = 0.92) -> MovementLayout {
        let f = focalLength
        let halfWidth = format.shortSide / 2 / f
        let halfHeight = format.longSide / 2 / f
        let directions = screenDirections(sideways: turnedLeft)
        let centerX = (movement.rise * directions.rise.x + movement.shift * directions.shift.x) / f
        let centerY = (movement.rise * directions.rise.y + movement.shift * directions.shift.y) / f

        // Fit the image circle, or the frame at its furthest possible movement.
        let neededX: Double
        let neededY: Double
        if let diameter {
            neededX = diameter / 2 / f
            neededY = neededX
        } else {
            let riseReach = limits.rise / f
            let shiftReach = limits.shift / f
            neededX = halfWidth + abs(riseReach * directions.rise.x) + abs(shiftReach * directions.shift.x)
            neededY = halfHeight + abs(riseReach * directions.rise.y) + abs(shiftReach * directions.shift.y)
        }
        let ideal = fill * min(optics.tanHalfShort / neededX, optics.tanHalfLong / neededY)
        let zoom = min(max(ideal, optics.minZoom), optics.maxZoom)

        return MovementLayout(zoom: zoom, frameHalfWidth: halfWidth, frameHalfHeight: halfHeight,
                              frameCenterX: centerX, frameCenterY: centerY,
                              circleRadius: diameter.map { $0 / 2 / f },
                              imageHalfWidth: optics.tanHalfShort / zoom, imageHalfHeight: optics.tanHalfLong / zoom)
    }
}
