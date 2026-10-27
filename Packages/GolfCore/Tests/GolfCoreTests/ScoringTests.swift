import Foundation
import Testing
@testable import GolfCore

struct ScoringTests {
    /// Medidas a mano: todas buenas salvo las que se pasen.
    static func measurements(_ overrides: [MetricKind: Double?] = [:]) -> SwingMeasurements {
        let good: [MetricKind: Double] = [
            .spineTilt: 35, .kneeFlex: 22, .armsHang: 0.05, .clubPlane: 45, .takeawayClubHead: 0.02,
            .midBackswingClub: 0, .backswingDuration: 0.8, .handsHeight: 0.6, .headAtTop: 1,
            .transitionClub: 2, .tiltLoss: 2, .hipToBall: 1, .headAtImpact: 1,
            .finishBalanced: 1, .finishComplete: 1, .tempo: 3,
        ]
        let items = MetricKind.allCases.map { kind -> MetricResult in
            let value: Double? = overrides.keys.contains(kind) ? overrides[kind]! : good[kind]
            return SwingMetrics.evaluate(kind, value: value)
        }
        return SwingMeasurements(items: items, scale: PixelScale(pixelsPerCentimeter: 5), staturePixels: 875, trunkLength: 280)
    }

    @Test("Todo bien: 100, nivel muy alto, sin nada que mejorar")
    func perfectSwing() {
        let score = Scoring.score(Self.measurements())
        #expect(score.total == 100)
        #expect(score.label == "Nivel muy alto")
        #expect(score.strengths.count == 4)
        #expect(score.improvements.isEmpty)
        #expect(score.priority == nil)
    }

    @Test("Pesos: transición e impacto cuentan doble y el ritmo 1,5 veces")
    func weights() {
        // Transición e impacto con un 5; el resto con un 10.
        // (5 × 10 + 2 × 5 + 2 × 5 + 1,5 × 10) / 10,5 × 10 = 80,95 → 81.
        let score = Scoring.score(Self.measurements([.transitionClub: 28, .tiltLoss: 8 + 5 / 0.3]))
        #expect(score[.transition]?.score == 5)
        #expect(abs((score[.impact]?.score ?? 0) - 5) < 1e-9)
        #expect(score.total == 81)
        #expect(score.label == "Muy sólido")
    }

    @Test("Ninguna fase baja de 2")
    func minimumPhaseScore() {
        let score = Scoring.score(Self.measurements([.armsHang: 1.0]))
        #expect(score[.address]?.score == 2)
    }

    @Test("Etiquetas de la nota en sus límites")
    func labels() {
        let cases: [(Int, String)] = [(100, "Nivel muy alto"), (90, "Nivel muy alto"), (89, "Muy sólido"), (80, "Muy sólido"),
                                      (79, "Buena base"), (70, "Buena base"), (69, "Con margen de mejora"),
                                      (60, "Con margen de mejora"), (59, "A construir"), (0, "A construir")]
        for (total, label) in cases { #expect(SwingRules.label(forTotal: total) == label) }
    }

    @Test("A mejorar: las 3 notas más bajas por debajo de 7, cada una con su fallo")
    func improvements() {
        let score = Scoring.score(Self.measurements([
            .spineTilt: 15,          // 10 − 13 × 0,25 = 6,75
            .takeawayClubHead: 0.3,  // 10 − 0,2 × 20 = 6
            .headAtTop: 15,          // 10 − 10 × 0,5 = 5
            .tempo: 2.0,             // 10 − 0,6 × 4 = 7,6 (no entra: 7 o más)
            .finishBalanced: 0,      // 10 − 3 = 7 (no entra)
            .transitionClub: 30,     // 10 − 22 × 0,25 = 4,5
        ]))
        #expect(score.improvements.map(\.phase) == [.transition, .top, .takeaway])
        #expect(score.improvements.map(\.fault) == [.steepDownswing, .headMovement, .takeawayOutside])
        #expect(!score.strengths.contains(.transition))
        #expect(score.strengths.allSatisfy { (score[$0]?.score ?? 0) >= 8 })
    }

    @Test("Prioridad: el fallo de mayor peso × (10 − nota)")
    func priorityByWeightedDeficit() {
        // Cabeza en el top: 10 − 5 = 5 (peso 1, cuenta 5). Impacto: 10 − 3,6 = 6,4 (peso 2, cuenta 7,2).
        let score = Scoring.score(Self.measurements([.headAtTop: 15, .tiltLoss: 8 + 6.4 / 0.3]))
        #expect(score.priority == .earlyExtension)
        #expect(score.priorityEffect == nil)
    }

    @Test("Cadena de causa: takeaway por dentro y palo plano → la prioridad es el takeaway")
    func causeChain() {
        // El palo plano resta más que el takeaway, pero el takeaway es su causa.
        let score = Scoring.score(Self.measurements([.takeawayClubHead: -0.1, .midBackswingClub: -35]))
        #expect(score[.midBackswing]?.mainFault == .flatMidBackswing)
        #expect(score.priority == .takeawayInside)
        #expect(score.priorityEffect == .flatMidBackswing)
    }

    @Test("Una fase sin medidas no cuenta en la nota total")
    func unavailablePhaseIsSkipped() {
        let score = Scoring.score(Self.measurements([.takeawayClubHead: nil, .transitionClub: 28]))
        #expect(score[.takeaway]?.score == nil)
        // Sin el takeaway: (4 × 10 + 2 × 5 + 2 × 10 + 1,5 × 10) / 9,5 × 10 = 89,47 → 89.
        #expect(score.total == 89)
    }

    @Test("Sin ninguna medida, no hay nota (y no se inventa)")
    func noMeasurements() {
        let empty = SwingMeasurements(items: MetricKind.allCases.map { SwingMetrics.evaluate($0, value: nil) },
                                      scale: nil, staturePixels: 0, trunkLength: nil)
        let score = Scoring.score(empty)
        #expect(score.total == nil)
        #expect(score.label == "Sin nota")
    }

    @Test("Del swing sintético con fallos a la nota, de punta a punta")
    func endToEnd() throws {
        // Levantarse 12° y adelantar 6 cm la cadera resta más (el impacto pesa doble) que el palo plano.
        let strong = try SwingFixture.input(frames: SwingFixture.faultyFrames(), takeawayOffset: -0.12, midAngleOffset: -35)
        let strongScore = Scoring.score(SwingMetrics.measure(strong))
        let total = try #require(strongScore.total)
        #expect(total > 40 && total < 90)
        #expect(strongScore.priority == .earlyExtension)
        // Con 10° y 5 cm, manda el palo plano… y como su causa es el takeaway, la prioridad es el takeaway.
        let mild = try SwingFixture.input(frames: SwingFixture.faultyFrames(tiltLoss: 10, hipShift: 5),
                                          takeawayOffset: -0.12, midAngleOffset: -35)
        let mildScore = Scoring.score(SwingMetrics.measure(mild))
        #expect(mildScore.priority == .takeawayInside)
        #expect(mildScore.priorityEffect == .flatMidBackswing)
    }
}
