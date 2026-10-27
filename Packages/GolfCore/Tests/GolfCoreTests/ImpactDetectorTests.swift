import Foundation
import Testing
@testable import GolfCore

struct ImpactDetectorTests {
    let fs = SyntheticAudio.sampleRate

    @Test("La FFT pone un seno en su frecuencia, con módulo N/2")
    func fftFindsSine() throws {
        let fft = try #require(FFT(size: 256))
        let input = (0..<256).map { sin(2 * Double.pi * 10 * Double($0) / 256) }
        let magnitudes = fft.magnitudes(of: input)
        #expect(magnitudes.count == 129)
        #expect(abs(magnitudes[10] - 128) < 1e-6)
        #expect(magnitudes.enumerated().filter { $0.offset != 10 }.allSatisfy { $0.element < 1e-6 })
        #expect(FFT(size: 100) == nil)
    }

    @Test("Un clic dentro de ruido se detecta con un error menor de 2 ms", arguments: [1, 2, 3] as [UInt64])
    func detectsClickInNoise(seed: UInt64) throws {
        var audio = SyntheticAudio.noise(seconds: 3, level: 0.02, seed: seed)
        let clickTime = 0.8 + 0.3123 * Double(seed)
        SyntheticAudio.addClick(to: &audio, at: clickTime)
        let impacts = ImpactDetector.detect(samples: audio, sampleRate: fs)
        #expect(impacts.count == 1)
        let impact = try #require(impacts.first)
        #expect(abs(impact.time - clickTime) < 0.002)
        #expect(impact.prominence > 50)
    }

    @Test("Varios clics dan varios impactos, cada uno en su sitio")
    func detectsSeveralClicks() {
        var audio = SyntheticAudio.noise(seconds: 3, level: 0.02, seed: 9)
        let times = [0.6, 1.5, 2.4]
        for t in times { SyntheticAudio.addClick(to: &audio, at: t) }
        let impacts = ImpactDetector.detect(samples: audio, sampleRate: fs)
        #expect(impacts.count == times.count)
        for (impact, t) in zip(impacts, times) { #expect(abs(impact.time - t) < 0.002) }
    }

    @Test("Solo ruido o silencio: ningún impacto", arguments: [4, 5, 6] as [UInt64])
    func noClickNoImpact(seed: UInt64) {
        let noise = SyntheticAudio.noise(seconds: 3, level: 0.02, seed: seed)
        #expect(ImpactDetector.detect(samples: noise, sampleRate: fs).isEmpty)
        let silence = [Float](repeating: 0, count: Int(fs))
        #expect(ImpactDetector.detect(samples: silence, sampleRate: fs).isEmpty)
        #expect(ImpactDetector.detect(samples: [0.5, -0.5], sampleRate: fs).isEmpty)
    }

    @Test("Dos clics a menos de 400 ms cuentan como uno: el más fuerte")
    func refractoryPeriodKeepsStrongest() throws {
        var audio = SyntheticAudio.noise(seconds: 2, level: 0.02, seed: 12)
        SyntheticAudio.addClick(to: &audio, at: 0.9, amplitude: 0.3)
        SyntheticAudio.addClick(to: &audio, at: 1.05, amplitude: 0.8)
        let impacts = ImpactDetector.detect(samples: audio, sampleRate: fs)
        #expect(impacts.count == 1)
        #expect(abs(try #require(impacts.first).time - 1.05) < 0.002)
    }

    @Test("Con golpes de otros jugadores, el más fuerte es el propio")
    func strongestImpact() throws {
        var audio = SyntheticAudio.noise(seconds: 3, level: 0.02, seed: 13)
        SyntheticAudio.addClick(to: &audio, at: 0.7, amplitude: 0.15)
        SyntheticAudio.addClick(to: &audio, at: 1.6, amplitude: 0.9)
        SyntheticAudio.addClick(to: &audio, at: 2.5, amplitude: 0.2)
        #expect(ImpactDetector.detect(samples: audio, sampleRate: fs).count == 3)
        let strongest = try #require(ImpactDetector.strongest(samples: audio, sampleRate: fs))
        #expect(abs(strongest.time - 1.6) < 0.002)
    }

    @Test("Un tono grave fuerte (fuera de la banda) no es un impacto")
    func lowRumbleIsIgnored() {
        var audio = SyntheticAudio.noise(seconds: 2, level: 0.01, seed: 14)
        let start = Int(0.8 * fs)
        for i in 0..<Int(0.3 * fs) {
            audio[start + i] += Float(0.8 * sin(2 * Double.pi * 120 * Double(i) / fs))
        }
        #expect(ImpactDetector.detect(samples: audio, sampleRate: fs).isEmpty)
    }
}
