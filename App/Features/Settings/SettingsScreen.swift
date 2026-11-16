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
    @State private var taps: [Date] = []
    @State private var message: String?

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
