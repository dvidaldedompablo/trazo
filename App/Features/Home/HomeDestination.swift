import GolfCore
import SwiftUI

/// Las pantallas que se abren desde Inicio. Las que aún no existen se ven como pantalla provisional
/// con su título y la etapa en que llegan (`stage`).
enum HomeDestination: Hashable {
    case library
    case settings
    case pickShotVideo
    case pickSwingVideo
    case help

    var title: String {
        switch self {
        case .library: "Tus vídeos"
        case .settings: "Ajustes"
        case .pickShotVideo: "Elegir vídeo"
        case .pickSwingVideo: "Elegir vídeo de swing"
        case .help: "Ayuda"
        }
    }

    /// Etapa de docs/00_PLAN_Y_PROMPTS.md en la que llega la pantalla completa.
    var stage: Int {
        switch self {
        case .library, .pickShotVideo, .pickSwingVideo: 3
        case .settings, .help: 9
        }
    }

    /// La pantalla de cada destino.
    @MainActor @ViewBuilder
    var screen: some View {
        switch self {
        case .library: LibraryView()
        case .settings: SettingsScreen()
        case .pickShotVideo: ImportScreen(mode: .tracer)
        case .pickSwingVideo: ImportScreen(mode: .swing)
        case .help: PlaceholderScreen(destination: .help)
        }
    }
}

/// Pantalla provisional: el título y en qué etapa llega.
struct PlaceholderScreen: View {
    let destination: HomeDestination

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(destination.title)
                .typeStyle(.tituloPantalla)
                .accessibilityAddTraits(.isHeader)
            Text("Esta pantalla llega en la etapa \(destination.stage).")
                .typeStyle(.sub)
                .opacity(0.8)
            Spacer()
        }
        .foregroundStyle(Color.pino)
        .padding(.horizontal, Spacing.textMargin)
        .padding(.top, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bola)
        .navigationBarTitleDisplayMode(.inline)
    }
}
