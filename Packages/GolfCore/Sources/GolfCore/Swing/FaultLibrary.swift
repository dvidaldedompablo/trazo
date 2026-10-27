import Foundation

/// Los fallos que reconoce el análisis. Los 13 de la tabla de docs/04 más 4 que hacen falta
/// para que cada medida que se sale por un lado tenga su fallo y su ejercicio:
/// `handsTooClose`, `flatDownswing`, `slowTempo` y `shortFinish`.
public enum FaultID: String, Sendable, Codable, CaseIterable {
    case uprightPosture, lowPosture, handsFarFromBody, handsTooClose
    case takeawayInside, takeawayOutside
    case flatMidBackswing, steepMidBackswing
    case shortBackswing, headMovement
    case steepDownswing, flatDownswing
    case earlyExtension
    case fastTempo, slowTempo
    case unbalancedFinish, shortFinish
}

/// Un fallo con sus textos.
public struct Fault: Sendable, Equatable {
    public let id: FaultID
    /// Nombre corto del fallo.
    public let name: String
    /// Etiqueta en el informe ("A mejorar").
    public let reportLabel: String
    /// Lo que se dice tras "Lo primero a trabajar:".
    public let focus: String
    /// Ejercicio para practicarlo.
    public let exercise: String
    /// Fallo que suele provocarlo. Si los dos aparecen, la prioridad es la causa.
    public let cause: FaultID?
}

/// Fallos, etiquetas, ejercicios y cadenas de causa (docs/04, puntos 6 y 7).
/// Son consejos generales: la Ayuda recomienda revisar el informe con el profesor.
public enum FaultLibrary {
    public static func fault(_ id: FaultID) -> Fault {
        switch id {
        case .uprightPosture:
            Fault(id: id, name: "Postura erguida", reportLabel: "Postura demasiado recta",
                  focus: "la inclinación desde la cadera",
                  exercise: "Palo apoyado en la espalda: cabeza, espalda alta y coxis tocándolo mientras te inclinas desde la cadera.",
                  cause: nil)
        case .lowPosture:
            Fault(id: id, name: "Demasiado inclinado o sentado", reportLabel: "Postura demasiado baja",
                  focus: "una postura menos baja",
                  exercise: "Frente al espejo: rodillas un poco flexionadas y peso en la mitad del pie.",
                  cause: nil)
        case .handsFarFromBody:
            Fault(id: id, name: "Manos lejos del cuerpo", reportLabel: "Brazos lejos",
                  focus: "dónde cuelgan los brazos",
                  exercise: "Deja caer los brazos relajados y agarra el palo donde caen las manos.",
                  cause: nil)
        case .handsTooClose:
            Fault(id: id, name: "Manos muy pegadas", reportLabel: "Brazos pegados",
                  focus: "dónde cuelgan los brazos",
                  exercise: "Deja caer los brazos relajados y agarra el palo donde caen las manos.",
                  cause: nil)
        case .takeawayInside:
            Fault(id: id, name: "Takeaway por dentro", reportLabel: "Takeaway por dentro",
                  focus: "el takeaway por dentro",
                  exercise: "Varilla en el suelo paralela a la línea: la cabeza del palo va por encima de ella hasta que el palo está paralelo al suelo.",
                  cause: nil)
        case .takeawayOutside:
            Fault(id: id, name: "Takeaway por fuera", reportLabel: "Takeaway por fuera",
                  focus: "el takeaway por fuera",
                  exercise: "Misma varilla: que la cabeza del palo no salga por fuera de ella.",
                  cause: nil)
        case .flatMidBackswing:
            Fault(id: id, name: "Palo plano a mitad de subida", reportLabel: "Subida plana",
                  focus: "la subida plana",
                  exercise: "Para en mitad de la subida: la punta del palo mira al cielo y la empuñadura apunta a la línea de la bola.",
                  cause: .takeawayInside)
        case .steepMidBackswing:
            Fault(id: id, name: "Palo vertical a mitad de subida", reportLabel: "Subida vertical",
                  focus: "la subida vertical",
                  exercise: "Swings lentos sintiendo que las manos van más alrededor del cuerpo.",
                  cause: .takeawayOutside)
        case .shortBackswing:
            Fault(id: id, name: "Subida corta", reportLabel: "Subida corta",
                  focus: "una subida más completa",
                  exercise: "Swings con pausa arriba, girando la espalda hacia el objetivo.",
                  cause: nil)
        case .headMovement:
            Fault(id: id, name: "Cabeza que se mueve", reportLabel: "Cabeza inestable",
                  focus: "la cabeza quieta",
                  exercise: "Graba con tu sombra delante: mantén la cabeza dentro de una marca hasta el impacto.",
                  cause: nil)
        case .steepDownswing:
            Fault(id: id, name: "Palo vertical al bajar", reportLabel: "Bajada vertical",
                  focus: "la bajada vertical",
                  exercise: "Swings a medio ritmo sintiendo que el palo cae por detrás de las manos al empezar a bajar.",
                  cause: nil)
        case .flatDownswing:
            Fault(id: id, name: "Palo plano al bajar", reportLabel: "Bajada plana",
                  focus: "la bajada plana",
                  exercise: "Swings a medio ritmo sintiendo que las manos bajan delante del pecho, sin que el palo se quede atrás.",
                  cause: nil)
        case .earlyExtension:
            Fault(id: id, name: "Se levanta en el impacto", reportLabel: "Te levantas en el impacto",
                  focus: "mantener la postura en el impacto",
                  exercise: "Silla o bolsa tocando el glúteo: mantén el contacto hasta pasar el impacto.",
                  cause: nil)
        case .fastTempo:
            Fault(id: id, name: "Ritmo rápido", reportLabel: "Ritmo rápido",
                  focus: "el ritmo de la subida",
                  exercise: "Cuenta \"uno, dos, tres\" en la subida y \"cuatro\" en el impacto.",
                  cause: nil)
        case .slowTempo:
            Fault(id: id, name: "Ritmo lento", reportLabel: "Ritmo lento",
                  focus: "el ritmo de la subida",
                  exercise: "Cuenta \"uno, dos\" en la subida y \"tres\" en el impacto, sin pararte arriba.",
                  cause: nil)
        case .unbalancedFinish:
            Fault(id: id, name: "Final sin equilibrio", reportLabel: "Final inestable",
                  focus: "el equilibrio del final",
                  exercise: "Aguanta el final 3 segundos con el peso en el pie de delante y el pecho mirando al objetivo.",
                  cause: nil)
        case .shortFinish:
            Fault(id: id, name: "Final corto", reportLabel: "Final corto",
                  focus: "un final completo",
                  exercise: "Aguanta el final 3 segundos con el peso en el pie de delante y el pecho mirando al objetivo.",
                  cause: nil)
        }
    }

    /// Todos los fallos, en el orden de `FaultID`.
    public static var all: [Fault] { FaultID.allCases.map(fault) }

    /// Fallo que suele provocar este (cadena de causa), si lo hay.
    public static func cause(of id: FaultID) -> FaultID? { fault(id).cause }
}
