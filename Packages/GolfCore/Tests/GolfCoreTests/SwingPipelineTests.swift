import Foundation
import Testing
@testable import GolfCore

/// Piezas nuevas de la etapa 6: limpieza de la pose, línea del palo y seguidor de plantilla.
struct PoseSeriesTests {
    /// Una muñeca que se mueve en línea recta con ruido y un hueco corto.
    private func frames(gap: Range<Int>?) -> [PoseFrame] {
        var rng = SeededRandom(seed: 5)
        return (0..<60).map { i in
            var joints: [Joint: Point2D] = [:]
            if gap == nil || !gap!.contains(i) {
                let noise = Point2D(rng.nextUnit() * 4 - 2, rng.nextUnit() * 4 - 2)
                joints[.leftWrist] = Point2D(100 + 5 * Double(i), 800 - 3 * Double(i)) + noise
            }
            joints[.neck] = Point2D(300, 300)
            return PoseFrame(time: Double(i) / 120, joints: joints)
        }
    }

    @Test("El suavizado quita el ruido sin torcer un movimiento recto")
    func smoothsNoise() {
        let processed = PoseSeries.process(frames(gap: nil))
        // Error frente a la recta verdadera: con ruido de ±2 px, tras suavizar queda muy por debajo.
        let errors = processed.indices.compactMap { i -> Double? in
            guard let p = processed[i].joints[.leftWrist] else { return nil }
            return p.distance(to: Point2D(100 + 5 * Double(i), 800 - 3 * Double(i)))
        }
        #expect(errors.count == 60)
        #expect(errors.reduce(0, +) / Double(errors.count) < 1.2)
    }

    @Test("Un hueco de 3 fotogramas se rellena; uno de 10 se queda vacío")
    func fillsShortGaps() {
        let short = PoseSeries.process(frames(gap: 20..<23))
        #expect((20..<23).allSatisfy { short[$0].joints[.leftWrist] != nil })
        let long = PoseSeries.process(frames(gap: 20..<30))
        #expect((20..<30).allSatisfy { long[$0].joints[.leftWrist] == nil })
        // Y lo demás sigue ahí.
        #expect(long[5].joints[.leftWrist] != nil && long[45].joints[.leftWrist] != nil)
    }

    @Test("La pose y las posiciones van y vuelven de JSON (para guardarlas en el iPhone)")
    func poseRoundTripsThroughJSON() throws {
        let original = frames(gap: 20..<23)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([PoseFrame].self, from: data)
        #expect(decoded == original)
    }
}

struct ClubLineFinderTests {
    /// Campo gris con una varilla oscura desde las manos hacia abajo a la derecha.
    private func scene(angle degrees: Double, length: Double) -> (GrayImage, Point2D) {
        var image = GrayImage(width: 240, height: 240, value: 128)
        // Algo de textura para que el umbral de bordes no se quede sin mediana.
        var rng = SeededRandom(seed: 3)
        for i in image.pixels.indices { image.pixels[i] = UInt8(120 + Int(rng.nextUnit() * 16)) }
        let hands = Point2D(70, 60)
        let radians = degrees * .pi / 180
        for step in stride(from: 0.0, through: length, by: 0.5) {
            let x = Int((hands.x + cos(radians) * step).rounded())
            let y = Int((hands.y + sin(radians) * step).rounded())
            for dy in -1...1 {
                for dx in -1...1 where x + dx >= 0 && x + dx < 240 && y + dy >= 0 && y + dy < 240 {
                    image.pixels[(y + dy) * 240 + (x + dx)] = 25
                }
            }
        }
        return (image, hands)
    }

    @Test("Encuentra la varilla: el ángulo sale a menos de 4° y la cabeza cerca de la punta")
    func findsShaft(  ) throws {
        let (image, hands) = scene(angle: 52, length: 150)
        let line = try #require(ClubLineFinder.find(in: image, hands: hands))
        let angle = atan2(line.head.y - line.grip.y, line.head.x - line.grip.x) * 180 / .pi
        #expect(abs(angle - 52) < 4)
        let trueHead = Point2D(70 + cos(52 * .pi / 180) * 150, 60 + sin(52 * .pi / 180) * 150)
        #expect(line.head.distance(to: trueHead) < 15)
    }

    @Test("Sin varilla (solo ruido) no se inventa ninguna línea")
    func noLineInNoise() {
        var image = GrayImage(width: 240, height: 240, value: 128)
        var rng = SeededRandom(seed: 9)
        for i in image.pixels.indices { image.pixels[i] = UInt8(100 + Int(rng.nextUnit() * 56)) }
        #expect(ClubLineFinder.find(in: image, hands: Point2D(120, 120)) == nil)
    }
}

struct TemplateTrackerTests {
    /// Una mancha clara con degradado sobre fondo con textura, desplazada entre fotogramas.
    private func frame(blobAt center: Point2D) -> GrayImage {
        var image = GrayImage(width: 160, height: 160, value: 90)
        var rng = SeededRandom(seed: 11)
        for i in image.pixels.indices { image.pixels[i] = UInt8(80 + Int(rng.nextUnit() * 20)) }
        for y in 0..<160 {
            for x in 0..<160 {
                let d = Point2D(Double(x), Double(y)).distance(to: center)
                if d < 9 { image.pixels[y * 160 + x] = UInt8(max(230 - d * 12, 120)) }
            }
        }
        return image
    }

    @Test("La mancha desplazada 6,4 px se encuentra a 1,5 px o menos, con parecido alto")
    func tracksBlob() throws {
        let start = Point2D(60, 90)
        let moved = Point2D(66, 94)
        let template = try #require(TemplateTracker.template(from: frame(blobAt: start), center: start, radius: 12))
        let found = try #require(TemplateTracker.find(template, in: frame(blobAt: moved), around: start, searchRadius: 14))
        #expect(found.center.distance(to: moved) <= 1.5)
        #expect(found.score > 0.6)
    }

    @Test("Si la mancha ya no está, el parecido se queda bajo")
    func lowScoreWhenMissing() throws {
        let start = Point2D(60, 90)
        let template = try #require(TemplateTracker.template(from: frame(blobAt: start), center: start, radius: 12))
        var empty = GrayImage(width: 160, height: 160, value: 90)
        var rng = SeededRandom(seed: 12)
        for i in empty.pixels.indices { empty.pixels[i] = UInt8(80 + Int(rng.nextUnit() * 20)) }
        let found = TemplateTracker.find(template, in: empty, around: start, searchRadius: 14)
        #expect((found?.score ?? 0) < 0.45)
    }
}
