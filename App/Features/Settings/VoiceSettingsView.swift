import AVFAudio
import GolfCore
import SwiftUI

/// Selector de la voz del análisis (docs/00, etapa 7): voces de español de España primero, con su
/// calidad, botón "Probar" y cómo descargar voces mejores. Todo pasa en el iPhone: no hay red.
///
/// Las voces de broma y las Eloquence no salen (suenan a robot a propósito). Lo que de verdad suena
/// natural son las voces "Mejorada" y "Premium", que el usuario descarga en Ajustes de iOS, y su
/// Voz personal, si la ha creado.
struct VoiceSettingsView: View {
    @AppStorage(SettingsKey.analysisVoice) private var chosenVoice = ""
    /// El sintetizador vive aquí para que "Probar" no se corte al soltar el botón.
    @State private var sampler = VoiceSampler()
    /// Se recalcula cuando iOS avisa de que cambian las voces (al descargar una, por ejemplo).
    @State private var voices = VoiceSynthesizer.spanishVoices()
    @State private var personal = VoiceSynthesizer.personalVoices()
    @State private var personalStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus

    var body: some View {
        List {
            // La voz del análisis es Kokoro (Dora, español). Las de iOS de abajo solo se usan si el
            // modelo no estuviera en la app o fallara al cargar.
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dora (Kokoro)").typeStyle(.filaTitulo).foregroundStyle(Color.pino)
                        Text(KokoroEngine.isInstalled ? "Voz natural en español. Funciona sin red." : "No está en esta instalación: se usa la voz de reserva.")
                            .typeStyle(.filaSub).foregroundStyle(Color.texto3)
                    }
                    Spacer()
                    Button {
                        sampler.playKokoro()
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(Color.pino)
                            .frame(width: Size.minTouch, height: Size.minTouch)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Probar la voz Dora")
                }
            } header: {
                Text("Voz del análisis")
            } footer: {
                Text("Las voces de abajo son de reserva: solo se usan si la voz Dora no puede cargarse.")
            }
            if !voices.contains(where: { $0.quality != .default }) {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("Descarga una voz natural").typeStyle(.filaTitulo).foregroundStyle(Color.pino)
                        Text("Las voces que tienes instaladas son las básicas y suenan a máquina. En Ajustes de iOS → Accesibilidad → Contenido leído → Voces → Español (España), descarga una voz con la etiqueta \"Mejorada\" o \"Premium\" (por ejemplo, Mónica o Jorge). Al volver, aparecerá aquí arriba.")
                            .typeStyle(.nota)
                            .foregroundStyle(Color.texto2)
                    }
                    .padding(.vertical, Spacing.xs)
                }
            }
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
            personalSection
        }
        .navigationTitle("Voz del análisis")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            refresh()
        }
    }

    /// Tu propia voz (Voz personal de iOS): la única que suena de verdad a persona, porque es la tuya.
    @ViewBuilder
    private var personalSection: some View {
        Section {
            ForEach(personal, id: \.identifier) { voice in
                row(identifier: voice.identifier, name: voice.name, detail: "Tu voz personal")
            }
            switch personalStatus {
            case .notDetermined:
                Button("Usar mi voz personal") {
                    Task {
                        personalStatus = await AVSpeechSynthesizer.requestPersonalVoiceAuthorization()
                        refresh()
                    }
                }
                .foregroundStyle(Color.pino)
            case .authorized where personal.isEmpty:
                Text("Aún no has creado tu voz personal. Se hace en Ajustes de iOS → Accesibilidad → Voz personal (lees unas frases en voz alta y el iPhone la prepara).")
                    .typeStyle(.nota).foregroundStyle(Color.texto2)
            case .denied:
                Text("No has dado permiso para usar tu voz personal. Puedes darlo en Ajustes de iOS → Trazo.")
                    .typeStyle(.nota).foregroundStyle(Color.texto2)
            case .unsupported:
                Text("Este iPhone no permite usar la voz personal en otras apps.")
                    .typeStyle(.nota).foregroundStyle(Color.texto2)
            default:
                EmptyView()
            }
        } header: {
            Text("Tu voz")
        } footer: {
            Text("La voz personal puede no estar disponible en español en todas las versiones de iOS.")
        }
    }

    private func refresh() {
        voices = VoiceSynthesizer.spanishVoices()
        personal = VoiceSynthesizer.personalVoices()
        personalStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
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

    private func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: "Premium"
        case .enhanced: "Mejorada"
        default: "Básica (suena a máquina)"
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
    @ObservationIgnored private var player: AVAudioPlayer?

    /// La frase de muestra con Kokoro: se sintetiza, se escribe en un archivo temporal y se reproduce.
    func playKokoro() {
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
        Task {
            guard let line = try? await VoiceSynthesizer.render("Tu ritmo es de dos coma ocho a uno. Muy cerca del tres a uno de los profesionales.",
                                                                voiceIdentifier: nil) else { return }
            let track = VoiceTrackBuilder.build(lines: [(.hook, line)])
            let url = URL.temporaryDirectory.appending(path: "muestra-voz.caf")
            try? VoiceTrackBuilder.writeFile(track, to: url)
            player = try? AVAudioPlayer(contentsOf: url)
            player?.play()
        }
    }

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
