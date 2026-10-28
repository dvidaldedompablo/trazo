import Foundation
import GolfCore
import SwiftData

/// En qué punto está el tracer de un golpe (lo que se ve en Tus vídeos).
enum TracerStatus: String, Codable {
    /// En la cola, esperando su turno.
    case pending
    /// Creándose ahora.
    case processing
    case ready
    /// Falló, con el motivo en una frase (`TracerResult.failureReason`).
    case failed
}

/// Un toque del usuario sobre la bola y los puntos que salieron al volver a seguirla desde él.
struct Reinforcement: Codable, Sendable, Equatable {
    var tap: TrajectorySample
    var added: [SourcedSample]
}

/// Cuánto tardó un paso (modo diagnóstico).
struct StepTiming: Codable, Sendable, Equatable {
    var name: String
    var seconds: Double
}

/// Todo lo que sale del análisis de un golpe. Se guarda en JSON dentro del `TracerResult`.
struct TracerAnalysis: Codable, Sendable, Equatable {
    var outcome: TracerOutcome
    /// Impacto en segundos del clip, de dónde salió y su número de fotograma.
    var impactTime: Double
    var impactSource: ImpactChooser.Source
    var impactFrame: Int
    /// Bola antes del impacto (px del vídeo girado) y si la tocó el usuario.
    var ball: Point2D
    var ballFromTap: Bool
    var videoWidth: Int
    var videoHeight: Int
    var frameRate: Double
    var horizonY: Double?
    /// Puntos del seguimiento automático (Vision y BlobTracker).
    var basePoints: [SourcedSample]
    /// Toques de refuerzo, en orden (como mucho 5).
    var reinforcements: [Reinforcement] = []
    var timings: [StepTiming] = []
    /// Avisos para el modo diagnóstico ("Vision no está disponible en el simulador").
    var notes: [String] = []

    /// Lo que necesita `TracerAssembler` con los puntos automáticos, los de los refuerzos y los toques.
    func assemblerInput(club: ClubCategory = .longIrons, handedness: Handedness = .right) -> TracerInput {
        var points = basePoints
        for reinforcement in reinforcements {
            points += reinforcement.added
            points.append(SourcedSample(reinforcement.tap, source: .tap))
        }
        return TracerInput(ball: ball, imageWidth: Double(videoWidth), imageHeight: Double(videoHeight), points: points,
                           horizonY: horizonY, club: club, handedness: handedness)
    }
}

/// El tracer de un clip de Tus vídeos: su estado en la cola y el resultado del análisis.
@Model
final class TracerResult {
    @Attribute(.unique) var id: UUID
    var clipID: UUID
    var createdAt: Date
    var statusRaw: String
    var failureReason: String?
    /// Falló porque no encontró la bola antes del golpe: al abrirlo se pide el toque.
    var needsBall: Bool
    /// Bola tocada por el usuario (px del vídeo girado) y en qué instante del clip.
    var manualBallX: Double?
    var manualBallY: Double?
    var manualBallTime: Double?
    /// `TracerAnalysis` en JSON.
    var analysisData: Data?

    init(clipID: UUID, createdAt: Date = .now) {
        id = UUID()
        self.clipID = clipID
        self.createdAt = createdAt
        statusRaw = TracerStatus.pending.rawValue
        needsBall = false
    }

    var status: TracerStatus {
        get { TracerStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var analysis: TracerAnalysis? {
        get { analysisData.flatMap { try? JSONDecoder().decode(TracerAnalysis.self, from: $0) } }
        set { analysisData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var manualBall: ManualBall? {
        get {
            guard let x = manualBallX, let y = manualBallY, let time = manualBallTime else { return nil }
            return ManualBall(point: Point2D(x, y), time: time)
        }
        set {
            manualBallX = newValue?.point.x
            manualBallY = newValue?.point.y
            manualBallTime = newValue?.time
        }
    }
}

/// La bola tocada a mano en un fotograma de antes del impacto.
struct ManualBall: Codable, Sendable, Equatable {
    var point: Point2D
    var time: Double
}
