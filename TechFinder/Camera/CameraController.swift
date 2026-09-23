import AVFoundation
import Observation
import TechFinderCore

/// Runs the back camera for the viewfinder and reports its optics so frames can be drawn to scale.
///
/// It prefers a multi-camera virtual device (ultra-wide + wide + tele). At zoom factor 1 such a device
/// shows the ultra-wide view and switches lenses automatically as zoom increases, so one field-of-view
/// figure covers the whole zoom range.
///
/// Capture objects are only touched on `queue`; observable state is only written on the main thread.
@Observable
final class CameraController: @unchecked Sendable {
    enum Status: Equatable {
        case idle
        case running
        case unauthorized
        /// No usable camera, e.g. in the Simulator. The viewfinder shows a simulated scene instead.
        case unavailable
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var optics: CameraOptics = .simulated

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "TechFinder.camera")
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var isConfigured = false
    /// Last zoom asked for; applied once the device exists if it was requested earlier.
    @ObservationIgnored private var requestedZoom: Double = 1

    /// Asks for permission if needed, then configures and starts the session.
    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                await MainActor.run { self.status = .unauthorized }
                return
            }
        default:
            await MainActor.run { self.status = .unauthorized }
            return
        }

        queue.async { [self] in
            if !isConfigured {
                configure()
            }
            guard isConfigured, !session.isRunning else { return }
            session.startRunning()
            DispatchQueue.main.async { self.status = .running }
        }
    }

    func stop() {
        queue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    /// Applies the zoom factor the framing solution asked for.
    func setZoom(_ factor: Double) {
        queue.async { [self] in
            requestedZoom = factor
            applyRequestedZoom()
        }
    }

    // MARK: - Configuration (session queue)

    private func applyRequestedZoom() {
        guard let device else { return }
        let factor = requestedZoom
        do {
            let clamped = min(max(CGFloat(factor), device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            try device.lockForConfiguration()
            device.cancelVideoZoomRamp()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {
            // Zoom is best effort: the frame is still computed from the requested factor.
        }
    }

    private func configure() {
        guard let device = Self.bestBackCamera() else {
            DispatchQueue.main.async { self.status = .unavailable }
            return
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // The 4:3 photo preset uses the full sensor width, so the reported field of view is the true one.
        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                DispatchQueue.main.async { self.status = .failed("The camera input could not be added.") }
                return
            }
            session.addInput(input)
        } catch {
            DispatchQueue.main.async { self.status = .failed(error.localizedDescription) }
            return
        }

        self.device = device
        isConfigured = true
        applyRequestedZoom()

        let optics = Self.optics(of: device)
        DispatchQueue.main.async { self.optics = optics }
    }

    private static func bestBackCamera() -> AVCaptureDevice? {
        let preferred: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera,
        ]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: preferred, mediaType: .video, position: .back)
        for type in preferred {
            if let device = discovery.devices.first(where: { $0.deviceType == type }) {
                return device
            }
        }
        return nil
    }

    private static func optics(of device: AVCaptureDevice) -> CameraOptics {
        let format = device.activeFormat
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let aspect = dimensions.height > 0 ? Double(dimensions.width) / Double(dimensions.height) : 4.0 / 3.0

        // Distortion correction (on by default for ultra-wide) trims the edges slightly.
        var fieldOfView = Double(format.videoFieldOfView)
        if device.isGeometricDistortionCorrectionSupported, device.isGeometricDistortionCorrectionEnabled,
           format.geometricDistortionCorrectedVideoFieldOfView > 0 {
            fieldOfView = Double(format.geometricDistortionCorrectedVideoFieldOfView)
        }

        return CameraOptics(
            horizontalFieldOfView: fieldOfView,
            aspectRatio: aspect,
            minZoom: Double(device.minAvailableVideoZoomFactor),
            maxZoom: Double(device.maxAvailableVideoZoomFactor)
        )
    }
}
