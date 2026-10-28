import Foundation

/// Tramo de Bézier cúbica: sale de p0 hacia p1, llega a p3 viniendo de p2.
public struct CubicBezier: Hashable, Sendable {
    public var p0: Point2D
    public var p1: Point2D
    public var p2: Point2D
    public var p3: Point2D

    public init(_ p0: Point2D, _ p1: Point2D, _ p2: Point2D, _ p3: Point2D) {
        self.p0 = p0
        self.p1 = p1
        self.p2 = p2
        self.p3 = p3
    }

    /// Punto para el parámetro u de 0 a 1 (no es proporcional a la distancia recorrida).
    public func point(at u: Double) -> Point2D {
        let v = 1 - u
        let a = p0 * (v * v * v)
        let b = p1 * (3 * v * v * u)
        let c = p2 * (3 * v * u * u)
        let d = p3 * (u * u * u)
        return a + b + c + d
    }
}

/// Modelo editable del vuelo de la bola (docs/03, "Modelo de la curva").
///
/// Se controla con lo que el usuario ve y arrastra: la salida S, el vértice A y la caída L
/// (en píxeles de la imagen), la forma (de −1, draw, a +1, fade) y el tiempo de vuelo.
/// La curva son dos Bézier cúbicas, S→A y A→L, con la tangente horizontal en A en las dos:
/// así la cima sale redonda y sin pico. El primer tramo sube casi recto y el segundo baja más corto.
///
/// Decisión: la curva pasa siempre por las tres asas, también con draw o fade (si no, al arrastrar
/// un asa la curva no la seguiría). La forma dobla el vuelo hacia un lado entre las asas:
/// en un diestro visto desde detrás, el draw sale hacia la derecha y vuelve a la izquierda
/// (el vuelo se abomba a la derecha) y el fade al revés. En un zurdo, todo se refleja.
public struct TracerCurve: Hashable, Sendable, Codable {
    public var launch: Point2D
    public var apex: Point2D
    public var landing: Point2D
    /// −1 draw, 0 recta, +1 fade. Se recorta a ese intervalo.
    public var shape: Double
    /// Segundos desde el impacto hasta la caída.
    public var flightTime: Double
    public var handedness: Handedness

    public init(launch: Point2D, apex: Point2D, landing: Point2D, shape: Double = 0,
                flightTime: Double, handedness: Handedness = .right) {
        self.launch = launch
        self.apex = apex
        self.landing = landing
        self.shape = shape
        self.flightTime = flightTime
        self.handedness = handedness
    }

    /// Los dos tramos de la curva con sus puntos de control.
    public var segments: (rise: CubicBezier, fall: CubicBezier) {
        let s = launch, a = apex, l = landing
        // Altura del vuelo en píxeles (como mínimo 1, por si el vértice se arrastra por debajo de la salida).
        let height = max(s.y - a.y, 1)
        let rise = a - s
        let fall = l - a
        // Sentido horizontal del vuelo: la tangente en el vértice apunta hacia donde cae la bola.
        let direction: Double = l.x >= s.x ? 1 : -1
        // Cuánto se abomba el vuelo hacia un lado (px). Draw (−1) en un diestro: hacia la derecha (+x).
        let clampedShape = min(max(shape, -1), 1)
        let bulge = -clampedShape * handedness.xSign * TracerConstants.shapeBulge * height

        // Las asas del vértice siguen al recorrido horizontal de cada tramo: así la curva no se pasa
        // de la salida ni de la caída. Solo con un vuelo casi vertical manda el mínimo (cima redonda).
        let minimumHandle = TracerConstants.apexMinimumHandle * height
        let riseHandle = TracerConstants.apexRoundness * max(abs(rise.x), minimumHandle)
        let fallHandle = TracerConstants.apexRoundness * max(abs(fall.x), minimumHandle)
        let first = CubicBezier(
            s,
            Point2D(s.x + TracerConstants.launchLean * rise.x + bulge / 2, s.y + TracerConstants.launchRise * rise.y),
            Point2D(a.x - direction * riseHandle, a.y),
            a)
        let second = CubicBezier(
            a,
            Point2D(a.x + direction * fallHandle, a.y),
            Point2D(l.x - TracerConstants.descentLean * fall.x + bulge, l.y - TracerConstants.descentDrop * fall.y),
            l)
        return (first, second)
    }

    /// Prepara la curva para preguntarle posiciones (mide su longitud una sola vez).
    public func makeFlight(samplesPerSegment: Int = 240) -> TracerFlight {
        TracerFlight(curve: self, samplesPerSegment: samplesPerSegment)
    }

    /// Propuesta inicial cuando no hay detección útil (docs/03, paso 6).
    /// - Parameters:
    ///   - ball: dónde está la bola antes del impacto (la salida).
    ///   - aimPoint: hacia dónde sale (punto de fuga de la línea del golpe). Por defecto, el centro alto de la imagen.
    ///   - horizonY: y del horizonte. Por defecto, el 44 % de la altura.
    public static func proposal(ball: Point2D, imageWidth: Double, imageHeight: Double, club: ClubCategory,
                                aimPoint: Point2D? = nil, horizonY: Double? = nil,
                                handedness: Handedness = .right) -> TracerCurve {
        let horizon = horizonY ?? TracerConstants.defaultHorizonFraction * imageHeight
        let aim = aimPoint ?? Point2D(imageWidth / 2, 0)
        // Caída: sobre el horizonte, en la recta que va de la bola al punto de mira.
        let dy = aim.y - ball.y
        let t = abs(dy) > 1e-9 ? (horizon - ball.y) / dy : 0
        let landingX = min(max(ball.x + (aim.x - ball.x) * t, 0), imageWidth)
        let landing = Point2D(landingX, horizon)
        // Vértice a la altura típica del palo y al 61 % del camino en horizontal (como la maqueta).
        let apexY = min(club.apexFromTop * imageHeight, horizon - 1)
        let apex = Point2D(ball.x + (landing.x - ball.x) * 0.61, apexY)
        return TracerCurve(launch: ball, apex: apex, landing: landing, shape: 0,
                           flightTime: club.typicalFlightTime, handedness: handedness)
    }
}

/// La curva medida y lista para dar la posición de la bola en cada instante.
///
/// Perfil de tiempo (docs/03): la bola parece muy rápida al salir y lenta al final, por la
/// perspectiva y porque frena. La fracción de recorrido sigue f(τ) = 1 − (1 − τ)^k (τ = t/T),
/// con k ajustado para llegar al vértice en τ = 0,5 (ver `TimeProfile`).
public struct TracerFlight: Sendable {
    public let curve: TracerCurve
    /// Puntos densos de toda la curva, de la salida a la caída.
    public let points: [Point2D]
    /// Longitud acumulada hasta cada punto (px).
    private let cumulative: [Double]
    /// Índice del vértice dentro de `points`.
    private let apexIndex: Int
    private let profile: TimeProfile

    init(curve: TracerCurve, samplesPerSegment: Int) {
        self.curve = curve
        let n = max(samplesPerSegment, 2)
        let (rise, fall) = curve.segments
        var points = (0...n).map { rise.point(at: Double($0) / Double(n)) }
        points += (1...n).map { fall.point(at: Double($0) / Double(n)) }
        var cumulative = [0.0]
        for i in 1..<points.count { cumulative.append(cumulative[i - 1] + points[i].distance(to: points[i - 1])) }
        self.points = points
        self.cumulative = cumulative
        apexIndex = n
        let total = cumulative.last!
        let apexFraction = total > 0 ? cumulative[n] / total : 0.5
        profile = TimeProfile(apexFraction: apexFraction)
    }

    /// Longitud total del vuelo dibujado (px).
    public var totalLength: Double { cumulative.last ?? 0 }

    /// Fracción del recorrido (0 a 1) en la que está el vértice.
    public var apexArcFraction: Double { profile.apexFraction }

    /// Fracción del recorrido hecha en el instante `time` (s desde el impacto).
    public func progress(at time: Double) -> Double {
        guard curve.flightTime > 0 else { return 1 }
        return profile.fraction(at: min(max(time / curve.flightTime, 0), 1))
    }

    /// Posición de la bola en el instante `time`. Antes del impacto, en la salida; después de la caída, en la caída.
    public func ballPosition(at time: Double) -> Point2D {
        point(atArcFraction: progress(at: time))
    }

    /// Punto de la curva a una fracción `s` de la longitud total.
    public func point(atArcFraction s: Double) -> Point2D {
        let target = min(max(s, 0), 1) * totalLength
        if target <= 0 { return points[0] }
        if target >= totalLength { return points[points.count - 1] }
        // Búsqueda binaria del tramo recto que contiene esa longitud.
        var low = 0
        var high = cumulative.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if cumulative[mid] < target { low = mid } else { high = mid }
        }
        let span = cumulative[high] - cumulative[low]
        let t = span > 0 ? (target - cumulative[low]) / span : 0
        return Point2D.lerp(points[low], points[high], t)
    }

    /// Trozo de la curva ya recorrido en `time`: lo que hay que dibujar del trazo en ese instante.
    public func path(upTo time: Double) -> [Point2D] {
        let target = progress(at: time) * totalLength
        var result: [Point2D] = []
        for (point, length) in zip(points, cumulative) {
            if length >= target { break }
            result.append(point)
        }
        result.append(point(atArcFraction: progress(at: time)))
        return result
    }

    /// Punto más alto (menor y) de la curva: con forma recta coincide con el asa del vértice.
    public var highestPoint: Point2D { points.min { $0.y < $1.y } ?? curve.apex }

    /// Índice del vértice en `points` (para dibujar subida y bajada por separado).
    public var apexPointIndex: Int { apexIndex }
}

/// Fracción del recorrido en función del tiempo normalizado τ (de 0 a 1).
///
/// La forma es la de docs/03, f(τ) = 1 − (1 − τ)^k: velocidad máxima al salir que baja sin saltos
/// hasta casi cero en la caída. El exponente se ajusta en cada curva para que la bola llegue al
/// vértice en τ = 0,5: si la subida es la fracción a del recorrido, 1 − 0,5^k = a.
/// Con la subida en el 81 % del recorrido sale el 2,4 de docs/03; con subidas más cortas
/// (como la de la maqueta, el 63 %) sale menor. Se limita entre 1,2 y 4: fuera de ese margen
/// el vértice llega algo antes o después de τ = 0,5, pero la velocidad sigue bajando siempre.
struct TimeProfile: Sendable {
    /// Fracción del recorrido que ocupa la subida (de la salida al vértice).
    let apexFraction: Double
    let exponent: Double

    init(apexFraction: Double, apexTime: Double = TracerConstants.apexTimeFraction) {
        let a = min(max(apexFraction, 0), 1)
        self.apexFraction = a
        if a > 0, a < 1, apexTime > 0, apexTime < 1 {
            let k = log(1 - a) / log(1 - apexTime)
            exponent = min(max(k, TracerConstants.timeProfileMinimumExponent), TracerConstants.timeProfileMaximumExponent)
        } else {
            exponent = TracerConstants.timeProfileExponent
        }
    }

    func fraction(at tau: Double) -> Double {
        1 - pow(1 - min(max(tau, 0), 1), exponent)
    }
}
