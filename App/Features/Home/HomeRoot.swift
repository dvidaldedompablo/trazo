import GolfCore
import SwiftUI

/// Inicio con su pila de navegación (las pantallas claras se apilan encima) y Grabar, que es una
/// pantalla de vídeo y se abre a pantalla completa por encima de todo (`fullScreenCover`).
///
/// Así Grabar tiene su propia presentación con el esquema oscuro (fondo negro y barra de estado
/// clara) sin pelearse con el modo claro de Inicio.
struct HomeRoot: View {
    /// Pantallas apiladas sobre Inicio. Como es un estado propio, Grabar puede pedir que se abra una.
    @State private var path: [HomeDestination] = []
    @State private var recording: RecordRequest?

    var body: some View {
        NavigationStack(path: $path) {
            HomeView { mode in recording = RecordRequest(mode: mode) }
        }
        .fullScreenCover(item: $recording) { request in
            RecordScreen(mode: request.mode) { destination in
                // Desde Grabar se va a otra pantalla: se cierra la cámara y se abre debajo.
                recording = nil
                path.append(destination)
            }
        }
    }
}

/// Petición de abrir Grabar en un modo. `fullScreenCover(item:)` necesita algo `Identifiable`.
struct RecordRequest: Identifiable {
    let mode: CaptureMode
    var id: String { mode.rawValue }
}
