import Foundation

/// Bloques del guion, en el orden del vídeo (docs/04, punto 8; docs/08).
public enum ScriptBlockKind: String, Sendable, Codable, CaseIterable {
    case hook, slowMotion
    case address, takeaway, midBackswing, top, transition, impact, finish
    case tempo, score, report
}

/// Un bloque del guion: sus frases, cada una pensada para una llamada a la voz.
public struct ScriptBlock: Sendable, Equatable {
    public var kind: ScriptBlockKind
    public var lines: [String]
}

/// El guion completo.
public struct SwingScript: Sendable, Equatable {
    public var blocks: [ScriptBlock]

    public subscript(kind: ScriptBlockKind) -> ScriptBlock? { blocks.first { $0.kind == kind } }

    /// Todas las frases seguidas.
    public var allLines: [String] { blocks.flatMap(\.lines) }
}

/// Escribe el guion en español a partir de las medidas y la nota (docs/04, punto 8).
///
/// Estilo: frases de 4 a 14 palabras, de tú, una idea por frase. Los números se escriben para que
/// la voz los lea bien: "2,8 a 1", "78 sobre 100", "30 grados". Algunas frases tienen variantes
/// para no repetir siempre lo mismo; `variantSeed` elige cuál (la misma semilla da el mismo guion).
public enum ScriptWriter {
    public static func write(measurements: SwingMeasurements, score: SwingScore, variantSeed: UInt64 = 0) -> SwingScript {
        var rng = SeededRandom(seed: variantSeed)
        func pick(_ options: [String]) -> String { options[Int.random(in: 0..<options.count, using: &rng)] }

        var blocks: [ScriptBlock] = []
        blocks.append(ScriptBlock(kind: .hook, lines: [hook(score)]))
        blocks.append(ScriptBlock(kind: .slowMotion, lines: ["Ahora, a cámara lenta y con líneas: plano, cadera y cabeza."]))

        let phaseBlocks: [(SwingPhase, ScriptBlockKind)] = [
            (.address, .address), (.takeaway, .takeaway), (.midBackswing, .midBackswing), (.top, .top),
            (.transition, .transition), (.impact, .impact), (.finish, .finish),
        ]
        for (phase, kind) in phaseBlocks {
            blocks.append(ScriptBlock(kind: kind, lines: phaseLines(phase, measurements: measurements, score: score, pick: pick)))
        }

        blocks.append(ScriptBlock(kind: .tempo, lines: tempoLines(measurements)))

        if let total = score.total {
            blocks.append(ScriptBlock(kind: .score, lines: ["¿Acertaste? Tu nota: \(total) sobre 100. \(score.label)."]))
        } else {
            blocks.append(ScriptBlock(kind: .score, lines: ["Esta vez no he podido ponerte nota."]))
        }

        if let priority = score.priority {
            blocks.append(ScriptBlock(kind: .report, lines: [
                "Lo primero a trabajar: \(FaultLibrary.fault(priority).focus).",
                "Practícalo con estos ejercicios.",
            ]))
        } else {
            blocks.append(ScriptBlock(kind: .report, lines: [
                "No hay nada urgente que trabajar.",
                "Sigue entrenando con esta misma rutina.",
            ]))
        }
        return SwingScript(blocks: blocks)
    }

    /// Gancho según la nota.
    static func hook(_ score: SwingScore) -> String {
        guard let total = score.total else { return "Vamos a ver este swing paso a paso." }
        switch total {
        case 80...:
            return score.improvements.isEmpty && score.priority == nil
                ? "Muy buen swing. Vamos a verlo paso a paso."
                : "Muy buen swing. Solo hay un detalle. ¿Lo ves?"
        case 70..<80: return "Casi todo encaja, pero hay un detalle. ¿Lo ves?"
        case 60..<70: return "Hay buena base y un par de cosas que cambiar."
        default: return "Vamos a ordenar este swing paso a paso."
        }
    }

    /// Frases de una posición: la del fallo principal si lo hay; si no, la de "bien".
    static func phaseLines(_ phase: SwingPhase, measurements: SwingMeasurements, score: SwingScore,
                           pick: (([String]) -> String)) -> [String] {
        guard let phaseScore = score[phase], phaseScore.score != nil else {
            return ["En esta posición no he podido medir lo suficiente."]
        }
        // Solo se nombra un fallo si alguna medida pasa su umbral de fallo (el que más resta).
        if let fault = phaseScore.faults.first {
            return faultLines(fault, phase: phase, measurements: measurements, score: score)
        }
        return goodLines(phase, measurements: measurements, pick: pick)
    }

    static func goodLines(_ phase: SwingPhase, measurements: SwingMeasurements, pick: (([String]) -> String)) -> [String] {
        switch phase {
        case .address:
            return [pick(["Buena preparación. Postura atlética, rodillas flexionadas y brazos relajados.",
                          "Buena postura de salida: atlética y con los brazos relajados."])]
        case .takeaway:
            return [pick(["El palo arranca recto hacia atrás.",
                          "El takeaway sale recto hacia atrás, sin prisa."])]
        case .midBackswing:
            return ["A mitad de subida, el palo está en su plano."]
        case .top:
            return [pick(["Arriba, compacto y controlado. Manos altas y la cabeza quieta.",
                          "Arriba llegas compacto, con las manos altas y la cabeza quieta."])]
        case .transition:
            // Si se pone algo más vertical sin salirse del margen, se dice tal cual (docs/04).
            if let value = measurements[.transitionClub]?.value, value > 2 {
                return ["Al bajar, el palo se pone más vertical, pero vuelve cerca de su plano."]
            }
            return ["Al bajar, el palo vuelve por su plano."]
        case .impact:
            return [pick(["En el impacto mantienes la postura. Muy bien.",
                          "En el impacto conservas la inclinación. Muy bien."])]
        case .finish:
            return [pick(["Y el final, completo y equilibrado.",
                          "Terminas con un final completo y equilibrado."])]
        case .tempo:
            return tempoLines(measurements)
        }
    }

    /// Frases de un fallo, con sus números.
    static func faultLines(_ fault: FaultID, phase: SwingPhase, measurements: SwingMeasurements, score: SwingScore) -> [String] {
        // Cadena de causa: si este fallo es consecuencia de la prioridad, se dice "Por eso,".
        let isEffect = score.priorityEffect == fault && score.priority == FaultLibrary.cause(of: fault)
        switch fault {
        case .uprightPosture:
            return ["Estás algo erguido. Inclínate un poco más desde la cadera."]
        case .lowPosture:
            return ["Estás demasiado bajo. Sube un poco el pecho y flexiona menos."]
        case .handsFarFromBody:
            return ["Las manos quedan lejos del cuerpo. Deja caer los brazos."]
        case .handsTooClose:
            return ["Las manos van muy pegadas al cuerpo. Deja caer los brazos."]
        case .takeawayInside:
            return ["El palo se va por dentro muy pronto, detrás de las manos."]
        case .takeawayOutside:
            return ["El palo sale hacia fuera, lejos de las manos."]
        case .flatMidBackswing:
            return [isEffect ? "Por eso, a mitad de subida, el palo queda plano."
                             : "A mitad de subida, el palo queda plano."]
        case .steepMidBackswing:
            return [isEffect ? "Por eso, a mitad de subida, el palo queda vertical."
                             : "A mitad de subida, el palo queda muy vertical."]
        case .shortBackswing:
            return ["La subida se queda corta. Gira más la espalda."]
        case .headMovement:
            if phase == .impact, let head = measurements[.headAtImpact] {
                let cm = SpanishFormat.number(head.value ?? 0)
                let direction = (head.reference ?? 0) < 0 ? "sube" : "baja"
                return ["En el impacto la cabeza \(direction) unos \(cm) centímetros."]
            }
            let cm = SpanishFormat.number(measurements[.headAtTop]?.value ?? 0)
            return ["La cabeza se mueve unos \(cm) centímetros. Intenta mantenerla."]
        case .steepDownswing:
            return ["Al bajar, el palo se queda vertical. Déjalo caer por detrás de las manos."]
        case .flatDownswing:
            return ["Al bajar, el palo se queda plano. Bájalo por encima de las manos."]
        case .earlyExtension:
            if let tilt = measurements[.tiltLoss], tilt.fault == .earlyExtension,
               let loss = tilt.value, let atImpact = tilt.reference {
                let a = SpanishFormat.number(atImpact + loss)
                let b = SpanishFormat.number(atImpact)
                return ["En el impacto pierdes inclinación: pasas de \(a) a \(b) grados.",
                        "Intenta quedarte más abajo."]
            }
            return ["En el impacto la cadera se acerca a la bola.",
                    "Mantén la cadera atrás hasta pasar la bola."]
        case .fastTempo, .slowTempo:
            return tempoLines(measurements)
        case .unbalancedFinish:
            return ["Pierdes el equilibrio al terminar. Aguanta el final tres segundos."]
        case .shortFinish:
            return ["El final se queda corto. Termina mirando al objetivo y aguanta tres segundos."]
        }
    }

    /// Bloque del ritmo.
    static func tempoLines(_ measurements: SwingMeasurements) -> [String] {
        guard let tempo = measurements[.tempo], let value = tempo.value else {
            return ["Esta vez no he podido medir tu ritmo."]
        }
        let first = "Tu ritmo es de \(SpanishFormat.spokenRatio(value))."
        switch tempo.fault {
        case .fastTempo?: return [first, "Subes demasiado rápido: tómate más tiempo arriba."]
        case .slowTempo?: return [first, "Subes muy despacio: arranca la bajada sin esperar."]
        default:
            return tempo.status == .good
                ? [first, "Muy cerca del 3 a 1 de los profesionales."]
                : [first, "Cerca del 3 a 1 de los profesionales."]
        }
    }
}
