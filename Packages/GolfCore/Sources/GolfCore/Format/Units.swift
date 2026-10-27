import Foundation

/// Unidad de distancia del tracer (Ajustes).
public enum DistanceUnit: String, Sendable, Codable, CaseIterable {
    case meters
    case yards

    /// Una yarda son 0,9144 m exactos (definición internacional).
    public static let metersPerYard = 0.9144

    public var symbol: String { self == .meters ? "m" : "yd" }

    /// Convierte una distancia guardada en metros a esta unidad.
    public func value(fromMeters meters: Double) -> Double {
        self == .meters ? meters : meters / Self.metersPerYard
    }

    /// Convierte un valor en esta unidad a metros (para guardarlo siempre igual).
    public func meters(fromValue value: Double) -> Double {
        self == .meters ? value : value * Self.metersPerYard
    }
}

/// Números y medidas escritos en español de España.
///
/// Se componen a mano (sin `NumberFormatter`) para que el texto sea siempre el mismo
/// en cualquier iPhone y en el CI, sin depender de la región configurada.
/// Reglas: coma decimal, signo menos tipográfico (−), sin separador de miles hasta 4 cifras
/// (como pide la RAE) y con espacio fino a partir de 5.
public enum SpanishFormat {
    /// "2,8" con `decimals` decimales; "−3,0" si es negativo.
    public static func number(_ value: Double, decimals: Int = 0) -> String {
        let places = min(max(decimals, 0), 6)
        var factor = 1
        for _ in 0..<places { factor *= 10 }
        // Sin número (o tan grande que no cabe en un entero): una raya, nunca un cuelgue.
        guard value.isFinite, abs(value) * Double(factor) < 1e15 else { return "—" }
        // Redondeo "de toda la vida" (0,5 sube). El empujoncito evita que 2,85 guardado como
        // 2,8499999… salga 2,8. Después todo es con enteros: sin errores de redondeo.
        let scaled = Int((abs(value) * Double(factor) * (1 + 1e-12)).rounded(.toNearestOrAwayFromZero))
        let integerPart = scaled / factor
        let fractionPart = scaled % factor
        var text = grouped(integerPart)
        if places > 0 {
            var fraction = String(fractionPart)
            while fraction.count < places { fraction = "0" + fraction }
            text += "," + fraction
        }
        // Un número que redondeado es cero no lleva signo ("0,0", no "−0,0").
        return value < 0 && scaled > 0 ? "−" + text : text
    }

    /// Ritmo en pantalla: "2,8 : 1".
    public static func ratio(_ value: Double) -> String {
        "\(number(value, decimals: 1)) : 1"
    }

    /// Ritmo para la voz: "2,8 a 1".
    public static func spokenRatio(_ value: Double) -> String {
        "\(number(value, decimals: 1)) a 1"
    }

    /// Medida aproximada en centímetros: "~2 cm". Las medidas del swing salen de un vídeo 2D
    /// y nunca se presentan como exactas.
    public static func approximateCentimeters(_ value: Double) -> String {
        "~\(number(value)) cm"
    }

    /// Ángulo: "30°".
    public static func degrees(_ value: Double) -> String {
        "\(number(value))°"
    }

    /// Duración: "0,73 s".
    public static func seconds(_ value: Double, decimals: Int = 2) -> String {
        "\(number(value, decimals: decimals)) s"
    }

    /// Distancia del tracer: "150 m" o "164 yd". El valor llega en metros y nunca es medido:
    /// lo escribe el usuario o sale de "Mis palos".
    public static func distance(meters: Double, unit: DistanceUnit) -> String {
        "\(number(unit.value(fromMeters: meters))) \(unit.symbol)"
    }

    /// Nota: "78/100".
    public static func score(_ value: Int) -> String {
        "\(value)/100"
    }

    /// Duración dicha en voz, redondeada a décimas: "siete décimas", "un segundo y dos décimas".
    /// (La pantalla enseña "0,73 s"; al oído suena mejor así.)
    public static func spokenTenths(_ seconds: Double) -> String {
        let tenths = Int((max(seconds, 0) * 10 * (1 + 1e-12)).rounded(.toNearestOrAwayFromZero))
        let whole = tenths / 10
        let rest = tenths % 10
        if tenths == 0 { return "menos de una décima" }
        let tenthsText = rest == 1 ? "una décima" : "\(spokenNumber(rest)) décimas"
        if whole == 0 { return tenthsText }
        let secondsText = whole == 1 ? "un segundo" : "\(spokenNumber(whole)) segundos"
        return rest == 0 ? secondsText : "\(secondsText) y \(tenthsText)"
    }

    /// Números del 0 al 10 en palabras (para las duraciones habladas); a partir de ahí, en cifras.
    static func spokenNumber(_ value: Int) -> String {
        let words = ["cero", "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez"]
        return value >= 0 && value < words.count ? words[value] : String(value)
    }

    /// Parte entera con espacio fino cada tres cifras, solo si tiene 5 o más.
    static func grouped(_ value: Int) -> String {
        let digits = String(value)
        guard digits.count >= 5 else { return digits }
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 { result += "\u{2009}" }
            result.append(character)
        }
        return result
    }
}
