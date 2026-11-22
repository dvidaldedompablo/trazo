import Foundation
import Testing
@testable import GolfCore

struct SwingCheckTests {
    /// Respuesta de posiciones con estos números de fotograma (1 = el primero).
    func positions(_ numbers: [String: Int], swing: String = "si", confidence: Double = 0.9) -> String {
        let items = SwingCheck.moments.map { #""\#($0.key)":{"fotograma":\#(numbers[$0.key] ?? 1),"confianza":\#(confidence)}"# }
        return #"{"hay_swing":"\#(swing)","momentos":{\#(items.joined(separator: ","))}}"#
    }

    let good = ["preparacion": 10, "inicio_subida": 12, "takeaway": 20, "mitad_subida": 26, "top": 40,
                "transicion": 44, "impacto": 50, "final": 70]

    func point(_ x: Int, _ y: Int, visible: Bool = true) -> String { #"{"x":\#(x),"y":\#(y),"visible":\#(visible)}"# }

    func body(addressJoints visible: Bool = true) -> String {
        let images = (1...7).map { k in
            let joints = SwingCheck.joints.enumerated().map { #""\#($0.element.key)":\#(point(100 + 10 * $0.offset, 200 + 20 * $0.offset, visible: k > 1 || visible))"# }
            return #"{"imagen":\#(k),\#(joints.joined(separator: ",")),"empunadura":\#(point(500, 500)),"cabeza_palo":\#(point(600, 900, visible: k != 4))}"#
        }
        return #"{"fotogramas":[\#(images.joined(separator: ","))]}"#
    }

    @Test("Las hojas van de 2,5 s antes a 1,5 s después del impacto, un fotograma cada 0,04 s y de 12 en 12")
    func plan() {
        let request = SwingCheck.positionsPlan(duration: 9, impactHint: 3.2)
        #expect(abs(request.frameTimes.first! - 0.7) < 1e-9)
        #expect(request.frameTimes.last! <= 4.7 + 1e-9)
        #expect(request.frameTimes.count == 101)
        #expect(request.sheets.count == 9)
        #expect(request.sheets.allSatisfy { $0.count <= 12 })
        // Sin impacto: todo el clip, como mucho 120 fotogramas.
        let whole = SwingCheck.positionsPlan(duration: 10, impactHint: nil)
        #expect(whole.frameTimes.count == 120)
        #expect(whole.frameTimes.first == 0)
    }

    @Test("Posiciones válidas: índices en orden y bajada de 0,1 a 0,6 s")
    func goodPositions() throws {
        let request = SwingCheck.positionsPlan(duration: 9, impactHint: 3.2)
        let chosen = try SwingCheck.parsePositions(positions(good), for: request).get()
        #expect(chosen.frameIndex["top"] == 39)
        #expect(abs(chosen.times["impacto"]! - chosen.times["top"]! - 0.4) < 1e-9)
    }

    @Test("El código decide: fuera de orden, bajada imposible o sin swing, no se usa")
    func badPositions() {
        let request = SwingCheck.positionsPlan(duration: 9, impactHint: 3.2)
        var swapped = good
        swapped["top"] = 60
        #expect(SwingCheck.parsePositions(positions(swapped), for: request) == .failure(.outOfOrder("top y transicion")))
        var slow = good
        slow["impacto"] = 60  // 0,8 s de bajada
        slow["final"] = 80
        if case .failure(.badDownswing) = SwingCheck.parsePositions(positions(slow), for: request) {} else { Issue.record("debía fallar") }
        #expect(SwingCheck.parsePositions(positions(good, swing: "no"), for: request) == .failure(.noSwing))
        var outside = good
        outside["final"] = 500
        #expect(SwingCheck.parsePositions(positions(outside), for: request) == .failure(.unreadable))
        #expect(SwingCheck.parsePositions("nada", for: request) == .failure(.unreadable))
    }

    @Test("El cuerpo: de 0-1000 a píxeles, sin los puntos no visibles, con cuello y cadera del medio")
    func parseBody() throws {
        let marks = try SwingCheck.parseBody(body(), width: 1000, height: 2000).get()
        #expect(marks.count == 7)
        let address = try #require(marks[.address])
        #expect(address.joints[.nose] == Point2D(x: 100, y: 400))
        #expect(address.joints[.neck] != nil && address.joints[.root] != nil)
        #expect(address.grip == Point2D(x: 500, y: 1000))
        #expect(marks[.top]?.clubHead == nil)  // la cabeza del palo no se ve en el top
        // Sin el cuerpo de la preparación, no hay estatura: plan B.
        #expect(SwingCheck.parseBody(body(addressJoints: false), width: 1000, height: 2000) == .failure(.noBody))
    }

    @Test("El resultado: articulaciones solo en las 7 posiciones, posiciones en orden y el palo")
    func result() throws {
        let request = SwingCheck.positionsPlan(duration: 9, impactHint: 3.2)
        let chosen = try SwingCheck.parsePositions(positions(good), for: request).get()
        let marks = try SwingCheck.parseBody(body(), width: 1000, height: 2000).get()
        let analysis = SwingCheck.result(request, chosen: chosen, marks: marks)
        #expect(analysis.frames.count == request.frameTimes.count)
        #expect(analysis.frames.filter { !$0.joints.isEmpty }.count == 7)
        #expect(analysis.phases.positions.map(\.position) == SwingPosition.allCases)
        #expect(analysis.phases[.top].frameIndex == 39)
        #expect(analysis.phases.backswingStartFrame == 11)
        #expect(analysis.clubHeadAtAddress != nil)
        #expect(analysis.clubLineAtMidBackswing != nil)
        #expect(abs(analysis.impactTime - analysis.phases[.impact].time) < 1e-9)
        // Las medidas se pueden calcular con esto.
        let measured = SwingMetrics.measure(SwingMetricsInput(frames: analysis.frames, phases: analysis.phases, handedness: .right,
                                                              heightCentimeters: 175, clubHeadAtAddress: analysis.clubHeadAtAddress,
                                                              clubHeadAtTakeaway: analysis.clubHeadAtTakeaway,
                                                              clubLineAtMidBackswing: analysis.clubLineAtMidBackswing,
                                                              clubLineAtTransition: analysis.clubLineAtTransition))
        #expect(!measured.items.isEmpty)
    }

    @Test("Los esquemas son JSON válido y los cuerpos llevan una imagen por hoja o por posición")
    func bodies() throws {
        _ = try JSONSerialization.jsonObject(with: Data(SwingCheck.positionsSchemaJSON.utf8))
        _ = try JSONSerialization.jsonObject(with: Data(SwingCheck.bodySchemaJSON.utf8))
        let request = SwingCheck.positionsPlan(duration: 3, impactHint: nil)
        let data = try SwingCheck.positionsBody(request, sheetJPEGs: request.sheets.map { _ in Data([1]) })
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try #require(object["input"] as? [[String: Any]])
        #expect(input.filter { $0["type"] as? String == "image" }.count == request.sheets.count)
        let bodyData = try SwingCheck.bodyBody(frameJPEGs: (0..<7).map { _ in Data([2]) })
        let bodyObject = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect((bodyObject["input"] as? [[String: Any]])?.filter { $0["type"] as? String == "image" }.count == 7)
    }
}
