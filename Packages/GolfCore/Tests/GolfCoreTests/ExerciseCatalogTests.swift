import Foundation
import Testing
@testable import GolfCore

struct ExerciseCatalogTests {
    @Test("15 fallos con id único, numerados del 1 al 15 y sin revisar por un profesional")
    func catalog() {
        let all = ExerciseCatalog.all
        #expect(all.count == 15)
        #expect(Set(all.map(\.id)).count == 15)
        #expect(all.map(\.number) == Array(1...15))
        #expect(all.allSatisfy { !$0.reviewedByProfessional })
        #expect(all.allSatisfy { $0.imageFile == "\($0.id).png" && $0.clipFile == "\($0.id).mp4" })
    }

    @Test("Cada ejercicio cabe en una o dos frases y ningún texto está vacío")
    func texts() {
        for e in ExerciseCatalog.all {
            let sentences = e.exercise.split(whereSeparator: { ".!?".contains($0) }).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            #expect((1...2).contains(sentences.count), "\(e.id): \(sentences.count) frases")
            for text in [e.fault, e.whatYouSee, e.equipment, e.repetitions, e.feeling, e.typicalMistake] {
                #expect(!text.isEmpty, "\(e.id)")
            }
        }
    }

    @Test("Con la cámara de detrás solo salen los que el análisis mide; los de frente, no")
    func measurable() {
        let shown = ExerciseCatalog.shown(camera: .behind).map(\.id)
        #expect(shown.contains("takeaway_dentro"))
        #expect(!shown.contains("deslizamiento_cadera"))   // de frente
        #expect(!shown.contains("transicion_brusca"))      // aún no se mide
        #expect(ExerciseCatalog.all.filter { !$0.isMeasurable() }.allSatisfy { $0.detectedBy.isEmpty || $0.camera == .front })
    }

    @Test("Cada fallo del análisis con ejercicio en el catálogo lo encuentra")
    func linkedFaults() {
        #expect(ExerciseCatalog.exercises(for: [.takeawayInside]).map(\.id) == ["takeaway_dentro"])
        #expect(ExerciseCatalog.exercises(for: [.shortFinish, .unbalancedFinish]).map(\.id) == ["equilibrio_final"])
        #expect(ExerciseCatalog.exercises(for: [.headMovement, .fastTempo]).map(\.id) == ["ritmo_rapido", "cabeza_se_mueve"])
        // Ningún fallo del análisis apunta a dos ejercicios distintos.
        for fault in FaultID.allCases {
            #expect(ExerciseCatalog.all.filter { $0.detectedBy.contains(fault) }.count <= 1, "\(fault)")
        }
    }
}
