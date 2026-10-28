@preconcurrency import AVFoundation
import SwiftUI

/// La imagen de la cámara a pantalla completa. SwiftUI no tiene una vista de cámara, así que se
/// envuelve una vista de UIKit cuya capa es `AVCaptureVideoPreviewLayer` (`UIViewRepresentable`).
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        // Llena la pantalla recortando los lados (el vídeo es 9:16 y la pantalla algo más alta).
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        // La conexión existe cuando la sesión ya tiene la cámara: se pone en vertical en cuanto aparece.
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90),
           connection.videoRotationAngle != 90 {
            connection.videoRotationAngle = 90
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}
