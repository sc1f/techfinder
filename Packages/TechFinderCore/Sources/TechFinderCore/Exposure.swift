import Foundation

/// The three exposure controls.
public enum ExposureAxis: String, Codable, CaseIterable, Sendable {
    case iso, aperture, shutter
}

/// Third-stop scales for ISO, aperture and shutter speed, with the labels printed on cameras and lenses.
///
/// Each value sits on an index; one index is a third of a stop. Exact values are powers of two so
/// exposure maths stays exact, while labels use the familiar rounded markings.
public enum ExposureScale {
    public static let isoLabels = [
        "6", "8", "10", "12", "16", "20", "25", "32", "40", "50", "64", "80", "100", "125", "160", "200",
        "250", "320", "400", "500", "640", "800", "1000", "1250", "1600", "2000", "2500", "3200", "4000",
        "5000", "6400", "8000", "10000", "12800", "16000", "20000", "25600",
    ]
    /// Index of ISO 100.
    static let iso100 = 12

    public static let apertureLabels = [
        "1", "1.1", "1.2", "1.4", "1.6", "1.8", "2", "2.2", "2.5", "2.8", "3.2", "3.5", "4", "4.5", "5", "5.6",
        "6.3", "7.1", "8", "9", "10", "11", "13", "14", "16", "18", "20", "22", "25", "29", "32", "36", "40",
        "45", "51", "57", "64", "72", "80", "90", "101", "114", "128",
    ]

    public static let shutterLabels = [
        "1/8000", "1/6400", "1/5000", "1/4000", "1/3200", "1/2500", "1/2000", "1/1600", "1/1250", "1/1000",
        "1/800", "1/640", "1/500", "1/400", "1/320", "1/250", "1/200", "1/160", "1/125", "1/100", "1/80",
        "1/60", "1/50", "1/40", "1/30", "1/25", "1/20", "1/15", "1/13", "1/10", "1/8", "1/6", "1/5", "1/4",
        "0.3\"", "0.4\"", "0.5\"", "0.6\"", "0.8\"", "1\"", "1.3\"", "1.6\"", "2\"", "2.5\"", "3.2\"", "4\"",
        "5\"", "6\"", "8\"", "10\"", "13\"", "15\"", "20\"", "25\"", "30\"", "40\"", "50\"", "60\"",
        "80\"", "100\"", "2m", "2m40", "3m20", "4m", "5m20", "6m40", "8m",
    ]
    /// Index of one second.
    static let oneSecond = 39

    public static func labels(_ axis: ExposureAxis) -> [String] {
        switch axis {
        case .iso: isoLabels
        case .aperture: apertureLabels
        case .shutter: shutterLabels
        }
    }

    public static func range(_ axis: ExposureAxis) -> ClosedRange<Int> {
        0...(labels(axis).count - 1)
    }

    /// ISO speed.
    public static func iso(_ index: Int) -> Double { 100 * pow(2, Double(index - iso100) / 3) }
    /// f-number.
    public static func aperture(_ index: Int) -> Double { pow(2, Double(index) / 6) }
    /// Exposure time in seconds.
    public static func shutter(_ index: Int) -> Double { pow(2, Double(index - oneSecond) / 3) }

    /// Fractional aperture index for an f-number.
    static func apertureIndex(forFNumber n: Double) -> Double { 6 * log2(n) }
    /// Fractional shutter index for an exposure time.
    static func shutterIndex(forSeconds t: Double) -> Double { Double(oneSecond) + 3 * log2(t) }

    /// Moves an index by `steps` of `thirdsPerStep`. Full-stop steps land on the standard full-stop series
    /// (ISO 100, 200, 400…; f/5.6, 8, 11…; 1/125, 1/250…): from an in-between value the first step goes to
    /// the next full stop in that direction.
    public static func stepped(_ index: Int, by steps: Int, thirdsPerStep: Int, axis: ExposureAxis) -> Int {
        guard steps != 0 else { return index }
        let range = range(axis)
        guard thirdsPerStep == 3 else {
            return min(max(index + steps * thirdsPerStep, range.lowerBound), range.upperBound)
        }
        // Full stops sit on every third index from the anchor (ISO 100, f/1, one second).
        let anchor = axis == .iso ? iso100 : (axis == .shutter ? oneSecond : 0)
        let offset = ((index - anchor) % 3 + 3) % 3
        var result: Int
        if steps > 0 {
            result = index + (offset == 0 ? 3 : 3 - offset) + 3 * (steps - 1)
        } else {
            result = index - (offset == 0 ? 3 : offset) + 3 * (steps + 1)
        }
        return min(max(result, range.lowerBound), range.upperBound)
    }

    /// Whether an index is on the standard full-stop series.
    public static func isFullStop(_ index: Int, axis: ExposureAxis) -> Bool {
        let anchor = axis == .iso ? iso100 : (axis == .shutter ? oneSecond : 0)
        return (index - anchor) % 3 == 0
    }

    public static func label(_ axis: ExposureAxis, _ index: Int) -> String {
        let labels = labels(axis)
        let text = labels[min(max(index, 0), labels.count - 1)]
        return axis == .aperture ? "f/\(text)" : text
    }
}

/// The photographer's exposure: ISO is always set by hand, and so is either the aperture or the shutter;
/// the meter gives the other.
public struct ExposureSettings: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        /// Aperture is set; shutter follows the meter.
        case aperturePriority
        /// Shutter is set; aperture follows the meter.
        case shutterPriority
    }

    public var isoIndex: Int
    public var apertureIndex: Int
    public var shutterIndex: Int
    public var mode: Mode

    public init(isoIndex: Int, apertureIndex: Int, shutterIndex: Int, mode: Mode) {
        self.isoIndex = isoIndex
        self.apertureIndex = apertureIndex
        self.shutterIndex = shutterIndex
        self.mode = mode
    }

    private enum CodingKeys: String, CodingKey {
        case isoIndex, apertureIndex, shutterIndex, mode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isoIndex = try container.decode(Int.self, forKey: .isoIndex)
        apertureIndex = try container.decode(Int.self, forKey: .apertureIndex)
        shutterIndex = try container.decode(Int.self, forKey: .shutterIndex)
        // Earlier versions had a manual mode; it becomes aperture priority.
        let raw = try container.decodeIfPresent(String.self, forKey: .mode)
        mode = raw.flatMap(Mode.init(rawValue:)) ?? .aperturePriority
    }

    /// ISO 100, f/8, 1/125, aperture priority.
    public static let `default` = ExposureSettings(isoIndex: 12, apertureIndex: 18, shutterIndex: 18, mode: .aperturePriority)

    /// The axis the meter sets.
    public var meteredAxis: ExposureAxis {
        mode == .aperturePriority ? .shutter : .aperture
    }

    /// The axis set by hand besides ISO.
    public var lockedAxis: ExposureAxis {
        mode == .aperturePriority ? .aperture : .shutter
    }

    /// Moves one axis along its scale by `steps`, each `thirdsPerStep` thirds of a stop, starting from what
    /// is shown in `solution`. Positive steps go up the scale's index (higher ISO, higher f-number, longer
    /// shutter). Moving the metered value makes it the one set by hand, and the meter then gives the other.
    public mutating func step(_ axis: ExposureAxis, by steps: Int, thirdsPerStep: Int = 1, from solution: ExposureSolution) {
        let index = ExposureScale.stepped(solution.index(axis), by: steps, thirdsPerStep: thirdsPerStep, axis: axis)
        set(axis, to: index)
    }

    /// Sets one axis to a scale index. Setting the metered value makes it the one set by hand.
    public mutating func set(_ axis: ExposureAxis, to index: Int) {
        let range = ExposureScale.range(axis)
        let index = min(max(index, range.lowerBound), range.upperBound)
        switch axis {
        case .iso:
            isoIndex = index
        case .aperture:
            apertureIndex = index
            mode = .aperturePriority
        case .shutter:
            shutterIndex = index
            mode = .shutterPriority
        }
    }

    /// Holds aperture or shutter at its current value and lets the other follow the meter.
    public mutating func lock(_ axis: ExposureAxis, from solution: ExposureSolution) {
        apertureIndex = solution.apertureIndex
        shutterIndex = solution.shutterIndex
        switch axis {
        case .aperture: mode = .aperturePriority
        case .shutter: mode = .shutterPriority
        case .iso: break
        }
    }
}

/// The photographer's equipment limits. Values outside them are shown as warnings, not prevented.
public struct ExposureLimits: Codable, Equatable, Sendable {
    public var iso: ClosedRange<Int>
    /// Widest (lowest f-number) to smallest aperture.
    public var aperture: ClosedRange<Int>
    /// Fastest to slowest shutter speed.
    public var shutter: ClosedRange<Int>

    public init(iso: ClosedRange<Int>, aperture: ClosedRange<Int>, shutter: ClosedRange<Int>) {
        self.iso = iso
        self.aperture = aperture
        self.shutter = shutter
    }

    /// ISO 50–3200, f/4–f/32, 1/500 s–60 s: typical for a digital back with leaf-shutter lenses.
    public static let `default` = ExposureLimits(iso: 9...27, aperture: 12...30, shutter: 12...57)

    public func range(_ axis: ExposureAxis) -> ClosedRange<Int> {
        switch axis {
        case .iso: iso
        case .aperture: aperture
        case .shutter: shutter
        }
    }

    public mutating func setRange(_ axis: ExposureAxis, _ range: ClosedRange<Int>) {
        switch axis {
        case .iso: iso = range
        case .aperture: aperture = range
        case .shutter: shutter = range
        }
    }
}

/// What to show for the current settings and light reading.
public struct ExposureSolution: Equatable, Sendable {
    public var isoIndex: Int
    public var apertureIndex: Int
    public var shutterIndex: Int
    /// The value set by the meter, or nil when there is no reading yet.
    public var meteredAxis: ExposureAxis?
    /// The metered value fell off the end of its scale.
    public var meteredValueIsOffScale: Bool

    public func index(_ axis: ExposureAxis) -> Int {
        switch axis {
        case .iso: isoIndex
        case .aperture: apertureIndex
        case .shutter: shutterIndex
        }
    }

    public func label(_ axis: ExposureAxis) -> String {
        ExposureScale.label(axis, index(axis))
    }

    public func isOutsideLimits(_ axis: ExposureAxis, _ limits: ExposureLimits) -> Bool {
        (meteredAxis == axis && meteredValueIsOffScale) || !limits.range(axis).contains(index(axis))
    }
}

public enum ExposureSolver {
    /// Exposure value at ISO 100 given by an f-number, exposure time and ISO: EV100 = log2(N²/t) − log2(S/100).
    public static func ev100(fNumber n: Double, seconds t: Double, iso s: Double) -> Double {
        log2(n * n / t) - log2(s / 100)
    }

    public static func ev100(isoIndex: Int, apertureIndex: Int, shutterIndex: Int) -> Double {
        ev100(fNumber: ExposureScale.aperture(apertureIndex), seconds: ExposureScale.shutter(shutterIndex),
              iso: ExposureScale.iso(isoIndex))
    }

    /// Fills in the metered value: the shutter speed or aperture that exposes correctly for the light.
    ///
    /// - Parameters:
    ///   - meteredEV100: The scene's exposure value at ISO 100 from the light meter, or nil if unknown.
    ///   - compensation: Stops to add to the meter's exposure; positive brightens.
    public static func solve(_ settings: ExposureSettings, meteredEV100: Double?, compensation: Double = 0) -> ExposureSolution {
        var solution = ExposureSolution(isoIndex: settings.isoIndex, apertureIndex: settings.apertureIndex,
                                        shutterIndex: settings.shutterIndex, meteredAxis: nil,
                                        meteredValueIsOffScale: false)
        guard let metered = meteredEV100, metered.isFinite else { return solution }

        let target = metered - compensation
        let iso = ExposureScale.iso(settings.isoIndex)
        switch settings.mode {
        case .aperturePriority:
            // t = N² · 100 / (S · 2^EV)
            let n = ExposureScale.aperture(settings.apertureIndex)
            let seconds = n * n * 100 / (iso * pow(2, target))
            let (index, offScale) = snap(ExposureScale.shutterIndex(forSeconds: seconds), .shutter)
            solution.shutterIndex = index
            solution.meteredAxis = .shutter
            solution.meteredValueIsOffScale = offScale
        case .shutterPriority:
            // N² = t · 2^EV · S / 100
            let t = ExposureScale.shutter(settings.shutterIndex)
            let n = (t * pow(2, target) * iso / 100).squareRoot()
            let (index, offScale) = snap(ExposureScale.apertureIndex(forFNumber: n), .aperture)
            solution.apertureIndex = index
            solution.meteredAxis = .aperture
            solution.meteredValueIsOffScale = offScale
        }
        return solution
    }

    private static func snap(_ fractionalIndex: Double, _ axis: ExposureAxis) -> (Int, Bool) {
        let range = ExposureScale.range(axis)
        let rounded = Int(fractionalIndex.rounded())
        let clamped = min(max(rounded, range.lowerBound), range.upperBound)
        return (clamped, clamped != rounded)
    }
}
