import Foundation

/// Las 7 posiciones del swing, en orden.
public enum SwingPosition: Int, Sendable, Codable, CaseIterable, Comparable {
    case address = 1, takeaway, midBackswing, top, transition, impact, finish

    /// Nombre en pantalla.
    public var title: String {
        switch self {
        case .address: "Preparación"
        case .takeaway: "Takeaway"
        case .midBackswing: "Mitad de subida"
        case .top: "Top"
        case .transition: "Transición"
        case .impact: "Impacto"
        case .finish: "Final"
        }
    }

    public static func < (a: SwingPosition, b: SwingPosition) -> Bool { a.rawValue < b.rawValue }
}

/// Una posición encontrada.
public struct DetectedPosition: Sendable, Equatable {
    public var position: SwingPosition
    public var frameIndex: Int
    public var time: Double
    /// Se usó la regla alternativa de docs/04 (la principal no se pudo aplicar).
    public var usedAlternative: Bool
    /// No respeta el orden B < 2 < 3 < … < 7: la pantalla de revisión la marca para que se compruebe.
    public var isDoubtful: Bool
}

/// Resultado del detector: el inicio de la subida (B), las 7 posiciones y el ritmo.
public struct SwingPhases: Sendable, Equatable {
    public var backswingStartFrame: Int
    public var backswingStartTime: Double
    /// Las 7 posiciones, en orden.
    public var positions: [DetectedPosition]

    public subscript(position: SwingPosition) -> DetectedPosition { positions[position.rawValue - 1] }

    /// Subida = top − B (s).
    public var backswingDuration: Double { self[.top].time - backswingStartTime }
    /// Bajada = impacto − top (s).
    public var downswingDuration: Double { self[.impact].time - self[.top].time }
    /// Ritmo = subida / bajada. Los profesionales rondan 3 : 1.
    public var tempo: Double? { downswingDuration > 0 ? backswingDuration / downswingDuration : nil }
    /// Se cumple B < 2 < 3 < 4 < 5 < 6 < 7.
    public var isOrdered: Bool { !positions.contains { $0.isDoubtful } }
}

/// Encuentra las 7 posiciones a partir de la pose de cada fotograma y del instante del impacto (docs/04, punto 3).
///
/// Casi todo sale de la trayectoria de las manos (punto medio de las muñecas), que es lo que
/// Vision ve con más seguridad desde detrás. Distancias en fracción de la estatura en píxeles,
/// así las reglas valen igual de cerca que de lejos.
public enum PhaseDetector {
    /// - Parameters:
    ///   - frames: pose de cada fotograma, en orden y ya suavizada.
    ///   - impactTime: instante del impacto por el sonido (s, en la misma escala que `frames`).
    ///     Sin él, se usa la alternativa: manos en su punto más bajo tras el top.
    /// - Returns: `nil` si no hay swing (las manos no llegan a moverse) o faltan las manos.
    public static func detect(frames: [PoseFrame], impactTime: Double?, handedness: Handedness = .right) -> SwingPhases? {
        let n = frames.count
        guard n >= 10 else { return nil }
        let times = frames.map(\.time)
        guard let hands = completeHands(frames) else { return nil }
        let stature = estimateStature(frames, handedness: handedness)
        guard stature > 0 else { return nil }
        let speeds = handSpeeds(hands, times: times)

        // Impacto (sonido) y top (manos en su punto más alto antes del impacto).
        var impactIndex: Int
        var impactIsAlternative = false
        if let impactTime {
            impactIndex = nearestIndex(times, to: impactTime)
        } else {
            // Sin sonido: el momento de más velocidad de las manos está en la bajada, cerca del impacto.
            impactIndex = speeds.indices.max { speeds[$0] < speeds[$1] } ?? n - 1
            impactIsAlternative = true
        }
        guard impactIndex >= 2 else { return nil }
        let top = (0..<impactIndex).min { hands[$0].y < hands[$1].y }!
        if impactIsAlternative {
            // Manos en su punto más bajo tras el top (y crece hacia abajo).
            let limit = min(n - 1, nearestIndex(times, to: times[top] + SwingRules.impactSearchAfterTop))
            if limit > top { impactIndex = ((top + 1)...limit).max { hands[$0].y < hands[$1].y }! }
        }

        // Inicio de la subida (B): referencia de las manos en el último tramo quieto antes del top.
        let addressWindow = framesIn(SwingRules.addressStillDuration, times: times)
        let stillTolerance = SwingRules.stillTolerance * stature
        var restIndex: Int?
        if addressWindow < top {
            for i in stride(from: top - 1, through: addressWindow, by: -1)
            where isStill(hands, from: i - addressWindow, to: i, tolerance: stillTolerance) {
                restIndex = i
                break
            }
        }
        let reference: Point2D
        if let restIndex {
            reference = mean(hands[(restIndex - addressWindow)...restIndex])
        } else {
            reference = hands[0]
        }
        let startDistance = SwingRules.backswingStartDistance * stature
        let keep = SwingRules.backswingKeepsMovingFrames
        var backswingStart: Int?
        for i in (restIndex ?? 0)..<top {
            let d = hands[i].distance(to: reference)
            guard d > startDistance else { continue }
            // "…y siguen alejándose": la distancia no baja en los fotogramas siguientes.
            var keepsMoving = true
            var last = d
            for k in 1...keep where i + k < n {
                let next = hands[i + k].distance(to: reference)
                if next < last { keepsMoving = false; break }
                last = next
            }
            if keepsMoving { backswingStart = i; break }
        }
        guard let b = backswingStart, b < top else { return nil }

        // 1. Preparación: último fotograma antes de B con las manos quietas al menos 0,3 s.
        var address: Int?
        if addressWindow < b {
            for i in stride(from: b - 1, through: addressWindow, by: -1)
            where isStill(hands, from: i - addressWindow, to: i, tolerance: stillTolerance) {
                address = i
                break
            }
        }
        let addressPosition = address.map { position(.address, $0, times) }
            ?? position(.address, nearestIndex(times, to: times[b] - SwingRules.addressFallbackOffset), times, alternative: true)

        // 2. Takeaway: el 22 % del camino de las manos entre B y el top.
        let path = cumulativePath(hands, from: b, to: top)
        let takeaway = indexAtPathFraction(path, from: b, fraction: SwingRules.takeawayPathFraction)

        // 3. Mitad de subida: brazo de delante paralelo al suelo entre 2 y el top.
        let armLength = leadArmLength(frames[addressPosition.frameIndex], handedness: handedness)
        let midBackswingPosition: DetectedPosition
        if let mid = parallelArmIndex(frames, in: (takeaway + 1)..<top, handedness: handedness, armLength: armLength) {
            midBackswingPosition = position(.midBackswing, mid, times)
        } else {
            let mid = indexAtPathFraction(path, from: b, fraction: SwingRules.midBackswingFallbackFraction)
            midBackswingPosition = position(.midBackswing, mid, times, alternative: true)
        }

        // 5. Transición: brazo de delante paralelo al suelo en la bajada.
        let transitionPosition: DetectedPosition
        if top + 1 < impactIndex,
           let transition = parallelArmIndex(frames, in: (top + 1)..<impactIndex, handedness: handedness, armLength: armLength) {
            transitionPosition = position(.transition, transition, times)
        } else {
            // Alternativa: manos a la altura que tenían en 3.
            let height = hands[midBackswingPosition.frameIndex].y
            let transition = ((top + 1)..<max(top + 1, impactIndex)).first { hands[$0].y >= height } ?? min(top + 1, n - 1)
            transitionPosition = position(.transition, transition, times, alternative: true)
        }

        // 7. Final: primer fotograma tras el impacto con las manos quietas 0,4 s.
        let finishWindow = framesIn(SwingRules.finishStillDuration, times: times)
        let finishTolerance = SwingRules.finishStillTolerance * stature
        let finishPosition: DetectedPosition
        if let finish = ((impactIndex + 1)..<max(impactIndex + 1, n - finishWindow)).first(where: {
            isStill(hands, from: $0, to: $0 + finishWindow, tolerance: finishTolerance)
        }) {
            finishPosition = position(.finish, finish, times)
        } else {
            let fallback = nearestIndex(times, to: times[impactIndex] + SwingRules.finishFallbackOffset)
            finishPosition = position(.finish, fallback, times, alternative: true)
        }

        var positions = [
            addressPosition,
            position(.takeaway, takeaway, times),
            midBackswingPosition,
            position(.top, top, times),
            transitionPosition,
            position(.impact, impactIndex, times, alternative: impactIsAlternative),
            finishPosition,
        ]
        // Comprobación del orden B < 2 < 3 < 4 < 5 < 6 < 7 (la preparación va antes de B).
        if positions[0].frameIndex >= b { positions[0].isDoubtful = true }
        if positions[1].frameIndex <= b { positions[1].isDoubtful = true }
        for i in 1..<positions.count where positions[i].frameIndex <= positions[i - 1].frameIndex {
            positions[i].isDoubtful = true
            positions[i - 1].isDoubtful = true
        }
        return SwingPhases(backswingStartFrame: b, backswingStartTime: times[b], positions: positions)
    }

    // MARK: Ayudantes

    private static func position(_ position: SwingPosition, _ index: Int, _ times: [Double],
                                 alternative: Bool = false) -> DetectedPosition {
        DetectedPosition(position: position, frameIndex: index, time: times[index],
                         usedAlternative: alternative, isDoubtful: false)
    }

    /// Las manos de todos los fotogramas: los huecos cortos se interpolan y los largos se rellenan
    /// con la última posición conocida. `nil` si no se ven las manos en ningún fotograma.
    static func completeHands(_ frames: [PoseFrame]) -> [Point2D]? {
        let filled = Smoothing.fillGaps(frames.map(\.hands), maxGap: 4)
        guard let firstKnown = filled.first(where: { $0 != nil }) ?? nil else { return nil }
        var last = firstKnown
        return filled.map { point in
            if let point { last = point }
            return last
        }
    }

    /// Estatura en píxeles: mediana de los primeros fotogramas (la preparación) en que se ve la cadena.
    /// Si no se ve, una estimación con la altura de lo que se ve del cuerpo.
    static func estimateStature(_ frames: [PoseFrame], handedness: Handedness) -> Double {
        let values = frames.prefix(30).compactMap { $0.staturePixels(handedness: handedness) }
        if !values.isEmpty { return LinearAlgebra.median(values) }
        let ys = frames.first?.joints.values.map(\.y) ?? []
        guard let low = ys.min(), let high = ys.max() else { return 0 }
        return (high - low) * 1.1
    }

    /// Velocidad de las manos (px/s) con diferencias centradas.
    static func handSpeeds(_ hands: [Point2D], times: [Double]) -> [Double] {
        hands.indices.map { i in
            let a = max(i - 1, 0)
            let b = min(i + 1, hands.count - 1)
            let dt = times[b] - times[a]
            return dt > 0 ? hands[b].distance(to: hands[a]) / dt : 0
        }
    }

    static func nearestIndex(_ times: [Double], to time: Double) -> Int {
        times.indices.min { abs(times[$0] - time) < abs(times[$1] - time) } ?? 0
    }

    /// Fotogramas que caben en `duration` segundos (con el paso medio entre fotogramas).
    static func framesIn(_ duration: Double, times: [Double]) -> Int {
        guard times.count > 1 else { return 1 }
        let step = (times.last! - times.first!) / Double(times.count - 1)
        return max(Int((duration / max(step, 1e-9)).rounded()), 1)
    }

    /// Las manos no se separan de su media más de `tolerance` entre `from` y `to` (incluidos).
    static func isStill(_ hands: [Point2D], from: Int, to: Int, tolerance: Double) -> Bool {
        guard from >= 0, to < hands.count, from <= to else { return false }
        let center = mean(hands[from...to])
        return hands[from...to].allSatisfy { $0.distance(to: center) <= tolerance }
    }

    static func mean(_ points: ArraySlice<Point2D>) -> Point2D {
        points.reduce(Point2D.zero, +) / Double(max(points.count, 1))
    }

    /// Camino recorrido por las manos desde `from` hasta cada fotograma hasta `to`.
    static func cumulativePath(_ hands: [Point2D], from: Int, to: Int) -> [Double] {
        var path = [0.0]
        if to > from {
            for i in (from + 1)...to { path.append(path.last! + hands[i].distance(to: hands[i - 1])) }
        }
        return path
    }

    /// Primer fotograma en que el camino recorrido llega a `fraction` del total.
    static func indexAtPathFraction(_ path: [Double], from: Int, fraction: Double) -> Int {
        let target = fraction * (path.last ?? 0)
        let offset = path.firstIndex { $0 >= target } ?? (path.count - 1)
        return from + offset
    }

    /// Longitud del brazo de delante (hombro-muñeca) en la preparación, en px.
    static func leadArmLength(_ frame: PoseFrame, handedness: Handedness) -> Double? {
        guard let shoulder = frame[handedness.leadShoulder], let wrist = frame[handedness.leadWrist] else { return nil }
        let length = shoulder.distance(to: wrist)
        return length > 0 ? length : nil
    }

    /// Fotograma del intervalo en que el brazo de delante está más cerca de la horizontal,
    /// si lo está con ±10° de margen.
    ///
    /// Desde detrás, en esas posiciones el brazo apunta en parte hacia la cámara y en la imagen
    /// se ve acortado: su ángulo en la imagen engaña. Por eso no se mide ese ángulo, sino la
    /// diferencia de altura entre hombro y muñeca frente a la longitud real del brazo (la de la
    /// preparación, cuando cuelga de frente): sen(ángulo) = diferencia de altura / longitud.
    static func parallelArmIndex(_ frames: [PoseFrame], in range: Range<Int>, handedness: Handedness,
                                 armLength: Double?) -> Int? {
        guard let armLength, !range.isEmpty else { return nil }
        var best: (index: Int, angle: Double)?
        for i in range {
            guard let shoulder = frames[i][handedness.leadShoulder], let wrist = frames[i][handedness.leadWrist] else { continue }
            let ratio = min(abs(wrist.y - shoulder.y) / armLength, 1)
            let angle = Geometry.degrees(asin(ratio))
            if best == nil || angle < best!.angle { best = (i, angle) }
        }
        guard let best, best.angle <= SwingRules.armParallelTolerance else { return nil }
        return best.index
    }
}
