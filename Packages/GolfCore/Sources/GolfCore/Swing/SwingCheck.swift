import Foundation

/// Análisis de swing con Gemini (docs/10, Fase 4, segunda función). El usuario lo pidió el 22-11-2026:
/// "quiero que lo haga todo Gemini", porque Vision no veía al jugador en una story de Instagram.
///
/// Dos peticiones:
/// 1. Posiciones: hojas de fotogramas alrededor del impacto; el modelo dice en qué fotograma está
///    cada uno de los 8 momentos de docs/04 (inicio de la subida y las 7 posiciones).
/// 2. Cuerpo y palo: los 7 fotogramas elegidos, sueltos y a buena resolución; el modelo marca las
///    articulaciones, la empuñadura y la cabeza del palo en cada uno.
/// El modelo propone y el código decide (docs/10, regla 2): las posiciones tienen que ir en orden y la
/// bajada durar de 0,1 a 0,6 s; si no, no se usa y la app sigue con Vision (el plan B sin red).
/// Aquí solo está la lógica pura; las imágenes y la red están en la app (`SwingGeminiAnalyzer`).
public enum SwingCheck {
    /// Un fotograma cada 0,04 s (25 por segundo) en las hojas de las posiciones.
    public static let sampleInterval = 0.04
    /// Tramo de las hojas: de 2,5 s antes a 1,5 s después del impacto que se conoce (el del sonido o
    /// el que confirmó el verificador). Sin impacto, los primeros `maximumFrames` del clip.
    public static let secondsBeforeImpact = 2.5
    public static let secondsAfterImpact = 1.5
    public static let maximumFrames = 120

    // MARK: Momentos

    /// Los 8 momentos que se piden, en orden: el inicio de la subida (B) y las 7 posiciones.
    public static let moments: [(key: String, position: SwingPosition?)] = [
        ("preparacion", .address), ("inicio_subida", nil), ("takeaway", .takeaway), ("mitad_subida", .midBackswing),
        ("top", .top), ("transicion", .transition), ("impacto", .impact), ("final", .finish),
    ]

    /// Articulaciones que se piden (nombres del golfista, no de la imagen) y su nombre en `Joint`.
    /// El cuello y el centro de la cadera, que da Vision, salen del punto medio de hombros y caderas.
    public static let joints: [(key: String, joint: Joint)] = [
        ("nariz", .nose), ("hombro_izq", .leftShoulder), ("hombro_der", .rightShoulder),
        ("codo_izq", .leftElbow), ("codo_der", .rightElbow), ("muneca_izq", .leftWrist), ("muneca_der", .rightWrist),
        ("cadera_izq", .leftHip), ("cadera_der", .rightHip), ("rodilla_izq", .leftKnee), ("rodilla_der", .rightKnee),
        ("tobillo_izq", .leftAnkle), ("tobillo_der", .rightAnkle),
    ]

    // MARK: Petición 1: posiciones

    public struct PositionsRequest: Sendable, Equatable {
        /// Instantes de todos los fotogramas, en orden; el número impreso es su posición + 1.
        public var frameTimes: [Double]
        /// Las hojas: índices en `frameTimes` de 12 en 12.
        public var sheets: [[Int]]

        public func caption(_ sheet: Int) -> String {
            let indices = sheets[sheet]
            return "Hoja \(sheet + 1): fotogramas \(indices[0] + 1) a \(indices[indices.count - 1] + 1)"
        }

        public var text: String {
            "Hojas de fotogramas seguidos de un swing, en orden de tiempo (un fotograma cada \(String(format: "%.2f", SwingCheck.sampleInterval)) s). "
                + "Los números de fotograma son únicos en todo el mensaje. Di en qué fotograma está cada momento."
        }
    }

    public static func positionsPlan(duration: Double, impactHint: Double?) -> PositionsRequest {
        var start = 0.0, end = duration
        if let impactHint {
            start = max(0, impactHint - secondsBeforeImpact)
            end = min(duration, impactHint + secondsAfterImpact)
        }
        let interval = max(sampleInterval, (end - start) / Double(maximumFrames))
        var times: [Double] = []
        var t = start
        while t <= end + 1e-9, times.count < maximumFrames {
            times.append(t)
            t += interval
        }
        let sheets = stride(from: 0, to: times.count, by: ShotCheck.framesPerSheet).map {
            Array($0..<min($0 + ShotCheck.framesPerSheet, times.count))
        }
        return PositionsRequest(frameTimes: times, sheets: sheets)
    }

    public static let positionsInstructions = """
    Eres un analista de swing de golf. Te paso hojas con fotogramas seguidos de un vídeo de un golfista, en orden de tiempo. Cada fotograma lleva su número arriba a la izquierda (en un recuadro negro) y su instante en segundos abajo a la izquierda.

    Di el número del fotograma de cada momento del swing:
    - preparacion: el último fotograma quieto ante la bola, antes de que empiece la subida.
    - inicio_subida: el primer fotograma en que las manos empiezan a alejarse hacia atrás.
    - takeaway: en la subida, el fotograma en que el palo queda paralelo al suelo.
    - mitad_subida: en la subida, el fotograma en que el brazo de delante queda paralelo al suelo.
    - top: las manos en su punto más alto, donde el palo cambia de sentido.
    - transicion: en la bajada, el fotograma en que el brazo de delante vuelve a quedar paralelo al suelo.
    - impacto: el fotograma más cercano al momento en que la cabeza del palo toca la bola.
    - final: el primer fotograma, tras el impacto, en que el swing ha terminado y el jugador se queda quieto; si no se para, el último en que se le ve terminar.
    El orden tiene que ser: preparacion, inicio_subida, takeaway, mitad_subida, top, transicion, impacto, final.
    hay_swing: si en las hojas se ve un swing completo que golpea la bola (si, no o no_se).
    confianza: de 0 a 1 en cada momento. Si dudas, pon una confianza baja; no inventes.
    """

    public static var positionsSchemaJSON: String {
        let moment = #"{"type":"object","properties":{"fotograma":{"type":"integer"},"confianza":{"type":"number"}},"required":["fotograma","confianza"]}"#
        let properties = moments.map { "\"\($0.key)\":\(moment)" }.joined(separator: ",")
        let required = moments.map { "\"\($0.key)\"" }.joined(separator: ",")
        return #"{"type":"object","properties":{"hay_swing":{"type":"string","enum":["si","no","no_se"]},"momentos":{"type":"object","properties":{"#
            + properties + #"},"required":["# + required + #"]}},"required":["hay_swing","momentos"]}"#
    }

    public static func positionsBody(_ request: PositionsRequest, sheetJPEGs: [Data]) throws -> Data {
        precondition(sheetJPEGs.count == request.sheets.count, "Una imagen por hoja")
        let images = request.sheets.indices.map { (request.caption($0), sheetJPEGs[$0]) }
        return try body(text: request.text, images: images, instructions: positionsInstructions, schema: positionsSchemaJSON)
    }

    /// Las posiciones elegidas, ya validadas: índice en `frameTimes` de cada momento.
    public struct ChosenPositions: Sendable, Equatable {
        public var frameIndex: [String: Int]
        public var confidence: [String: Double]
        public var times: [String: Double]
    }

    public enum Failure: Error, Sendable, Equatable {
        case unreadable
        case noSwing
        case outOfOrder(String)
        case badDownswing(Double)
        case noBody

        /// Para el registro y las notas del análisis.
        public var description: String {
            switch self {
            case .unreadable: "la respuesta no es el JSON pedido"
            case .noSwing: "no ve un swing completo"
            case .outOfOrder(let what): "posiciones fuera de orden (\(what))"
            case .badDownswing(let s): "bajada imposible (\(String(format: "%.2f", s)) s)"
            case .noBody: "no marca el cuerpo en la preparación"
            }
        }
    }

    public static func parsePositions(_ text: String, for request: PositionsRequest) -> Swift.Result<ChosenPositions, Failure> {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let items = object["momentos"] as? [String: Any]
        else { return .failure(.unreadable) }
        if (object["hay_swing"] as? String) == "no" { return .failure(.noSwing) }
        var index: [String: Int] = [:]
        var confidence: [String: Double] = [:]
        for (key, _) in moments {
            guard let item = items[key] as? [String: Any], let number = item["fotograma"] as? Int,
                  request.frameTimes.indices.contains(number - 1)
            else { return .failure(.unreadable) }
            index[key] = number - 1
            let c = (item["confianza"] as? Double) ?? (item["confianza"] as? Int).map(Double.init) ?? 0
            confidence[key] = min(max(c, 0), 1)
        }
        // En orden; la preparación puede ser el mismo fotograma que el inicio de la subida.
        for (a, b) in zip(moments, moments.dropFirst()) {
            let ia = index[a.key]!, ib = index[b.key]!
            let ok = a.key == "preparacion" ? ia <= ib : ia < ib
            if !ok { return .failure(.outOfOrder("\(a.key) y \(b.key)")) }
        }
        let times = index.mapValues { request.frameTimes[$0] }
        let downswing = times["impacto"]! - times["top"]!
        guard SwingImpactChooser.downswingRange.contains(downswing) else { return .failure(.badDownswing(downswing)) }
        return .success(ChosenPositions(frameIndex: index, confidence: confidence, times: times))
    }

    // MARK: Petición 2: cuerpo y palo

    /// Las 7 posiciones de las que se pide el cuerpo, en orden (las imágenes van en este orden).
    public static let bodyMoments: [(key: String, position: SwingPosition)] = moments.compactMap { m in m.position.map { (key: m.key, position: $0) } }

    public static let bodyInstructions = """
    Eres un analista de swing de golf. Te paso fotogramas sueltos de un golfista, uno por cada posición del swing. En cada imagen marca el centro de cada articulación del golfista (izquierda y derecha son las del propio golfista, no las de la imagen), la empuñadura del palo (donde están las manos) y el centro de la cabeza del palo.
    x e y van de 0 a 1000 y son relativos a ESA imagen: 0,0 es la esquina de arriba a la izquierda y 1000,1000 la de abajo a la derecha.
    visible: false si ese punto está tapado o fuera de la imagen (pon igualmente tu mejor estimación en x e y). No inventes: si no lo ves, visible false.
    """

    public static var bodySchemaJSON: String {
        let point = #"{"type":"object","properties":{"x":{"type":"integer"},"y":{"type":"integer"},"visible":{"type":"boolean"}},"required":["x","y","visible"]}"#
        let keys = joints.map(\.key) + ["empunadura", "cabeza_palo"]
        let properties = keys.map { "\"\($0)\":\(point)" }.joined(separator: ",")
        let required = (["imagen"] + keys).map { "\"\($0)\"" }.joined(separator: ",")
        return #"{"type":"object","properties":{"fotogramas":{"type":"array","items":{"type":"object","properties":{"imagen":{"type":"integer"},"#
            + properties + #"},"required":["# + required + #"]}}},"required":["fotogramas"]}"#
    }

    public static var bodyText: String {
        "\(bodyMoments.count) imágenes, numeradas de 1 a \(bodyMoments.count) en orden: "
            + bodyMoments.enumerated().map { "\($0.offset + 1) \($0.element.key)" }.joined(separator: ", ") + "."
    }

    /// Una imagen por posición, en el orden de `bodyMoments`.
    public static func bodyBody(frameJPEGs: [Data]) throws -> Data {
        precondition(frameJPEGs.count == bodyMoments.count, "Una imagen por posición")
        let images = bodyMoments.enumerated().map { ("Imagen \($0.offset + 1): \($0.element.key)", frameJPEGs[$0.offset]) }
        return try body(text: bodyText, images: images, instructions: bodyInstructions, schema: bodySchemaJSON)
    }

    /// El cuerpo y el palo de una posición, en píxeles del vídeo girado.
    public struct BodyMarks: Sendable, Equatable {
        public var joints: [Joint: Point2D]
        public var grip: Point2D?
        public var clubHead: Point2D?
    }

    /// Valida la respuesta del cuerpo: puntos de 0 a 1000; los no visibles no se usan (como las
    /// articulaciones de poca confianza de Vision). Hace falta el cuerpo de la preparación.
    public static func parseBody(_ text: String, width: Int, height: Int) -> Swift.Result<[SwingPosition: BodyMarks], Failure> {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let items = object["fotogramas"] as? [[String: Any]]
        else { return .failure(.unreadable) }
        func point(_ value: Any?) -> Point2D? {
            guard let p = value as? [String: Any], (p["visible"] as? Bool) == true,
                  let x = (p["x"] as? Int) ?? (p["x"] as? Double).map({ Int($0) }),
                  let y = (p["y"] as? Int) ?? (p["y"] as? Double).map({ Int($0) }),
                  (0...1000).contains(x), (0...1000).contains(y)
            else { return nil }
            return Point2D(x: Double(x) / 1000 * Double(width), y: Double(y) / 1000 * Double(height))
        }
        var marks: [SwingPosition: BodyMarks] = [:]
        for item in items {
            guard let number = item["imagen"] as? Int, bodyMoments.indices.contains(number - 1) else { continue }
            var found: [Joint: Point2D] = [:]
            for (key, joint) in joints { found[joint] = point(item[key]) }
            if let l = found[.leftShoulder], let r = found[.rightShoulder] { found[.neck] = Point2D.midpoint(l, r) }
            if let l = found[.leftHip], let r = found[.rightHip] { found[.root] = Point2D.midpoint(l, r) }
            marks[bodyMoments[number - 1].position] = BodyMarks(joints: found, grip: point(item["empunadura"]),
                                                               clubHead: point(item["cabeza_palo"]))
        }
        // Sin el cuerpo de la preparación no hay estatura ni medidas: mejor el plan B.
        guard let address = marks[.address], address.joints.count >= 8 else { return .failure(.noBody) }
        return .success(marks)
    }

    // MARK: Resultado

    /// Lo que necesita el análisis de la app: la pose (con articulaciones solo en las 7 posiciones),
    /// las posiciones y lo del palo.
    public struct Analysis: Sendable, Equatable {
        public var frames: [PoseFrame]
        public var phases: SwingPhases
        public var clubHeadAtAddress: Point2D?
        public var clubHeadAtTakeaway: Point2D?
        public var clubLineAtMidBackswing: ClubLine?
        public var clubLineAtTransition: ClubLine?
        public var impactTime: Double
    }

    public static func result(_ request: PositionsRequest, chosen: ChosenPositions,
                              marks: [SwingPosition: BodyMarks]) -> Analysis {
        var frames = request.frameTimes.map { PoseFrame(time: $0, joints: [:]) }
        var positions: [DetectedPosition] = []
        for (key, position) in bodyMoments {
            let index = chosen.frameIndex[key]!
            frames[index].joints = marks[position]?.joints ?? [:]
            positions.append(DetectedPosition(position: position, frameIndex: index, time: request.frameTimes[index],
                                              usedAlternative: false,
                                              isDoubtful: (chosen.confidence[key] ?? 0) < ShotCheck.minimumConfidence))
        }
        let start = chosen.frameIndex["inicio_subida"]!
        let phases = SwingPhases(backswingStartFrame: start, backswingStartTime: request.frameTimes[start], positions: positions)
        func line(_ position: SwingPosition) -> ClubLine? {
            guard let grip = marks[position]?.grip, let head = marks[position]?.clubHead else { return nil }
            return ClubLine(grip: grip, head: head)
        }
        return Analysis(frames: frames, phases: phases,
                      clubHeadAtAddress: marks[.address]?.clubHead, clubHeadAtTakeaway: marks[.takeaway]?.clubHead,
                      clubLineAtMidBackswing: line(.midBackswing), clubLineAtTransition: line(.transition),
                      impactTime: chosen.times["impacto"]!)
    }

    // MARK: Cuerpo de las peticiones

    static func body(text: String, images: [(caption: String, jpeg: Data)], instructions: String, schema: String) throws -> Data {
        var input: [[String: Any]] = [["type": "text", "text": text]]
        for image in images {
            input.append(["type": "text", "text": image.caption])
            input.append(["type": "image", "mime_type": "image/jpeg", "data": image.jpeg.base64EncodedString(), "resolution": "high"])
        }
        let body: [String: Any] = [
            "model": ShotCheck.model,
            "system_instruction": instructions,
            "input": input,
            "generation_config": ["seed": ShotCheck.seed, "thinking_level": ShotCheck.thinkingLevel],
            "response_format": ["type": "text", "mime_type": "application/json",
                                "schema": try JSONSerialization.jsonObject(with: Data(schema.utf8))],
            "store": false,
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
}
