import Foundation

/// Un punto de la bola en un instante.
public struct TrajectorySample: Hashable, Sendable, Codable {
    /// Segundos desde el impacto.
    public var time: Double
    public var point: Point2D
    /// Toque del usuario: pesa más en el ajuste y nunca se descarta como atípico.
    public var isFixed: Bool

    public init(time: Double, point: Point2D, isFixed: Bool = false) {
        self.time = time
        self.point = point
        self.isFixed = isFixed
    }
}

/// Movimiento con x(t) e y(t) de segundo grado: c0 + c1·u + c2·u², con u = t − center.
/// Centrar el tiempo en el tramo mantiene los números pequeños y el ajuste estable.
public struct QuadraticMotion: Hashable, Sendable, Codable {
    public var center: Double
    public var x: [Double]
    public var y: [Double]

    public func position(at t: Double) -> Point2D {
        let u = t - center
        return Point2D(x[0] + (x[1] + x[2] * u) * u, y[0] + (y[1] + y[2] * u) * u)
    }

    public func velocity(at t: Double) -> Point2D {
        let u = t - center
        return Point2D(x[1] + 2 * x[2] * u, y[1] + 2 * y[2] * u)
    }

    /// Aceleración (constante en este modelo), px/s².
    public var acceleration: Point2D { Point2D(2 * x[2], 2 * y[2]) }

    /// Ajuste por mínimos cuadrados con pesos. `nil` si no hay tres instantes distintos.
    public static func fit(_ samples: [TrajectorySample], weights: [Double]? = nil, center: Double? = nil) -> QuadraticMotion? {
        guard samples.count >= 3 else { return nil }
        let c = center ?? (samples.map(\.time).reduce(0, +) / Double(samples.count))
        let u = samples.map { $0.time - c }
        guard let cx = LinearAlgebra.fitPolynomial(times: u, values: samples.map(\.point.x), weights: weights, degree: 2),
              let cy = LinearAlgebra.fitPolynomial(times: u, values: samples.map(\.point.y), weights: weights, degree: 2)
        else { return nil }
        return QuadraticMotion(center: c, x: cx, y: cy)
    }
}

/// Opciones del ajuste. Los valores por defecto salen de `TracerConstants`.
public struct TrajectoryFitOptions: Sendable {
    public var segmentDuration = TracerConstants.fitSegmentDuration
    public var outlierFactor = TracerConstants.outlierFactor
    public var minimumOutlierThreshold = TracerConstants.minimumOutlierThreshold
    public var fixedPointWeight = TracerConstants.fixedPointWeight
    /// Hipótesis que prueba el RANSAC en cada tramo.
    public var iterations = 60
    /// Un tramo con menos puntos no se ajusta por separado (sus puntos los juzga el tramo vecino).
    public var minimumSamplesPerSegment = 6
    /// Semilla del RANSAC: el mismo vídeo da siempre el mismo resultado.
    public var seed: UInt64 = 1

    public init() {}
}

/// Un tramo del ajuste: su intervalo de tiempo, su movimiento y su error mediano.
public struct FitSegment: Sendable {
    public let start: Double
    public let end: Double
    public let motion: QuadraticMotion
    /// Error mediano (px) de los puntos del tramo frente a su movimiento.
    public let medianError: Double
}

/// Resultado del ajuste: qué puntos son buenos, el movimiento por tramos y el error medio.
public struct TrajectoryFitResult: Sendable {
    /// Las muestras ordenadas por tiempo.
    public let samples: [TrajectorySample]
    /// `isOutlier[i]` dice si `samples[i]` se ha descartado.
    public let isOutlier: [Bool]
    public let segments: [FitSegment]
    /// Distancia media (px) de los puntos buenos a la curva ajustada. Si un toque la hace subir,
    /// la app avisa: "Ese toque no encaja con el resto".
    public let meanError: Double
    let options: TrajectoryFitOptions

    public var inliers: [TrajectorySample] { zip(samples, isOutlier).filter { !$0.1 }.map { $0.0 } }
    public var outliers: [TrajectorySample] { zip(samples, isOutlier).filter { $0.1 }.map { $0.0 } }

    /// Posición ajustada en el instante t. Donde se solapan dos tramos se mezclan con pesos
    /// en triángulo (más peso cuanto más cerca del centro del tramo), así la curva no da saltos.
    /// Fuera del intervalo con datos se usa el tramo del extremo.
    public func position(at t: Double) -> Point2D {
        guard let first = segments.first, let last = segments.last else { return samples.first?.point ?? .zero }
        if t <= first.start { return first.motion.position(at: t) }
        if t >= last.end { return last.motion.position(at: t) }
        var sum = Point2D.zero
        var totalWeight = 0.0
        for segment in segments where t >= segment.start && t <= segment.end {
            let half = max((segment.end - segment.start) / 2, 1e-9)
            let middle = (segment.start + segment.end) / 2
            let w = max(1 - abs(t - middle) / half, 1e-3)
            sum += segment.motion.position(at: t) * w
            totalWeight += w
        }
        if totalWeight > 0 { return sum / totalWeight }
        // Hueco entre tramos (faltan puntos): el tramo con el centro más cercano.
        let nearest = segments.min { abs(($0.start + $0.end) / 2 - t) < abs(($1.start + $1.end) / 2 - t) }!
        return nearest.motion.position(at: t)
    }

    /// Prolonga la trayectoria más allá del último punto bueno hasta que la bola baja a `groundY`
    /// (la caída), con una parábola ajustada a todos los puntos buenos o, si no encajan en una sola,
    /// a los últimos `TracerConstants.extrapolationWindow` s.
    /// Devuelve `nil` si con lo visto la bola todavía no tiende a bajar o tardaría más de `maximumDuration`:
    /// entonces la caída la completa `TracerCurve` con los valores típicos del palo.
    public func extrapolateToLanding(groundY: Double, timeStep: Double = 1.0 / 120,
                                     maximumDuration: Double = 10) -> LandingExtrapolation? {
        let good = inliers
        guard let lastTime = good.last?.time else { return nil }
        func weights(_ samples: [TrajectorySample]) -> [Double] { samples.map { $0.isFixed ? options.fixedPointWeight : 1 } }
        // Cuanto más largo el tramo que se ajusta, menos se disparan los errores al prolongarlo.
        // Si todo lo visto encaja en una sola parábola (casi tan bien como el ajuste por tramos),
        // se usa entero; si no (la perspectiva la deforma), solo los últimos 0,5 s.
        var motion: QuadraticMotion?
        if let global = QuadraticMotion.fit(good, weights: weights(good)) {
            let error = good.map { global.position(at: $0.time).distance(to: $0.point) }.reduce(0, +) / Double(good.count)
            if error <= max(1.5 * meanError, options.minimumOutlierThreshold) { motion = global }
        }
        if motion == nil {
            var window = good.filter { $0.time >= lastTime - TracerConstants.extrapolationWindow }
            if Set(window.map(\.time)).count < 3 { window = good }
            motion = QuadraticMotion.fit(window, weights: weights(window))
        }
        guard let motion else { return nil }

        // y(u) = c0 + c1·u + c2·u² = groundY, con u = t − center. Se busca la primera raíz
        // posterior al último punto en la que la bola baja (y crece hacia abajo: y'(t) > 0).
        let a = motion.y[2]
        let b = motion.y[1]
        let c = motion.y[0] - groundY
        var roots: [Double] = []
        if abs(a) < 1e-9 {
            if abs(b) > 1e-9 { roots = [-c / b] }
        } else {
            let discriminant = b * b - 4 * a * c
            if discriminant >= 0 {
                let s = discriminant.squareRoot()
                roots = [(-b - s) / (2 * a), (-b + s) / (2 * a)]
            }
        }
        let landing = roots.map { $0 + motion.center }
            .filter { $0 > lastTime && motion.velocity(at: $0).y > 0 }
            .min()
        guard let landingTime = landing, landingTime - lastTime <= maximumDuration else { return nil }

        var points: [TrajectorySample] = []
        var t = lastTime + timeStep
        while t < landingTime {
            points.append(TrajectorySample(time: t, point: motion.position(at: t)))
            t += timeStep
        }
        let landingPoint = motion.position(at: landingTime)
        points.append(TrajectorySample(time: landingTime, point: landingPoint))
        return LandingExtrapolation(points: points, landingTime: landingTime, landingPoint: landingPoint, motion: motion)
    }
}

/// Prolongación hasta la caída.
public struct LandingExtrapolation: Sendable {
    /// Puntos desde justo después del último punto bueno hasta la caída (incluida).
    public let points: [TrajectorySample]
    public let landingTime: Double
    public let landingPoint: Point2D
    /// Parábola usada para extrapolar.
    public let motion: QuadraticMotion
}

/// Ajuste robusto por tramos de la trayectoria de la bola (docs/03, paso 5; clave 5 de la guía).
///
/// La bola no sigue una sola parábola en la imagen (la perspectiva la deforma), pero en un
/// cuarto de segundo sí se parece mucho a una. Por eso:
/// 1. Se corta el vuelo en tramos de 0,25 s que se solapan a la mitad.
/// 2. En cada tramo, RANSAC: se prueban parábolas que pasan por 3 puntos al azar (más los toques)
///    y se queda la que deja el error mediano más bajo (variante LMedS, que no necesita fijar un umbral
///    de antemano y aguanta hasta casi la mitad de puntos malos).
/// 3. Un punto es atípico si se aleja de su tramo más de 3 veces el error mediano del tramo.
///    Como cada punto cae en dos tramos, se descarta si lo marca al menos la mitad de sus tramos.
/// 4. Los toques del usuario nunca se descartan y pesan 100 veces más en cada ajuste.
/// 5. Con los puntos buenos se vuelve a ajustar cada tramo por mínimos cuadrados.
public enum TrajectoryFit {
    public static func fit(_ samples: [TrajectorySample], options: TrajectoryFitOptions = .init()) -> TrajectoryFitResult? {
        let sorted = samples.sorted { $0.time < $1.time }
        guard Set(sorted.map(\.time)).count >= 3 else { return nil }
        var rng = SeededRandom(seed: options.seed)

        let windows = makeWindows(start: sorted.first!.time, end: sorted.last!.time, duration: options.segmentDuration)
        var outlierVotes = [Int](repeating: 0, count: sorted.count)
        var totalVotes = [Int](repeating: 0, count: sorted.count)
        var robustSegments: [(start: Double, end: Double, indices: [Int], fit: RobustFit)] = []

        for window in windows {
            let indices = sorted.indices.filter { sorted[$0].time >= window.start - 1e-9 && sorted[$0].time <= window.end + 1e-9 }
            guard indices.count >= options.minimumSamplesPerSegment,
                  Set(indices.map { sorted[$0].time }).count >= 3,
                  let robust = robustFit(sorted, indices: indices, center: (window.start + window.end) / 2,
                                         options: options, rng: &rng)
            else { continue }
            for (k, index) in indices.enumerated() {
                totalVotes[index] += 1
                if !sorted[index].isFixed && robust.residuals[k] > robust.threshold { outlierVotes[index] += 1 }
            }
            robustSegments.append((window.start, window.end, indices, robust))
        }

        // Si ningún tramo tenía puntos suficientes (vuelo muy corto), un solo tramo con todo.
        if robustSegments.isEmpty {
            let all = Array(sorted.indices)
            let start = sorted.first!.time
            let end = sorted.last!.time
            guard let robust = robustFit(sorted, indices: all, center: (start + end) / 2, options: options, rng: &rng)
            else { return nil }
            for (k, index) in all.enumerated() {
                totalVotes[index] += 1
                if !sorted[index].isFixed && robust.residuals[k] > robust.threshold { outlierVotes[index] += 1 }
            }
            robustSegments.append((start, end, all, robust))
        }

        var isOutlier = [Bool](repeating: false, count: sorted.count)
        for i in sorted.indices where !sorted[i].isFixed {
            if totalVotes[i] > 0 {
                isOutlier[i] = 2 * outlierVotes[i] >= totalVotes[i]
            } else {
                // Punto que no cae en ningún tramo con datos: lo juzga el tramo más cercano en el tiempo.
                let t = sorted[i].time
                let nearest = robustSegments.min { abs(($0.start + $0.end) / 2 - t) < abs(($1.start + $1.end) / 2 - t) }!
                isOutlier[i] = nearest.fit.motion.position(at: t).distance(to: sorted[i].point) > nearest.fit.threshold
            }
        }

        // Ajuste final de cada tramo solo con los puntos buenos (los toques con su peso).
        var segments: [FitSegment] = []
        for segment in robustSegments {
            let good = segment.indices.filter { !isOutlier[$0] }
            let goodSamples = good.map { sorted[$0] }
            let weights = goodSamples.map { $0.isFixed ? options.fixedPointWeight : 1 }
            let center = (segment.start + segment.end) / 2
            let motion = (Set(goodSamples.map(\.time)).count >= 3
                ? QuadraticMotion.fit(goodSamples, weights: weights, center: center) : nil) ?? segment.fit.motion
            let errors = goodSamples.map { motion.position(at: $0.time).distance(to: $0.point) }
            segments.append(FitSegment(start: segment.start, end: segment.end, motion: motion,
                                       medianError: LinearAlgebra.median(errors)))
        }

        var result = TrajectoryFitResult(samples: sorted, isOutlier: isOutlier, segments: segments,
                                         meanError: 0, options: options)
        let good = result.inliers
        let meanError = good.isEmpty ? 0 : good.map { result.position(at: $0.time).distance(to: $0.point) }
            .reduce(0, +) / Double(good.count)
        result = TrajectoryFitResult(samples: sorted, isOutlier: isOutlier, segments: segments,
                                     meanError: meanError, options: options)
        return result
    }

    /// Tramos de `duration` s que se solapan a la mitad y cubren de `start` a `end`.
    /// El último se alinea con el final para que el final del vuelo no quede en un tramo cojo.
    static func makeWindows(start: Double, end: Double, duration: Double) -> [(start: Double, end: Double)] {
        guard end - start > duration else { return [(start, end)] }
        var windows: [(start: Double, end: Double)] = []
        let step = duration / 2
        var s = start
        while s + duration < end - 1e-9 {
            windows.append((s, s + duration))
            s += step
        }
        windows.append((end - duration, end))
        return windows
    }

    struct RobustFit {
        let motion: QuadraticMotion
        /// Error (px) de cada punto del tramo, en el mismo orden que sus índices.
        let residuals: [Double]
        /// Distancia a partir de la cual un punto es atípico: 3 × error mediano (con un mínimo).
        let threshold: Double
    }

    /// RANSAC (LMedS) dentro de un tramo.
    static func robustFit(_ samples: [TrajectorySample], indices: [Int], center: Double,
                          options: TrajectoryFitOptions, rng: inout SeededRandom) -> RobustFit? {
        let fixed = indices.filter { samples[$0].isFixed }
        let free = indices.filter { !samples[$0].isFixed }

        func residuals(of motion: QuadraticMotion) -> [Double] {
            indices.map { motion.position(at: samples[$0].time).distance(to: samples[$0].point) }
        }
        func fitSubset(_ subset: [Int]) -> QuadraticMotion? {
            let chosen = subset.map { samples[$0] }
            let weights = chosen.map { $0.isFixed ? options.fixedPointWeight : 1 }
            return QuadraticMotion.fit(chosen, weights: weights, center: center)
        }

        var best: (motion: QuadraticMotion, median: Double)?
        if free.count >= 3 {
            for _ in 0..<options.iterations {
                // Tres puntos distintos al azar (más todos los toques del tramo).
                var pick: [Int] = []
                while pick.count < 3 {
                    let candidate = free[Int.random(in: 0..<free.count, using: &rng)]
                    if !pick.contains(candidate) { pick.append(candidate) }
                }
                guard Set(pick.map { samples[$0].time }).count == 3, let motion = fitSubset(pick + fixed) else { continue }
                let median = LinearAlgebra.median(residuals(of: motion))
                if best == nil || median < best!.median { best = (motion, median) }
            }
        }
        // Sin hipótesis válidas (casi todo son toques): mínimos cuadrados con todo.
        if best == nil, let motion = fitSubset(indices) {
            best = (motion, LinearAlgebra.median(residuals(of: motion)))
        }
        guard let chosen = best else { return nil }

        // Refinado: se vuelve a ajustar con los puntos que la mejor hipótesis da por buenos.
        let firstThreshold = max(options.outlierFactor * chosen.median, options.minimumOutlierThreshold)
        let firstResiduals = residuals(of: chosen.motion)
        let consensus = zip(indices, firstResiduals).filter { samples[$0.0].isFixed || $0.1 <= firstThreshold }.map { $0.0 }
        let refined = (Set(consensus.map { samples[$0].time }).count >= 3 ? fitSubset(consensus) : nil) ?? chosen.motion
        let finalResiduals = residuals(of: refined)
        let median = LinearAlgebra.median(finalResiduals)
        let threshold = max(options.outlierFactor * median, options.minimumOutlierThreshold)
        return RobustFit(motion: refined, residuals: finalResiduals, threshold: threshold)
    }
}
