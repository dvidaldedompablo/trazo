import Foundation
import Testing
@testable import GolfCore

struct LoudnessTests {
    let fs = SyntheticAudio.sampleRate

    @Test("A 48 kHz, la ponderación K da los coeficientes de la tabla de BS.1770")
    func kWeightingCoefficients() {
        let stages = Loudness.kWeighting(sampleRate: 48_000)
        let shelf = stages[0]
        #expect(abs(shelf.b0 - 1.53512485958697) < 1e-9)
        #expect(abs(shelf.b1 - -2.69169618940638) < 1e-9)
        #expect(abs(shelf.b2 - 1.19839281085285) < 1e-9)
        #expect(abs(shelf.a1 - -1.69065929318241) < 1e-9)
        #expect(abs(shelf.a2 - 0.73248077421585) < 1e-9)
        let highPass = stages[1]
        #expect(highPass.b0 == 1 && highPass.b1 == -2 && highPass.b2 == 1)
        #expect(abs(highPass.a1 - -1.99004745483398) < 1e-9)
        #expect(abs(highPass.a2 - 0.99007225036621) < 1e-9)
    }

    @Test("Un seno de 997 Hz a 0 dBFS en un canal da −3,01 LUFS")
    func sineAtFullScaleIsMinus3() throws {
        let sine = SyntheticAudio.sine(frequency: 997, seconds: 2)
        let mono = try #require(Loudness.integratedLoudness(mono: sine, sampleRate: fs))
        #expect(abs(mono - -3.01) < 0.01)
        // En estéreo con el otro canal en silencio, lo mismo.
        let stereo = try #require(Loudness.integratedLoudness(channels: [sine, [Float](repeating: 0, count: sine.count)], sampleRate: fs))
        #expect(abs(stereo - -3.01) < 0.01)
    }

    @Test("20 dB menos de señal son 20 LU menos")
    func quieterSine() throws {
        let sine = SyntheticAudio.sine(frequency: 997, seconds: 2, amplitude: 0.1)
        let value = try #require(Loudness.integratedLoudness(mono: sine, sampleRate: fs))
        #expect(abs(value - -23.01) < 0.01)
    }

    @Test("Las pausas no bajan la sonoridad integrada (puertas absoluta y relativa)")
    func gatesIgnorePauses() throws {
        let tone = SyntheticAudio.sine(frequency: 997, seconds: 2, amplitude: 0.5)
        let withPause = tone + [Float](repeating: 0, count: Int(2 * fs)) + tone
        let alone = try #require(Loudness.integratedLoudness(mono: tone, sampleRate: fs))
        let paused = try #require(Loudness.integratedLoudness(mono: withPause, sampleRate: fs))
        // Sin puertas, dos segundos de silencio de cada seis bajarían 1,8 LU.
        #expect(abs(paused - alone) < 0.5)
    }

    @Test("Silencio o menos de 400 ms: no hay sonoridad")
    func silenceAndShortAudio() {
        #expect(Loudness.integratedLoudness(mono: [Float](repeating: 0, count: Int(fs)), sampleRate: fs) == nil)
        #expect(Loudness.integratedLoudness(mono: SyntheticAudio.sine(frequency: 997, seconds: 0.3), sampleRate: fs) == nil)
    }

    @Test("El pico real encuentra el pico escondido entre muestras")
    func truePeakFindsHiddenPeak() {
        // Seno a fs/4 con fase de 45°: las muestras valen ±0,707 pero la onda llega a 1.
        let sine = SyntheticAudio.sine(frequency: fs / 4, seconds: 0.1, amplitude: 1, phase: .pi / 4)
        #expect(abs(Loudness.samplePeak(sine) - -3.01) < 0.05)
        #expect(abs(Loudness.truePeak(sine)) < 0.3)
    }

    @Test("Ganancia hasta el objetivo, limitada por el pico real")
    func normalizationGain() {
        #expect(Loudness.gainToTarget(integrated: -23, target: -16) == 7)
        #expect(Loudness.normalizationGain(integrated: -23, truePeak: -10) == 7)
        #expect(Loudness.normalizationGain(integrated: -23, truePeak: -4) == 3)
        #expect(abs(Loudness.linearGain(decibels: -6.020599913) - 0.5) < 1e-9)
    }
}
