import Foundation

/// Propone la línea del palo en un fotograma (docs/04, punto 4): bordes alrededor de las manos
/// y votación de rectas que pasan por ellas (una transformada de Hough pequeña anclada en el grip).
///
/// La varilla del palo es lo único recto y largo que sale de las manos: sus dos bordes dejan
/// muchos píxeles de gradiente alto alineados con el grip, y ese ángulo gana la votación.
public enum ClubLineFinder {
    /// Resolución de la votación: anchura de cada casilla de ángulo (grados).
    public static let binDegrees = 1.5
    /// La casilla ganadora tiene que doblar a la mediana para que la línea valga.
    public static let minimumPeakRatio = 2.5

    /// - Parameters:
    ///   - image: el fotograma en gris (entero o un recorte alrededor de las manos).
    ///   - hands: el grip en píxeles de esa imagen.
    ///   - minimumLength: a menos de esto de las manos no se vota (ahí están los brazos).
    ///   - maximumLength: largo máximo del palo en píxeles. Por defecto, media diagonal de la imagen.
    /// - Returns: la línea del grip a la cabeza del palo, o `nil` si ningún ángulo destaca.
    public static func find(in image: GrayImage, hands: Point2D, minimumLength: Double = 25,
                            maximumLength: Double? = nil) -> ClubLine? {
        let w = image.width, h = image.height
        guard w > 8, h > 8 else { return nil }
        let maxLen = maximumLength ?? Double((w + h)) / 2
        let bins = Int((360 / binDegrees).rounded())

        // Gradiente por diferencias centrales, solo en la zona útil alrededor de las manos.
        let x0 = max(Int(hands.x - maxLen), 1), x1 = min(Int(hands.x + maxLen), w - 2)
        let y0 = max(Int(hands.y - maxLen), 1), y1 = min(Int(hands.y + maxLen), h - 2)
        guard x1 > x0, y1 > y0 else { return nil }
        var edges: [(x: Int, y: Int, magnitude: Double)] = []
        edges.reserveCapacity((x1 - x0) * (y1 - y0) / 8)
        for y in y0...y1 {
            let row = y * w
            for x in x0...x1 {
                let gx = Double(image.pixels[row + x + 1]) - Double(image.pixels[row + x - 1])
                let gy = Double(image.pixels[row + w + x]) - Double(image.pixels[row - w + x])
                let magnitude = abs(gx) + abs(gy)
                if magnitude >= 24 { edges.append((x, y, magnitude)) }
            }
        }
        guard edges.count >= 12 else { return nil }

        // Votación: cada píxel de borde vota al ángulo de la recta manos → píxel.
        var votes = [Double](repeating: 0, count: bins)
        for edge in edges {
            let dx = Double(edge.x) - hands.x
            let dy = Double(edge.y) - hands.y
            let distance = (dx * dx + dy * dy).squareRoot()
            guard distance >= minimumLength, distance <= maxLen else { continue }
            let angle = atan2(dy, dx) * 180 / .pi
            let bin = Int(((angle + 360).truncatingRemainder(dividingBy: 360)) / binDegrees) % bins
            votes[bin] += edge.magnitude
        }

        // Suavizado circular ±1 casilla y búsqueda del pico.
        let smoothed = (0..<bins).map { votes[($0 + bins - 1) % bins] + votes[$0] + votes[($0 + 1) % bins] }
        guard let peak = smoothed.indices.max(by: { smoothed[$0] < smoothed[$1] }) else { return nil }
        let median = smoothed.sorted(by: <)[bins / 2]
        guard smoothed[peak] > minimumPeakRatio * max(median, 1) else { return nil }

        // La cabeza del palo: el final del tramo seguido de bordes en el ángulo ganador (±2 casillas).
        // Si se cogiera el borde más lejano a secas, un píxel de ruido en ese mismo ángulo
        // alargaría el palo hasta cualquier parte.
        var along: [(distance: Double, point: Point2D, magnitude: Double)] = []
        for edge in edges {
            let dx = Double(edge.x) - hands.x
            let dy = Double(edge.y) - hands.y
            let distance = (dx * dx + dy * dy).squareRoot()
            guard distance >= minimumLength, distance <= maxLen else { continue }
            let angle = atan2(dy, dx) * 180 / .pi
            let bin = Int(((angle + 360).truncatingRemainder(dividingBy: 360)) / binDegrees) % bins
            let gap = min((bin - peak + bins) % bins, (peak - bin + bins) % bins)
            if gap <= 2 { along.append((distance, Point2D(Double(edge.x), Double(edge.y)), edge.magnitude)) }
        }
        // Solo cuentan los bordes fuertes del ángulo ganador: la textura del fondo también deja
        // bordes flojos por todas partes y, sin este filtro, el paseo saltaría por ellos.
        let strongest = along.map(\.magnitude).max() ?? 0
        var strong = along.filter { $0.magnitude >= 0.45 * strongest }
        strong.sort { $0.distance < $1.distance }
        guard var head = strong.first else { return nil }
        for edge in strong.dropFirst() {
            // Un hueco de más de 14 px corta la varilla: lo de después es otra cosa.
            guard edge.distance - head.distance <= 14 else { break }
            head = edge
        }
        return ClubLine(grip: hands, head: head.point)
    }
}
