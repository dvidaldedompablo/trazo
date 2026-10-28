import Foundation
import Testing
@testable import GolfCore

struct ClipPlannerTests {
    func impact(_ time: Double, _ strength: Double = 100) -> Impact {
        Impact(time: time, strength: strength, prominence: 200)
    }

    @Test("Tracer: 1 s antes y 8 s después del impacto; swing: 2,5 s antes y 2 s después")
    func margins() throws {
        let tracer = try #require(ClipPlanner.windows(for: [impact(10)], recordingDuration: 60, mode: .tracer).first)
        #expect(tracer.start == 9 && tracer.end == 18)
        #expect(tracer.impactOffset == 1)
        let swing = try #require(ClipPlanner.windows(for: [impact(10)], recordingDuration: 60, mode: .swing).first)
        #expect(swing.start == 7.5 && swing.end == 12)
        #expect(swing.duration == 4.5)
    }

    @Test("Un clip por golpe, en orden, recortado a la grabación")
    func onePerImpactClamped() {
        let windows = ClipPlanner.windows(for: [impact(20), impact(0.5), impact(25)], recordingDuration: 27, mode: .tracer)
        #expect(windows.map(\.impactTime) == [0.5, 20, 25])
        #expect(windows[0].start == 0)
        #expect(windows[2].end == 27)
        // Golpes seguidos: los clips se solapan antes que cortar uno.
        #expect(windows[1].end > windows[2].start)
    }

    @Test("Menos de 1 s antes o después del golpe: demasiado corto y sin proponer")
    func tooShort() {
        let windows = ClipPlanner.windows(for: [impact(0.4), impact(5), impact(9.6)], recordingDuration: 10, mode: .swing)
        #expect(windows.map(\.isTooShort) == [true, false, true])
        #expect(windows.map(\.isSuggested) == [false, true, false])
    }

    @Test("Se proponen los golpes que suenan al menos una cuarta parte del más fuerte")
    func suggestions() {
        let windows = ClipPlanner.windows(for: [impact(5, 100), impact(15, 30), impact(25, 10)], recordingDuration: 40, mode: .tracer)
        #expect(windows.map(\.isSuggested) == [true, true, false])
        #expect(ClipPlanner.windows(for: [], recordingDuration: 40, mode: .tracer).isEmpty)
    }

    @Test("La onda en barras: el pico de cada trozo, de 0 a 1")
    func waveformBars() {
        var samples = [Float](repeating: 0.01, count: 1000)
        samples[750] = -0.5
        samples[100] = 0.25
        let bars = Waveform.bars(samples: samples, count: 10)
        #expect(bars.count == 10)
        #expect(bars[7] == 1)
        #expect(abs(bars[1] - 0.5) < 1e-9)
        #expect(abs(bars[0] - 0.02) < 1e-6)
        #expect(Waveform.bars(samples: [], count: 4) == [0, 0, 0, 0])
        #expect(Waveform.barIndex(for: 7.5, duration: 10, count: 10) == 7)
        #expect(Waveform.barIndex(for: 99, duration: 10, count: 10) == 9)
    }
}
