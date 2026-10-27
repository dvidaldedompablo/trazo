import Foundation

/// Filtro One Euro (Casiez, Roussel y Vogel, 2012) para una señal que llega muestra a muestra.
///
/// Es un paso bajo cuya frecuencia de corte se adapta a la velocidad de la señal:
/// - quieta o lenta, corta mucho y quita el temblor (el "jitter" de la pose de Vision);
/// - rápida, corta poco y no se queda atrás (en la bajada del swing las manos van muy deprisa).
/// `minCutoff` (Hz) fija cuánto suaviza en reposo y `beta` cuánto se abre al moverse.
public struct OneEuroFilter: Sendable {
    public var minCutoff: Double
    public var beta: Double
    /// Corte del filtro que suaviza la velocidad usada para adaptar el corte principal.
    public var derivativeCutoff: Double

    private var previousValue: Double?
    private var previousDerivative = 0.0
    private var previousTime: Double?

    public init(minCutoff: Double = 1.0, beta: Double = 0.0, derivativeCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    /// Filtra el valor de la muestra tomada en `time` (segundos). Las muestras deben llegar en orden.
    public mutating func filter(_ value: Double, at time: Double) -> Double {
        guard let lastValue = previousValue, let lastTime = previousTime else {
            previousValue = value
            previousTime = time
            return value
        }
        let dt = time - lastTime
        // Una muestra repetida o desordenada no aporta nada: se devuelve lo que ya había.
        guard dt > 0 else { return lastValue }

        let derivative = (value - lastValue) / dt
        let smoothedDerivative = Self.lowPass(derivative, previous: previousDerivative,
                                              alpha: Self.alpha(cutoff: derivativeCutoff, dt: dt))
        let cutoff = minCutoff + beta * abs(smoothedDerivative)
        let result = Self.lowPass(value, previous: lastValue, alpha: Self.alpha(cutoff: cutoff, dt: dt))

        previousValue = result
        previousDerivative = smoothedDerivative
        previousTime = time
        return result
    }

    /// Vuelve al estado inicial (la siguiente muestra pasa sin filtrar).
    public mutating func reset() {
        previousValue = nil
        previousTime = nil
        previousDerivative = 0
    }

    /// Peso de la muestra nueva en un paso bajo de primer orden con ese corte.
    static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * max(cutoff, 1e-9))
        return 1 / (1 + tau / dt)
    }

    static func lowPass(_ value: Double, previous: Double, alpha: Double) -> Double {
        alpha * value + (1 - alpha) * previous
    }
}

/// One Euro para puntos: un filtro por coordenada, como en el artículo original.
public struct OneEuroFilter2D: Sendable {
    private var x: OneEuroFilter
    private var y: OneEuroFilter

    public init(minCutoff: Double = 1.0, beta: Double = 0.0, derivativeCutoff: Double = 1.0) {
        x = OneEuroFilter(minCutoff: minCutoff, beta: beta, derivativeCutoff: derivativeCutoff)
        y = OneEuroFilter(minCutoff: minCutoff, beta: beta, derivativeCutoff: derivativeCutoff)
    }

    public mutating func filter(_ point: Point2D, at time: Double) -> Point2D {
        Point2D(x.filter(point.x, at: time), y.filter(point.y, at: time))
    }

    public mutating func reset() {
        x.reset()
        y.reset()
    }
}

/// Suavizado de series completas (cuando ya se tienen todos los fotogramas).
public enum Smoothing {
    /// Filtro One Euro sobre una serie entera de puntos con sus instantes.
    public static func oneEuro(_ points: [Point2D], times: [Double],
                               minCutoff: Double = 1.0, beta: Double = 0.0) -> [Point2D] {
        precondition(points.count == times.count, "Cada punto necesita su instante")
        var filter = OneEuroFilter2D(minCutoff: minCutoff, beta: beta)
        return zip(points, times).map { filter.filter($0, at: $1) }
    }

    /// Filtro de Savitzky-Golay: en cada muestra ajusta un polinomio de grado `order`
    /// a las `window` muestras de alrededor y se queda con su valor (o su derivada) en ese punto.
    ///
    /// A diferencia de una media móvil, no achata los picos: un movimiento que es un polinomio
    /// de ese grado sale intacto y solo se va el ruido. docs/04 usa ventana 9 y orden 3 para la pose.
    /// En los extremos la ventana no se puede centrar: se usa la primera (o la última) ventana completa
    /// y se evalúa su polinomio en la posición que toca, en vez de rellenar con copias.
    /// - Parameters:
    ///   - derivative: 0 para suavizar; 1 para la velocidad; 2 para la aceleración.
    ///   - sampleSpacing: tiempo entre muestras (para que la derivada salga por segundo y no por muestra).
    public static func savitzkyGolay(_ values: [Double], window: Int = 9, order: Int = 3,
                                     derivative: Int = 0, sampleSpacing: Double = 1) -> [Double] {
        let n = values.count
        guard n > 0 else { return [] }
        // Si hay menos muestras que ventana, la ventana encoge (impar) y el grado con ella.
        var w = min(max(window, 1), n)
        if w % 2 == 0 { w -= 1 }
        let p = min(max(order, 0), w - 1)
        let half = w / 2
        let table = (0..<w).map { position in
            coefficients(window: w, order: p, at: Double(position - half), derivative: derivative)
        }
        let scale = LinearAlgebra.power(sampleSpacing, derivative)
        var result = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let start = min(max(i - half, 0), n - w)
            let h = table[i - start]
            var sum = 0.0
            for j in 0..<w { sum += h[j] * values[start + j] }
            result[i] = sum / scale
        }
        return result
    }

    /// Savitzky-Golay para puntos: cada coordenada por separado.
    public static func savitzkyGolay(_ points: [Point2D], window: Int = 9, order: Int = 3) -> [Point2D] {
        let xs = savitzkyGolay(points.map(\.x), window: window, order: order)
        let ys = savitzkyGolay(points.map(\.y), window: window, order: order)
        return zip(xs, ys).map { Point2D($0, $1) }
    }

    /// Pesos h tales que el valor suavizado es Σ h[j]·y[j] dentro de la ventana.
    ///
    /// El polinomio ajustado es a = (AᵀA)⁻¹Aᵀy, con A la matriz de potencias de las posiciones
    /// −half…half. Su valor (o derivada) en u es eᵀa, con e = [1, u, u², …] (o su derivada).
    /// Eso es (A·z)ᵀ·y con (AᵀA)·z = e: un sistema pequeño por posición, que se calcula una sola vez.
    static func coefficients(window: Int, order: Int, at u: Double, derivative: Int) -> [Double] {
        let half = window / 2
        let terms = order + 1
        guard derivative <= order else { return [Double](repeating: 0, count: window) }
        let positions = (0..<window).map { Double($0 - half) }
        var normal = [Double](repeating: 0, count: terms * terms)
        for x in positions {
            for r in 0..<terms {
                for c in 0..<terms { normal[r * terms + c] += LinearAlgebra.power(x, r + c) }
            }
        }
        // e[k] = derivada d-ésima de u^k = k!/(k−d)! · u^(k−d).
        var e = [Double](repeating: 0, count: terms)
        for k in derivative..<terms {
            var factor = 1.0
            for m in 0..<derivative { factor *= Double(k - m) }
            e[k] = factor * LinearAlgebra.power(u, k - derivative)
        }
        guard let z = LinearAlgebra.solve(normal, e) else { return [Double](repeating: 0, count: window) }
        return positions.map { x in
            var sum = 0.0
            for k in 0..<terms { sum += LinearAlgebra.power(x, k) * z[k] }
            return sum
        }
    }

    /// Rellena huecos cortos (como mucho `maxGap` muestras seguidas) interpolando en línea recta
    /// entre la muestra anterior y la siguiente. Los huecos más largos y los de los extremos
    /// se dejan vacíos: ahí no sabemos dónde estaba la articulación y no se inventa.
    public static func fillGaps(_ values: [Double?], maxGap: Int) -> [Double?] {
        var result = values
        var i = 0
        while i < result.count {
            guard result[i] == nil else { i += 1; continue }
            var end = i
            while end < result.count, result[end] == nil { end += 1 }
            let length = end - i
            if i > 0, end < result.count, length <= maxGap,
               let before = result[i - 1], let after = result[end] {
                for k in 0..<length {
                    let t = Double(k + 1) / Double(length + 1)
                    result[i + k] = before + (after - before) * t
                }
            }
            i = end
        }
        return result
    }

    /// Lo mismo para puntos.
    public static func fillGaps(_ points: [Point2D?], maxGap: Int) -> [Point2D?] {
        let xs = fillGaps(points.map { $0?.x }, maxGap: maxGap)
        let ys = fillGaps(points.map { $0?.y }, maxGap: maxGap)
        return zip(xs, ys).map { x, y in
            guard let x, let y else { return nil }
            return Point2D(x, y)
        }
    }
}
