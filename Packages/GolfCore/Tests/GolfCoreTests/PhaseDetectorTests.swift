import Foundation
import Testing
@testable import GolfCore

struct PhaseDetectorTests {
    typealias Swing = SyntheticSwing
    let frameTime = 1 / SyntheticSwing.frameRate

    @Test("Las 7 posiciones caen donde deben en un swing sintético")
    func detectsSevenPositions() throws {
        let phases = try #require(PhaseDetector.detect(frames: Swing.frames(), impactTime: Swing.impactTime))
        // Inicio de la subida: cuando las manos ya se han alejado un 2 % de la estatura (poco después de 1,0 s).
        #expect(phases.backswingStartTime >= 1.0 && phases.backswingStartTime <= 1.1)
        let address = phases[.address]
        #expect(address.time >= 0.9 && address.frameIndex < phases.backswingStartFrame)
        // Takeaway: el brazo ha girado el 22 % de lo que gira entre B y el top.
        let startAngle = Swing.armAngle(at: phases.backswingStartTime)
        let takeawayAngle = Swing.armAngle(at: phases[.takeaway].time)
        #expect(abs(takeawayAngle - (startAngle + 0.22 * (150 - startAngle))) < 3)
        // Mitad de subida y transición: brazo de delante paralelo al suelo (90°), subiendo y bajando.
        #expect(abs(Swing.armAngle(at: phases[.midBackswing].time) - 90) < 3)
        #expect(phases[.midBackswing].time < Swing.topTime)
        #expect(abs(Swing.armAngle(at: phases[.transition].time) - 90) < 7)
        #expect(phases[.transition].time > Swing.topTime)
        // Top, impacto y final.
        #expect(abs(phases[.top].time - Swing.topTime) <= frameTime + 1e-9)
        #expect(abs(phases[.impact].time - Swing.impactTime) <= frameTime / 2 + 1e-9)
        #expect(phases[.finish].time >= 2.45 && phases[.finish].time <= 2.65)
        // Todo en orden y sin alternativas.
        #expect(phases.isOrdered)
        #expect(phases.positions.allSatisfy { !$0.usedAlternative })
        #expect(phases.positions.map(\.position) == SwingPosition.allCases)
    }

    @Test("Ritmo = subida / bajada")
    func tempo() throws {
        let phases = try #require(PhaseDetector.detect(frames: Swing.frames(), impactTime: Swing.impactTime))
        let tempo = try #require(phases.tempo)
        #expect(abs(tempo - phases.backswingDuration / phases.downswingDuration) < 1e-12)
        #expect(abs(phases.downswingDuration - 0.27) <= 2 * frameTime)
        #expect(tempo > 2.5 && tempo < 3.0)
    }

    @Test("Sin sonido, el impacto sale de las manos (punto más bajo tras el top)")
    func impactWithoutSound() throws {
        let phases = try #require(PhaseDetector.detect(frames: Swing.frames(), impactTime: nil))
        #expect(abs(phases[.impact].time - Swing.impactTime) <= 2 * frameTime)
        #expect(phases[.impact].usedAlternative)
    }

    @Test("Un zurdo (el mismo swing reflejado) da las mismas posiciones")
    func leftHanded() throws {
        let right = try #require(PhaseDetector.detect(frames: Swing.frames(), impactTime: Swing.impactTime))
        let left = try #require(PhaseDetector.detect(frames: Swing.mirrored(Swing.frames()), impactTime: Swing.impactTime,
                                                     handedness: .left))
        #expect(right.positions.map(\.frameIndex) == left.positions.map(\.frameIndex))
    }

    @Test("Sin el brazo de delante, la mitad de subida usa la alternativa del 55 % del recorrido")
    func missingLeadArm() throws {
        let phases = try #require(PhaseDetector.detect(frames: Swing.frames(dropLeadArm: true), impactTime: Swing.impactTime))
        #expect(phases[.midBackswing].usedAlternative)
        #expect(phases[.transition].usedAlternative)
        let startAngle = Swing.armAngle(at: phases.backswingStartTime)
        #expect(abs(Swing.armAngle(at: phases[.midBackswing].time) - (startAngle + 0.55 * (150 - startAngle))) < 3)
        #expect(phases.isOrdered)
    }

    @Test("Si las manos no se mueven, no hay swing")
    func noSwing() {
        let still = (0..<200).map { i in
            PoseFrame(time: Double(i) / 120, joints: SyntheticSwing.body.merging([.leftWrist: Point2D(650, 1180)]) { a, _ in a })
        }
        #expect(PhaseDetector.detect(frames: still, impactTime: 1.0) == nil)
        #expect(PhaseDetector.detect(frames: [], impactTime: nil) == nil)
    }

    @Test("Un impacto puesto antes del top marca las posiciones como dudosas")
    func outOfOrderIsDoubtful() throws {
        // Un impacto de otro jugador en mitad de la subida: el top se busca antes de él y el orden se rompe.
        let phases = try #require(PhaseDetector.detect(frames: Swing.frames(), impactTime: 1.6))
        #expect(!phases.isOrdered)
    }
}
