import Foundation
import SwiftData

/// Un palo de "Mis palos": su nombre y la distancia de vuelo que pone el usuario.
/// La distancia del tracer sale de aquí si no se escribe a mano (docs/03). Nunca se mide.
@Model
final class Club {
    var name: String
    /// Distancia de vuelo por defecto, en metros (se enseña en m o yd según Ajustes). `nil` = sin poner.
    var distanceMeters: Double?
    /// Posición en la lista.
    var order: Int

    init(name: String, distanceMeters: Double?, order: Int) {
        self.name = name
        self.distanceMeters = distanceMeters
        self.order = order
    }
}

/// Lista inicial de palos (docs/01): solo el hierro 7 trae distancia, el resto lo rellena el usuario.
enum ClubDefaults {
    static let list: [(name: String, distanceMeters: Double?)] = [
        ("Driver", nil), ("Madera 3", nil), ("Madera 5", nil), ("Madera 7", nil),
        ("Hierro 5", nil), ("Hierro 6", nil), ("Hierro 7", 150), ("Hierro 8", nil), ("Hierro 9", nil),
        ("PW", nil), ("AW", nil), ("Wedge 52°", nil), ("Wedge 56°", nil), ("Wedge 60°", nil),
    ]
}
