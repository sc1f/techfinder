import AVFoundation
import CoreImage

/// Turns camera frames into a tiny, blurred, upright image for the backdrop behind the controls, so
/// Liquid Glass has live colour and light to refract instead of flat black.
///
/// Runs on its own queue and renders about 8 frames a second at about a hundred pixels wide; the view
/// crossfades between them.
final class BackdropRenderer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Called on the main thread with each new backdrop.
    var onImage: ((CGImage) -> Void)?

    private let context = CIContext(options: [.cacheIntermediates: false, .priorityRequestLow: true])
    private var lastFrameTime = CMTime.zero
    private let interval = CMTime(value: 1, timescale: 8)
    private let outputWidth: CGFloat = 108

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard CMTimeCompare(CMTimeSubtract(time, lastFrameTime), interval) >= 0,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrameTime = time

        // The sensor delivers landscape frames; turn them upright like the portrait preview.
        let upright = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let scale = outputWidth / upright.extent.width
        let small = upright.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = small.extent.integral
        let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: 6).cropped(to: extent)
        guard let image = context.createCGImage(blurred, from: extent) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.onImage?(image)
        }
    }
}
