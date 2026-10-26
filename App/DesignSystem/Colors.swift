import SwiftUI

// Colores de docs/02_DISENO.md. Las vistas usan solo estos nombres, nunca un color suelto.
// En la etapa 1 se completa la paleta.
extension Color {
    /// Fondo de las pantallas claras.
    static let bola = Color(hex: 0xF6F7F4)
    /// Texto principal.
    static let pino = Color(hex: 0x10241D)
    /// Texto secundario.
    static let texto2 = Color(hex: 0x4B5D55)

    /// Crea un color a partir de un número hexadecimal como 0xF6F7F4.
    /// Cada pareja de cifras es un canal (rojo, verde, azul) de 0 a 255.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
