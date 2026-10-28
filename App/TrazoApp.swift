import SwiftData
import SwiftUI
import UIKit

/// Punto de entrada de la app. `@main` le dice a Swift que la app empieza aquí.
@main
struct TrazoApp: App {
    /// La biblioteca (SwiftData). En las capturas del CI va en memoria y con datos de demostración.
    private let container: ModelContainer
    /// Cola de tracers: procesa los golpes uno detrás de otro.
    @State private var tracerQueue: TracerQueue

    init() {
        if UITestHarness.isActive {
            UITestHarness.prepare()
        }
        container = DataStore.makeContainer(inMemory: UITestHarness.isActive)
        DataStore.seedClubsIfNeeded(in: container.mainContext)
        if UITestHarness.isActive {
            DemoData.populateLibrary(in: container.mainContext)
        }
        // En las capturas no se procesa nada: los estados de demostración se quedan quietos.
        _tracerQueue = State(initialValue: TracerQueue(context: container.mainContext, isEnabled: !UITestHarness.isActive))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(tracerQueue)
        }
        // Todas las vistas de debajo pueden leer y escribir la biblioteca (@Query, modelContext).
        .modelContainer(container)
    }
}

/// Decide qué pantalla se ve al abrir la app.
private struct RootView: View {
    var body: some View {
        // Sin argumento de capturas se abre Inicio.
        let name = UITestHarness.requestedName ?? UITestScreen.home.rawValue
        // UITestScreen(rawValue:) devuelve nil si el nombre no es ninguno de los casos.
        let screen = UITestScreen(rawValue: name)
        content(screen, name: name)
            // Las pantallas de navegación van en modo claro y las de vídeo en oscuro (docs/02).
            // Va aquí, en la raíz, porque la preferencia de más arriba manda sobre las de dentro.
            .preferredColorScheme(screen.map { Self.videoScreens.contains($0) } ?? false ? .dark : .light)
            // En las capturas del CI: avisa al script de que la pantalla ya está abierta.
            .task {
                if UITestHarness.isActive { UITestHarness.markReady() }
            }
    }

    /// Pantallas de vídeo (negras, con la barra de estado clara).
    private static let videoScreens: [UITestScreen] = [.cameraTracer, .cameraSwing, .ballTap, .tracerCheck]

    @ViewBuilder
    private func content(_ screen: UITestScreen?, name: String) -> some View {
        switch screen {
        case .home:
            // Inicio con su pila de navegación; Grabar se abre a pantalla completa por encima.
            HomeRoot()
        case .components:
            ComponentCatalogView()
        case .cameraTracer:
            RecordScreen(mode: .tracer)
        case .cameraSwing:
            RecordScreen(mode: .swing)
        case .library:
            NavigationStack { LibraryView() }
        case .autocut:
            ClipPickerView(pending: DemoData.pendingRecording()) { _, _ in }
        case .autocutVoice:
            ClipPickerView(pending: DemoData.pendingVoiceRecording()) { _, _ in }
        case .processing:
            NavigationStack { TracerProcessingView(clipID: UUID(), demo: DemoData.processingLive()) }
        case .ballTap:
            BallTapView(request: DemoData.ballTapRequest(), demoImage: UIImage(named: "escena_tracer")) { _, _ in }
        case .tracerCheck:
            TracerReviewView(clipID: UUID(), demo: (DemoData.reviewAnalysis(), UIImage(named: "escena_tracer")))
        case nil:
            // Nombre que la app no conoce: se dice en la captura en vez de enseñar otra pantalla.
            Text("Pantalla de prueba desconocida: \(name)")
                .typeStyle(.sub)
                .foregroundStyle(Color.pino)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bola)
        }
    }
}
