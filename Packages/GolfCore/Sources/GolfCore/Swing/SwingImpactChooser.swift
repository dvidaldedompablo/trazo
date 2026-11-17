import Foundation

/// Elige el impacto del swing contrastando el sonido con el movimiento de las manos.
///
/// Por qué hace falta (caso real, 17-11-2026): en una story de Instagram con música, el sonido
/// más fuerte de un clip puede ser un golpe de la canción y no el del palo. Si se le da a
/// `PhaseDetector` ese instante, no encuentra la subida y el análisis fallaba con
/// "No se ve a nadie", aunque el jugador se veía perfectamente.
///
/// Cómo decide: prueba cada candidato del sonido (y, al final, el movimiento solo) y se queda
/// con el que da un swing creíble: en el impacto las manos vuelven cerca de donde estaban en la
/// preparación, y en el top estaban claramente más arriba. Entre los que lo cumplen, el que
/// deja las manos más cerca de la preparación; a igualdad, el que suena más fuerte.
public enum SwingImpactChooser {
    public struct Choice: Sendable, Equatable {
        public var phases: SwingPhases
        /// Instante del impacto si salió del sonido; `nil` si salió solo del movimiento.
        public var soundTime: Double?
    }

    /// Por qué no se ha reconocido un swing (para decirlo claro en la pantalla).
    public enum Failure: Error, Sendable, Equatable {
        /// No se ven las manos en ningún fotograma.
        case noHands
        /// Se ve al jugador, pero ningún instante da un swing completo (subida, top e impacto).
        case noSwing
    }

    /// En el impacto, las manos a menos de esta fracción de la estatura de su sitio en la preparación.
    public static let impactNearAddress = 0.15
    /// En el top, las manos al menos esta fracción de la estatura por encima de la preparación.
    public static let topMinimumRise = 0.15

    public static func choose(frames: [PoseFrame], soundCandidates: [Impact],
                              handedness: Handedness = .right) -> Result<Choice, Failure> {
        guard let hands = PhaseDetector.completeHands(frames) else { return .failure(.noHands) }
        let stature = PhaseDetector.estimateStature(frames, handedness: handedness)
        guard stature > 0 else { return .failure(.noHands) }

        /// Lo lejos que quedan las manos de la preparación en el impacto, o `nil` si no es un swing creíble.
        func score(_ phases: SwingPhases) -> Double? {
            let address = hands[phases[.address].frameIndex]
            let top = hands[phases[.top].frameIndex]
            let impact = hands[phases[.impact].frameIndex]
            let back = impact.distance(to: address) / stature
            let rise = (address.y - top.y) / stature // y crece hacia abajo
            guard back <= impactNearAddress, rise >= topMinimumRise else { return nil }
            return back
        }

        var best: (choice: Choice, score: Double)?
        for candidate in soundCandidates.sorted(by: { $0.strength > $1.strength }) {
            guard let phases = PhaseDetector.detect(frames: frames, impactTime: candidate.time, handedness: handedness),
                  let value = score(phases) else { continue }
            // Van de más a menos fuerte: uno más flojo solo gana si es claramente mejor.
            if best == nil || value < best!.score - 0.02 {
                best = (Choice(phases: phases, soundTime: candidate.time), value)
            }
        }
        if let best { return .success(best.choice) }
        // Ningún sonido encaja: el movimiento solo (manos en su punto más bajo tras el top).
        if let phases = PhaseDetector.detect(frames: frames, impactTime: nil, handedness: handedness),
           score(phases) != nil {
            return .success(Choice(phases: phases, soundTime: nil))
        }
        return .failure(.noSwing)
    }
}
