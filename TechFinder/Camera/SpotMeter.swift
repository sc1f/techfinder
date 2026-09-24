import AVFoundation
import os
import TechFinderCore

/// A reflected-light spot meter built on the camera's video frames.
///
/// It averages the linear brightness inside a small circle and turns it into an exposure value at
/// ISO 100 using the exposure the frame was taken with:
///
///     EV100 = log2(N² / t) − log2(ISO / 100) + log2(Y / 0.18)
///
/// so a spot the camera renders as mid-grey (18%) reads exactly the camera's own exposure. Spots that
/// are mostly clipped white read too dark and are flagged.
final class SpotMeter: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Where to meter, in the sensor's landscape image: centre in 0...1 and radius as a share of the
    /// image width and height.
    struct Region: Equatable {
        var center = CGPoint(x: 0.5, y: 0.5)
        var radius = CGSize(width: 0.02, height: 0.027)
    }

    struct Reading {
        var ev100: Double
        /// Most of the spot is at full brightness, so the reading is a lower bound.
        var isClipped: Bool
    }

    /// Called on the main thread with each reading.
    var onReading: ((Reading) -> Void)?
    /// The camera being metered; set once the session is configured.
    weak var device: AVCaptureDevice?

    private let regionLock = OSAllocatedUnfairLock(initialState: Region())
    private var lastSample = CMTime.zero
    private let interval = CMTime(value: 1, timescale: 8)

    var region: Region {
        get { regionLock.withLock { $0 } }
        set { regionLock.withLock { $0 = newValue } }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard CMTimeCompare(CMTimeSubtract(time, lastSample), interval) >= 0,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let device else { return }
        lastSample = time

        guard let (luminance, clippedShare) = averageLinearLuminance(pixelBuffer, region: region) else { return }
        let seconds = CMTimeGetSeconds(device.exposureDuration)
        let iso = Double(device.iso)
        let fNumber = Double((device.activePrimaryConstituent ?? device).lensAperture)
        guard seconds > 0, iso > 0, fNumber > 0, luminance > 0 else { return }

        let ev = ExposureSolver.ev100(fNumber: fNumber, seconds: seconds, iso: iso) + log2(luminance / 0.18)
        guard ev.isFinite else { return }
        let reading = Reading(ev100: ev, isClipped: clippedShare > 0.5)
        DispatchQueue.main.async { [weak self] in self?.onReading?(reading) }
    }

    /// Mean linear luminance (0...1) of the luma plane inside the region's ellipse, and the share of
    /// samples at full brightness. Expects full-range biplanar YCbCr.
    private func averageLinearLuminance(_ buffer: CVPixelBuffer, region: Region) -> (Double, Double)? {
        guard CVPixelBufferGetPlaneCount(buffer) >= 1 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }

        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        let cx = Double(region.center.x) * Double(width)
        let cy = Double(region.center.y) * Double(height)
        let rx = max(Double(region.radius.width) * Double(width), 2)
        let ry = max(Double(region.radius.height) * Double(height), 2)
        // About 40 samples across the spot, whatever its size in pixels.
        let step = max(Int(2 * rx / 40), 1)

        var total = 0.0
        var count = 0
        var clipped = 0
        var y = Int(cy - ry)
        while y <= Int(cy + ry) {
            if y >= 0, y < height {
                var x = Int(cx - rx)
                while x <= Int(cx + rx) {
                    let dx = (Double(x) - cx) / rx
                    let dy = (Double(y) - cy) / ry
                    if x >= 0, x < width, dx * dx + dy * dy <= 1 {
                        let value = Double(pixels[y * rowBytes + x]) / 255
                        total += Self.linear(value)
                        count += 1
                        if value > 0.98 { clipped += 1 }
                    }
                    x += step
                }
            }
            y += step
        }
        guard count > 0 else { return nil }
        return (total / Double(count), Double(clipped) / Double(count))
    }

    /// Undoes the sRGB-style transfer curve applied to camera video.
    private static func linear(_ encoded: Double) -> Double {
        encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
    }
}
