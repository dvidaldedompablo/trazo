import Foundation

/// Desde dónde se ve un fallo en el vídeo.
public enum CameraView: String, Sendable, Codable {
    /// Desde detrás del jugador, mirando hacia el objetivo (la que pide la app al grabar).
    case behind = "detras"
    /// De frente al jugador.
    case front = "frente"
    case both = "ambas"

    public var title: String {
        switch self {
        case .behind: "Detrás"
        case .front: "Frente"
        case .both: "Detrás o frente"
        }
    }
}

/// Un fallo del swing con su ejercicio de práctica (catálogo pedido por el usuario el 22-11-2026).
/// Los textos van en lenguaje llano: los tiene que entender alguien que no sabe de golf.
public struct Exercise: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    /// Número del 1 al 15, en el orden del catálogo.
    public let number: Int
    /// Nombre corto del fallo.
    public let fault: String
    /// Qué se ve en el vídeo cuando pasa.
    public let whatYouSee: String
    /// El ejercicio, en una o dos frases.
    public let exercise: String
    public let equipment: String
    public let repetitions: String
    /// Qué debe sentir el jugador cuando lo hace bien.
    public let feeling: String
    public let typicalMistake: String
    /// Cámara en la que se ve el fallo.
    public let camera: CameraView
    /// Fallos del análisis que lo detectan. Vacío: el análisis todavía no puede medirlo.
    public let detectedBy: [FaultID]
    /// Si la animación quedaba rara, solo hay imagen y texto (sin clip).
    public let hasClip: Bool
    /// Nadie con título de profesor lo ha revisado todavía.
    public let reviewedByProfessional: Bool

    /// Imagen y clip en bucle: `assets/ejercicios/<id>.png` y `.mp4`. Para cambiar el clip por uno
    /// propio basta con sustituir el archivo, sin tocar código.
    public var imageFile: String { "\(id).png" }
    public var clipFile: String { "\(id).mp4" }

    /// El análisis puede medirlo con la cámara que se usa (hoy, siempre desde detrás).
    public func isMeasurable(with camera: CameraView = .behind) -> Bool {
        guard !detectedBy.isEmpty else { return false }
        switch (self.camera, camera) {
        case (.both, _), (_, .both): return true
        default: return self.camera == camera
        }
    }
}

public enum ExerciseCatalog {
    public static let all: [Exercise] = [
        e(1, "takeaway_dentro", "Takeaway por dentro",
          see: "Al empezar a subir, la cabeza del palo se va enseguida hacia detrás del cuerpo, por detrás de las manos.",
          exercise: "Pon una varilla en el suelo, paralela a la línea hacia el objetivo. Al subir, la cabeza del palo pasa por encima de la varilla hasta que el palo queda paralelo al suelo.",
          equipment: "Una varilla de alineación o un palo en el suelo", reps: "10 subidas lentas y 10 golpes",
          feeling: "Que el palo sale recto hacia atrás y las manos y la cabeza del palo se mueven juntas.",
          mistake: "Girar las muñecas al empezar, que mete el palo hacia dentro.", camera: .behind, faults: [.takeawayInside]),
        e(2, "takeaway_fuera", "Takeaway por fuera",
          see: "Al empezar a subir, la cabeza del palo se aleja del cuerpo, hacia fuera de la línea de la bola.",
          exercise: "Pon una funda de palo justo fuera y detrás de la bola. Al subir, el palo no debe tocarla.",
          equipment: "Una funda de palo o una varilla", reps: "10 subidas lentas y 10 golpes",
          feeling: "Que el palo empieza a subir pegado a la línea y gira con el cuerpo.",
          mistake: "Empujar el palo con los brazos en vez de girar los hombros.", camera: .behind, faults: [.takeawayOutside]),
        e(3, "subida_vertical", "Subida vertical",
          see: "A mitad de la subida, el palo apunta muy hacia arriba y las manos suben pegadas a la cabeza.",
          exercise: "Haz swings lentos sintiendo que las manos van más alrededor del cuerpo y menos hacia arriba.",
          equipment: "Solo el palo", reps: "10 swings lentos",
          feeling: "Que las manos giran alrededor del cuerpo, como si rodearas un barril.",
          mistake: "Levantar los brazos sin girar el cuerpo.", camera: .behind, faults: [.steepMidBackswing]),
        e(4, "subida_plana", "Subida plana",
          see: "A mitad de la subida, el palo queda muy tumbado y las manos se van hacia detrás del cuerpo.",
          exercise: "Haz swings lentos sintiendo que las manos suben más cerca de la cabeza.",
          equipment: "Solo el palo", reps: "10 swings lentos",
          feeling: "Que las manos suben por delante del pecho y no por detrás.",
          mistake: "Girar las muñecas hacia dentro al empezar la subida.", camera: .behind, faults: [.flatMidBackswing]),
        e(5, "ritmo_rapido", "Ritmo rápido",
          see: "La subida dura muy poco comparada con la bajada: el swing parece un tirón.",
          exercise: "Cuenta en voz alta \"uno, dos, tres\" mientras subes y \"cuatro\" al golpear la bola.",
          equipment: "Solo el palo", reps: "10 swings contando",
          feeling: "Que la subida es tranquila y la velocidad llega al bajar.",
          mistake: "Contar deprisa: el ritmo de la cuenta también tiene que ser lento.", camera: .both, faults: [.fastTempo]),
        e(6, "transicion_brusca", "Transición brusca",
          see: "Arriba del todo, el palo cambia de dirección de golpe, sin un instante de calma.",
          exercise: "Haz swings parando un segundo arriba del todo antes de empezar a bajar.",
          equipment: "Solo el palo", reps: "10 swings con pausa",
          feeling: "Que arriba hay un momento de calma y la bajada empieza suave.",
          mistake: "Hacer la pausa demasiado corta o no llegar a terminar la subida.", camera: .both, faults: []),
        e(7, "cadera_adelante", "La cadera se adelanta hacia la bola",
          see: "Al bajar, el culo se separa de donde estaba y la cadera se acerca a la bola: el cuerpo se levanta.",
          exercise: "Ponte con el culo tocando una silla o una pared. Mantén ese contacto durante la subida y la bajada.",
          equipment: "Una silla o una pared detrás", reps: "10 swings lentos y 5 golpes",
          feeling: "Que el culo se queda atrás y el cuerpo gira sin levantarse.",
          mistake: "Separarse de la silla justo antes de golpear.", camera: .behind, faults: [.earlyExtension]),
        e(8, "deslizamiento_cadera", "La cadera se desliza al subir",
          see: "Al subir, la cadera se mueve de lado hacia atrás en vez de girar.",
          exercise: "Clava una varilla en el suelo, justo por fuera de la cadera de atrás. Al subir, la cadera gira sin tocarla.",
          equipment: "Una varilla de alineación clavada en el suelo", reps: "10 subidas lentas",
          feeling: "Que la cadera gira sobre sí misma, como una puerta, sin irse de lado.",
          mistake: "Tocar la varilla al llegar arriba del todo.", camera: .front, faults: []),
        e(9, "brazos_separados", "Brazos separados del cuerpo",
          see: "Los brazos se alejan del pecho y se mueven por su cuenta, sin ir con el cuerpo.",
          exercise: "Pon una toalla bajo las dos axilas. Haz el swing sin que se caiga.",
          equipment: "Una toalla pequeña", reps: "10 swings cortos",
          feeling: "Que los brazos y el pecho giran juntos.",
          mistake: "Apretar tanto los brazos que el swing queda rígido.", camera: .both, faults: [.handsFarFromBody]),
        e(10, "poco_giro_hombros", "Poco giro de hombros",
          see: "Arriba del todo, la espalda casi no mira al objetivo: los hombros han girado poco.",
          exercise: "Cruza un palo sobre el pecho. Gira hasta que el hombro de delante quede bajo la barbilla.",
          equipment: "Un palo", reps: "10 giros lentos a cada lado",
          feeling: "Que la espalda acaba mirando al objetivo.",
          mistake: "Inclinar los hombros en vez de girarlos.", camera: .front, faults: []),
        e(11, "transferencia_peso", "Poca transferencia de peso",
          see: "Al golpear, el peso sigue en el pie de atrás y el cuerpo se queda atrás.",
          exercise: "Junta los pies. Al empezar a bajar, da un paso con el pie de delante hacia el objetivo y golpea.",
          equipment: "Solo el palo", reps: "10 swings con el paso",
          feeling: "Que el peso pasa al pie de delante antes de golpear.",
          mistake: "Dar el paso tarde, cuando ya estás golpeando.", camera: .front, faults: []),
        e(12, "equilibrio_final", "Pérdida de equilibrio en el final",
          see: "Al terminar el swing, el jugador da un paso o se tambalea.",
          exercise: "Termina cada swing y aguanta la posición final tres segundos sin moverte.",
          equipment: "Solo el palo", reps: "10 swings aguantando el final",
          feeling: "Que acabas con el peso en el pie de delante y el pecho mirando al objetivo.",
          mistake: "Swing tan fuerte que no puedes quedarte quieto.", camera: .both, faults: [.unbalancedFinish, .shortFinish]),
        e(13, "cabeza_se_mueve", "La cabeza se mueve",
          see: "Durante el swing, la cabeza sube, baja o se va de lado.",
          exercise: "Fija la vista en un punto de la bola. Mantenla ahí hasta después de golpear.",
          equipment: "Solo el palo y una bola", reps: "10 golpes",
          feeling: "Que la cabeza se queda quieta y el cuerpo gira debajo.",
          mistake: "Levantar la cabeza para ver adónde va la bola.", camera: .both, faults: [.headMovement]),
        e(14, "manos_atras", "Impacto con las manos atrás",
          see: "Al golpear, las manos van por detrás de la bola y el palo se inclina hacia atrás.",
          exercise: "Haz golpes cortos con el mango por delante de la bola en el momento de golpear.",
          equipment: "Palo y bola", reps: "10 golpes cortos",
          feeling: "Que las manos llegan a la bola antes que la cabeza del palo.",
          mistake: "Echar la bola hacia arriba con las muñecas.", camera: .front, faults: []),
        e(15, "bajada_por_fuera", "Bajada por fuera",
          see: "Al empezar a bajar, el palo sale hacia fuera y baja por encima, cruzando la línea de la bola.",
          exercise: "Pon una funda de palo por fuera de la bola. Al bajar, el palo llega desde dentro sin tocarla.",
          equipment: "Una funda de palo", reps: "10 swings lentos y 10 golpes",
          feeling: "Que el palo baja por detrás de las manos y llega a la bola desde dentro.",
          mistake: "Empezar la bajada con los hombros, que lanza el palo hacia fuera.", camera: .behind, faults: [.steepDownswing]),
    ]

    /// Los ejercicios de unos fallos del análisis, sin repetir y en el orden del catálogo.
    public static func exercises(for faults: [FaultID], camera: CameraView = .behind) -> [Exercise] {
        all.filter { exercise in exercise.isMeasurable(with: camera) && exercise.detectedBy.contains { faults.contains($0) } }
    }

    /// Los que la app enseña: los que puede medir con la cámara disponible.
    public static func shown(camera: CameraView = .behind) -> [Exercise] {
        all.filter { $0.isMeasurable(with: camera) }
    }

    public static func exercise(id: String) -> Exercise? { all.first { $0.id == id } }

    private static func e(_ number: Int, _ id: String, _ fault: String, see: String, exercise: String, equipment: String,
                          reps: String, feeling: String, mistake: String, camera: CameraView, faults: [FaultID],
                          clip: Bool = true) -> Exercise {
        Exercise(id: id, number: number, fault: fault, whatYouSee: see, exercise: exercise, equipment: equipment,
                 repetitions: reps, feeling: feeling, typicalMistake: mistake, camera: camera, detectedBy: faults,
                 hasClip: clip, reviewedByProfessional: false)
    }
}
