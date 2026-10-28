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

    @Test("Corto también si el clip no llega al 60 % de lo previsto (5,4 s en Tracer, 2,7 s en Swing)")
    func tooShortByDuration() {
        // Tracer: 1 s antes y 3 s después tienen margen, pero el clip de 4 s se queda sin casi todo el vuelo.
        let cut = ClipPlanner.windows(for: [impact(2)], recordingDuration: 5, mode: .tracer)[0]
        #expect(cut.duration == 4)
        #expect(cut.isTooShort)
        #expect(!cut.isSuggested)
        // Justo por debajo y por encima del 60 % de 9 s.
        #expect(ClipPlanner.windows(for: [impact(1)], recordingDuration: 5.3, mode: .tracer)[0].isTooShort)
        #expect(!ClipPlanner.windows(for: [impact(1)], recordingDuration: 5.5, mode: .tracer)[0].isTooShort)
        // Swing: 2,6 s no llega a 2,7 aunque haya 1,3 s a cada lado; 3 s sí.
        #expect(ClipPlanner.windows(for: [impact(1.3)], recordingDuration: 2.6, mode: .swing)[0].isTooShort)
        #expect(!ClipPlanner.windows(for: [impact(1.5)], recordingDuration: 3, mode: .swing)[0].isTooShort)
        #expect(CaptureMode.tracer.clipDuration == 9)
        #expect(CaptureMode.swing.clipDuration == 4.5)
    }

    @Test("Control de sensatez: una voz (sonidos secos cada menos de 2 s) no es una tanda de golpes")
    func voiceIsNotAShotSeries() {
        // Como el vídeo de referencia narrado: 133 "impactos" en 95 s, casi todos muy seguidos.
        var rng = SeededRandom(seed: 8)
        var t = 0.3
        var voice: [Impact] = []
        for _ in 0..<133 {
            voice.append(impact(t))
            t += 0.42 + rng.nextUnit() * 0.6
        }
        #expect(!ClipPlanner.isShotSeries(voice))
        // Golpes de verdad: uno cada 15 a 30 s.
        let shots = [5.0, 22, 41, 60, 88].map { impact($0) }
        #expect(ClipPlanner.isShotSeries(shots))
        // Golpes con un eco o el golpe de otro jugador justo detrás: sigue siendo una tanda.
        #expect(ClipPlanner.isShotSeries(shots + [impact(23.1)]))
    }

    @Test("Control de sensatez: la regla es \"más de la mitad\" y con menos de dos impactos no se aplica")
    func shotSeriesThreshold() {
        // 4 impactos y 2 muy seguidos (la mitad justa): todavía es una tanda.
        #expect(ClipPlanner.isShotSeries([impact(0), impact(1), impact(10), impact(11)]))
        // 0, 1, 2 y 10 s: el primero no tiene anterior, así que solo 2 de 4 van muy seguidos. Tanda.
        #expect(ClipPlanner.isShotSeries([impact(0), impact(1), impact(2), impact(10)]))
        // 0, 1, 2 y 3 s: 3 de 4 a menos de 2 s del anterior. Ya no.
        #expect(!ClipPlanner.isShotSeries([impact(0), impact(1), impact(2), impact(3)]))
        // Desordenados, igual.
        #expect(!ClipPlanner.isShotSeries([impact(3), impact(1), impact(0), impact(2)]))
        #expect(ClipPlanner.isShotSeries([]))
        #expect(ClipPlanner.isShotSeries([impact(4)]))
    }

    @Test("Marcas de tiempo de la onda: pocas, redondas y repartidas")
    func waveformTicks() {
        #expect(Waveform.timeTicks(duration: 38) == [0, 10, 20, 30])
        #expect(Waveform.timeTicks(duration: 95) == [0, 20, 40, 60, 80])
        #expect(Waveform.timeTicks(duration: 3) == [0, 1, 2, 3])
        #expect(Waveform.timeTicks(duration: 600).count <= 5)
        #expect(Waveform.timeTicks(duration: 0) == [0])
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
