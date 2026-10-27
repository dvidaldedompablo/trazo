import Foundation

/// Geometría del plano de la imagen: ángulos, rectas y distancias.
/// Recuerda la convención de `Point2D`: y crece hacia abajo. Por eso "hacia arriba" es (0, −1).
/// Las funciones que necesitan una dirección devuelven `nil` si un segmento mide cero:
/// mejor no dar un ángulo que inventarlo.
public enum Geometry {
    /// Grados a partir de radianes.
    public static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    /// Radianes a partir de grados.
    public static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    /// Ángulo entre dos vectores, de 0° (misma dirección) a 180° (opuestos).
    public static func angle(between u: Point2D, and v: Point2D) -> Double? {
        let lu = u.length
        let lv = v.length
        guard lu > 0, lv > 0 else { return nil }
        // atan2(|u×v|, u·v) es más preciso que acos(u·v) cuando el ángulo es casi 0° o 180°.
        return degrees(atan2(abs(u.cross(v)), u.dot(v)))
    }

    /// Ángulo en `vertex` entre los segmentos vertex→a y vertex→b, de 0° a 180°.
    /// Ejemplo: la rodilla es `angle(at: rodilla, cadera, tobillo)`; con la pierna recta da 180°.
    public static func angle(at vertex: Point2D, _ a: Point2D, _ b: Point2D) -> Double? {
        angle(between: a - vertex, and: b - vertex)
    }

    /// Ángulo entre los segmentos p1→p2 y q1→q2 teniendo en cuenta su sentido (0° a 180°).
    public static func angle(between p1: Point2D, _ p2: Point2D, and q1: Point2D, _ q2: Point2D) -> Double? {
        angle(between: p2 - p1, and: q2 - q1)
    }

    /// Ángulo entre dos rectas, sin sentido (0° a 90°). Sirve para comparar la línea del palo con el plano.
    public static func lineAngle(between p1: Point2D, _ p2: Point2D, and q1: Point2D, _ q2: Point2D) -> Double? {
        guard let a = angle(between: p1, p2, and: q1, q2) else { return nil }
        return min(a, 180 - a)
    }

    /// Ángulo del segmento from→to con la vertical hacia arriba, de 0° (recto hacia arriba) a 180°.
    /// La inclinación del tronco es `angleFromVertical(from: centroCadera, to: cuello)`.
    public static func angleFromVertical(from: Point2D, to: Point2D) -> Double? {
        angle(between: to - from, and: Point2D(0, -1))
    }

    /// Ángulo de la recta que pasa por los dos puntos con la horizontal, de 0° a 90° (sin sentido).
    /// Es lo que se mide del palo: da igual si se toma de la cabeza a las manos o al revés.
    public static func angleFromHorizontal(from: Point2D, to: Point2D) -> Double? {
        let d = to - from
        guard d.length > 0 else { return nil }
        return degrees(atan2(abs(d.y), abs(d.x)))
    }

    /// Punto donde se cortan las rectas p1–p2 y q1–q2, o `nil` si son paralelas.
    public static func intersection(_ p1: Point2D, _ p2: Point2D, _ q1: Point2D, _ q2: Point2D) -> Point2D? {
        let r = p2 - p1
        let s = q2 - q1
        let denominator = r.cross(s)
        guard abs(denominator) > 1e-12 else { return nil }
        let t = (q1 - p1).cross(s) / denominator
        return p1 + r * t
    }

    /// Distancia con signo de `point` a la recta que pasa por a y b.
    /// El signo dice a qué lado queda: positivo a la izquierda de a→b (mirando la imagen con y hacia abajo,
    /// es el lado en que gira el reloj). Si a y b coinciden, `nil`.
    public static func signedDistance(from point: Point2D, toLineThrough a: Point2D, _ b: Point2D) -> Double? {
        let d = b - a
        let l = d.length
        guard l > 0 else { return nil }
        return d.cross(point - a) / l
    }

    /// Distancia (sin signo) de `point` a la recta que pasa por a y b.
    public static func distance(from point: Point2D, toLineThrough a: Point2D, _ b: Point2D) -> Double? {
        signedDistance(from: point, toLineThrough: a, b).map(abs)
    }

    /// Distancia de `point` al segmento a–b (no a la recta infinita): fuera del segmento cuenta el extremo más cercano.
    public static func distance(from point: Point2D, toSegment a: Point2D, _ b: Point2D) -> Double {
        let d = b - a
        let l2 = d.dot(d)
        guard l2 > 0 else { return point.distance(to: a) }
        let t = min(max((point - a).dot(d) / l2, 0), 1)
        return point.distance(to: a + d * t)
    }
}

/// Escala de píxeles a centímetros sacada de la estatura del jugador (docs/04, punto 2).
///
/// La cadena tobillo-rodilla + rodilla-cadera + cadera-cuello + cuello-nariz mide alrededor del 87 %
/// de la estatura. Desde detrás, el cuerpo queda casi paralelo a la imagen y esas longitudes
/// se conservan bastante, así que su suma en píxeles dividida entre el 87 % de la estatura en cm
/// da los píxeles por centímetro. Es una aproximación: la app escribe siempre "~" delante.
public struct PixelScale: Sendable, Equatable {
    /// Fracción de la estatura que cubre la cadena de segmentos.
    public static let bodyChainFraction = 0.87

    public let pixelsPerCentimeter: Double

    public init?(pixelsPerCentimeter: Double) {
        guard pixelsPerCentimeter > 0, pixelsPerCentimeter.isFinite else { return nil }
        self.pixelsPerCentimeter = pixelsPerCentimeter
    }

    /// Escala a partir de las articulaciones en la preparación y la estatura (en cm) de Ajustes.
    public init?(ankle: Point2D, knee: Point2D, hip: Point2D, neck: Point2D, nose: Point2D, heightCentimeters: Double) {
        guard heightCentimeters > 0 else { return nil }
        let chain = Self.bodyChainPixels(ankle: ankle, knee: knee, hip: hip, neck: neck, nose: nose)
        self.init(pixelsPerCentimeter: chain / (Self.bodyChainFraction * heightCentimeters))
    }

    /// Suma de los cuatro segmentos, en píxeles.
    public static func bodyChainPixels(ankle: Point2D, knee: Point2D, hip: Point2D, neck: Point2D, nose: Point2D) -> Double {
        ankle.distance(to: knee) + knee.distance(to: hip) + hip.distance(to: neck) + neck.distance(to: nose)
    }

    /// Estatura en píxeles. No necesita los cm: la cadena es el 87 % de la estatura en cualquier unidad.
    public static func staturePixels(ankle: Point2D, knee: Point2D, hip: Point2D, neck: Point2D, nose: Point2D) -> Double {
        bodyChainPixels(ankle: ankle, knee: knee, hip: hip, neck: neck, nose: nose) / bodyChainFraction
    }

    public func centimeters(fromPixels pixels: Double) -> Double { pixels / pixelsPerCentimeter }

    public func pixels(fromCentimeters centimeters: Double) -> Double { centimeters * pixelsPerCentimeter }
}
