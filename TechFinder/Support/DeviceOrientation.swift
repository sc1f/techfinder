import Observation
import SwiftUI
import UIKit

/// Tracks how the phone is held. The interface stays portrait like the Camera app; only icons turn.
@Observable
final class DeviceOrientation {
    private(set) var iconRotation: Angle = .zero

    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.update()
        }
        update()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func update() {
        switch UIDevice.current.orientation {
        case .portrait: iconRotation = .zero
        case .landscapeLeft: iconRotation = .degrees(90)
        case .landscapeRight: iconRotation = .degrees(-90)
        default: break // Face up, face down and upside down keep the last rotation.
        }
    }
}
