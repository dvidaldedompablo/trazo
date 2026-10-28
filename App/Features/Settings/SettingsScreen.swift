import GolfCore
import SwiftUI

/// Ajustes (provisional hasta la etapa 9): la versión instalada y el modo diagnóstico oculto,
/// que se activa o desactiva con 5 toques seguidos en la versión.
struct SettingsScreen: View {
    @AppStorage(SettingsKey.diagnostics) private var diagnostics = false
    @State private var taps: [Date] = []
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Ajustes")
                .typeStyle(.tituloPantalla)
                .foregroundStyle(Color.pino)
                .accessibilityAddTraits(.isHeader)
            Text("Esta pantalla llega en la etapa 9.")
                .typeStyle(.sub)
                .foregroundStyle(Color.pino.opacity(0.8))
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(BuildLabel.version(BuildInfo.version, build: BuildInfo.build))
                Text(BuildInfo.date.map { "Compilada el \(BuildLabel.date($0))" } ?? "Sin fecha de compilación")
            }
            .typeStyle(.sub)
            .foregroundStyle(Color.texto2)
            .padding(.top, Spacing.l)
            .contentShape(Rectangle())
            .onTapGesture(perform: countTap)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Cinco toques activan o desactivan el modo diagnóstico")
            if diagnostics {
                Text("Modo diagnóstico activado: verás los fps, la exposición y el nivel al grabar, y los fps reales y el impacto al abrir un vídeo.")
                    .typeStyle(.nota)
                    .foregroundStyle(Color.texto2)
                    .padding(.top, Spacing.s)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.textMargin)
        .padding(.top, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bola)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { Toast(message: $message) }
        .sensoryFeedback(.success, trigger: diagnostics)
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
