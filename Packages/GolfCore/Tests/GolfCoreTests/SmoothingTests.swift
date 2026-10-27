import Foundation
import Testing
@testable import GolfCore

struct SmoothingTests {
    @Test("Savitzky-Golay (9, 3) deja intacto un polinomio de grado 3, también en los extremos")
    func savitzkyGolayKeepsCubic() {
        let values = (0..<40).map { i -> Double in
            let t = Double(i)
            return 0.002 * t * t * t - 0.1 * t * t + 3 * t + 7
        }
        let smoothed = Smoothing.savitzkyGolay(values, window: 9, order: 3)
        let maxError = zip(values, smoothed).map { abs($0 - $1) }.max() ?? 1
        #expect(maxError < 1e-8)
    }

    @Test("La derivada de Savitzky-Golay es exacta en una parábola")
    func savitzkyGolayDerivative() {
        let dt = 0.01
        let values = (0..<50).map { i -> Double in
            let t = Double(i) * dt
            return 3 * t * t + 2 * t + 1
        }
        let derivative = Smoothing.savitzkyGolay(values, window: 9, order: 3, derivative: 1, sampleSpacing: dt)
        for (i, value) in derivative.enumerated() {
            #expect(abs(value - (6 * Double(i) * dt + 2)) < 1e-6)
        }
    }

    @Test("Savitzky-Golay quita buena parte del ruido de una señal suave")
    func savitzkyGolayReducesNoise() {
        var rng = SeededRandom(seed: 3)
        let clean = (0..<200).map { 100 * sin(Double($0) * 0.05) }
        let noisy = clean.map { $0 + rng.nextGaussian() * 2 }
        let smoothed = Smoothing.savitzkyGolay(noisy, window: 9, order: 3)
        func rms(_ a: [Double]) -> Double { (zip(a, clean).map { ($0 - $1) * ($0 - $1) }.reduce(0, +) / Double(a.count)).squareRoot() }
        #expect(rms(smoothed) < 0.7 * rms(noisy))
    }

    @Test("Con menos muestras que la ventana, la ventana encoge")
    func savitzkyGolayShortSeries() {
        let line = [1.0, 3, 5, 7, 9]
        let smoothed = Smoothing.savitzkyGolay(line, window: 9, order: 3)
        #expect(smoothed.count == 5)
        #expect(zip(line, smoothed).allSatisfy { abs($0 - $1) < 1e-9 })
        #expect(Smoothing.savitzkyGolay([], window: 9, order: 3).isEmpty)
    }

    @Test("One Euro: una señal quieta con temblor se calma mucho")
    func oneEuroCalmsJitter() {
        var rng = SeededRandom(seed: 5)
        var filter = OneEuroFilter(minCutoff: 1, beta: 0)
        var raw: [Double] = []
        var filtered: [Double] = []
        for i in 0..<240 {
            let value = 50 + rng.nextGaussian() * 2
            raw.append(value)
            filtered.append(filter.filter(value, at: Double(i) / 120))
        }
        func spread(_ a: [Double]) -> Double {
            let tail = Array(a.suffix(120))
            let mean = tail.reduce(0, +) / Double(tail.count)
            return (tail.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(tail.count)).squareRoot()
        }
        #expect(spread(filtered) < 0.3 * spread(raw))
    }

    @Test("One Euro: con beta se queda menos atrás en un movimiento rápido")
    func oneEuroFollowsFastMotion() {
        func lag(beta: Double) -> Double {
            var filter = OneEuroFilter(minCutoff: 1, beta: beta)
            var last = 0.0
            for i in 0..<60 {
                let t = Double(i) / 120
                last = filter.filter(2000 * t, at: t)
            }
            return 2000 * 59.0 / 120 - last
        }
        #expect(lag(beta: 0.05) < 0.5 * lag(beta: 0))
        // Una muestra repetida (mismo instante) no rompe nada.
        var filter = OneEuroFilter()
        _ = filter.filter(1, at: 0)
        #expect(filter.filter(5, at: 0) == 1)
    }

    @Test("Huecos de hasta 4 muestras se rellenan en línea recta; los largos y los de los extremos no")
    func fillGaps() {
        #expect(Smoothing.fillGaps([1, nil, nil, 4], maxGap: 4) == [1, 2, 3, 4])
        let long: [Double?] = [0, nil, nil, nil, nil, nil, 6]
        #expect(Smoothing.fillGaps(long, maxGap: 4) == long)
        #expect(Smoothing.fillGaps([nil, 2, nil, 4, nil], maxGap: 4) == [nil, 2, 3, 4, nil])
        let points: [Point2D?] = [Point2D(0, 0), nil, Point2D(4, 8)]
        #expect(Smoothing.fillGaps(points, maxGap: 4)[1] == Point2D(2, 4))
    }
}
