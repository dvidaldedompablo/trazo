import GolfCore
import SwiftUI

/// Las pantallas que se abren desde Inicio. Cada una existe de momento como pantalla provisional
/// con su título; se irán construyendo en las etapas que dice `stage`.
enum HomeDestination: Hashable {
    case library
    case settings
    case recordShot
    case pickShotVideo
    case recordSwing
    case pickSwingVideo
    case help

    var title: String {
        switch self {
        case .library: "Tus vídeos"
        case .settings: "Ajustes"
        case .recordShot: "Grabar golpe"
        case .pickShotVideo: "Elegir vídeo"
        case .recordSwing: "Grabar swing"
        case .pickSwingVideo: "Elegir vídeo de swing"
        case .help: "Ayuda"
        }
    }

    /// Etapa de docs/00_PLAN_Y_PROMPTS.md en la que llega la pantalla de verdad.
    var stage: Int {
        switch self {
        case .library, .recordShot, .pickShotVideo, .recordSwing, .pickSwingVideo: 3
        case .settings, .help: 9
        }
    }

    /// Las pantallas de cámara son de vídeo: fondo negro puro (docs/02).
    var isVideoScreen: Bool {
        self == .recordShot || self == .recordSwing
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
            if destination == .settings {
                // Hasta que exista Ajustes, aquí se ve qué compilación tienes instalada.
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(BuildLabel.version(BuildInfo.version, build: BuildInfo.build))
                    Text(BuildInfo.date.map { "Compilada el \(BuildLabel.date($0))" } ?? "Sin fecha de compilación")
                }
                .typeStyle(.sub)
                .foregroundStyle(Color.texto2)
                .padding(.top, Spacing.l)
            }
            Spacer()
        }
        .foregroundStyle(destination.isVideoScreen ? Color.white : Color.pino)
        .padding(.horizontal, Spacing.textMargin)
        .padding(.top, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(destination.isVideoScreen ? Color.escenario : Color.bola)
        .navigationBarTitleDisplayMode(.inline)
        // En las pantallas negras, la flecha de volver va en claro para que se vea.
        .toolbarColorScheme(destination.isVideoScreen ? .dark : .light, for: .navigationBar)
    }
}
