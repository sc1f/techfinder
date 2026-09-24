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
    /// The spot meter's exposure value at ISO 100, smoothed. Nil until the first reading.
    private(set) var meteredEV: Double?
    /// Most of the metered spot is clipped white, so the reading is too dark.
    private(set) var meterIsClipped = false

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "TechFinder.camera")
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var isConfigured = false
    /// Last zoom asked for; applied once the device exists if it was requested earlier.
    @ObservationIgnored private var requestedZoom: Double = 1
    @ObservationIgnored private var appliedZoom: Double?
    @ObservationIgnored private var runtimeErrorObserver: NSObjectProtocol?
    private let meterOutput = AVCaptureVideoDataOutput()
    private let spotMeter = SpotMeter()
    private let meterQueue = DispatchQueue(label: "TechFinder.meter", qos: .userInitiated)
    /// Last exposure bias applied, to skip redundant updates (session queue).
    @ObservationIgnored private var appliedBias: Float = 0

    deinit {
        if let runtimeErrorObserver {
            NotificationCenter.default.removeObserver(runtimeErrorObserver)
        }
    }

    /// Asks for permission if needed, then configures and starts the session.
    func start() async {
        #if targetEnvironment(simulator)
        // No real camera in the Simulator; skip the permission prompt and show the simulated scene
        // under a bright overcast sky.
        await MainActor.run {
            self.status = .unavailable
            self.meteredEV = 12
        }
        return
        #else
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
        #endif
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

    /// Brightens or darkens the preview relative to the camera's automatic exposure, in stops. Used to
    /// show how the chosen exposure will look.
    func setExposureBias(_ stops: Float) {
        queue.async { [self] in
            guard let device, abs(stops - appliedBias) > 0.05 else { return }
            applyExposureBias(stops, on: device)
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

    private func applyExposureBias(_ stops: Float, on device: AVCaptureDevice) {
        let bias = min(max(stops, device.minExposureTargetBias), device.maxExposureTargetBias)
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(bias, completionHandler: nil)
            device.unlockForConfiguration()
            appliedBias = stops
        } catch {
            // Exposure compensation is a convenience; framing does not depend on it.
        }
    }

    /// Continuous focus and exposure weighted to `point`, so the phone keeps adjusting there as it moves.
    /// The exposure bias is left alone: it shows the chosen exposure and is owned by the light meter.
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
        addSpotMeter(for: device)

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

    // MARK: - Spot meter

    /// Moves or resizes the metered spot (sensor landscape coordinates).
    func setSpot(_ region: SpotMeter.Region) {
        spotMeter.region = region
    }

    /// Feeds video frames to the spot meter (session queue).
    private func addSpotMeter(for device: AVCaptureDevice) {
        // Video HDR tone-maps highlights and shadows differently frame to frame, which would skew readings.
        if device.activeFormat.isVideoHDRSupported, (try? device.lockForConfiguration()) != nil {
            device.automaticallyAdjustsVideoHDREnabled = false
            device.isVideoHDREnabled = false
            device.unlockForConfiguration()
        }

        spotMeter.device = device
        spotMeter.onReading = { [weak self] reading in
            guard let self else { return }
            // Smooth frame-to-frame jitter; publish only changes worth redrawing for.
            let smoothed = self.meteredEV.map { $0 + (reading.ev100 - $0) * 0.4 } ?? reading.ev100
            if self.meteredEV.map({ abs($0 - smoothed) > 0.02 }) ?? true {
                self.meteredEV = smoothed
            }
            if self.meterIsClipped != reading.isClipped {
                self.meterIsClipped = reading.isClipped
            }
        }
        meterOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        meterOutput.alwaysDiscardsLateVideoFrames = true
        meterOutput.setSampleBufferDelegate(spotMeter, queue: meterQueue)
        if session.canAddOutput(meterOutput) {
            session.addOutput(meterOutput)
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
