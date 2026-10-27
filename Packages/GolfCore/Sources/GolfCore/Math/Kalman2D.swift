import Foundation

/// Filtro de Kalman con modelo de velocidad constante en 2D.
///
/// Estado: posición (x, y) y velocidad (vx, vy). En cada fotograma hace dos pasos:
/// 1. `predict(dt:)`: mueve la posición con la velocidad y aumenta la incertidumbre
///    (la bola puede acelerar o frenar un poco: eso es el "ruido de proceso").
/// 2. `correct(measurement:)`: mezcla la predicción con la medida, pesando cada una
///    por lo fiable que es. Si la incertidumbre de la predicción es grande, manda la medida.
///
/// Sirve para dos cosas en el tracer: saber dónde buscar la bola en el fotograma siguiente
/// (con una "puerta" que crece con la incertidumbre) y seguir cuando un fotograma no la ve.
///
/// Por dentro son dos filtros de una dimensión, uno por eje. Con ruidos independientes en x e y,
/// el filtro 2D completo se separa exactamente así (las covarianzas cruzadas x-y se quedan a cero),
/// y las cuentas son de matrices 2x2, fáciles de seguir.
public struct KalmanFilter2D: Sendable {
    /// Intensidad de la aceleración aleatoria (px²/s³). Más alta: el filtro acepta giros más bruscos.
    public var processNoise: Double
    /// Desviación típica del error de cada medida (px).
    public var measurementNoise: Double

    private var xAxis: Axis
    private var yAxis: Axis

    /// - Parameters:
    ///   - positionStdDev: duda inicial sobre la posición (px).
    ///   - velocityStdDev: duda inicial sobre la velocidad (px/s). Grande si no se sabe hacia dónde va.
    public init(position: Point2D, velocity: Point2D = .zero,
                positionStdDev: Double, velocityStdDev: Double,
                processNoise: Double, measurementNoise: Double) {
        self.processNoise = processNoise
        self.measurementNoise = measurementNoise
        let pp = positionStdDev * positionStdDev
        let vv = velocityStdDev * velocityStdDev
        xAxis = Axis(p: position.x, v: velocity.x, pp: pp, pv: 0, vv: vv)
        yAxis = Axis(p: position.y, v: velocity.y, pp: pp, pv: 0, vv: vv)
    }

    public var position: Point2D { Point2D(xAxis.p, yAxis.p) }
    public var velocity: Point2D { Point2D(xAxis.v, yAxis.v) }

    /// Desviación típica de la posición estimada (la mayor de los dos ejes), en px.
    public var positionStdDev: Double { max(xAxis.pp, yAxis.pp).squareRoot() }

    /// Avanza el estado `dt` segundos. `dt` debe ser positivo; para ir hacia atrás en el vídeo
    /// se crea el filtro con la velocidad cambiada de signo (ver `BlobTracker`).
    public mutating func predict(dt: Double) {
        guard dt > 0 else { return }
        xAxis.predict(dt: dt, q: processNoise)
        yAxis.predict(dt: dt, q: processNoise)
    }

    /// Corrige con una posición medida.
    public mutating func correct(measurement: Point2D) {
        let r = measurementNoise * measurementNoise
        xAxis.correct(measurement.x, r: r)
        yAxis.correct(measurement.y, r: r)
    }

    /// Cuántas desviaciones típicas separan una medida de la predicción (distancia de Mahalanobis).
    /// Cuenta la duda de la predicción y la de la medida.
    public func mahalanobisDistance(to measurement: Point2D) -> Double {
        let r = measurementNoise * measurementNoise
        let dx = measurement.x - xAxis.p
        let dy = measurement.y - yAxis.p
        return (dx * dx / (xAxis.pp + r) + dy * dy / (yAxis.pp + r)).squareRoot()
    }

    /// Radio de búsqueda (px) que abarca `sigmas` desviaciones típicas de la diferencia esperada
    /// entre la medida y la predicción. Crece mientras no se ve la bola.
    public func gateRadius(sigmas: Double) -> Double {
        let r = measurementNoise * measurementNoise
        return sigmas * (max(xAxis.pp, yAxis.pp) + r).squareRoot()
    }

    /// Un eje: estado [posición, velocidad] y covarianza simétrica [[pp, pv], [pv, vv]].
    struct Axis: Sendable {
        var p: Double
        var v: Double
        var pp: Double
        var pv: Double
        var vv: Double

        mutating func predict(dt: Double, q: Double) {
            // Estado: x ← F·x con F = [[1, dt], [0, 1]].
            p += v * dt
            // Covarianza: P ← F·P·Fᵀ + Q. Q es el ruido de aceleración blanca continua:
            // q·[[dt³/3, dt²/2], [dt²/2, dt]].
            let dt2 = dt * dt
            let newPP = pp + 2 * dt * pv + dt2 * vv + q * dt2 * dt / 3
            let newPV = pv + dt * vv + q * dt2 / 2
            let newVV = vv + q * dt
            pp = newPP
            pv = newPV
            vv = newVV
        }

        mutating func correct(_ z: Double, r: Double) {
            // Se mide solo la posición (H = [1, 0]). S es la varianza de la innovación (z − p)
            // y K la ganancia: cuánto de esa innovación se cree.
            let s = pp + r
            guard s > 0 else { return }
            let kp = pp / s
            let kv = pv / s
            let innovation = z - p
            p += kp * innovation
            v += kv * innovation
            // P ← (I − K·H)·P
            let newPP = (1 - kp) * pp
            let newPV = (1 - kp) * pv
            let newVV = vv - kv * pv
            pp = newPP
            pv = newPV
            vv = newVV
        }
    }
}
