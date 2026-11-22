import Foundation

/// Un bloque del vídeo del análisis, ya colocado en el tiempo.
public struct TimelineBlock: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case script(ScriptBlockKind)
        /// El cierre (marca y fecha), sin narración.
        case closing
    }

    public var kind: Kind
    public var start: Double
    public var duration: Double

    public var end: Double { start + duration }

    public var scriptKind: ScriptBlockKind? {
        if case let .script(kind) = kind { return kind }
        return nil
    }
}

/// Construye la línea de tiempo del vídeo (docs/04, punto 10): la duración de cada bloque es el
/// máximo entre su mínimo visual y su narración más 0,6 s. Así los cambios de bloque caen siempre
/// en los silencios: la voz manda el montaje, como en el vídeo de referencia.
public enum AnalysisTimeline {
    /// Margen tras la narración antes de cambiar de bloque (s).
    public static let narrationTail = 0.6
    /// Duración del cierre (s).
    public static let closingDuration = 2.0

    /// Mínimo visual de cada bloque (docs/04, punto 10).
    public static func minimumDuration(for kind: ScriptBlockKind, swingDuration: Double,
                                       slowMotionFactor: Double) -> Double {
        switch kind {
        case .hook: 3
        case .slowMotion: swingDuration * slowMotionFactor
        case .address, .takeaway, .midBackswing, .top, .transition, .impact, .finish: 2.5
        case .tempo: 4
        case .score: 5
        case .report: 6
        case .improveIntro, .improveSummary: 3
        case .improve1, .improve2, .improve3: 8
        }
    }

    /// Qué bloques lleva el vídeo. La versión corta (docs/04): gancho, cámara lenta a × 0,5,
    /// las 3 fases más importantes para la nota, la nota y el informe con la prioridad.
    /// Las dos versiones terminan con la sección "A mejorar" (el vídeo se reenvía y tiene que entenderse solo);
    /// sus bloques solo suenan si el guion los trae (si no hay fallos con ejercicio, no hay sección).
    public static let improvementKinds: [ScriptBlockKind] = [.improveIntro, .improve1, .improve2, .improve3, .improveSummary]

    public static func blockKinds(short: Bool, importantPhases: [SwingPhase]) -> [ScriptBlockKind] {
        let phaseKinds: [ScriptBlockKind] = [.address, .takeaway, .midBackswing, .top, .transition, .impact, .finish]
        guard short else {
            return [.hook, .slowMotion] + phaseKinds + [.tempo, .score, .report] + improvementKinds
        }
        let chosen = phaseKinds.enumerated().filter { index, _ in
            importantPhases.contains { $0.rawValue == index + 1 }
        }.map(\.element)
        return [.hook, .slowMotion] + chosen.prefix(3) + [.score, .report] + improvementKinds
    }

    /// Las 3 fases que más pesan en la nota (las de la lista "a mejorar" y, si faltan, las más bajas).
    public static func importantPhases(of score: SwingScore) -> [SwingPhase] {
        var phases = score.improvements.map(\.phase).filter { $0 != .tempo }
        for item in score.phases.sorted(by: { ($0.score ?? 10) < ($1.score ?? 10) })
        where !phases.contains(item.phase) && item.phase != .tempo {
            phases.append(item.phase)
        }
        return Array(phases.prefix(3)).sorted()
    }

    /// Coloca los bloques: cada uno dura max(mínimo visual, narración + 0,6 s); al final, el cierre.
    public static func build(kinds: [ScriptBlockKind], narration: [ScriptBlockKind: Double],
                             swingDuration: Double, slowMotionFactor: Double,
                             withClosing: Bool = true) -> [TimelineBlock] {
        var blocks: [TimelineBlock] = []
        var cursor = 0.0
        for kind in kinds {
            let minimum = minimumDuration(for: kind, swingDuration: swingDuration, slowMotionFactor: slowMotionFactor)
            let narrated = narration[kind].map { $0 + narrationTail } ?? 0
            let duration = max(minimum, narrated)
            blocks.append(TimelineBlock(kind: .script(kind), start: cursor, duration: duration))
            cursor += duration
        }
        if withClosing {
            blocks.append(TimelineBlock(kind: .closing, start: cursor, duration: closingDuration))
        }
        return blocks
    }
}
