import Foundation
import OSLog
import UIKit

/// Etapa 10: el envoltorio de los trabajos largos (crear el vídeo del tracer o del análisis).
/// - Pide a iOS unos minutos extra si sales de la app a mitad (`beginBackgroundTask`). Sin esto, la
///   exportación se cortaría al bloquear el iPhone o al entrar una llamada.
/// - Antes de empezar comprueba que queda espacio, y si el iPhone está muy caliente lo dice.
/// - Marca el tiempo con `os_signpost` (se ve en Instruments) y guarda lo que tardó la última vez,
///   que sale en Ajustes con el modo diagnóstico, junto al objetivo de docs/07.
@MainActor
enum BackgroundWork {
    enum Job: String, CaseIterable {
        case tracerVideo = "Vídeo del tracer"
        case analysisVideo = "Vídeo del análisis"

        /// Objetivo de docs/07 (s). El del vídeo del tracer no está en docs/07: se toma el del tracer.
        var targetSeconds: Double {
            switch self {
            case .tracerVideo: 60
            case .analysisVideo: 120
            }
        }
    }

    enum Failure: LocalizedError {
        case noSpace

        var errorDescription: String? {
            switch self {
            case .noSpace: "No queda espacio en el iPhone. Libera al menos 500 MB y vuelve a intentarlo."
            }
        }
    }

    /// Por debajo de esto no se empieza a exportar: el vídeo temporal y el final necesitan sitio.
    static let minimumFreeSpace: Int64 = 500_000_000

    static let signposter = OSSignposter(subsystem: "io.github.dvidaldedompablo.trazo", category: .pointsOfInterest)

    /// Si el iPhone está en estado térmico serio o crítico, una frase para avisar; si no, nil.
    static var heatWarning: String? {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical: "El iPhone está muy caliente: tardará más. Si puedes, déjalo enfriar a la sombra."
        default: nil
        }
    }

    /// Corre `work` con tiempo extra en segundo plano, comprobando el espacio y midiendo cuánto tarda.
    static func run<T>(_ job: Job, _ work: () async throws -> T) async throws -> T {
        if let free = MediaStore.availableCapacity, free < minimumFreeSpace { throw Failure.noSpace }
        let token = TaskToken()
        token.id = UIApplication.shared.beginBackgroundTask(withName: job.rawValue) {
            // iOS avisa de que se acaba el tiempo extra: hay que cerrar la tarea ya. Si la exportación
            // no ha terminado, fallará y la app lo dirá al volver.
            MainActor.assumeIsolated { token.end() }
        }
        let interval = signposter.beginInterval("Trabajo largo", id: signposter.makeSignpostID(), "\(job.rawValue, privacy: .public)")
        let started = ContinuousClock.now
        defer {
            signposter.endInterval("Trabajo largo", interval)
            let elapsed = ContinuousClock.now - started
            record(job, seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
            token.end()
        }
        return try await work()
    }

    /// Lo que tardó cada trabajo la última vez, para el modo diagnóstico.
    static func lastSeconds(_ job: Job) -> Double? {
        let values = UserDefaults.standard.dictionary(forKey: SettingsKey.lastJobSeconds) as? [String: Double]
        return values?[job.rawValue]
    }

    private static func record(_ job: Job, seconds: Double) {
        var values = UserDefaults.standard.dictionary(forKey: SettingsKey.lastJobSeconds) as? [String: Double] ?? [:]
        values[job.rawValue] = seconds
        UserDefaults.standard.set(values, forKey: SettingsKey.lastJobSeconds)
    }

    /// El identificador de la tarea en segundo plano, compartido con el aviso de iOS.
    @MainActor
    private final class TaskToken {
        var id: UIBackgroundTaskIdentifier = .invalid

        func end() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }
}
