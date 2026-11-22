import Foundation
import Testing
@testable import GolfCore

struct ImprovementPlanTests {
    func score(priority: FaultID?, improvements: [(SwingPhase, Double, FaultID)], phaseFaults: [(SwingPhase, Double, [FaultID])] = []) -> SwingScore {
        SwingScore(phases: phaseFaults.map { PhaseScore(phase: $0.0, score: $0.1, faults: $0.2, mainFault: $0.2.first) },
                   total: 70, label: "Bien", strengths: [],
                   improvements: improvements.map { Improvement(phase: $0.0, score: $0.1, fault: $0.2) },
                   priority: priority, priorityEffect: nil)
    }

    @Test("Los 3 fallos principales con ejercicio: la prioridad primero y sin repetir")
    func topThree() {
        let s = score(priority: .takeawayInside,
                      improvements: [(.tempo, 4, .fastTempo), (.address, 5, .uprightPosture), (.impact, 6, .headMovement)],
                      phaseFaults: [(.finish, 3, [.unbalancedFinish])])
        let items = ImprovementPlan.items(s)
        // La postura erguida no tiene ejercicio en el catálogo: se salta, no se inventa otro.
        #expect(items.map(\.exercise.id) == ["takeaway_dentro", "ritmo_rapido", "cabeza_se_mueve"])
        #expect(items.map(\.number) == [1, 2, 3])
        #expect(items[0].title == "1. Takeaway por dentro")
    }

    @Test("Con un solo fallo con ejercicio, sale uno; sin ninguno, no hay sección")
    func fewer() {
        let one = score(priority: .earlyExtension, improvements: [(.address, 4, .lowPosture)])
        #expect(ImprovementPlan.items(one).count == 1)
        #expect(ImprovementPlan.scriptBlocks(one).map(\.kind) == [.improveIntro, .improve1, .improveSummary])
        #expect(ImprovementPlan.scriptBlocks(one)[0].lines == ["Una cosa para mejorar."])
        let none = score(priority: nil, improvements: [(.address, 4, .lowPosture)])
        #expect(ImprovementPlan.scriptBlocks(none).isEmpty)
    }

    @Test("La voz dice las mismas palabras que la pantalla")
    func sameWords() {
        let s = score(priority: .takeawayInside, improvements: [(.tempo, 4, .fastTempo), (.finish, 5, .shortFinish)])
        let blocks = ImprovementPlan.scriptBlocks(s)
        #expect(blocks.map(\.kind) == [.improveIntro, .improve1, .improve2, .improve3, .improveSummary])
        let items = ImprovementPlan.items(s)
        for (item, block) in zip(items, blocks[1...3]) {
            let spoken = block.lines.joined(separator: " ")
            #expect(spoken == "\(item.title). Ejercicio: \(item.instruction) \(item.repetitions).")
        }
        #expect(blocks.last!.lines == ["Recuerda: takeaway por dentro, ritmo rápido y pérdida de equilibrio en el final."])
        #expect(blocks.flatMap(\.lines).allSatisfy { $0.hasSuffix(".") })
    }
}
