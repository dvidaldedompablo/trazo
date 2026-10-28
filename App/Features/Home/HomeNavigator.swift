import SwiftUI

/// Abrir una pantalla en la navegación de Inicio desde cualquier sitio (por ejemplo, "Creando tu tracer"
/// al importar un golpe). `HomeRoot` lo pone en el entorno; fuera de Inicio (capturas del CI) no hace nada.
struct HomeNavigator: Sendable {
    let open: @MainActor @Sendable (HomeDestination) -> Void

    static let none = HomeNavigator { _ in }
}

extension EnvironmentValues {
    /// Se lee con `@Environment(\.homeNavigator)`.
    @Entry var homeNavigator: HomeNavigator = .none
}
