import Foundation
import Testing
@testable import GolfCore

struct ScriptWriterTests {
    typealias Fixture = ScoringTests

    /// Escenarios variados: perfecto, con fallos de todas las fases, sin palo y sin nada.
    static func scenarios() -> [(SwingMeasurements, SwingScore)] {
        let overrides: [[MetricKind: Double?]] = [
            [:],
            [.spineTilt: 20, .takeawayClubHead: -0.15, .midBackswingClub: -30, .headAtTop: 9, .transitionClub: 20,
             .tiltLoss: 14, .finishComplete: 0, .tempo: 2.1],
            [.kneeFlex: 40, .armsHang: 0.4, .takeawayClubHead: 0.3, .midBackswingClub: 25, .handsHeight: 0.05,
             .transitionClub: -20, .hipToBall: 7, .headAtImpact: 8, .finishBalanced: 0, .tempo: 4.2],
            [.armsHang: -0.3, .tiltLoss: 2, .hipToBall: 6],
            [.takeawayClubHead: nil, .midBackswingClub: nil, .transitionClub: nil, .clubPlane: nil, .tempo: nil],
        ]
        var result = overrides.map { o -> (SwingMeasurements, SwingScore) in
            let m = Fixture.measurements(o)
            return (m, Scoring.score(m))
        }
        let empty = SwingMeasurements(items: MetricKind.allCases.map { SwingMetrics.evaluate($0, value: nil) },
                                      scale: nil, staturePixels: 0, trunkLength: nil)
        result.append((empty, Scoring.score(empty)))
        return result
    }

    @Test("Todas las frases: de 4 a 14 palabras, sin huecos, con números en español")
    func linesFollowStyle() throws {
        let decimalPoint = try Regex(#"\d\.\d"#)
        for (measurements, score) in Self.scenarios() {
            for seed in 0..<8 as Range<UInt64> {
                let script = ScriptWriter.write(measurements: measurements, score: score, variantSeed: seed)
                #expect(script.blocks.map(\.kind) == ScriptBlockKind.allCases)
                for line in script.allLines {
                    let words = line.split(whereSeparator: \.isWhitespace).count
                    #expect(words >= 4 && words <= 14, "\(words) palabras: \(line)")
                    #expect(!line.contains("{") && !line.contains("}"), "\(line)")
                    #expect(line.firstMatch(of: decimalPoint) == nil, "\(line)")
                    #expect(line.hasSuffix(".") || line.hasSuffix("?"), "\(line)")
                }
            }
        }
    }

    @Test("Gancho según la nota")
    func hookByScore() {
        func hook(_ overrides: [MetricKind: Double?]) -> String {
            let m = Fixture.measurements(overrides)
            return ScriptWriter.write(measurements: m, score: Scoring.score(m))[.hook]!.lines[0]
        }
        #expect(hook([:]) == "Muy buen swing. Vamos a verlo paso a paso.")
        #expect(hook([.headAtTop: 15]) == "Muy buen swing. Solo hay un detalle. ¿Lo ves?")
        // Transición e impacto con un 5 y la cabeza con un 5: 76.
        #expect(hook([.transitionClub: 28, .tiltLoss: 8 + 5 / 0.3, .headAtTop: 15]) == "Casi todo encaja, pero hay un detalle. ¿Lo ves?")
    }

    @Test("Con la cadena de causa, la mitad de subida empieza por \"Por eso,\"")
    func causeChainSaysPorEso() {
        let m = Fixture.measurements([.takeawayClubHead: -0.1, .midBackswingClub: -35])
        let script = ScriptWriter.write(measurements: m, score: Scoring.score(m))
        #expect(script[.midBackswing]!.lines[0] == "Por eso, a mitad de subida, el palo queda plano.")
        #expect(script[.takeaway]!.lines[0] == "El palo se va por dentro muy pronto, detrás de las manos.")
        #expect(script[.report]!.lines[0] == "Lo primero a trabajar: el takeaway por dentro.")
    }

    @Test("Los números se dicen bien: ritmo, grados, centímetros y nota")
    func spokenNumbers() {
        let m = Fixture.measurements([.tempo: 2.83, .tiltLoss: 12.4, .headAtTop: 7.6])
        // La inclinación del impacto (referencia de tiltLoss) es 35 − 12,4 = 22,6.
        var items = m.items
        let index = items.firstIndex { $0.kind == .tiltLoss }!
        items[index].reference = 22.6
        let measurements = SwingMeasurements(items: items, scale: m.scale, staturePixels: m.staturePixels, trunkLength: m.trunkLength)
        let score = Scoring.score(measurements)
        let script = ScriptWriter.write(measurements: measurements, score: score)
        #expect(script[.tempo]!.lines == ["Tu ritmo es de 2,8 a 1.", "Muy cerca del 3 a 1 de los profesionales."])
        #expect(script[.impact]!.lines[0] == "En el impacto pierdes inclinación: pasas de 35 a 23 grados.")
        #expect(script[.top]!.lines[0] == "La cabeza se mueve unos 8 centímetros. Intenta mantenerla.")
        #expect(script[.score]!.lines[0] == "¿Acertaste? Tu nota: \(score.total!) sobre 100. \(score.label).")
    }

    @Test("Ritmo rápido y lento")
    func tempoFaults() {
        let fast = Fixture.measurements([.tempo: 2.1])
        #expect(ScriptWriter.write(measurements: fast, score: Scoring.score(fast))[.tempo]!.lines[1]
                == "Subes demasiado rápido: tómate más tiempo arriba.")
        let slow = Fixture.measurements([.tempo: 4.1])
        #expect(ScriptWriter.write(measurements: slow, score: Scoring.score(slow))[.tempo]!.lines[1]
                == "Subes muy despacio: arranca la bajada sin esperar.")
    }

    @Test("Lo que no se pudo medir se dice, no se inventa")
    func missingDataIsHonest() {
        let m = Fixture.measurements([.takeawayClubHead: nil, .tempo: nil])
        let script = ScriptWriter.write(measurements: m, score: Scoring.score(m))
        #expect(script[.takeaway]!.lines == ["En esta posición no he podido medir lo suficiente."])
        #expect(script[.tempo]!.lines == ["Esta vez no he podido medir tu ritmo."])
    }

    @Test("La misma semilla da el mismo guion")
    func deterministic() {
        let m = Fixture.measurements()
        let s = Scoring.score(m)
        #expect(ScriptWriter.write(measurements: m, score: s, variantSeed: 3) == ScriptWriter.write(measurements: m, score: s, variantSeed: 3))
    }

    @Test("Biblioteca de fallos: textos completos y cadenas de causa")
    func faultLibrary() {
        #expect(FaultLibrary.all.count == FaultID.allCases.count)
        for fault in FaultLibrary.all {
            #expect(!fault.name.isEmpty && !fault.reportLabel.isEmpty && !fault.focus.isEmpty)
            #expect(fault.exercise.hasSuffix("."))
        }
        #expect(FaultLibrary.cause(of: .flatMidBackswing) == .takeawayInside)
        #expect(FaultLibrary.cause(of: .steepMidBackswing) == .takeawayOutside)
        #expect(FaultLibrary.cause(of: .fastTempo) == nil)
        #expect(Set(FaultLibrary.all.map(\.reportLabel)).count == FaultLibrary.all.count)
        #expect(FaultLibrary.fault(.earlyExtension).reportLabel == "Te levantas en el impacto")
    }
}
