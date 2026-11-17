import Foundation

/// Elige el impacto del swing contrastando el sonido con el movimiento de las manos.
///
/// Por qué hace falta (casos reales, 17-11-2026): en una story de Instagram con música, el sonido
/// más fuerte de un clip puede ser un golpe de la canción y no el del palo. Si se le da a
/// `PhaseDetector` ese instante, no encuentra la subida o da posiciones sin sentido.
///
/// Cómo decide: prueba cada candidato del sonido (y, al final, el movimiento solo) y se queda con
/// el que suena más fuerte entre los que dan un swing creíble:
/// - la bajada (del top al impacto) dura décimas de segundo, no segundos;
/// - en el impacto las manos han vuelto abajo: han deshecho buena parte de lo que subieron.
///
/// Se mide en vertical y no con la distancia total a la preparación: justo después del impacto las
/// manos van muy deprisa hacia el objetivo, y un fotograma de más (a 30 fps) o unas centésimas de
/// desfase entre sonido e imagen las alejan mucho en horizontal. Y no basta con "manos cerca de la
/// preparación": tras el final el jugador baja los brazos y vuelven ahí, sin que haya impacto.
///
/// Si el sonido no encaja tal cual, se prueba el punto más bajo de las manos a ±0,1 s de él: en un
/// vídeo editado el audio puede ir desfasado de la imagen.
public enum SwingImpactChooser {
    public struct Choice: Sendable, Equatable {
        public var phases: SwingPhases
        /// Instante del sonido elegido; `nil` si el impacto salió solo del movimiento.
        public var soundTime: Double?
        /// Impacto en la imagen menos instante del sonido (s): 0 si coinciden. Distinto de 0 cuando
        /// el audio va desfasado (una story editada, por ejemplo) y el impacto se ajustó a las manos.
        public var syncOffset: Double = 0
    }

    /// Por qué no se ha reconocido un swing (para decirlo claro en la pantalla).
    public enum Failure: Error, Sendable, Equatable {
        /// No se ven las manos en ningún fotograma.
        case noHands
        /// Se ve al jugador, pero ningún instante da un swing completo (subida, top e impacto).
        case noSwing
    }

    /// En el top, las manos al menos esta fracción de la estatura por encima de la preparación.
    public static let topMinimumRise = 0.15
    /// Duración de la bajada admitida (s). En un swing real ronda 0,25 a 0,45 s; el margen cubre
    /// swings lentos y el desfase de un fotograma o del sonido.
    public static let downswingRange = 0.1...0.6
    /// En el impacto, las manos han bajado al menos esta fracción de lo que subieron hasta el top.
    public static let minimumReturnFraction = 0.6
    /// Desfase máximo entre sonido e imagen que se corrige (s). Caso real: una story de Instagram
    /// con el "clac" 0,09 s después de que las manos llegaran abajo.
    public static let maximumSyncOffset = 0.1

    /// Cuánto bajaron las manos desde el top hasta el impacto, en fracción de la subida;
    /// `nil` si las posiciones no forman un swing creíble.
    static func returnFraction(_ phases: SwingPhases, hands: [Point2D], stature: Double) -> Double? {
        let address = hands[phases[.address].frameIndex]
        let top = hands[phases[.top].frameIndex]
        let impact = hands[phases[.impact].frameIndex]
        let rise = address.y - top.y // y crece hacia abajo
        guard rise >= topMinimumRise * stature, downswingRange.contains(phases.downswingDuration) else { return nil }
        let fraction = (impact.y - top.y) / rise
        return fraction >= minimumReturnFraction ? fraction : nil
    }

    public static func choose(frames: [PoseFrame], soundCandidates: [Impact],
                              handedness: Handedness = .right) -> Result<Choice, Failure> {
        guard let hands = PhaseDetector.completeHands(frames) else { return .failure(.noHands) }
        let stature = PhaseDetector.estimateStature(frames, handedness: handedness)
        guard stature > 0 else { return .failure(.noHands) }

        func credible(at time: Double) -> SwingPhases? {
            guard let phases = PhaseDetector.detect(frames: frames, impactTime: time, handedness: handedness),
                  returnFraction(phases, hands: hands, stature: stature) != nil else { return nil }
            return phases
        }
        let times = frames.map(\.time)

        // De más a menos fuerte: el primero creíble es el palo (en un vídeo normal, el más fuerte).
        for candidate in soundCandidates.sorted(by: { $0.strength > $1.strength }) {
            // Primero el sonido tal cual (con el audio en sincronía, el impacto exacto).
            if let phases = credible(at: candidate.time) {
                return .success(Choice(phases: phases, soundTime: candidate.time))
            }
            // Si no encaja, quizá el audio va desfasado: las manos en su punto más bajo cerca del sonido.
            let near = times.indices.filter { abs(times[$0] - candidate.time) <= maximumSyncOffset }
            if let lowest = near.max(by: { hands[$0].y < hands[$1].y }),
               let phases = credible(at: times[lowest]) {
                return .success(Choice(phases: phases, soundTime: candidate.time,
                                       syncOffset: phases[.impact].time - candidate.time))
            }
        }
        // Ningún sonido encaja: el movimiento solo (manos en su punto más bajo tras el top).
        if let phases = PhaseDetector.detect(frames: frames, impactTime: nil, handedness: handedness),
           returnFraction(phases, hands: hands, stature: stature) != nil {
            return .success(Choice(phases: phases, soundTime: nil))
        }
        return .failure(.noSwing)
    }
}
