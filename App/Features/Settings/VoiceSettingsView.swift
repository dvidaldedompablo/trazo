import AVFAudio
import SwiftUI

/// Selector de la voz del análisis (docs/00, etapa 7): voces de español de España primero, con su
/// calidad, botón "Probar" y cómo descargar voces mejores. Todo pasa en el iPhone: no hay red.
struct VoiceSettingsView: View {
    @AppStorage(SettingsKey.analysisVoice) private var chosenVoice = ""
    /// El sintetizador vive aquí para que "Probar" no se corte al soltar el botón.
    @State private var sampler = VoiceSampler()

    var body: some View {
        let voices = Self.spanishVoices()
        List {
            Section {
                row(identifier: "", name: "Automática", detail: "La mejor voz de español de España instalada")
            }
            Section("Español de España") {
                ForEach(voices.filter { $0.language == "es-ES" }, id: \.identifier) { voice in
                    row(identifier: voice.identifier, name: voice.name, detail: qualityName(voice.quality))
                }
            }
            Section("Otras voces en español") {
                ForEach(voices.filter { $0.language != "es-ES" }, id: \.identifier) { voice in
                    row(identifier: voice.identifier, name: voice.name,
                        detail: "\(regionName(voice.language)) · \(qualityName(voice.quality))")
                }
            }
            Section {
                Text("Para voces más naturales: Ajustes de iOS → Accesibilidad → Contenido leído → Voces → Español, y descarga una voz mejorada o premium. Aparecerá aquí sola.")
                    .typeStyle(.nota)
                    .foregroundStyle(Color.texto2)
            }
        }
        .navigationTitle("Voz del análisis")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(identifier: String, name: String, detail: String) -> some View {
        HStack {
            Button {
                chosenVoice = identifier
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).typeStyle(.filaTitulo).foregroundStyle(Color.pino)
                        Text(detail).typeStyle(.filaSub).foregroundStyle(Color.texto3)
                    }
                    Spacer()
                    if chosenVoice == identifier {
                        Image(systemName: "checkmark").foregroundStyle(Color.pino).fontWeight(.semibold)
                    }
                }
            }
            Button {
                sampler.play(identifier: identifier)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(Color.pino)
                    .frame(width: Size.minTouch, height: Size.minTouch)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Probar la voz \(name)")
        }
    }

    /// Todas las voces en español, ordenadas: es-ES primero y, dentro, de más a menos calidad.
    static func spanishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("es") }
            .sorted { a, b in
                if (a.language == "es-ES") != (b.language == "es-ES") { return a.language == "es-ES" }
                if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
                return a.name < b.name
            }
    }

    private func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: "Premium"
        case .enhanced: "Mejorada"
        default: "Normal"
        }
    }

    private func regionName(_ language: String) -> String {
        Locale.current.localizedString(forIdentifier: language)?.capitalized ?? language
    }
}

/// Reproduce una frase de muestra con la voz elegida.
@MainActor
@Observable
final class VoiceSampler {
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    func play(identifier: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: "Tu ritmo es de dos coma ocho a uno. Muy cerca del tres a uno de los profesionales.")
        if identifier.isEmpty {
            utterance.voice = VoiceSynthesizer.bestSpanishVoice()
        } else {
            utterance.voice = AVSpeechSynthesisVoice(identifier: identifier)
        }
        utterance.rate = VoiceSynthesizer.rate
        synthesizer.speak(utterance)
    }
}
