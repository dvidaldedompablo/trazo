import Foundation

/// Nota de una fase (o del ritmo) de 0 a 10.
public struct PhaseScore: Sendable, Equatable {
    public var phase: SwingPhase
    /// `nil` si ninguna medida de la fase se pudo calcular: la fase no cuenta en la nota total.
    public var score: Double?
    /// Fallos dichos en la fase, del que más resta al que menos.
    public var faults: [FaultID]
    /// Fallo principal para el informe: el primero de `faults` o, si la fase pierde puntos sin llegar
    /// a ningún umbral de fallo, el del lado por el que más se sale.
    public var mainFault: FaultID?
}

/// Un punto "A mejorar" del informe.
public struct Improvement: Sendable, Equatable {
    public var phase: SwingPhase
    public var score: Double
    public var fault: FaultID
}

/// La nota completa del swing y lo que va en el informe.
public struct SwingScore: Sendable, Equatable {
    public var phases: [PhaseScore]
    /// Nota sobre 100, o `nil` si no se pudo puntuar ninguna fase.
    public var total: Int?
    public var label: String
    /// Fases con 8 o más (hasta 4), de mejor a peor.
    public var strengths: [SwingPhase]
    /// Las 3 notas más bajas por debajo de 7, cada una con su fallo.
    public var improvements: [Improvement]
    /// Prioridad nº 1.
    public var priority: FaultID?
    /// Si la prioridad es la causa de otro fallo, ese otro (su frase empieza por "Por eso,").
    public var priorityEffect: FaultID?

    public subscript(phase: SwingPhase) -> PhaseScore? { phases.first { $0.phase == phase } }
}

/// Notas por fase, nota total, puntos fuertes, a mejorar y prioridad (docs/04, punto 6).
public enum Scoring {
    public static func score(_ measurements: SwingMeasurements) -> SwingScore {
        // Nota de cada fase: 10 menos lo que resta cada medida fuera de rango, con un mínimo de 2.
        let phases = SwingPhase.allCases.map { phase -> PhaseScore in
            let scored = measurements.items.filter {
                $0.phase == phase && $0.status != .unavailable && $0.status != .informative
            }
            guard !scored.isEmpty else { return PhaseScore(phase: phase, score: nil, faults: [], mainFault: nil) }
            let penalty = scored.reduce(0) { $0 + $1.penalty }
            let score = max(10 - penalty, SwingRules.minimumPhaseScore)
            let worstFirst = scored.sorted { $0.penalty > $1.penalty }
            var faults: [FaultID] = []
            for measurement in worstFirst {
                if let fault = measurement.fault, !faults.contains(fault) { faults.append(fault) }
            }
            let fallback = worstFirst.first.flatMap { m -> FaultID? in
                guard m.penalty > 0 else { return nil }
                let rule = SwingRules.rule(for: m.kind)
                return m.status == .low ? rule.lowFault : rule.highFault
            }
            return PhaseScore(phase: phase, score: score, faults: faults, mainFault: faults.first ?? fallback)
        }

        // Nota total = Σ peso × nota / Σ pesos × 10, redondeada. Solo cuentan las fases con nota.
        let scored = phases.compactMap { p in p.score.map { (p.phase, $0) } }
        var total: Int?
        if !scored.isEmpty {
            let weighted = scored.reduce(0) { $0 + SwingRules.weight(of: $1.0) * $1.1 }
            let weights = scored.reduce(0) { $0 + SwingRules.weight(of: $1.0) }
            total = Int((weighted / weights * 10).rounded())
        }

        let strengths = scored
            .filter { $0.1 >= SwingRules.strengthScore }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .prefix(SwingRules.maximumStrengths)
            .map { $0.0 }

        let improvements = phases
            .compactMap { p -> Improvement? in
                guard let score = p.score, score < SwingRules.improvementScore, let fault = p.mainFault else { return nil }
                return Improvement(phase: p.phase, score: score, fault: fault)
            }
            .sorted { $0.score != $1.score ? $0.score < $1.score : $0.phase < $1.phase }
            .prefix(SwingRules.maximumImprovements)

        // Prioridad: el fallo con mayor peso × (10 − nota). Si su causa también aparece, manda la causa.
        let candidates = phases.compactMap { p -> (fault: FaultID, impact: Double)? in
            guard let score = p.score, let fault = p.mainFault else { return nil }
            return (fault, SwingRules.weight(of: p.phase) * (10 - score))
        }
        var priority = candidates.max { $0.impact < $1.impact }?.fault
        var effect: FaultID?
        if let chosen = priority, let cause = FaultLibrary.cause(of: chosen), candidates.contains(where: { $0.fault == cause }) {
            effect = chosen
            priority = cause
        } else if let chosen = priority,
                  let caused = candidates.first(where: { FaultLibrary.cause(of: $0.fault) == chosen })?.fault {
            // La prioridad ya es la causa de otro fallo presente: ese otro empieza por "Por eso,".
            effect = caused
        }

        return SwingScore(phases: phases, total: total,
                          label: total.map(SwingRules.label(forTotal:)) ?? "Sin nota",
                          strengths: Array(strengths), improvements: Array(improvements),
                          priority: priority, priorityEffect: effect)
    }
}
