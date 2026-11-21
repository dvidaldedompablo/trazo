import GolfCore
import SwiftUI

/// Ajustes (todavía parcial; se completa en la etapa 9). Ya están los ajustes que usa el análisis
/// de swing: quién eres (mano dominante y estatura) y el vídeo del análisis (voz, duración y
/// subtítulos). El modo diagnóstico sigue oculto: 5 toques seguidos en la versión.
struct SettingsScreen: View {
    @AppStorage(SettingsKey.diagnostics) private var diagnostics = false
    @AppStorage(SettingsKey.handedness) private var handedness = Handedness.right.rawValue
    @AppStorage(SettingsKey.heightCentimeters) private var heightCentimeters = 175.0
    @AppStorage(SettingsKey.shortAnalysisVideo) private var shortVideo = false
    @AppStorage(SettingsKey.analysisSubtitles) private var subtitles = true
    @AppStorage(SettingsKey.geminiAlwaysCheck) private var geminiAlways = true
    @State private var taps: [Date] = []
    @State private var message: String?
    /// La clave de Gemini mientras se escribe; al guardarla va al llavero y aquí se vacía.
    @State private var keyDraft = ""
    @State private var hasKey = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("Ajustes")
                    .typeStyle(.tituloPantalla)
                    .foregroundStyle(Color.pino)
                    .accessibilityAddTraits(.isHeader)

                section("Tú") {
                    HStack {
                        Text("Mano dominante").typeStyle(.etiqueta).foregroundStyle(Color.pino)
                        Spacer()
                        Picker("Mano dominante", selection: $handedness) {
                            Text("Diestro").tag(Handedness.right.rawValue)
                            Text("Zurdo").tag(Handedness.left.rawValue)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    HStack {
                        Text("Estatura").typeStyle(.etiqueta).foregroundStyle(Color.pino)
                        Spacer()
                        Stepper(value: $heightCentimeters, in: 120...220, step: 1) {
                            Text("\(Int(heightCentimeters)) cm")
                                .typeStyle(.valor)
                                .foregroundStyle(Color.pino)
                                .monospacedDigit()
                        }
                        .frame(width: 190)
                    }
                    Text("Con tu estatura, las medidas del swing salen en centímetros aproximados.")
                        .typeStyle(.nota)
                        .foregroundStyle(Color.texto3)
                }

                section("Análisis") {
                    NavigationLink {
                        VoiceSettingsView()
                    } label: {
                        HStack {
                            Text("Voz del análisis").typeStyle(.etiqueta).foregroundStyle(Color.pino)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Color.texto3)
                        }
                    }
                    Toggle(isOn: $shortVideo) {
                        Text("Vídeo corto (30 a 40 s)").typeStyle(.etiqueta).foregroundStyle(Color.pino)
                    }
                    .tint(Color.pino)
                    Toggle(isOn: $subtitles) {
                        Text("Subtítulos en el vídeo").typeStyle(.etiqueta).foregroundStyle(Color.pino)
                    }
                    .tint(Color.pino)
                }

                geminiSection

                Text("El resto de Ajustes (unidades, Mis palos, color del trazo…) llega en la etapa 9.")
                    .typeStyle(.sub)
                    .foregroundStyle(Color.pino.opacity(0.7))

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(BuildLabel.version(BuildInfo.version, build: BuildInfo.build))
                    Text(BuildInfo.date.map { "Compilada el \(BuildLabel.date($0))" } ?? "Sin fecha de compilación")
                }
                .typeStyle(.sub)
                .foregroundStyle(Color.texto2)
                .padding(.top, Spacing.m)
                .contentShape(Rectangle())
                .onTapGesture(perform: countTap)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Cinco toques activan o desactivan el modo diagnóstico")
                if diagnostics {
                    Text("Modo diagnóstico activado: verás los fps, la exposición y el nivel al grabar; los puntos del tracer; y el esqueleto y la tabla de medidas del swing (dos toques en el pie de la revisión).")
                        .typeStyle(.nota)
                        .foregroundStyle(Color.texto2)
                }
            }
            .padding(.horizontal, Spacing.textMargin)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.bola)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { Toast(message: $message) }
        .sensoryFeedback(.success, trigger: diagnostics)
        .onAppear { hasKey = KeychainStore.geminiKey != nil }
    }

    /// La clave de Gemini para el verificador de golpes (docs/10, Fase 4). Va al llavero, nunca se
    /// enseña entera y no sale del iPhone salvo en la cabecera de cada comprobación que aceptes.
    private var geminiSection: some View {
        section("Comprobar golpes con Gemini") {
            if hasKey {
                HStack {
                    Label("Clave guardada en el llavero", systemImage: "key.fill")
                        .typeStyle(.etiqueta)
                        .foregroundStyle(Color.pino)
                    Spacer()
                    Button("Borrar") {
                        KeychainStore.deleteGeminiKey()
                        hasKey = false
                        message = "Clave borrada"
                    }
                    .typeStyle(.etiqueta)
                    .foregroundStyle(Color.texto2)
                }
                Toggle(isOn: $geminiAlways) {
                    Text("Comprobar siempre, sin preguntar").typeStyle(.etiqueta).foregroundStyle(Color.pino)
                }
                .tint(Color.pino)
            } else {
                SecureField("Pega aquí tu clave de Gemini", text: $keyDraft)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .typeStyle(.cuerpo)
                    .padding(Spacing.m)
                    .background(Color.bola, in: RoundedRectangle(cornerRadius: Radius.thumbnailSmall, style: .continuous))
                Button {
                    let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if KeychainStore.saveGeminiKey(key) {
                        hasKey = true
                        message = "Clave guardada"
                    } else {
                        message = "No se ha podido guardar la clave"
                    }
                    keyDraft = ""
                } label: {
                    Text("Guardar la clave")
                }
                .buttonStyle(.principal)
                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Al elegir los golpes de una grabación, Gemini mira los fotogramas de cada sonido fuerte, dice cuáles son golpes y el vídeo se reparte en un clip por golpe. Con \"Comprobar siempre\" las hojas se envían sin preguntarte cada vez; si lo quitas, te pido permiso antes. Solo van hojas de fotogramas: ni el vídeo ni el sonido. Con la clave gratuita de Google AI Studio (aistudio.google.com) no pagas nada; da para unas 20 comprobaciones al día. Sin red o si falla, los golpes salen solo por el sonido, como siempre.")
                .typeStyle(.nota)
                .foregroundStyle(Color.texto3)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(title)
                .typeStyle(.etiqueta)
                .foregroundStyle(Color.texto2)
            content()
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }

    /// Cuenta los toques de los últimos 3 s; al quinto cambia el modo diagnóstico.
    private func countTap() {
        let now = Date.now
        taps = taps.filter { now.timeIntervalSince($0) < 3 } + [now]
        guard taps.count >= 5 else { return }
        taps = []
        diagnostics.toggle()
        message = diagnostics ? "Modo diagnóstico activado" : "Modo diagnóstico desactivado"
    }
}
