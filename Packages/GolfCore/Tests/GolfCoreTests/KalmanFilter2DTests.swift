import Foundation
import Testing
@testable import GolfCore

struct KalmanFilter2DTests {
    func makeFilter(velocity: Point2D = .zero, velocityStdDev: Double = 500) -> KalmanFilter2D {
        KalmanFilter2D(position: Point2D(10, 300), velocity: velocity, positionStdDev: 2,
                       velocityStdDev: velocityStdDev, processNoise: 1000, measurementNoise: 1)
    }

    @Test("La predicción mueve la posición con la velocidad")
    func predictionMovesWithVelocity() {
        var filter = makeFilter(velocity: Point2D(100, -50))
        filter.predict(dt: 0.1)
        #expect(filter.position.distance(to: Point2D(20, 295)) < 1e-9)
    }

    @Test("La duda crece al predecir y baja al corregir")
    func uncertaintyGrowsAndShrinks() {
        var filter = makeFilter()
        let initial = filter.positionStdDev
        filter.predict(dt: 1.0 / 120)
        let predicted = filter.positionStdDev
        filter.correct(measurement: filter.position)
        let corrected = filter.positionStdDev
        #expect(predicted > initial)
        #expect(corrected < predicted)
        // La puerta de búsqueda crece mientras no hay medidas.
        let gate = filter.gateRadius(sigmas: 4)
        for _ in 0..<5 { filter.predict(dt: 1.0 / 120) }
        #expect(filter.gateRadius(sigmas: 4) > gate)
    }

    @Test("Sigue un movimiento uniforme con ruido y aprende la velocidad sin conocerla")
    func tracksConstantVelocity() {
        var rng = SeededRandom(seed: 11)
        var filter = makeFilter()
        let dt = 1.0 / 120
        var truth = Point2D.zero
        for i in 1...120 {
            let t = Double(i) * dt
            truth = Point2D(10 + 240 * t, 300 - 120 * t)
            filter.predict(dt: dt)
            filter.correct(measurement: truth + Point2D(rng.nextGaussian(), rng.nextGaussian()))
        }
        #expect(filter.position.distance(to: truth) < 1)
        #expect(filter.velocity.distance(to: Point2D(240, -120)) < 15)
    }

    @Test("Distancia de Mahalanobis: cero en la predicción y mayor cuanto más lejos")
    func mahalanobis() {
        var filter = makeFilter()
        filter.predict(dt: 1.0 / 120)
        let p = filter.position
        #expect(filter.mahalanobisDistance(to: p) == 0)
        #expect(filter.mahalanobisDistance(to: p + Point2D(10, 0)) > filter.mahalanobisDistance(to: p + Point2D(3, 0)))
    }
}
