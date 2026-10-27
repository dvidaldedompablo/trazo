import SwiftUI

/// Punto de entrada de la app. `@main` le dice a Swift que la app empieza aquí.
@main
struct TrazoApp: App {
    init() {
        if UITestHarness.isActive {
            UITestHarness.prepare()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Las pantallas de navegación van siempre en modo claro (docs/02).
                .preferredColorScheme(.light)
        }
    }
}

/// Decide qué pantalla se ve al abrir la app.
private struct RootView: View {
    var body: some View {
        // Sin argumento de capturas se abre Inicio.
        let name = UITestHarness.requestedName ?? UITestScreen.home.rawValue
        // UITestScreen(rawValue:) devuelve nil si el nombre no es ninguno de los casos.
        switch UITestScreen(rawValue: name) {
        case .home:
            // NavigationStack lleva la pila de pantallas: Inicio abajo y lo que se abra encima.
            NavigationStack {
                HomeView()
            }
        case .components:
            ComponentCatalogView()
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
