import Foundation
import Testing
@testable import GolfCore

/// Prepara medidas a partir del swing sintético, con la cabeza del palo y sus líneas.
enum SwingFixture {
    static let height = 175.0

    /// Plano del address: cabeza del palo en (900, 1400) y manos en (640, 1180), unos 40,2° con la horizontal.
    static let clubHead = Point2D(900, 1400)

    static func clubLine(angle: Double, through grip: Point2D) -> ClubLine {
        let r = Geometry.radians(angle)
        return ClubLine(grip: grip, head: grip + Point2D(cos(r) * 200, sin(r) * 200))
    }

    static func input(frames: [PoseFrame], handedness: Handedness = .right, takeawayOffset: Double = 0.02,
                      midAngleOffset: Double = -3, transitionAngleOffset: Double = 4, withClub: Bool = true) throws -> SwingMetricsInput {
        let phases = try #require(PhaseDetector.detect(frames: frames, impactTime: SyntheticSwing.impactTime, handedness: handedness))
        let address = frames[phases[.address].frameIndex]
        let neck = try #require(address[.neck])
        let root = try #require(address[.root])
        let addressHands = try #require(address.hands)
        let trunk = neck.distance(to: root)
        let sign = handedness.xSign
        let head = handedness == .right ? clubHead : Point2D(1080 - clubHead.x, clubHead.y)
        let plane = try #require(Geometry.angleFromHorizontal(from: head, to: addressHands))
        let takeawayHands = try #require(frames[phases[.takeaway].frameIndex].hands)
        let midHands = try #require(frames[phases[.midBackswing].frameIndex].hands)
        let transitionHands = try #require(frames[phases[.transition].frameIndex].hands)
        guard withClub else {
            return SwingMetricsInput(frames: frames, phases: phases, handedness: handedness, heightCentimeters: height)
        }
        return SwingMetricsInput(
            frames: frames, phases: phases, handedness: handedness, heightCentimeters: height,
            clubHeadAtAddress: head,
            clubHeadAtTakeaway: takeawayHands + Point2D(sign * takeawayOffset * trunk, 120),
            clubLineAtMidBackswing: clubLine(angle: plane + midAngleOffset, through: midHands),
            clubLineAtTransition: clubLine(angle: plane + transitionAngleOffset, through: transitionHands))
    }

    /// Un swing con fallos: cabeza que se mueve 8 cm en el top, se levanta `tiltLoss` grados en el impacto
    /// y la cadera avanza `hipShift` cm hacia la bola.
    static func faultyFrames(tiltLoss: Double = 12, hipShift: Double = 6) -> [PoseFrame] {
        let pixelsPerCm = 878.0 / height
        return SyntheticSwing.frames { t, joints in
            if t > 1.5 && t < 1.95 {
                joints[.nose]! += Point2D(0, -8 * pixelsPerCm)
            }
            if t > 2.0 && t < 2.2 {
                // Se levanta: el cuello gira hacia la vertical alrededor de la cadera.
                let root = joints[.root]!
                let neck = joints[.neck]!
                let length = neck.distance(to: root)
                let tilt = Geometry.angleFromVertical(from: root, to: neck)! - tiltLoss
                joints[.neck] = root + Point2D(sin(Geometry.radians(tilt)) * length, -cos(Geometry.radians(tilt)) * length)
                joints[.root]! += Point2D(hipShift * pixelsPerCm, 0)
                joints[.neck]! += Point2D(hipShift * pixelsPerCm, 0)
            }
        }
    }
}

struct SwingMetricsTests {
    @Test("Un swing correcto: todas las medidas en su rango")
    func goodSwingMeasurements() throws {
        let input = try SwingFixture.input(frames: SyntheticSwing.frames())
        let m = SwingMetrics.measure(input)
        let tilt = try #require(m[.spineTilt]?.value)
        #expect(abs(tilt - 31.98) < 0.1)
        #expect(m[.spineTilt]?.status == .good)
        let knee = try #require(m[.kneeFlex]?.value)
        #expect(knee > 15 && knee < 30)
        #expect(m[.armsHang]?.status == .good)
        #expect(m[.clubPlane]?.status == .informative)
        // Plano: de la cabeza del palo a las manos en la preparación (unos 40° con la horizontal).
        let addressHands = try #require(input.frames[input.phases[.address].frameIndex].hands)
        let plane = try #require(Geometry.angleFromHorizontal(from: SwingFixture.clubHead, to: addressHands))
        #expect(abs(try #require(m.clubPlaneAngle) - plane) < 1e-9)
        #expect(abs(plane - 40.2) < 1.5)
        #expect(m[.takeawayClubHead]?.status == .good)
        #expect(abs(try #require(m[.midBackswingClub]?.value) - -3) < 1e-6)
        #expect(m[.handsHeight]?.status == .good)
        #expect(try #require(m[.headAtTop]?.value) < 0.5)
        #expect(m[.transitionClub]?.status == .good)
        #expect(abs(try #require(m[.tiltLoss]?.value)) < 0.1)
        #expect(m[.finishBalanced]?.value == 1)
        #expect(m[.finishComplete]?.value == 1)
        #expect(m[.tempo]?.status == .good)
        #expect(m.items.allSatisfy { $0.fault == nil })
        #expect(m.unavailable.isEmpty)
        // Escala: unos 5 px por cm con 175 cm de estatura.
        #expect(abs(try #require(m.scale).pixelsPerCentimeter - 5.02) < 0.05)
    }

    @Test("Un swing con fallos: cada medida dice el suyo con su número")
    func faultySwingMeasurements() throws {
        let m = SwingMetrics.measure(try SwingFixture.input(frames: SwingFixture.faultyFrames(), takeawayOffset: -0.12,
                                                            midAngleOffset: -35))
        #expect(m[.takeawayClubHead]?.fault == .takeawayInside)
        #expect(m[.midBackswingClub]?.fault == .flatMidBackswing)
        let head = try #require(m[.headAtTop])
        #expect(abs(try #require(head.value) - 8) < 0.3)
        #expect(head.fault == .headMovement)
        let tilt = try #require(m[.tiltLoss])
        #expect(abs(try #require(tilt.value) - 12) < 0.3)
        #expect(abs(try #require(tilt.reference) - 19.98) < 0.3)
        #expect(tilt.fault == .earlyExtension)
        let hip = try #require(m[.hipToBall])
        #expect(abs(try #require(hip.value) - 6) < 0.3)
        #expect(hip.fault == .earlyExtension)
    }

    @Test("Sin cabeza del palo, las medidas del palo se omiten (y se dice cuáles)")
    func missingClub() throws {
        let m = SwingMetrics.measure(try SwingFixture.input(frames: SyntheticSwing.frames(), withClub: false))
        let missing = Set(m.unavailable)
        #expect(missing == [.clubPlane, .takeawayClubHead, .midBackswingClub, .transitionClub])
        #expect(m[.spineTilt]?.value != nil)
    }

    @Test("Un zurdo reflejado da las mismas medidas")
    func leftHandedMirrors() throws {
        let right = SwingMetrics.measure(try SwingFixture.input(frames: SyntheticSwing.frames()))
        let left = SwingMetrics.measure(try SwingFixture.input(frames: SyntheticSwing.mirrored(SyntheticSwing.frames()), handedness: .left))
        for kind in MetricKind.allCases {
            let a = right[kind]?.value
            let b = left[kind]?.value
            #expect((a == nil) == (b == nil), "\(kind)")
            if let a, let b { #expect(abs(a - b) < 1e-6, "\(kind)") }
        }
    }

    @Test("Las reglas: dentro del rango, bien; fuera, penalización proporcional; fallo solo pasado su umbral")
    func ruleEvaluation() {
        #expect(SwingMetrics.evaluate(.spineTilt, value: 35).status == .good)
        let upright = SwingMetrics.evaluate(.spineTilt, value: 24)
        #expect(upright.status == .low && upright.fault == .uprightPosture && abs(upright.penalty - 1) < 1e-9)
        // Manos un poco bajas en el top: resta, pero "Subida corta" solo se dice por debajo de 0,10.
        let lowHands = SwingMetrics.evaluate(.handsHeight, value: 0.25)
        #expect(lowHands.penalty > 0 && lowHands.fault == nil)
        #expect(SwingMetrics.evaluate(.handsHeight, value: 0.05).fault == .shortBackswing)
        // Ritmo 2,5: fuera de 2,6 a 3,4 pero sin llegar a "rápido" (< 2,4).
        #expect(SwingMetrics.evaluate(.tempo, value: 2.5).fault == nil)
        #expect(SwingMetrics.evaluate(.tempo, value: 2.2).fault == .fastTempo)
        #expect(SwingMetrics.evaluate(.tempo, value: 4.0).fault == .slowTempo)
        #expect(SwingMetrics.evaluate(.backswingDuration, value: 0.8).status == .informative)
        #expect(SwingMetrics.evaluate(.headAtTop, value: nil).status == .unavailable)
    }
}
