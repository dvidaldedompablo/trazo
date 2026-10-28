import SwiftUI
import UIKit

// Colores de docs/02_DISENO.md. Las vistas usan solo estos nombres, nunca un color suelto.
// Los nombres son los de la tabla del documento, para que sea fácil buscarlos en los dos sitios.
extension Color {
    /// Fondo de las pantallas claras.
    static let bola = Color(hex: 0xF6F7F4)
    /// Tarjetas, paneles y hojas.
    static let papel = Color(hex: 0xFFFFFF)
    /// Botones secundarios, fondos de icono, controles segmentados.
    static let niebla = Color(hex: 0xE5EBE7)
    /// Separadores y pistas de deslizadores.
    static let linea = Color(hex: 0xD5DDD8)
    /// Borde de la muestra blanca y fondo del interruptor apagado.
    static let borde = Color(hex: 0xC9D2CC)
    /// Texto principal, botón principal y tarjeta de Análisis.
    static let pino = Color(hex: 0x10241D)
    /// Variante para capas sobre Pino.
    static let pino2 = Color(hex: 0x1C362C)
    /// Texto secundario.
    static let texto2 = Color(hex: 0x4B5D55)
    /// Texto terciario y flechas.
    static let texto3 = Color(hex: 0x7D8B84)
    /// Tracer: trazo, punto de grabar, impacto en la onda.
    static let rojoTrazo = Color(hex: 0xFF3B2E)
    /// Análisis: líneas del telestrador, botón de grabar swing.
    static let amarillo = Color(hex: 0xFFD02E)
    /// Confirmaciones (uso mínimo).
    static let bien = Color(hex: 0x1F9D63)
    /// Fondo de las pantallas de vídeo: negro puro.
    static let escenario = Color(hex: 0x000000)
    /// Nivel de la cámara cuando el móvil está recto ("Nivelado"), de la maqueta (s02).
    static let nivelado = Color(hex: 0x7CF0A9)

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

    /// El color en formato 0xRRGGBB, para guardarlo en los ajustes.
    /// SwiftUI no deja leer los canales de un `Color` directamente; UIKit sí.
    var hexValue: UInt32 {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        // getRed puede dar valores fuera de 0...1 en colores de gama amplia: se recortan.
        func channel(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return channel(red) << 16 | channel(green) << 8 | channel(blue)
    }
}

/// Colores de las ilustraciones de Inicio (la ventana del Tracer y la figura del telestrador).
/// Son dibujos, no interfaz: salen tal cual de `design/maqueta.html`.
enum SceneColors {
    // Cielo: degradado vertical de arriba abajo, con el sol arriba a la derecha.
    static let skyTop = Color(hex: 0x8FBCD6)
    static let skyMiddle = Color(hex: 0xC9E0EA)
    static let skyHorizon = Color(hex: 0xE6EEEA)
    static let sun = Color(hex: 0xFFFBEA)
    // Arboleda: dos filas, la de atrás más clara.
    static let treesBack = Color(hex: 0x3C5A47)
    static let treesFront = Color(hex: 0x2B4636)
    // Calle del campo de prácticas.
    static let grassTop = Color(hex: 0x7FA866)
    static let grassMiddle = Color(hex: 0x6E9F57)
    static let grassBottom = Color(hex: 0x5C8E48)
    // Carteles de distancia.
    static let board = Color(hex: 0xF7F7F2)
    static let boardPost = Color(hex: 0xE9EEEA)
    // Zona de golpeo y bola del fondo de demostración de Grabar (s02).
    static let teeBox = Color(hex: 0x3B7446)
    static let teeBoxEdge = Color(hex: 0x9CC596)
    static let ball = Color(hex: 0xFDFDFB)
    // Figura del golfista en la tarjeta de Análisis (y pierna de atrás de la silueta de Grabar).
    static let figureBack = Color(hex: 0x2E3D36)
    static let figure = Color(hex: 0x2D4A3E)
    static let clubShaft = Color(hex: 0x151A18)
    static let clubHead = Color(hex: 0x2A2F2D)
}
