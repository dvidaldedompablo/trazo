import Foundation
import Testing
@testable import GolfCore

struct ShotCheckTests {
    func impact(_ time: Double, _ strength: Double = 100) -> Impact {
        Impact(time: time, strength: strength, prominence: 200)
    }

    func answer(_ sheets: [(String, String, String, Double)]) -> String {
        let items = sheets.map { #"{"hoja":"\#($0.0)","hay_swing":"\#($0.1)","sonido_es_impacto":"\#($0.2)","confianza":\#($0.3)}"# }
        return #"{"hojas":[\#(items.joined(separator: ","))]}"#
    }

    @Test("Se mandan los 12 sonidos más fuertes, en orden de tiempo, en peticiones de 6 hojas")
    func plan() throws {
        let impacts = (0..<15).map { impact(Double($0) + 1, Double(100 - $0)) }
        let requests = ShotCheck.plan(for: impacts, duration: 20)
        #expect(requests.count == 2)
        #expect(requests.map(\.sheets.count) == [6, 6])
        let sheets = requests.flatMap(\.sheets)
        #expect(sheets.map(\.soundTime) == (1...12).map(Double.init))
        #expect(sheets.map(\.name) == (1...12).map { "P\($0)" })
        // Los números de fotograma empiezan en 1 en cada petición y no se repiten dentro de ella.
        #expect(requests[0].sheets[0].numbers.first == 1)
        #expect(requests[0].sheets[1].numbers.first == 13)
        #expect(requests[1].sheets[0].numbers.first == 1)
    }

    @Test("Cada hoja va de 0,6 s antes a 0,2 s después del sonido, recortada al vídeo")
    func sheetTimes() throws {
        let sheet = try #require(ShotCheck.plan(for: [impact(3)], duration: 10).first?.sheets.first)
        #expect(sheet.frameTimes.count == 12)
        #expect(abs(sheet.frameTimes.first! - 2.4) < 1e-9)
        #expect(abs(sheet.frameTimes.last! - 3.2) < 1e-9)
        let early = try #require(ShotCheck.plan(for: [impact(0.2)], duration: 10).first?.sheets.first)
        #expect(early.frameTimes.first == 0)
        #expect(early.numberNearestSound != nil)
    }

    @Test("Un vídeo vertical se dibuja con más columnas y la hoja no pasa de 1536 px")
    func layout() {
        let vertical = ShotCheck.layout(frameWidth: 1080, frameHeight: 1920)
        let horizontal = ShotCheck.layout(frameWidth: 1920, frameHeight: 1080)
        #expect(vertical.columns > horizontal.columns)
        #expect(vertical.columns * vertical.rows >= 12)
        for l in [vertical, horizontal] {
            #expect(l.width <= 1536 && l.height <= 1536)
        }
    }

    @Test("La respuesta se valida: hojas enviadas, valores conocidos y confianza de 0 a 1")
    func parse() throws {
        let request = try #require(ShotCheck.plan(for: [impact(2), impact(6), impact(9)], duration: 12).first)
        let text = answer([("P1", "si", "si", 0.95), ("P2", "no", "talvez", 0.9), ("P3", "no", "no", 1.4),
                           ("P9", "si", "si", 0.9), ("P1", "no", "no", 0.9)])
        let (verdicts, warnings) = ShotCheck.parse(text, for: request)
        #expect(verdicts.count == 1)
        #expect(verdicts[0].soundTime == 2 && verdicts[0].soundIsImpact == .yes)
        #expect(warnings.count == 4)
        #expect(ShotCheck.parse("esto no es JSON", for: request).verdicts.isEmpty)
    }

    @Test("Con música: el corte automático no propone nada y el modelo encuentra el golpe; un golpe, el vídeo entero")
    func musicVideo() {
        // Muchos sonidos seguidos (la música): el control de sensatez dice que no es una tanda de golpes.
        let impacts = stride(from: 0.2, to: 10, by: 0.7).map { impact($0, 80) } + [impact(5.25, 70)]
        #expect(!ClipPlanner.isShotSeries(impacts))
        let verdicts = impacts.map { ShotCheck.Verdict(soundTime: $0.time, hasSwing: .no, soundIsImpact: $0.time == 5.25 ? .yes : .no,
                                                       confidence: 0.95) }
        let checked = ShotCheck.proposal(impacts: impacts, verdicts: verdicts, recordingDuration: 10, mode: .swing)
        #expect(checked.windows.map(\.impactTime) == [5.25])
        #expect(checked.windows[0].start == 0 && checked.windows[0].end == 10)
        #expect(checked.outcomes == [.confirmed])
        #expect(checked.selected == [true])
        #expect(checked.confirmedCount == 1)
        #expect(checked.discardedCount == impacts.count - 1)
    }

    @Test("Un golpe de la música que proponía el corte automático no sale en la lista")
    func rejectedLeavesTheList() {
        let impacts = [impact(3.2, 100), impact(6.4, 30)]
        let original = ClipPlanner.propose(for: impacts, recordingDuration: 10, mode: .swing)
        #expect(original.windows.map(\.isSuggested) == [true, true])
        let verdicts = [ShotCheck.Verdict(soundTime: 3.2, hasSwing: .yes, soundIsImpact: .yes, confidence: 0.95),
                        ShotCheck.Verdict(soundTime: 6.4, hasSwing: .no, soundIsImpact: .no, confidence: 0.95)]
        let checked = ShotCheck.proposal(impacts: impacts, verdicts: verdicts, recordingDuration: 10, mode: .swing)
        #expect(checked.windows.map(\.impactTime) == [3.2])
        #expect(checked.windows[0].start == 0 && checked.windows[0].end == 10)
        #expect(checked.discardedCount == 1)
    }

    @Test("Dos golpes confirmados: el vídeo se divide en dos por la mitad del hueco")
    func twoShotsSplit() {
        let impacts = [impact(4, 100), impact(12, 90), impact(8, 40)]
        let verdicts = [ShotCheck.Verdict(soundTime: 4, hasSwing: .yes, soundIsImpact: .yes, confidence: 0.95),
                        ShotCheck.Verdict(soundTime: 12, hasSwing: .yes, soundIsImpact: .yes, confidence: 0.95),
                        ShotCheck.Verdict(soundTime: 8, hasSwing: .no, soundIsImpact: .no, confidence: 0.95)]
        let checked = ShotCheck.proposal(impacts: impacts, verdicts: verdicts, recordingDuration: 16, mode: .swing)
        #expect(checked.windows.map(\.impactTime) == [4, 12])
        #expect(checked.windows.map(\.start) == [0, 8])
        #expect(checked.windows.map(\.end) == [8, 16])
        #expect(checked.selected == [true, true])
    }

    @Test("Sin respuesta o con duda: se queda lo que proponía el corte automático")
    func unknownKeepsOriginal() {
        let impacts = [impact(3, 100), impact(8, 90)]
        let verdicts = [ShotCheck.Verdict(soundTime: 3, hasSwing: .yes, soundIsImpact: .unsure, confidence: 0.9),
                        ShotCheck.Verdict(soundTime: 8, hasSwing: .yes, soundIsImpact: .yes, confidence: 0.3)]
        let checked = ShotCheck.proposal(impacts: impacts, verdicts: verdicts, recordingDuration: 12, mode: .swing)
        #expect(checked.windows.map(\.impactTime) == [3, 8])
        #expect(checked.outcomes == [.unknown, .unknown])
        #expect(checked.selected == [true, true])
        #expect(checked.discardedCount == 0)
        // Sin ninguna respuesta, los mismos golpes que proponía el corte automático.
        let none = ShotCheck.proposal(impacts: impacts, verdicts: [], recordingDuration: 12, mode: .swing)
        #expect(none.windows.map(\.impactTime) == ClipPlanner.propose(for: impacts, recordingDuration: 12, mode: .swing)
            .windows.filter(\.isSuggested).map(\.impactTime))
    }

    @Test("Dos confirmados a menos de 2 s son el mismo swing: se queda el de más confianza")
    func sameSwing() {
        let impacts = [impact(4.0, 100), impact(4.6, 90)]
        let verdicts = [ShotCheck.Verdict(soundTime: 4.0, hasSwing: .yes, soundIsImpact: .yes, confidence: 0.7),
                        ShotCheck.Verdict(soundTime: 4.6, hasSwing: .yes, soundIsImpact: .yes, confidence: 0.95)]
        let checked = ShotCheck.proposal(impacts: impacts, verdicts: verdicts, recordingDuration: 10, mode: .swing)
        #expect(checked.windows.map(\.impactTime) == [4.6])
        #expect(checked.outcomes == [.confirmed])
        #expect(checked.discardedCount == 1)
    }

    @Test("El cuerpo de la petición lleva el modelo, la semilla, el esquema, una imagen por hoja y store false")
    func body() throws {
        let request = try #require(ShotCheck.plan(for: [impact(2), impact(6)], duration: 10).first)
        let data = try ShotCheck.requestBody(request, sheetJPEGs: [Data([1, 2]), Data([3])])
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["model"] as? String == ShotCheck.model)
        #expect(object["store"] as? Bool == false)
        let input = try #require(object["input"] as? [[String: Any]])
        #expect(input.filter { $0["type"] as? String == "image" }.count == 2)
        let format = try #require(object["response_format"] as? [String: Any])
        #expect(format["schema"] is [String: Any])
        let config = try #require(object["generation_config"] as? [String: Any])
        #expect(config["seed"] as? Int == ShotCheck.seed)
    }

    @Test("El texto del modelo se saca de los pasos de la respuesta de la API")
    func outputText() {
        let response = #"{"steps":[{"type":"thought"},{"type":"model_output","content":[{"type":"text","text":"{\"hojas\":[]}"}]}]}"#
        #expect(ShotCheck.outputText(fromResponse: Data(response.utf8)) == #"{"hojas":[]}"#)
        #expect(ShotCheck.outputText(fromResponse: Data("{}".utf8)) == nil)
    }
}
