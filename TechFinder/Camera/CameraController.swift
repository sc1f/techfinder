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
    /// A small blurred copy of the live image for the backdrop behind the controls.
    private(set) var backdrop: CGImage?

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "TechFinder.camera")
    private let backdropOutput = AVCaptureVideoDataOutput()
    private let backdropRenderer = BackdropRenderer()
    private let backdropQueue = DispatchQueue(label: "TechFinder.backdrop", qos: .utility)
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var isConfigured = false
    /// Last zoom asked for; applied once the device exists if it was requested earlier.
    @ObservationIgnored private var requestedZoom: Double = 1
    @ObservationIgnored private var appliedZoom: Double?
    @ObservationIgnored private var runtimeErrorObserver: NSObjectProtocol?

    deinit {
        if let runtimeErrorObserver {
            NotificationCenter.default.removeObserver(runtimeErrorObserver)
        }
    }

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
            let isRunning = session.isRunning
            DispatchQueue.main.async {
                // A runtime error may already have been reported; only claim success if the session came up.
                if isRunning { self.status = .running }
            }
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

    /// Keeps focusing and metering at a point, in device coordinates ((0,0) top-left of the landscape
    /// sensor image), until another point is chosen, the lens changes or `resetFocusAndExposure()`.
    func focusAndMeter(at devicePoint: CGPoint) {
        queue.async { [self] in
            guard let device else { return }
            setFocusAndExposure(on: device, at: devicePoint)
        }
    }

    /// Returns to automatic focus and exposure for the centre of the image.
    func resetFocusAndExposure() {
        queue.async { [self] in
            guard let device else { return }
            setFocusAndExposure(on: device, at: CGPoint(x: 0.5, y: 0.5))
        }
    }

    // MARK: - Configuration (session queue)

    private func applyRequestedZoom() {
        guard let device else { return }
        let factor = min(max(CGFloat(requestedZoom), device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        let isNewFraming = appliedZoom.map { abs($0 - Double(factor)) > 0.001 } ?? true
        do {
            try device.lockForConfiguration()
            if appliedZoom == nil {
                device.videoZoomFactor = factor
            } else {
                // A quick ramp reads as smooth and lets a multi-camera device hand over between lenses mid-move.
                device.ramp(toVideoZoomFactor: factor, withRate: 20)
            }
            device.unlockForConfiguration()
            appliedZoom = Double(factor)
        } catch {
            // Zoom is best effort: the frame is still computed from the requested factor.
        }
        if isNewFraming {
            // A chosen focus point belongs to the previous framing.
            setFocusAndExposure(on: device, at: CGPoint(x: 0.5, y: 0.5))
        }
    }

    /// Continuous focus and exposure weighted to `point`, so the phone keeps adjusting there as it moves.
    private func setFocusAndExposure(on device: AVCaptureDevice, at point: CGPoint) {
        let focusMode: AVCaptureDevice.FocusMode = .continuousAutoFocus
        let exposureMode: AVCaptureDevice.ExposureMode = .continuousAutoExposure
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(focusMode) {
                device.focusPointOfInterest = point
                device.focusMode = focusMode
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(exposureMode) {
                device.exposurePointOfInterest = point
                device.exposureMode = exposureMode
            }
            device.unlockForConfiguration()
        } catch {
            // Focus and metering are conveniences; framing does not depend on them.
        }
    }

    private func configure() {
        #if targetEnvironment(simulator)
        // Recent Simulators expose a placeholder camera that fails on start; use the simulated scene instead.
        let camera: AVCaptureDevice? = nil
        #else
        let camera = Self.bestBackCamera()
        #endif
        guard let device = camera else {
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

        // Frames for the blurred backdrop behind Liquid Glass. Without glass the background stays black.
        if LiquidGlass.isAvailable {
            addBackdropOutput()
        }

        self.device = device
        isConfigured = true

        applyRequestedZoom()

        runtimeErrorObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main
        ) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
            self?.status = .failed(error?.localizedDescription ?? "The camera stopped unexpectedly.")
        }


        let optics = Self.optics(of: device)
        DispatchQueue.main.async { self.optics = optics }
    }

    private func addBackdropOutput() {
        backdropOutput.alwaysDiscardsLateVideoFrames = true
        backdropOutput.setSampleBufferDelegate(backdropRenderer, queue: backdropQueue)
        backdropRenderer.onImage = { [weak self] image in
            self?.backdrop = image
        }
        if session.canAddOutput(backdropOutput) {
            session.addOutput(backdropOutput)
        }
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
