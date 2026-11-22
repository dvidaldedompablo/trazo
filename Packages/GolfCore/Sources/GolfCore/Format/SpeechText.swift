import Foundation

/// El texto tal como lo lee la voz Kokoro (petición del usuario del 22-11-2026: "sin leer signos de
/// puntuación"), y los instantes aproximados de cada palabra para los subtítulos.
///
/// Kokoro no dice en qué momento suena cada palabra (la voz del iPhone sí lo decía). Se reparte la
/// duración de la frase entre sus palabras según su número de letras: los subtítulos palabra a
/// palabra quedan a unas décimas de la voz, suficiente para seguirla.
public enum SpeechText {
    /// Quita o traduce lo que no se debe leer en voz alta: "~2 cm" → "unos 2 centímetros",
    /// "8°" → "8 grados", "45 %" → "45 por ciento"; fuera comillas, paréntesis y símbolos.
    public static func forSpeech(_ text: String) -> String {
        var t = text
        let replacements: [(String, String)] = [
            ("~", "unos "), ("≈", "unos "), ("%", " por ciento"), ("º", " grados"), ("°", " grados"),
            (" cm", " centímetros"), (" km/h", " kilómetros por hora"), (" m ", " metros "),
            ("×", " por "), ("·", ", "), ("–", ", "), ("—", ", "), (":", "."), (";", "."),
        ]
        for (from, to) in replacements { t = t.replacingOccurrences(of: from, with: to) }
        // Una cifra seguida de "m" al final de frase ("150 m.") también son metros.
        t = t.replacingOccurrences(of: #"(\d) m(\.|,|$)"#, with: "$1 metros$2", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[\"“”«»()\[\]{}*_#/\\|<>]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Instante (s desde el principio de la frase) de cada palabra de `text`, repartiendo `duration`
    /// según las letras de cada palabra (con un pequeño margen al principio y al final, donde la voz
    /// suele dejar silencio). Los rangos son de `text` (lo que se enseña), no del texto hablado.
    public static func estimatedWordTimes(text: String, duration: Double) -> [(range: NSRange, time: Double)] {
        // Palabras: letras o cifras seguidas ("2,8" cuenta como una). Con una expresión regular porque
        // `enumerateSubstrings(.byWords)` no existe en el Foundation de Linux (tests en Docker).
        let ns = text as NSString
        let pattern = try? NSRegularExpression(pattern: #"[\p{L}\p{N}]+(?:[,.'’][\p{N}\p{L}]+)*"#)
        let words: [(range: NSRange, letters: Int)] = (pattern?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? [])
            .map { ($0.range, max($0.range.length, 1)) }
        guard !words.isEmpty, duration > 0 else { return [] }
        let lead = min(0.08, duration * 0.05), tail = min(0.12, duration * 0.08)
        let speaking = max(duration - lead - tail, duration * 0.5)
        // Cada palabra pesa sus letras más una (el hueco entre palabras).
        let total = Double(words.reduce(0) { $0 + $1.letters + 1 })
        var elapsed = 0.0
        return words.map { word in
            let time = lead + speaking * elapsed / total
            elapsed += Double(word.letters + 1)
            return (word.range, time)
        }
    }
}
