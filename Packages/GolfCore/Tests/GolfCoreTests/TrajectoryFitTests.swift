import Foundation
import Testing
@testable import GolfCore

struct TrajectoryFitTests {
    /// Parábola verdadera (y hacia abajo): sube, hace el vértice en t = 1,4 s y vuelve a y = 900 en t = 2,8 s.
    static func truth(_ t: Double) -> Point2D { Point2D(200 + 120 * t, 900 - 700 * t + 250 * t * t) }

    /// 145 puntos de 0 a 1,2 s a 120 fps con ruido de 0,5 px. El 20 % se sustituye por atípicos
    /// desplazados entre 15 y 80 px en cualquier dirección.
    static func samples(seed: UInt64 = 21) -> (samples: [TrajectorySample], outlierTimes: Set<Double>) {
        var rng = SeededRandom(seed: seed)
        var result: [TrajectorySample] = []
        var outliers = Set<Double>()
        for i in 0...144 {
            let t = Double(i) / 120
            var p = truth(t) + Point2D(rng.nextGaussian() * 0.5, rng.nextGaussian() * 0.5)
            if rng.nextUnit() < 0.2 {
                let angle = rng.nextUnit() * 2 * .pi
                let distance = 15 + rng.nextUnit() * 65
                p += Point2D(cos(angle) * distance, sin(angle) * distance)
                outliers.insert(t)
            }
            result.append(TrajectorySample(time: t, point: p))
        }
        return (result, outliers)
    }

    @Test("Una parábola con un 20 % de atípicos se recupera")
    func recoversParabolaWithOutliers() throws {
        let (samples, planted) = Self.samples()
        #expect(Double(planted.count) / Double(samples.count) > 0.15)
        let fit = try #require(TrajectoryFit.fit(samples))
        let flagged = Set(fit.outliers.map(\.time))
        // Todos los atípicos sembrados se descartan…
        #expect(planted.isSubset(of: flagged))
        // …y casi ningún punto bueno (como mucho el 2 %).
        let wronglyFlagged = flagged.subtracting(planted).count
        #expect(Double(wronglyFlagged) / Double(samples.count - planted.count) <= 0.02)
        // La curva ajustada pasa a menos de 1 px de la verdadera en todo el tramo visto.
        for i in 0...120 {
            let t = Double(i) / 100
            #expect(fit.position(at: t).distance(to: Self.truth(t)) < 1)
        }
        #expect(fit.meanError < 1)
    }

    @Test("Un toque (punto fijo) se respeta: nunca es atípico y la curva pasa por él")
    func fixedPointIsRespected() throws {
        var (samples, _) = Self.samples()
        // El usuario toca 4 px al lado de donde el detector ve la bola.
        let tapTime = 0.6
        let tap = Self.truth(tapTime) + Point2D(4, 0)
        samples.removeAll { abs($0.time - tapTime) < 1e-9 }
        samples.append(TrajectorySample(time: tapTime, point: tap, isFixed: true))
        let fit = try #require(TrajectoryFit.fit(samples))
        let fixed = try #require(fit.samples.firstIndex { $0.isFixed })
        #expect(fit.isOutlier[fixed] == false)
        #expect(fit.position(at: tapTime).distance(to: tap) < 1)
    }

    @Test("Un toque muy desviado sigue sin descartarse, pero sube el error medio (aviso de toque dudoso)")
    func badTapRaisesMeanError() throws {
        let (samples, _) = Self.samples()
        let clean = try #require(TrajectoryFit.fit(samples))
        let tap = TrajectorySample(time: 0.6 + 0.5 / 120, point: Self.truth(0.6) + Point2D(25, 0), isFixed: true)
        let withTap = try #require(TrajectoryFit.fit(samples + [tap]))
        let index = try #require(withTap.samples.firstIndex { $0.isFixed })
        #expect(withTap.isOutlier[index] == false)
        #expect(withTap.meanError > clean.meanError)
    }

    @Test("La extrapolación llega a la caída cerca del instante y el punto verdaderos")
    func extrapolatesToLanding() throws {
        let (samples, _) = Self.samples()
        let fit = try #require(TrajectoryFit.fit(samples))
        let landing = try #require(fit.extrapolateToLanding(groundY: 900))
        #expect(abs(landing.landingTime - 2.8) < 0.1)
        #expect(landing.landingPoint.distance(to: Self.truth(2.8)) < 15)
        #expect(abs(landing.landingPoint.y - 900) < 1e-6)
        #expect(landing.points.first!.time > samples.last!.time)
    }

    @Test("Si la bola todavía no tiende a bajar, no se inventa la caída")
    func noLandingWhenStillAccelerating() throws {
        // Movimiento recto hacia arriba, sin curvatura: nunca vuelve al suelo.
        let samples = (0..<60).map { TrajectorySample(time: Double($0) / 120, point: Point2D(100, 500 - 300 * Double($0) / 120)) }
        let fit = try #require(TrajectoryFit.fit(samples))
        #expect(fit.extrapolateToLanding(groundY: 600) == nil)
    }

    @Test("Con menos de tres instantes distintos no hay ajuste")
    func tooFewSamples() {
        let samples = [TrajectorySample(time: 0, point: .zero), TrajectorySample(time: 0.1, point: Point2D(1, 1))]
        #expect(TrajectoryFit.fit(samples) == nil)
    }

    @Test("Los tramos se solapan a la mitad y cubren todo el vuelo")
    func windowsOverlap() {
        let windows = TrajectoryFit.makeWindows(start: 0, end: 1.2, duration: 0.25)
        #expect(windows.first!.start == 0)
        #expect(abs(windows.last!.end - 1.2) < 1e-12)
        for (a, b) in zip(windows, windows.dropFirst()) { #expect(b.start < a.end) }
        #expect(TrajectoryFit.makeWindows(start: 0, end: 0.2, duration: 0.25).count == 1)
    }
}
