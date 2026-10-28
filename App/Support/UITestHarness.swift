import UIKit

/// Pantallas que el CI puede abrir directamente con el argumento de arranque `-UITestScreen <nombre>`.
/// Se añade un caso por cada pantalla nueva (la lista completa está en docs/01_ARQUITECTURA.md).
enum UITestScreen: String {
    case home
    /// Catálogo de componentes del sistema de diseño (no es una pantalla de la app).
    case components
    /// Grabar en modo Tracer y en modo Swing, con el campo de la maqueta en vez de la cámara.
    case cameraTracer = "camera-tracer"
    case cameraSwing = "camera-swing"
    /// Tus vídeos con clips de demostración.
    case library
    /// La hoja de elegir golpes tras grabar con "Corte auto".
    case autocut
    /// La misma hoja con un vídeo narrado, sin golpes: el control de sensatez no propone clips.
    case autocutVoice = "autocut-voice"
}

/// Arnés de capturas: con `-UITestScreen` la app abre esa pantalla con datos de demostración,
/// sin cámara ni permisos y sin animaciones, para que las capturas del CI salgan siempre iguales.
enum UITestHarness {
    /// El nombre pedido, tal cual. iOS convierte los argumentos de arranque con forma
    /// "-Clave valor" en valores de UserDefaults, así que no hace falta leer CommandLine a mano.
    static var requestedName: String? {
        UserDefaults.standard.string(forKey: "UITestScreen")
    }

    static var isActive: Bool { requestedName != nil }

    /// Se llama una vez al arrancar, solo en modo de capturas.
    @MainActor
    static func prepare() {
        UIView.setAnimationsEnabled(false)
        // Ajustes de fábrica (trazo rojo, distancia activada, 240 fps…), por si quedó algo de otra prueba.
        for key in SettingsKey.all {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
