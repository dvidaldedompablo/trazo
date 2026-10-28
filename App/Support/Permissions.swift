@preconcurrency import AVFoundation
import UIKit

/// Permisos de cámara y micrófono. Los textos que enseña iOS al pedirlos están en project.yml
/// (NSCameraUsageDescription y NSMicrophoneUsageDescription), en español.
enum Permissions {
    enum State {
        case granted, denied, notAsked
    }

    static var camera: State { state(for: .video) }
    static var microphone: State { state(for: .audio) }

    /// Pide el permiso si todavía no se ha preguntado y dice si está concedido.
    static func requestCamera() async -> Bool {
        camera == .notAsked ? await AVCaptureDevice.requestAccess(for: .video) : camera == .granted
    }

    static func requestMicrophone() async -> Bool {
        microphone == .notAsked ? await AVCaptureDevice.requestAccess(for: .audio) : microphone == .granted
    }

    /// Abre la página de Trazo en Ajustes de iOS, donde se cambian los permisos.
    @MainActor
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private static func state(for media: AVMediaType) -> State {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }
}
