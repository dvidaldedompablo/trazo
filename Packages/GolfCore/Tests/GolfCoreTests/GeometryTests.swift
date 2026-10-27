import Foundation
import Testing
@testable import GolfCore

struct GeometryTests {
    @Test("Ángulo en un vértice: ángulo recto y pierna estirada")
    func angleAtVertex() throws {
        let right = try #require(Geometry.angle(at: Point2D(0, 0), Point2D(10, 0), Point2D(0, 10)))
        #expect(abs(right - 90) < 1e-9)
        let straight = try #require(Geometry.angle(at: Point2D(0, 0), Point2D(0, -10), Point2D(0, 10)))
        #expect(abs(straight - 180) < 1e-9)
    }

    @Test("Ángulo con la vertical: 0° hacia arriba, 45° inclinado, 90° tumbado (y hacia abajo)")
    func angleFromVertical() throws {
        let origin = Point2D(0, 0)
        #expect(abs(try #require(Geometry.angleFromVertical(from: origin, to: Point2D(0, -10)))) < 1e-9)
        #expect(abs(try #require(Geometry.angleFromVertical(from: origin, to: Point2D(10, -10))) - 45) < 1e-9)
        #expect(abs(try #require(Geometry.angleFromVertical(from: origin, to: Point2D(-10, 0))) - 90) < 1e-9)
    }

    @Test("Ángulo con la horizontal no depende del sentido")
    func angleFromHorizontal() throws {
        let a = try #require(Geometry.angleFromHorizontal(from: Point2D(0, 0), to: Point2D(10, -10)))
        let b = try #require(Geometry.angleFromHorizontal(from: Point2D(10, -10), to: Point2D(0, 0)))
        #expect(abs(a - 45) < 1e-9)
        #expect(abs(a - b) < 1e-9)
        let thirty = try #require(Geometry.angleFromHorizontal(from: .zero, to: Point2D(-10, 10 * tan(Geometry.radians(30)))))
        #expect(abs(thirty - 30) < 1e-9)
    }

    @Test("Ángulo entre segmentos (con sentido) y entre rectas (sin sentido)")
    func anglesBetweenSegmentsAndLines() throws {
        let p1 = Point2D(0, 0), p2 = Point2D(10, 0)
        let q1 = Point2D(0, 0), q2 = Point2D(-10, -10 * tan(Geometry.radians(30)))
        let segments = try #require(Geometry.angle(between: p1, p2, and: q1, q2))
        #expect(abs(segments - 150) < 1e-9)
        let lines = try #require(Geometry.lineAngle(between: p1, p2, and: q1, q2))
        #expect(abs(lines - 30) < 1e-9)
    }

    @Test("Un segmento de longitud cero no tiene ángulo")
    func zeroLengthHasNoAngle() {
        #expect(Geometry.angle(at: .zero, .zero, Point2D(1, 0)) == nil)
        #expect(Geometry.angleFromVertical(from: Point2D(3, 3), to: Point2D(3, 3)) == nil)
        #expect(Geometry.distance(from: .zero, toLineThrough: Point2D(1, 1), Point2D(1, 1)) == nil)
    }

    @Test("Intersección de rectas y rectas paralelas")
    func intersection() throws {
        let point = try #require(Geometry.intersection(Point2D(-5, 2), Point2D(5, 2), Point2D(3, -1), Point2D(3, 9)))
        #expect(point.distance(to: Point2D(3, 2)) < 1e-9)
        #expect(Geometry.intersection(Point2D(0, 0), Point2D(1, 0), Point2D(0, 1), Point2D(1, 1)) == nil)
    }

    @Test("Distancia a una recta (con signo) y a un segmento")
    func distances() throws {
        let a = Point2D(-1, 0), b = Point2D(1, 0)
        #expect(abs(try #require(Geometry.distance(from: Point2D(0, 5), toLineThrough: a, b)) - 5) < 1e-9)
        let up = try #require(Geometry.signedDistance(from: Point2D(0, -5), toLineThrough: a, b))
        let down = try #require(Geometry.signedDistance(from: Point2D(0, 5), toLineThrough: a, b))
        #expect(up == -down)
        // Más allá del extremo del segmento cuenta la distancia al extremo.
        #expect(abs(Geometry.distance(from: Point2D(4, 4), toSegment: a, b) - 5) < 1e-9)
    }

    @Test("Escala de píxeles a cm con la estatura (cadena = 87 % de la estatura)")
    func pixelScaleFromHeight() throws {
        // Cadena vertical de 761,25 px: 0,87 × 175 cm × 5 px/cm.
        let ankle = Point2D(0, 1000), knee = Point2D(0, 800), hip = Point2D(0, 600)
        let neck = Point2D(0, 300), nose = Point2D(0, 238.75)
        let scale = try #require(PixelScale(ankle: ankle, knee: knee, hip: hip, neck: neck, nose: nose, heightCentimeters: 175))
        #expect(abs(scale.pixelsPerCentimeter - 5) < 1e-9)
        #expect(abs(scale.centimeters(fromPixels: 50) - 10) < 1e-9)
        #expect(abs(scale.pixels(fromCentimeters: 2) - 10) < 1e-9)
        let stature = PixelScale.staturePixels(ankle: ankle, knee: knee, hip: hip, neck: neck, nose: nose)
        #expect(abs(stature - 875) < 1e-9)
        #expect(PixelScale(ankle: ankle, knee: knee, hip: hip, neck: neck, nose: nose, heightCentimeters: 0) == nil)
    }
}
