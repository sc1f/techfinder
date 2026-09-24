import CoreMotion
import Observation
import SwiftUI

/// Tracks how the phone is physically held. The interface stays portrait like the Camera app; icons and
/// labels turn to stay upright.
///
/// Reads gravity from Core Motion rather than `UIDevice.orientation`, which stops updating while the
/// user has Rotation Lock on.
@Observable
final class DeviceOrientation {
    enum Hold: Equatable {
        case portrait
        /// Top of the phone pointing left; the viewer's "up" is the screen's right edge.
        case landscapeLeft
        /// Top of the phone pointing right; the viewer's "up" is the screen's left edge.
        case landscapeRight
    }

    private(set) var hold: Hold = .portrait

    /// Rotation that keeps content upright for the viewer.
    var rotation: Angle {
        switch hold {
        case .portrait: .zero
        case .landscapeLeft: .degrees(90)
        case .landscapeRight: .degrees(-90)
        }
    }

    var isLandscape: Bool { hold != .portrait }

    @ObservationIgnored private let motion = CMMotionManager()
    /// An orientation must be held this long before the interface turns, so passing through 45° doesn't flicker.
    @ObservationIgnored private let settleTime: TimeInterval = 0.2
    @ObservationIgnored private var candidate: Hold?
    @ObservationIgnored private var candidateSince = Date.distantPast

    init() {
        #if DEBUG
        // For screenshots and Simulator testing: `-TFSimulateHold landscapeLeft` (or landscapeRight).
        switch UserDefaults.standard.string(forKey: "TFSimulateHold") {
        case "landscapeLeft": hold = .landscapeLeft; return
        case "landscapeRight": hold = .landscapeRight; return
        default: break
        }
        #endif
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 0.05
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let gravity = data?.gravity else { return }
            self.update(x: gravity.x, y: gravity.y, z: gravity.z)
        }
    }

    deinit {
        motion.stopDeviceMotionUpdates()
    }

    private func update(x: Double, y: Double, z: Double) {
        // Lying flat: keep the last orientation, as the Camera app does.
        guard abs(z) < 0.8 else { return }
        // Require a clear winner so the icons don't flicker around 45°.
        let margin = 0.25
        let next: Hold
        if abs(x) > abs(y) + margin {
            next = x < 0 ? .landscapeLeft : .landscapeRight
        } else if y < 0, abs(y) > abs(x) + margin {
            next = .portrait
        } else {
            return // Upside down or ambiguous.
        }
        guard next != hold else {
            candidate = nil
            return
        }
        if next != candidate {
            candidate = next
            candidateSince = Date()
        } else if Date().timeIntervalSince(candidateSince) >= settleTime {
            candidate = nil
            hold = next
        }
    }
}
