import Foundation
import Testing
@testable import GolfCore

struct SpeechTextTests {
    @Test("No se leen signos: medidas y símbolos pasan a palabras")
    func forSpeech() {
        #expect(SpeechText.forSpeech("La cabeza se movió ~2 cm.") == "La cabeza se movió unos 2 centímetros.")
        #expect(SpeechText.forSpeech("Inclinación de 38° (bien).") == "Inclinación de 38 grados bien .")
        #expect(SpeechText.forSpeech("Ritmo: 2,8 a 1") == "Ritmo. 2,8 a 1")
        #expect(SpeechText.forSpeech("Llega a 150 m.") == "Llega a 150 metros.")
        #expect(SpeechText.forSpeech("\"Subes rápido\"") == "Subes rápido")
        #expect(SpeechText.forSpeech("45 %") == "45 por ciento")
    }

    @Test("Instantes de las palabras: en orden, dentro de la frase, y más tiempo para las palabras largas")
    func wordTimes() {
        let text = "Bajas con buen ritmo, enhorabuena."
        let times = SpeechText.estimatedWordTimes(text: text, duration: 2)
        let words = times.map { (text as NSString).substring(with: $0.range) }
        #expect(words == ["Bajas", "con", "buen", "ritmo", "enhorabuena"])
        #expect(zip(times, times.dropFirst()).allSatisfy { $0.time < $1.time })
        #expect(times.first!.time > 0 && times.last!.time < 2)
        // "ritmo" (5 letras) deja más hueco hasta la siguiente que "con" (3).
        let gaps = zip(times, times.dropFirst()).map { $1.time - $0.time }
        #expect(gaps[3] > gaps[1])
        #expect(SpeechText.estimatedWordTimes(text: "", duration: 1).isEmpty)
    }
}
