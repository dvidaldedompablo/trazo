import Foundation

/// La sección "A mejorar" del final del vídeo (Fase 4 de los cambios del análisis, 22-11-2026):
/// los 3 fallos principales con su ejercicio, para que el vídeo se entienda solo al reenviarlo.
///
/// - Bloque de entrada (unos 3 s): "Tres cosas para mejorar" y los fallos numerados.
/// - Un bloque por fallo (de 8 a 10 s): número y nombre, el clip del ejercicio, "Ejercicio:" con la
///   instrucción y las repeticiones. La voz dice exactamente las mismas palabras que la pantalla.
/// - Bloque final (unos 3 s): "Recuerda" y los mismos fallos.
/// Solo entran fallos que el análisis ha visto y que tienen ejercicio en el catálogo: nunca se inventa
/// un fallo para llegar a tres (si hay dos, salen dos).
public enum ImprovementPlan {
    public static let maximumItems = 3

    /// Un fallo de la sección: su número, su nombre y su ejercicio.
    public struct Item: Sendable, Equatable {
        public let number: Int
        public let exercise: Exercise

        /// Título en pantalla y en la voz: "1. Takeaway por dentro".
        public var title: String { "\(number). \(exercise.fault)" }
        /// "Ejercicio:" y la instrucción, igual en pantalla y en la voz.
        public var instruction: String { exercise.exercise }
        public var repetitions: String { exercise.repetitions }
    }

    /// Los fallos del análisis en orden de importancia: la prioridad, su efecto, los de "a mejorar" y
    /// después el resto de fallos de cada fase, de la fase con peor nota a la mejor.
    public static func rankedFaults(_ score: SwingScore) -> [FaultID] {
        var ranked: [FaultID] = []
        func add(_ fault: FaultID?) {
            if let fault, !ranked.contains(fault) { ranked.append(fault) }
        }
        add(score.priority)
        add(score.priorityEffect)
        score.improvements.sorted { $0.score < $1.score }.forEach { add($0.fault) }
        for phase in score.phases.sorted(by: { ($0.score ?? 10) < ($1.score ?? 10) }) {
            phase.faults.forEach(add)
        }
        return ranked
    }

    /// Hasta 3 fallos con ejercicio medible con la cámara de detrás, sin repetir ejercicio.
    public static func items(_ score: SwingScore, camera: CameraView = .behind) -> [Item] {
        var chosen: [Exercise] = []
        for fault in rankedFaults(score) {
            guard let exercise = ExerciseCatalog.exercises(for: [fault], camera: camera).first,
                  !chosen.contains(exercise) else { continue }
            chosen.append(exercise)
            if chosen.count == maximumItems { break }
        }
        return chosen.enumerated().map { Item(number: $0.offset + 1, exercise: $0.element) }
    }

    /// "Tres cosas para mejorar", "Dos cosas…" o "Una cosa…": título de la entrada y lo que dice la voz.
    public static func introTitle(count: Int) -> String {
        switch count {
        case 1: "Una cosa para mejorar"
        case 2: "Dos cosas para mejorar"
        default: "Tres cosas para mejorar"
        }
    }

    public static let summaryTitle = "Recuerda"

    /// Los bloques del guion de la sección. La voz lee lo mismo que sale en pantalla.
    public static func scriptBlocks(_ score: SwingScore) -> [ScriptBlock] {
        let items = items(score)
        guard !items.isEmpty else { return [] }
        var blocks = [ScriptBlock(kind: .improveIntro, lines: [introTitle(count: items.count) + "."])]
        let kinds: [ScriptBlockKind] = [.improve1, .improve2, .improve3]
        for (item, kind) in zip(items, kinds) {
            // Una frase por oración (pausas naturales); juntas son exactamente el texto de la pantalla.
            let sentences = item.instruction.sentences
            blocks.append(ScriptBlock(kind: kind, lines: [item.title + "."]
                + sentences.enumerated().map { $0.offset == 0 ? "Ejercicio: " + $0.element : $0.element }
                + [item.repetitions + "."]))
        }
        let names = items.map { $0.exercise.fault.lowercasedFirst }
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " y " + names.last!
        blocks.append(ScriptBlock(kind: .improveSummary, lines: ["\(summaryTitle): \(list)."]))
        return blocks
    }
}

extension String {
    /// Las oraciones del texto, cada una con su punto final.
    var sentences: [String] {
        var result: [String] = []
        var current = ""
        for character in self {
            current.append(character)
            if ".!?".contains(character) {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { result.append(trimmed) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { result.append(rest + ".") }
        return result
    }

    /// La primera letra en minúscula, salvo que la palabra sea una sigla o un nombre propio que ya
    /// empiece por mayúscula seguida de otra mayúscula.
    var lowercasedFirst: String {
        guard let first = first else { return self }
        if count > 1, self[index(after: startIndex)].isUppercase { return self }
        return first.lowercased() + dropFirst()
    }
}
