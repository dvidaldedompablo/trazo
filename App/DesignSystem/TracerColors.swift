import SwiftUI

/// Los colores del trazo que se pueden elegir (docs/02): cinco fijos y "Otro color".
/// El valor en texto (`rawValue`) es lo que se guarda en los ajustes, así que no conviene cambiarlo.
enum TracerColorChoice: String, CaseIterable, Identifiable {
    case rojoTV
    case amarillo
    case blanco
    case azulTee
    case verde
    /// Un color que eliges tú con el selector de colores de iOS.
    case otro

    var id: String { rawValue }

    /// Los cinco fijos, en el orden de la fila.
    static let presets: [TracerColorChoice] = [.rojoTV, .amarillo, .blanco, .azulTee, .verde]

    /// Nombre para VoiceOver y para Ajustes.
    var name: String {
        switch self {
        case .rojoTV: "Rojo TV"
        case .amarillo: "Amarillo"
        case .blanco: "Blanco"
        case .azulTee: "Azul tee"
        case .verde: "Verde"
        case .otro: "Otro color"
        }
    }

    /// El color del trazo. Para "Otro color" hace falta el que eligió el usuario.
    func color(custom: Color) -> Color {
        switch self {
        case .rojoTV: .rojoTrazo
        case .amarillo: .amarillo
        case .blanco: .white
        case .azulTee: TracerPalette.azulTee
        case .verde: TracerPalette.verde
        case .otro: custom
        }
    }
}

/// Colores que solo existen como opción del trazo.
enum TracerPalette {
    static let azulTee = Color(hex: 0x2F7CFF)
    static let verde = Color(hex: 0x2FD27A)
    /// Rosa del anillo arcoíris: el primer "Otro color" antes de que elijas uno.
    static let rosa = Color(hex: 0xFF3FA4)
    static let customDefaultHex: UInt32 = 0xFF3FA4
    /// Anillo arcoíris de "Otro color", en el orden de la maqueta (empieza arriba y gira a la derecha).
    static let rainbow: [Color] = [.rojoTrazo, .amarillo, verde, azulTee, rosa, .rojoTrazo]
}
