import SwiftUI
import AVFoundation

/// Full-screen camera preview backed by AVCaptureVideoPreviewLayer via Metal.
struct CameraPreviewView: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // Session changes are handled by AVCaptureVideoPreviewLayer automatically
    }
}

// MARK: - PreviewUIView

final class PreviewUIView: UIView {

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds

        // Keep preview orientation in sync with device orientation
        if let connection = previewLayer.connection,
           connection.isVideoRotationAngleSupported(0) {
            let angle = currentVideoRotationAngle()
            connection.videoRotationAngle = angle
        }
    }

    private func currentVideoRotationAngle() -> CGFloat {
        switch UIDevice.current.orientation {
        case .landscapeLeft:  return 0
        case .landscapeRight: return 180
        case .portraitUpsideDown: return 270
        default: return 90 // portrait
        }
    }
}
