import CoreMotion
import Foundation
import Observation

/// Nivel del móvil con CoreMotion: cuánto está girado respecto a la vertical.
///
/// La gravedad, vista desde el móvil, apunta "hacia abajo" del móvil cuando está recto: (0, −1, 0).
/// Si lo giras, la gravedad se va hacia un lado (x) y el ángulo es atan2(x, −y).
/// Se lee 20 veces por segundo, que basta para que el indicador se mueva suave.
@MainActor
@Observable
final class LevelMonitor {
    /// Grados de giro (positivo = la parte de arriba hacia la derecha).
    private(set) var roll: Double = 0
    /// Recto con ±1,5° de margen.
    var isLevel: Bool { abs(roll) <= Self.tolerance }

    static let tolerance = 1.5

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var task: Task<Void, Never>?

    func start() {
        guard manager.isDeviceMotionAvailable, task == nil else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 20
        manager.startDeviceMotionUpdates()
        // Se pregunta el último dato en un bucle del hilo principal, en vez de recibir avisos:
        // así no hay que pasar datos entre hilos.
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.read()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        manager.stopDeviceMotionUpdates()
    }

    private func read() {
        guard let gravity = manager.deviceMotion?.gravity else { return }
        roll = atan2(gravity.x, -gravity.y) * 180 / .pi
    }
}
