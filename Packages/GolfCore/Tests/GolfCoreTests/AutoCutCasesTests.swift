import Foundation
import Testing
@testable import GolfCore

/// Casos completos del corte automático: uno medido en un vídeo real de golf y su contrario, una voz.
struct AutoCutCasesTests {
    /// Caso real medido: vídeo de 46,5 s con 6 impactos de golf. La fuerza va en "veces el umbral"
    /// del detector, tal como se midió; la propuesta solo compara fuerzas entre sí, así que la unidad da igual.
    static let duration = 46.5
    static let shots: [(time: Double, strength: Double)] = [
        (1.27, 128), (9.05, 154), (19.10, 42), (29.20, 70), (37.98, 100), (43.58, 97),
    ]
    /// El resto de lo que detecta el detector: ruido de fondo por debajo de 17 veces el umbral.
    /// Se ponen como transitorios sueltos entre los golpes (el caso medido no da sus instantes).
    static let background: [(time: Double, strength: Double)] = [
        (4.5, 16.9), (12.0, 12.3), (15.5, 8.0), (22.4, 5.5), (25.8, 3.1), (32.6, 14.2), (35.5, 1.6), (40.5, 10.7), (46.0, 6.4),
    ]

    static var impacts: [Impact] {
        (shots + background).map { Impact(time: $0.time, strength: $0.strength, prominence: 6 * $0.strength) }
    }

    @Test("Caso real: los 6 golpes se proponen y el ruido de fondo queda sin marcar")
    func measuredGolfSession() {
        let proposal = ClipPlanner.propose(for: Self.impacts, recordingDuration: Self.duration, mode: .swing)
        #expect(proposal.isShotSeries)
        #expect(proposal.windows.count == Self.shots.count + Self.background.count)
        let suggested = proposal.windows.filter { $0.isSuggested }.map { $0.impactTime }
        #expect(suggested == Self.shots.map { $0.time })
        let unmarked = proposal.windows.filter { !$0.isSuggested }.map { $0.impactTime }
        #expect(unmarked == Self.background.map { $0.time })
        // Ninguno de los 6 se queda corto en Swing (el primero, a 1,27 s, tiene 1,27 s antes: basta).
        #expect(proposal.windows.filter { $0.isSuggested }.allSatisfy { !$0.isTooShort })
    }

    @Test("Caso real en Tracer: el golpe de 43,58 s se queda corto (solo hay 2,92 s de vuelo grabado)")
    func measuredGolfSessionTracer() throws {
        let proposal = ClipPlanner.propose(for: Self.impacts, recordingDuration: Self.duration, mode: .tracer)
        let suggested = proposal.windows.filter { $0.isSuggested }.map { $0.impactTime }
        #expect(suggested == Self.shots.dropLast().map { $0.time })
        let last = try #require(proposal.windows.first { $0.impactTime == 43.58 })
        #expect(last.isTooShort)
        // 42,58 a 46,5 s: 3,92 s, menos del 60 % de los 9 s previstos.
        #expect(abs(last.duration - 3.92) < 1e-9)
    }

    @Test("Caso contrario: 95 s de voz continua con 214 transitorios no dan ninguna lista")
    func continuousVoice() {
        let voice = SyntheticVoice.make(seconds: 95, transients: 214, seed: 11)
        // El sonido es el descrito: 214 transitorios, hueco mediano de 0,30 s, dentro de los 95 s,
        // y más energía en 200 a 1000 Hz que en 1,5 a 7 kHz.
        let times = voice.transientTimes
        #expect(times.count == 214)
        #expect(times.last! < 95)
        let gaps = zip(times, times.dropFirst()).map { $1 - $0 }
        #expect(abs(LinearAlgebra.median(gaps) - 0.30) < 0.02)
        let low = SyntheticVoice.bandEnergy(voice.samples, low: 200, high: 1000, sampleRate: voice.sampleRate)
        let high = SyntheticVoice.bandEnergy(voice.samples, low: 1500, high: 7000, sampleRate: voice.sampleRate)
        #expect(low > high)

        // El detector sí oye muchos "golpes" (las consonantes)…
        let impacts = ImpactDetector.detect(samples: voice.samples, sampleRate: voice.sampleRate)
        #expect(impacts.count > 50)
        // (Con la semilla de este test salen 97: el periodo refractario de 0,4 s junta los 214 transitorios,
        // y 88 quedan a menos de 2 s del anterior.)
        // …pero el control de sensatez no lo reconoce como una tanda y no se propone ninguna lista.
        for mode in CaptureMode.allCases {
            let proposal = ClipPlanner.propose(for: impacts, recordingDuration: 95, mode: mode)
            #expect(!proposal.isShotSeries)
            #expect(proposal.windows.isEmpty)
        }
    }
}
