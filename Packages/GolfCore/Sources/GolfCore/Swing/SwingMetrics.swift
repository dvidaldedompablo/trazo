import Foundation

/// Lo que recibe nota: las 7 posiciones y el ritmo.
public enum SwingPhase: Int, Sendable, Codable, CaseIterable, Comparable {
    case address = 1, takeaway, midBackswing, top, transition, impact, finish, tempo

    public var title: String {
        switch self {
        case .tempo: "Ritmo"
        default: SwingPosition(rawValue: rawValue)!.title
        }
    }

    public static func < (a: SwingPhase, b: SwingPhase) -> Bool { a.rawValue < b.rawValue }
}

/// Las medidas de docs/04 (punto 5).
public enum MetricKind: String, Sendable, Codable, CaseIterable {
    case spineTilt, kneeFlex, armsHang, clubPlane
    case takeawayClubHead
    case midBackswingClub
    case backswingDuration, handsHeight, headAtTop
    case transitionClub
    case tiltLoss, hipToBall, headAtImpact
    case finishBalanced, finishComplete
    case tempo

    public var phase: SwingPhase {
        switch self {
        case .spineTilt, .kneeFlex, .armsHang, .clubPlane: .address
        case .takeawayClubHead: .takeaway
        case .midBackswingClub: .midBackswing
        case .backswingDuration, .handsHeight, .headAtTop: .top
        case .transitionClub: .transition
        case .tiltLoss, .hipToBall, .headAtImpact: .impact
        case .finishBalanced, .finishComplete: .finish
        case .tempo: .tempo
        }
    }

    /// Nombre en pantalla.
    public var title: String {
        switch self {
        case .spineTilt: "Inclinación"
        case .kneeFlex: "Flexión de rodilla"
        case .armsHang: "Brazos bajo los hombros"
        case .clubPlane: "Plano del palo"
        case .takeawayClubHead: "Cabeza del palo y manos"
        case .midBackswingClub: "Palo a mitad de subida"
        case .backswingDuration: "Duración de la subida"
        case .handsHeight: "Manos altas"
        case .headAtTop: "Cabeza estable"
        case .transitionClub: "Palo en la bajada"
        case .tiltLoss: "Inclinación en el impacto"
        case .hipToBall: "Cadera hacia la bola"
        case .headAtImpact: "Cabeza en el impacto"
        case .finishBalanced: "Final equilibrado"
        case .finishComplete: "Final completo"
        case .tempo: "Ritmo"
        }
    }

    public var unit: MetricUnit {
        switch self {
        case .spineTilt, .kneeFlex, .clubPlane, .midBackswingClub, .transitionClub, .tiltLoss: .degrees
        case .armsHang, .takeawayClubHead, .handsHeight: .trunkFraction
        case .backswingDuration: .seconds
        case .headAtTop, .headAtImpact, .hipToBall: .centimeters
        case .finishBalanced, .finishComplete: .yesNo
        case .tempo: .ratio
        }
    }
}

public enum MetricUnit: String, Sendable, Codable {
    case degrees, centimeters, seconds, ratio, yesNo
    /// Fracción de la longitud del tronco (cuello-centro de cadera en la preparación).
    case trunkFraction
}

/// Cómo ha salido una medida.
public enum MeasurementStatus: String, Sendable, Codable {
    case good, low, high
    /// No puntúa: solo informa (o sirve de referencia para otras medidas).
    case informative
    /// No se pudo medir (articulación tapada, palo sin marcar). Se omite y el informe lo dice.
    case unavailable
}

/// Una medida con su estado y, si toca, su fallo.
public struct MetricResult: Sendable, Equatable {
    public var kind: MetricKind
    /// Valor en la unidad de la medida; 1 o 0 para sí o no. `nil` si no se pudo medir.
    public var value: Double?
    /// Valor de referencia que acompaña a algunas medidas: la inclinación del impacto en
    /// `tiltLoss` ("pasas de A a B grados"), el plano del address en las del palo,
    /// el movimiento vertical de la cabeza (cm, negativo = sube) en `headAtImpact`.
    public var reference: Double?
    public var status: MeasurementStatus
    /// Fallo que se dice (fuera de los umbrales de fallo de su regla).
    public var fault: FaultID?
    /// Puntos que resta en la nota de su fase.
    public var penalty: Double

    public var phase: SwingPhase { kind.phase }
}

/// Lo que necesita `SwingMetrics`. Lo del palo es opcional: llega de la pantalla de revisión.
public struct SwingMetricsInput: Sendable {
    public var frames: [PoseFrame]
    public var phases: SwingPhases
    public var handedness: Handedness
    /// Estatura del jugador en cm (Ajustes): solo para pasar los píxeles a cm.
    public var heightCentimeters: Double
    /// Cabeza del palo en la preparación (la toca el usuario).
    public var clubHeadAtAddress: Point2D?
    /// Cabeza del palo en el takeaway (seguida desde la preparación o colocada por el usuario).
    public var clubHeadAtTakeaway: Point2D?
    /// Línea del palo en la mitad de subida y en la transición.
    public var clubLineAtMidBackswing: ClubLine?
    public var clubLineAtTransition: ClubLine?

    public init(frames: [PoseFrame], phases: SwingPhases, handedness: Handedness = .right,
                heightCentimeters: Double, clubHeadAtAddress: Point2D? = nil, clubHeadAtTakeaway: Point2D? = nil,
                clubLineAtMidBackswing: ClubLine? = nil, clubLineAtTransition: ClubLine? = nil) {
        self.frames = frames
        self.phases = phases
        self.handedness = handedness
        self.heightCentimeters = heightCentimeters
        self.clubHeadAtAddress = clubHeadAtAddress
        self.clubHeadAtTakeaway = clubHeadAtTakeaway
        self.clubLineAtMidBackswing = clubLineAtMidBackswing
        self.clubLineAtTransition = clubLineAtTransition
    }
}

/// La línea del palo: dos puntos sobre él (la empuñadura y otro punto, por ejemplo la cabeza).
public struct ClubLine: Sendable, Equatable, Codable {
    public var grip: Point2D
    public var head: Point2D

    public init(grip: Point2D, head: Point2D) {
        self.grip = grip
        self.head = head
    }

    /// Ángulo con la horizontal (0° a 90°).
    public var angleFromHorizontal: Double? { Geometry.angleFromHorizontal(from: grip, to: head) }
}

/// Todas las medidas y las referencias que dibujan los gráficos.
public struct SwingMeasurements: Sendable {
    public var items: [MetricResult]
    /// Píxeles por cm (aproximado). `nil` si no se pudo calcular: entonces no hay medidas en cm.
    public var scale: PixelScale?
    public var staturePixels: Double
    /// Longitud del tronco en la preparación (px).
    public var trunkLength: Double?
    /// Círculo de la cabeza en la preparación.
    public var headReference: Point2D?
    public var headRadius: Double?
    /// x de la línea de la parte de atrás de la cadera en la preparación.
    public var hipLineX: Double?
    /// Ángulo del plano del palo en la preparación (con la horizontal).
    public var clubPlaneAngle: Double?
    /// Ritmo (subida / bajada), el mismo que da `SwingPhases`.
    public var tempo: Double?

    public subscript(kind: MetricKind) -> MetricResult? { items.first { $0.kind == kind } }

    /// Medidas que no se pudieron calcular (el informe las nombra).
    public var unavailable: [MetricKind] { items.filter { $0.status == .unavailable }.map(\.kind) }
}

/// Calcula las medidas de docs/04 (punto 5) para la vista desde detrás.
/// Coordenadas de imagen con y hacia abajo; para un diestro "hacia la bola" es +x
/// (para un zurdo se multiplica por −1 con `Handedness.xSign`).
public enum SwingMetrics {
    public static func measure(_ input: SwingMetricsInput) -> SwingMeasurements {
        let hand = input.handedness
        let sign = hand.xSign
        let phases = input.phases
        func frame(_ position: SwingPosition) -> PoseFrame { input.frames[phases[position].frameIndex] }
        let address = frame(.address)

        let stature = address.staturePixels(handedness: hand)
            ?? PhaseDetector.estimateStature(input.frames, handedness: hand)
        let scale = input.heightCentimeters > 0 ? PixelScale(pixelsPerCentimeter: stature / input.heightCentimeters) : nil
        let trunk: Double? = {
            guard let neck = address[.neck], let root = address[.root] else { return nil }
            let length = neck.distance(to: root)
            return length > 0 ? length : nil
        }()
        let clubPlane: Double? = {
            guard let head = input.clubHeadAtAddress, let hands = address.hands else { return nil }
            return Geometry.angleFromHorizontal(from: head, to: hands)
        }()

        var values: [MetricKind: (value: Double?, reference: Double?)] = [:]

        // 1. Preparación.
        let tiltAtAddress = spineTilt(address)
        values[.spineTilt] = (tiltAtAddress, nil)
        values[.kneeFlex] = (kneeFlex(address, handedness: hand), nil)
        if let trunk, let hands = address.hands, let shoulder = address.first(hand.trailShoulder, hand.leadShoulder) {
            values[.armsHang] = ((hands.x - shoulder.x) * sign / trunk, nil)
        }
        values[.clubPlane] = (clubPlane, nil)

        // 2. Takeaway: distancia horizontal cabeza del palo − manos (negativa = por dentro, detrás de las manos).
        if let trunk, let head = input.clubHeadAtTakeaway, let hands = frame(.takeaway).hands {
            values[.takeawayClubHead] = ((head.x - hands.x) * sign / trunk, nil)
        }

        // 3. Mitad de subida: ángulo del palo frente al plano del address (negativo = más plano).
        let midAngle = input.clubLineAtMidBackswing?.angleFromHorizontal
        if let midAngle, let clubPlane { values[.midBackswingClub] = (midAngle - clubPlane, clubPlane) }

        // 4. Top.
        values[.backswingDuration] = (phases.backswingDuration, nil)
        let top = frame(.top)
        if let trunk, let hands = top.hands, let shoulder = shoulderLine(top, handedness: hand) {
            values[.handsHeight] = ((shoulder - hands.y) / trunk, nil)
        }
        if let scale, let start = address.head, let now = top.head {
            values[.headAtTop] = (scale.centimeters(fromPixels: start.distance(to: now)), nil)
        }

        // 5. Transición: palo en la bajada frente al plano (positivo = más vertical). Referencia: el de 3.
        if let angle = input.clubLineAtTransition?.angleFromHorizontal, let clubPlane {
            values[.transitionClub] = (angle - clubPlane, midAngle)
        }

        // 6. Impacto.
        let impact = frame(.impact)
        let tiltAtImpact = spineTilt(impact)
        if let a = tiltAtAddress, let b = tiltAtImpact { values[.tiltLoss] = (a - b, b) }
        if let scale, let rootStart = address[.root], let rootNow = impact[.root] {
            // La línea de la parte de atrás de la cadera se mueve igual que el centro de la cadera.
            values[.hipToBall] = (scale.centimeters(fromPixels: (rootNow.x - rootStart.x) * sign), nil)
        }
        if let scale, let start = address.head, let now = impact.head {
            values[.headAtImpact] = (scale.centimeters(fromPixels: start.distance(to: now)),
                                     scale.centimeters(fromPixels: now.y - start.y))
        }

        // 7. Final.
        values[.finishBalanced] = (finishBalanced(input.frames, from: phases[.finish].frameIndex, stature: stature), nil)
        let finish = frame(.finish)
        if let hands = finish.hands, let shoulder = finish[hand.leadShoulder] {
            values[.finishComplete] = (hands.y < shoulder.y ? 1 : 0, nil)
        }

        // R. Ritmo.
        values[.tempo] = (phases.tempo, nil)

        let items = MetricKind.allCases.map { kind in
            evaluate(kind, value: values[kind]?.value, reference: values[kind]?.reference)
        }
        var result = SwingMeasurements(items: items, scale: scale, staturePixels: stature, trunkLength: trunk)
        result.headReference = address.head
        result.headRadius = SwingRules.headCircleRadius * stature
        result.hipLineX = address[.root].map { $0.x - sign * SwingRules.backOfHipOffset * stature }
        result.clubPlaneAngle = clubPlane
        result.tempo = phases.tempo
        return result
    }

    /// Aplica la regla de la medida: estado, fallo y penalización.
    public static func evaluate(_ kind: MetricKind, value: Double?, reference: Double? = nil) -> MetricResult {
        let rule = SwingRules.rule(for: kind)
        guard let value, value.isFinite else {
            return MetricResult(kind: kind, value: nil, reference: reference, status: .unavailable, fault: nil, penalty: 0)
        }
        guard let good = rule.good else {
            return MetricResult(kind: kind, value: value, reference: reference, status: .informative, fault: nil, penalty: 0)
        }
        var status = MeasurementStatus.good
        var fault: FaultID?
        var penalty = 0.0
        if value < good.lowerBound {
            status = .low
            penalty = (good.lowerBound - value) * rule.penaltyPerUnit
            if let limit = rule.faultBelow, value < limit { fault = rule.lowFault }
        } else if value > good.upperBound {
            status = .high
            penalty = (value - good.upperBound) * rule.penaltyPerUnit
            if let limit = rule.faultAbove, value > limit { fault = rule.highFault }
        }
        return MetricResult(kind: kind, value: value, reference: reference, status: status, fault: fault, penalty: penalty)
    }

    /// Inclinación: ángulo entre centro de cadera→cuello y la vertical.
    static func spineTilt(_ frame: PoseFrame) -> Double? {
        guard let root = frame[.root], let neck = frame[.neck] else { return nil }
        return Geometry.angleFromVertical(from: root, to: neck)
    }

    /// Flexión de rodilla: 180° − ángulo cadera-rodilla-tobillo, con el lado de atrás si se ve.
    static func kneeFlex(_ frame: PoseFrame, handedness: Handedness) -> Double? {
        let sides = [(handedness.trailHip, handedness.trailKnee, handedness.trailAnkle),
                     (handedness.leadHip, handedness.leadKnee, handedness.leadAnkle)]
        for (hip, knee, ankle) in sides {
            if let h = frame[hip], let k = frame[knee], let a = frame[ankle], let angle = Geometry.angle(at: k, h, a) {
                return 180 - angle
            }
        }
        return nil
    }

    /// Altura (y) de los hombros: media de los dos, o el que se vea.
    static func shoulderLine(_ frame: PoseFrame, handedness: Handedness) -> Double? {
        switch (frame[handedness.leadShoulder], frame[handedness.trailShoulder]) {
        case let (a?, b?): (a.y + b.y) / 2
        case let (a?, nil): a.y
        case let (nil, b?): b.y
        case (nil, nil): nil
        }
    }

    /// Final equilibrado: cabeza, manos y cadera casi quietas durante 0,8 s desde el final.
    /// `nil` si el vídeo se acaba antes (no se puede saber).
    static func finishBalanced(_ frames: [PoseFrame], from start: Int, stature: Double) -> Double? {
        guard start < frames.count else { return nil }
        let endTime = frames[start].time + SwingRules.finishBalanceDuration
        guard let end = frames.lastIndex(where: { $0.time <= endTime + 1e-9 }), frames[end].time >= endTime - 1e-6
        else { return nil }
        let tolerance = SwingRules.finishBalanceTolerance * stature
        let parts: [(PoseFrame) -> Point2D?] = [{ $0.head }, { $0.hands }, { $0[.root] }]
        for part in parts {
            guard let origin = part(frames[start]) else { continue }
            for i in start...end {
                if let point = part(frames[i]), point.distance(to: origin) > tolerance { return 0 }
            }
        }
        return 1
    }
}
