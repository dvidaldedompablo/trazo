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
    /// "Creando tu tracer" (s03) a mitad del seguimiento.
    case processing
    /// Toca la bola, con un toque y la lupa.
    case ballTap = "ball-tap"
    /// El resultado del tracer con el modo diagnóstico (puntos, descartados, curva y datos).
    case tracerCheck = "tracer-check"
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

    /// Marca de "pantalla lista" para el script de capturas: un archivo vacío en la carpeta temporal
    /// de la app. El script espera a que exista antes de hacer la foto, así no captura la pantalla de
    /// arranque cuando el runner del CI va lento (pasó en el run 16 con una espera fija de 5 s).
    static let readyMarker = URL.temporaryDirectory.appending(path: "uitest-ready", directoryHint: .notDirectory)

    /// La pantalla pedida ya se ha abierto.
    static func markReady() {
        try? Data().write(to: readyMarker)
    }

    /// Se llama una vez al arrancar, solo en modo de capturas.
    @MainActor
    static func prepare() {
        UIView.setAnimationsEnabled(false)
        try? FileManager.default.removeItem(at: readyMarker)
        // Ajustes de fábrica (trazo rojo, distancia activada, 240 fps…), por si quedó algo de otra prueba.
        for key in SettingsKey.all {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
