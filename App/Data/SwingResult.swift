import Foundation
import GolfCore
import SwiftData

/// Todo el análisis de un swing: lo que encontró la app y lo que corrigió el usuario.
/// Se guarda entero como JSON dentro de `SwingResult`; las medidas, la nota y el guion no se
/// guardan: salen de aquí al momento (son cálculo puro de GolfCore) y así nunca se desincronizan.
struct SwingAnalysis: Codable, Sendable {
    var videoWidth: Int
    var videoHeight: Int
    /// fps reales del clip y fps a los que se analizó la pose (~120: uno de cada dos a 240).
    var frameRate: Double
    var analysisFrameRate: Double
    /// Instante del impacto (s del clip) y si salió del sonido o del movimiento de las manos.
    var impactTime: Double?
    var impactFromSound: Bool
    /// Pose suavizada de cada fotograma analizado, en orden (los índices de `phases` apuntan aquí).
    var poses: [PoseFrame]
    var phases: SwingPhases
    var handedness: Handedness
    /// Estatura de Ajustes cuando se analizó (cm): con ella se pasan los píxeles a cm.
    var heightCentimeters: Double
    /// Lo del palo: el toque del usuario en la preparación, el seguimiento en el takeaway
    /// y las líneas propuestas (o arrastradas) en la mitad de subida y la transición.
    var clubHeadAtAddress: Point2D?
    var clubHeadAtTakeaway: Point2D?
    var clubLineAtMidBackswing: ClubLine?
    var clubLineAtTransition: ClubLine?
    /// El usuario ya pasó por "Revisa las posiciones" y generó el análisis.
    var reviewed = false
    var notes: [String] = []
    var timings: [StepTiming] = []

    /// La entrada de `SwingMetrics` con todo lo revisado.
    func metricsInput() -> SwingMetricsInput {
        SwingMetricsInput(frames: poses, phases: phases, handedness: handedness,
                          heightCentimeters: heightCentimeters,
                          clubHeadAtAddress: clubHeadAtAddress, clubHeadAtTakeaway: clubHeadAtTakeaway,
                          clubLineAtMidBackswing: clubLineAtMidBackswing, clubLineAtTransition: clubLineAtTransition)
    }

    /// Medidas, nota y guion, recalculados de la pose y las posiciones (rápido: es solo aritmética).
    func measurements() -> SwingMeasurements { SwingMetrics.measure(metricsInput()) }
    func score() -> SwingScore { Scoring.score(measurements()) }
    func script(seed: UInt64 = 0) -> SwingScript { ScriptWriter.write(measurements: measurements(), score: score(), variantSeed: seed) }

    /// Número de fotograma del clip (el que se enseña en pantalla) para un índice del análisis.
    func clipFrameNumber(at index: Int) -> Int {
        guard poses.indices.contains(index) else { return 0 }
        return Int((poses[index].time * frameRate).rounded())
    }

    /// Mueve una posición al índice `index` del análisis y recalcula qué posiciones quedan dudosas
    /// (el orden B < 2 < … < 7 de docs/04).
    mutating func move(_ position: SwingPosition, to index: Int) {
        guard poses.indices.contains(index) else { return }
        let i = position.rawValue - 1
        phases.positions[i].frameIndex = index
        phases.positions[i].time = poses[index].time
        phases.positions[i].usedAlternative = false
        var last = phases.backswingStartFrame
        for k in phases.positions.indices {
            phases.positions[k].isDoubtful = phases.positions[k].frameIndex < last
            last = max(last, phases.positions[k].frameIndex)
        }
    }
}

/// El análisis de swing de un clip, guardado con SwiftData.
@Model
final class SwingResult {
    @Attribute(.unique) var id: UUID
    var clipID: UUID
    var createdAt: Date
    /// `SwingAnalysis` como JSON.
    var analysisData: Data?
    /// Nota total (0 a 100) para enseñarla en Tus vídeos sin decodificar el análisis.
    var scoreTotal: Int?
    /// Vídeo del análisis ya generado (etapa 8): nombre del archivo en la carpeta de clips.
    var videoFileName: String?
    /// Si el vídeo generado es la versión corta.
    var videoIsShort = false

    init(id: UUID = UUID(), clipID: UUID, createdAt: Date = .now) {
        self.id = id
        self.clipID = clipID
        self.createdAt = createdAt
    }

    var analysis: SwingAnalysis? {
        get {
            guard let analysisData else { return nil }
            return try? JSONDecoder().decode(SwingAnalysis.self, from: analysisData)
        }
        set {
            analysisData = newValue.flatMap { try? JSONEncoder().encode($0) }
            if let newValue, newValue.reviewed {
                scoreTotal = newValue.score().total
            }
        }
    }

    var videoURL: URL? { videoFileName.map(MediaStore.url(forFile:)) }
}
