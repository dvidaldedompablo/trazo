import Foundation

/// Verificador de golpes con un modelo externo con visión (docs/10, Fase 4, primera función).
///
/// Por qué existe: el corte automático decide solo con el sonido, y en un vídeo con música se
/// equivoca (línea base del 22-11-2026: acierta 1 de 3 vídeos; el modelo, 3 de 3). Con el permiso
/// del usuario, la app manda al modelo una hoja de fotogramas alrededor de cada sonido fuerte y le
/// pregunta si ese sonido es el palo golpeando la bola.
///
/// Aquí solo está la lógica pura: qué sonidos se mandan, qué fotogramas lleva cada hoja, el texto y
/// el esquema de la petición, y cómo se valida la respuesta y se decide con ella. El modelo propone y
/// el código decide (docs/10, regla 2): lo que no valida se ignora y ese sonido se queda como lo
/// dejó el corte automático. Las imágenes y la llamada de red están en la app (`ShotChecker`); el
/// laboratorio del PC usa esta misma lógica a través de GolfLab para medirla antes.
public enum ShotCheck {
    // MARK: Ajustes de la petición (los del preetiquetado medido en la línea base)

    /// Modelo gratuito de Google AI Studio (el usuario no quiere ningún gasto).
    public static let model = "gemini-3.6-flash"
    /// Revisión de la API Interactions con la que se escribió la petición.
    public static let apiRevision = "2026-05-20"
    public static let endpoint = "https://generativelanguage.googleapis.com/v1beta/interactions"
    /// Se mandan como mucho los 12 sonidos más fuertes. En la línea base el golpe real era el 5.º
    /// más fuerte de 15 en una story con música; en las otras, el 1.º.
    public static let maximumCandidates = 12
    /// Hojas por petición: con 12 sonidos, 2 peticiones (el plan gratuito da unas 20 al día).
    public static let sheetsPerRequest = 6
    /// Fotogramas por hoja, repartidos de 0,6 s antes a 0,2 s después del sonido: así entran la
    /// bajada (de 0,1 a 0,6 s) y el impacto.
    public static let framesPerSheet = 12
    public static let secondsBeforeSound = 0.6
    public static let secondsAfterSound = 0.2
    /// Lado largo máximo de cada hoja, en píxeles.
    public static let maximumSheetSide = 1536.0
    /// Estos modelos ya no admiten temperatura: semilla y razonamiento fijos (docs/10, regla 2).
    public static let seed = 7
    public static let thinkingLevel = "medium"
    /// Por debajo de esta confianza, la respuesta cuenta como "no sé".
    public static let minimumConfidence = 0.5

    // MARK: Plan

    /// Una hoja: los fotogramas de alrededor de un sonido.
    public struct Sheet: Sendable, Equatable {
        /// "P1", "P2"... único en todo el plan.
        public var name: String
        public var soundTime: Double
        /// Instantes de los fotogramas (s), en orden.
        public var frameTimes: [Double]
        /// Número impreso en cada fotograma, único dentro de su petición.
        public var numbers: [Int]

        /// El número del fotograma más cercano al sonido.
        public var numberNearestSound: Int? {
            frameTimes.indices.min { abs(frameTimes[$0] - soundTime) < abs(frameTimes[$1] - soundTime) }.map { numbers[$0] }
        }

        /// Texto que acompaña a la imagen de la hoja.
        public var caption: String {
            "Hoja \(name): alrededor de un sonido fuerte en \(String(format: "%.3f", soundTime)) s"
        }
    }

    /// Una petición al modelo: varias hojas y el texto que las explica.
    public struct Request: Sendable, Equatable {
        public var sheets: [Sheet]

        public var text: String {
            let list = sheets.map { sheet in
                "- \(sheet.name): alrededor de un sonido fuerte en \(String(format: "%.3f", sheet.soundTime)) s"
                    + (sheet.numberNearestSound.map { " (el fotograma más cercano al sonido es el \($0))." } ?? ".")
            }
            return "Hojas de fotogramas seguidos de tramos concretos del mismo vídeo. Los números de fotograma son únicos en todo el mensaje.\n"
                + list.joined(separator: "\n")
                + "\nPara cada hoja: hay_swing, sonido_es_impacto y confianza."
        }
    }

    /// Los sonidos que se mandan: los más fuertes, en orden de tiempo.
    public static func candidates(_ impacts: [Impact]) -> [Impact] {
        Array(impacts.sorted { $0.strength > $1.strength }.prefix(maximumCandidates)).sorted { $0.time < $1.time }
    }

    /// Una hoja por candidato, repartidas en peticiones de `sheetsPerRequest`.
    public static func plan(for impacts: [Impact], duration: Double) -> [Request] {
        let sheets = candidates(impacts).enumerated().map { k, impact in
            let start = max(0, impact.time - secondsBeforeSound)
            let end = min(duration, impact.time + secondsAfterSound)
            let times = (0..<framesPerSheet).map { i in
                framesPerSheet == 1 ? start : start + Double(i) * (end - start) / Double(framesPerSheet - 1)
            }
            return Sheet(name: "P\(k + 1)", soundTime: impact.time, frameTimes: times, numbers: [])
        }
        return stride(from: 0, to: sheets.count, by: sheetsPerRequest).map { first in
            var batch = Array(sheets[first..<min(first + sheetsPerRequest, sheets.count)])
            var next = 1
            for k in batch.indices {
                batch[k].numbers = Array(next..<(next + batch[k].frameTimes.count))
                next += batch[k].frameTimes.count
            }
            return Request(sheets: batch)
        }
    }

    /// Cómo se dibuja una hoja: columnas y filas (más columnas si el vídeo es vertical) y el tamaño
    /// de cada fotograma para que la hoja no pase de `maximumSheetSide`.
    public struct SheetLayout: Sendable, Equatable {
        public var columns: Int
        public var rows: Int
        public var cellWidth: Int
        public var cellHeight: Int
        public var gap: Int
        public var header: Int
        public var width: Int { columns * (cellWidth + gap) + gap }
        public var height: Int { header + rows * (cellHeight + gap) + gap }
    }

    public static func layout(frameWidth: Int, frameHeight: Int, count: Int = framesPerSheet) -> SheetLayout {
        let n = max(count, 1)
        let columns = max(2, min(n, Int((Double(n) * Double(frameHeight) / Double(max(frameWidth, 1))).squareRoot().rounded())))
        let rows = (n + columns - 1) / columns
        let gap = 6, header = 40
        let scale = min((maximumSheetSide - Double(gap * (columns + 1))) / Double(columns * frameWidth),
                        (maximumSheetSide - Double(header) - Double(gap * (rows + 1))) / Double(rows * frameHeight))
        return SheetLayout(columns: columns, rows: rows, cellWidth: Int(Double(frameWidth) * scale),
                           cellHeight: Int(Double(frameHeight) * scale), gap: gap, header: header)
    }

    // MARK: Texto y esquema

    public static let instructions = """
    Eres un analista de swing de golf. Te paso hojas con fotogramas de un vídeo, en orden de tiempo. Cada hoja enseña el tramo alrededor de un sonido fuerte de la grabación, desde 0,6 s antes hasta 0,2 s después. Cada fotograma lleva su número arriba a la izquierda (en un recuadro negro) y su instante en segundos abajo a la izquierda.

    Para cada hoja di:
    - hay_swing: si en esa hoja se ve a un golfista haciendo un swing que golpea la bola (si, no o no_se).
    - sonido_es_impacto: si el sonido coincide con el impacto del palo con la bola, es decir, si el palo toca la bola en los fotogramas cercanos al sonido (si, no o no_se). Un golpe de la música, una voz, un aplauso, el golpe de otro jugador o un ruido mientras el jugador está quieto, se prepara o camina es "no".
    - confianza: de 0 a 1.

    Si dudas, pon no_se o una confianza baja; no inventes. Es mejor decir no_se que adivinar.
    """

    /// Esquema JSON de la respuesta (lo que la API obliga a cumplir).
    public static let schemaJSON = """
    {"type":"object","properties":{"hojas":{"type":"array","items":{"type":"object","properties":{\
    "hoja":{"type":"string"},\
    "hay_swing":{"type":"string","enum":["si","no","no_se"]},\
    "sonido_es_impacto":{"type":"string","enum":["si","no","no_se"]},\
    "confianza":{"type":"number"}},\
    "required":["hoja","hay_swing","sonido_es_impacto","confianza"]}}},"required":["hojas"]}
    """

    /// El cuerpo de la petición a la API Interactions, con una imagen JPEG por hoja (en el orden de
    /// `request.sheets`). `store: false`: que Google no guarde la conversación.
    public static func requestBody(_ request: Request, sheetJPEGs: [Data], resolution: String = "high") throws -> Data {
        precondition(sheetJPEGs.count == request.sheets.count, "Una imagen por hoja")
        var input: [[String: Any]] = [["type": "text", "text": request.text]]
        for (sheet, jpeg) in zip(request.sheets, sheetJPEGs) {
            input.append(["type": "text", "text": sheet.caption])
            input.append(["type": "image", "mime_type": "image/jpeg", "data": jpeg.base64EncodedString(),
                          "resolution": resolution])
        }
        let schema = try JSONSerialization.jsonObject(with: Data(schemaJSON.utf8))
        let body: [String: Any] = [
            "model": model,
            "system_instruction": instructions,
            "input": input,
            "generation_config": ["seed": seed, "thinking_level": thinkingLevel],
            "response_format": ["type": "text", "mime_type": "application/json", "schema": schema],
            "store": false,
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// El texto que contesta el modelo dentro de la respuesta de la API (o `nil` si no lo hay).
    public static func outputText(fromResponse data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let text = object["output_text"] as? String { return text }
        let parts = (object["steps"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "model_output" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        return parts.isEmpty ? nil : parts.joined()
    }

    // MARK: Respuesta

    public enum Answer: String, Sendable, Codable {
        case yes = "si"
        case no
        case unsure = "no_se"
    }

    /// Lo que dijo el modelo de un sonido, ya validado.
    public struct Verdict: Sendable, Equatable {
        public var soundTime: Double
        public var hasSwing: Answer
        public var soundIsImpact: Answer
        public var confidence: Double

        public init(soundTime: Double, hasSwing: Answer, soundIsImpact: Answer, confidence: Double) {
            self.soundTime = soundTime
            self.hasSwing = hasSwing
            self.soundIsImpact = soundIsImpact
            self.confidence = confidence
        }
    }

    /// Valida el JSON que contestó el modelo para una petición. Solo valen hojas que se mandaron, con
    /// respuestas conocidas y confianza de 0 a 1; lo demás se descarta y se cuenta en `warnings`.
    public static func parse(_ text: String, for request: Request) -> (verdicts: [Verdict], warnings: [String]) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let sheets = object["hojas"] as? [[String: Any]]
        else { return ([], ["La respuesta no es el JSON pedido"]) }
        let byName = Dictionary(uniqueKeysWithValues: request.sheets.map { ($0.name, $0) })
        var verdicts: [Verdict] = []
        var warnings: [String] = []
        var seen = Set<String>()
        for item in sheets {
            guard let name = item["hoja"] as? String, let sheet = byName[name] else {
                warnings.append("Hoja desconocida: \((item["hoja"] as? String) ?? "sin nombre")")
                continue
            }
            guard !seen.contains(name) else {
                warnings.append("Hoja repetida: \(name)")
                continue
            }
            guard let swing = (item["hay_swing"] as? String).flatMap(Answer.init(rawValue:)),
                  let impact = (item["sonido_es_impacto"] as? String).flatMap(Answer.init(rawValue:)),
                  // En Linux (laboratorio) JSONSerialization da Double o Int; en iOS, NSNumber, que vale para los dos.
                  let confidence = (item["confianza"] as? Double) ?? (item["confianza"] as? Int).map(Double.init),
                  (0...1).contains(confidence)
            else {
                warnings.append("Respuesta imposible para la hoja \(name)")
                continue
            }
            seen.insert(name)
            verdicts.append(Verdict(soundTime: sheet.soundTime, hasSwing: swing, soundIsImpact: impact, confidence: confidence))
        }
        return (verdicts, warnings)
    }

    // MARK: Decisión

    public enum Outcome: String, Sendable, Codable {
        /// El modelo dice que el sonido es el palo golpeando la bola.
        case confirmed
        /// El modelo dice que no.
        case rejected
        /// No contestó, dudó o la respuesta no validó: se queda como lo dejó el corte automático.
        case unknown
        /// Confirmado, pero a menos de 2 s de otro confirmado con más confianza: es el mismo swing.
        case sameSwing
    }

    public static func outcome(for soundTime: Double, in verdicts: [Verdict]) -> Outcome {
        guard let verdict = verdicts.first(where: { abs($0.soundTime - soundTime) < 1e-6 }),
              verdict.confidence >= minimumConfidence
        else { return .unknown }
        switch verdict.soundIsImpact {
        case .yes: return .confirmed
        case .no: return .rejected
        case .unsure: return .unknown
        }
    }

    /// Los clips que se proponen tras la comprobación.
    public struct CheckedProposal: Sendable, Equatable {
        public var windows: [ClipWindow]
        /// Lo que dijo el modelo de cada clip.
        public var outcomes: [Outcome]
        /// Marcado para guardar al abrir la lista.
        public var selected: [Bool]
        public var confirmedCount: Int { outcomes.filter { $0 == .confirmed }.count }
    }

    /// Junta la propuesta del corte automático con lo que dijo el modelo:
    /// - un sonido confirmado se propone (si no es demasiado corto), aunque el corte automático no
    ///   lo propusiera o dijera que no parecía una tanda de golpes;
    /// - uno descartado sigue en la lista, sin marcar, por si el usuario no está de acuerdo;
    /// - uno sin respuesta se queda como lo dejó el corte automático.
    /// Dos confirmados a menos de `ClipPlanner.minimumShotSpacing` son el mismo swing: se queda el de
    /// más confianza (y, si empatan, el que más suena).
    public static func proposal(impacts: [Impact], verdicts: [Verdict], recordingDuration: Double,
                                mode: CaptureMode) -> CheckedProposal {
        let original = ClipPlanner.propose(for: impacts, recordingDuration: recordingDuration, mode: mode)
        let originalTimes = Set(original.windows.map(\.impactTime))
        let confidence = Dictionary(verdicts.map { ($0.soundTime, $0.confidence) }, uniquingKeysWith: max)

        var confirmed = impacts.filter { outcome(for: $0.time, in: verdicts) == .confirmed }
        confirmed.sort { (confidence[$0.time] ?? 0, $0.strength) > (confidence[$1.time] ?? 0, $1.strength) }
        var kept: [Impact] = []
        for impact in confirmed where !kept.contains(where: { abs($0.time - impact.time) < ClipPlanner.minimumShotSpacing }) {
            kept.append(impact)
        }
        let keptTimes = Set(kept.map(\.time))
        let shown = impacts.filter { keptTimes.contains($0.time) || originalTimes.contains($0.time) }

        // Las ventanas se calculan con todos los impactos para que "propuesto" siga comparando con el más fuerte.
        let all = ClipPlanner.windows(for: impacts, recordingDuration: recordingDuration, mode: mode)
        let windows = all.filter { window in shown.contains { $0.time == window.impactTime } }
        var outcomes: [Outcome] = []
        var selected: [Bool] = []
        for window in windows {
            let said = outcome(for: window.impactTime, in: verdicts)
            let result: Outcome = keptTimes.contains(window.impactTime) ? .confirmed : (said == .confirmed ? .sameSwing : said)
            outcomes.append(result)
            switch result {
            case .confirmed: selected.append(!window.isTooShort)
            case .rejected, .sameSwing: selected.append(false)
            case .unknown: selected.append(original.isShotSeries && window.isSuggested)
            }
        }
        return CheckedProposal(windows: windows, outcomes: outcomes, selected: selected)
    }
}
