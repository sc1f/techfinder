import AVFoundation
import SwiftUI

/// Shows the live camera image, scaled to fit without cropping so its edges are the camera's true edges.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// Passed in so SwiftUI refreshes the view once the session has a connection to rotate.
    let isRunning: Bool

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.applyPortraitRotation()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyPortraitRotation()
        }

        func applyPortraitRotation() {
            // The interface is portrait-only, so the sensor's landscape image is always turned upright.
            if let connection = previewLayer.connection,
               connection.isVideoRotationAngleSupported(90),
               connection.videoRotationAngle != 90 {
                connection.videoRotationAngle = 90
            }
        }
    }
}
