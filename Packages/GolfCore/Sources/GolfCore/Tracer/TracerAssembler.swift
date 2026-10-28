import Foundation

/// De dónde sale un punto de la bola (el modo diagnóstico los pinta de colores distintos).
public enum PointSource: String, Sendable, Codable, CaseIterable {
    case vision
    case blob
    /// Toque del usuario (punto fijo).
    case tap
}

/// Un punto de la bola con su origen.
public struct SourcedSample: Sendable, Codable, Hashable {
    public var sample: TrajectorySample
    public var source: PointSource

    public init(_ sample: TrajectorySample, source: PointSource) {
        self.sample = sample
        self.source = source
    }
}

/// Un punto tras el ajuste: si se usó o se descartó como atípico.
public struct AssembledPoint: Sendable, Codable, Hashable {
    public var time: Double
    public var point: Point2D
    public var source: PointSource
    public var isOutlier: Bool
}

/// Lo que hace falta para montar el vuelo.
public struct TracerInput: Sendable {
    /// Bola antes del impacto (la salida), en píxeles de la imagen.
    public var ball: Point2D
    public var imageWidth: Double
    public var imageHeight: Double
    /// Puntos de Vision, de BlobTracker y toques, con el tiempo desde el impacto.
    public var points: [SourcedSample]
    /// Horizonte (px). Sin él, el 44 % de la altura.
    public var horizonY: Double?
    /// Hacia dónde sale la bola si no hay puntos (punto de fuga de la línea del golpe).
    public var aimPoint: Point2D?
    public var club: ClubCategory
    public var handedness: Handedness

    public init(ball: Point2D, imageWidth: Double, imageHeight: Double, points: [SourcedSample], horizonY: Double? = nil,
                aimPoint: Point2D? = nil, club: ClubCategory = .longIrons, handedness: Handedness = .right) {
        self.ball = ball
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.points = points
        self.horizonY = horizonY
        self.aimPoint = aimPoint
        self.club = club
        self.handedness = handedness
    }
}

/// El vuelo montado: la curva, la confianza y, si hace falta, el aviso de pérdida.
public struct TracerOutcome: Sendable, Codable, Equatable {
    public var curve: TracerCurve
    /// De 0 a 1 (docs/03, paso 5).
    public var confidence: Double
    /// Hasta qué instante (s desde el impacto) se ha seguido la bola con puntos buenos.
    public var trackedDuration: Double
    /// Distancia media (px) de los puntos buenos a la curva ajustada; `nil` sin ajuste.
    public var meanError: Double?
    /// Hay que pasar por "Ajusta el vuelo": se siguió menos de 0,5 s o la confianza es baja.
    public var needsReview: Bool
    /// Para el aviso "Perdí la bola a los X s" (solo si `needsReview`).
    public var lostAt: Double?
    /// Todos los puntos, con su origen y si se descartaron.
    public var points: [AssembledPoint]
    /// La curva sale de lo visto (y no solo de la propuesta inicial).
    public var usesObservations: Bool
}

/// El montaje y el ajuste (para seguir con un toque de refuerzo).
public struct TracerAssembly: Sendable {
    public var outcome: TracerOutcome
    public var fit: TrajectoryFitResult?

    /// Velocidad de la bola en un instante (px/s): la del ajuste dentro de lo visto y, si no, la de la curva.
    /// Con ella arranca BlobTracker desde un toque (docs/03, paso 4 bis).
    public func velocity(at time: Double) -> Point2D {
        if let fit, let segment = fit.segments.min(by: { abs(($0.start + $0.end) / 2 - time) < abs(($1.start + $1.end) / 2 - time) }) {
            return segment.motion.velocity(at: time)
        }
        let flight = outcome.curve.makeFlight()
        let dt = 1.0 / 120
        return (flight.ballPosition(at: time + dt) - flight.ballPosition(at: time - dt)) / (2 * dt)
    }
}

/// Monta el vuelo (docs/03, paso 5; clave 5 de la guía):
/// 1. Junta los puntos de Vision, de BlobTracker y los toques.
/// 2. Quita atípicos por tramos con `TrajectoryFit` (los toques nunca se quitan).
/// 3. Calcula la confianza con los puntos buenos, el tiempo cubierto y el error medio, y comprueba que la
///    bola sube al principio.
/// 4. Completa el vuelo con `TracerCurve`: lo visto (dirección, vértice si se ve, caída si se puede
///    prolongar hasta el horizonte) más los valores típicos del palo. Sin puntos útiles, la propuesta inicial.
public enum TracerAssembler {
    public static func assemble(_ input: TracerInput, options: TrajectoryFitOptions = .init()) -> TracerAssembly {
        let scale = input.imageWidth / 1080
        let horizon = input.horizonY ?? TracerConstants.defaultHorizonFraction * input.imageHeight
        // Dos detectores juntos: el umbral de atípico no baja de lo que se separan entre ellos.
        var options = options
        options.minimumOutlierThreshold = max(options.minimumOutlierThreshold, TracerConstants.sourceOutlierFloor * scale)
        // Solo cuenta lo de después del impacto.
        let usable = input.points.filter { $0.sample.time > 0 }
        let samples = usable.map(\.sample)

        guard Set(samples.map(\.time)).count >= 3, let fit = TrajectoryFit.fit(samples, options: options) else {
            return proposalOnly(input, horizon: horizon, points: usable.map {
                AssembledPoint(time: $0.sample.time, point: $0.sample.point, source: $0.source, isOutlier: false)
            })
        }

        // El ajuste ordena las muestras por tiempo: se recupera el origen de cada una.
        var sources: [TrajectorySample: [PointSource]] = [:]
        for point in usable { sources[point.sample, default: []].append(point.source) }
        var points: [AssembledPoint] = []
        for (sample, isOutlier) in zip(fit.samples, fit.isOutlier) {
            let source = sources[sample]?.isEmpty == false ? sources[sample]!.removeFirst() : .blob
            points.append(AssembledPoint(time: sample.time, point: sample.point, source: source, isOutlier: isOutlier))
        }
        let good = fit.inliers
        let tracked = good.map(\.time).max() ?? 0

        // Confianza (constantes en TracerConstants).
        let weights = TracerConstants.confidenceWeights
        let pointScore = min(Double(good.count) / TracerConstants.confidenceFullPoints, 1)
        let durationScore = min(tracked / TracerConstants.confidenceFullDuration, 1)
        let goodError = TracerConstants.confidenceGoodError * scale
        let badError = TracerConstants.confidenceBadError * scale
        let errorScore = min(max(1 - (fit.meanError - goodError) / (badError - goodError), 0), 1)
        var confidence = weights.points * pointScore + weights.duration * durationScore + weights.error * errorScore
        // La bola tiene que subir al principio: si el ajuste empieza bajando, algo no cuadra.
        let start = good.map(\.time).min() ?? 0
        if fit.position(at: min(start + 0.1, tracked)).y >= fit.position(at: start).y {
            confidence *= TracerConstants.confidenceNotRisingFactor
        }

        let needsReview = tracked < TracerConstants.minimumTrackedFlight || confidence < TracerConstants.minimumConfidence
        let curve = completeCurve(input, fit: fit, tracked: tracked, horizon: horizon)
        let outcome = TracerOutcome(curve: curve, confidence: confidence, trackedDuration: tracked, meanError: fit.meanError,
                                    needsReview: needsReview, lostAt: needsReview ? tracked : nil, points: points,
                                    usesObservations: true)
        return TracerAssembly(outcome: outcome, fit: fit)
    }

    /// Sin puntos útiles: la propuesta inicial de docs/03 (paso 6) y el aviso de pérdida en 0 s.
    static func proposalOnly(_ input: TracerInput, horizon: Double, points: [AssembledPoint]) -> TracerAssembly {
        let curve = TracerCurve.proposal(ball: input.ball, imageWidth: input.imageWidth, imageHeight: input.imageHeight,
                                         club: input.club, aimPoint: input.aimPoint, horizonY: horizon,
                                         handedness: input.handedness)
        let tracked = points.map(\.time).max() ?? 0
        let outcome = TracerOutcome(curve: curve, confidence: 0, trackedDuration: tracked, meanError: nil,
                                    needsReview: true, lostAt: tracked, points: points, usesObservations: false)
        return TracerAssembly(outcome: outcome, fit: nil)
    }

    /// Completa el vuelo con lo visto y los valores típicos del palo.
    static func completeCurve(_ input: TracerInput, fit: TrajectoryFitResult, tracked: Double, horizon: Double) -> TracerCurve {
        let w = input.imageWidth
        let h = input.imageHeight
        let ball = input.ball
        // Punto más alto de lo visto (cada 1/120 s).
        var highest = (time: 0.0, point: fit.position(at: 0))
        var t = 0.0
        while t <= tracked {
            let p = fit.position(at: t)
            if p.y < highest.point.y { highest = (t, p) }
            t += 1.0 / 120
        }
        let last = fit.position(at: tracked)
        // ¿Se ha visto el vértice? El punto más alto no es el último y después la bola baja claramente.
        let sawApex = highest.time < tracked - 0.05 && last.y > highest.point.y + 2 * (w / 1080)

        var apex: Point2D
        var landing: Point2D
        var flightTime = input.club.typicalFlightTime
        if sawApex {
            apex = highest.point
            if let extrapolated = fit.extrapolateToLanding(groundY: horizon, maximumDuration: 12) {
                landing = extrapolated.landingPoint
                flightTime = extrapolated.landingTime
            } else {
                landing = Point2D(apex.x + (apex.x - ball.x) * 0.64, horizon)
            }
        } else {
            // Aún subía al perderla: el vértice sigue la dirección vista hasta la altura típica del palo
            // (y siempre por encima del último punto visto); la caída, sobre el horizonte, como en la maqueta
            // (el vértice al 61 % del camino en horizontal).
            let apexY = min(input.club.apexFromTop * h, last.y - 0.03 * h)
            let direction = last - ball
            let along = direction.y < -1e-6 ? (apexY - ball.y) / direction.y : 0
            let apexX = min(max(ball.x + direction.x * along, 0.05 * w), 0.95 * w)
            apex = Point2D(apexX, apexY)
            landing = Point2D(min(max(ball.x + (apexX - ball.x) / 0.61, 0.02 * w), 0.98 * w), horizon)
        }
        // El vértice siempre por encima de la caída y de la salida.
        if apex.y >= min(landing.y, ball.y) - 0.02 * h {
            apex.y = min(landing.y, ball.y) - 0.1 * h
        }
        return TracerCurve(launch: ball, apex: apex, landing: landing, shape: 0,
                           flightTime: max(flightTime, 1), handedness: input.handedness)
    }
}
