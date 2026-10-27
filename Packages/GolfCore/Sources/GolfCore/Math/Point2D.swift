import Foundation

/// Un punto (o un vector) en el plano de la imagen, en píxeles.
///
/// Convención de todo GolfCore: origen arriba a la izquierda, x hacia la derecha e y hacia abajo,
/// como en los fotogramas y en UIKit. Vision usa y hacia arriba y coordenadas de 0 a 1:
/// la app las convierte al leerlas, y aquí dentro ya no hay que pensar en ello.
/// Es un tipo propio (y no `CGPoint`) para que GolfCore no dependa de Core Graphics
/// y para hacer todas las cuentas en `Double`.
public struct Point2D: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Forma corta: `Point2D(3, 4)`.
    public init(_ x: Double, _ y: Double) {
        self.init(x: x, y: y)
    }

    public static let zero = Point2D(0, 0)

    /// Longitud del vector (su distancia al origen).
    public var length: Double { (x * x + y * y).squareRoot() }

    public func distance(to other: Point2D) -> Double { (self - other).length }

    /// Producto escalar: mide cuánto apuntan dos vectores en la misma dirección.
    public func dot(_ other: Point2D) -> Double { x * other.x + y * other.y }

    /// Producto vectorial en 2D (la componente z). Su signo dice a qué lado de un vector queda el otro.
    public func cross(_ other: Point2D) -> Double { x * other.y - y * other.x }

    /// El mismo vector con longitud 1, o `nil` si es el vector cero (no tiene dirección).
    public var normalized: Point2D? {
        let l = length
        return l > 0 ? self / l : nil
    }

    public static func + (a: Point2D, b: Point2D) -> Point2D { Point2D(a.x + b.x, a.y + b.y) }
    public static func - (a: Point2D, b: Point2D) -> Point2D { Point2D(a.x - b.x, a.y - b.y) }
    public static func * (a: Point2D, k: Double) -> Point2D { Point2D(a.x * k, a.y * k) }
    public static func * (k: Double, a: Point2D) -> Point2D { Point2D(a.x * k, a.y * k) }
    public static func / (a: Point2D, k: Double) -> Point2D { Point2D(a.x / k, a.y / k) }
    public static prefix func - (a: Point2D) -> Point2D { Point2D(-a.x, -a.y) }
    public static func += (a: inout Point2D, b: Point2D) { a = a + b }
    public static func -= (a: inout Point2D, b: Point2D) { a = a - b }

    /// Punto medio entre dos puntos.
    public static func midpoint(_ a: Point2D, _ b: Point2D) -> Point2D { (a + b) / 2 }

    /// Interpolación lineal: t = 0 da `a`, t = 1 da `b`.
    public static func lerp(_ a: Point2D, _ b: Point2D, _ t: Double) -> Point2D { a + (b - a) * t }
}
