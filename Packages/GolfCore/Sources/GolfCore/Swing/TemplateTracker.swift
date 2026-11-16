import Foundation

/// Sigue un parche pequeño de imagen (la cabeza del palo) de un fotograma al siguiente con
/// correlación cruzada normalizada (docs/04, punto 4: el takeaway es lento y el parche cambia poco).
public enum TemplateTracker {
    /// Recorta el parche cuadrado centrado en `center` (lado 2 × radius + 1), o `nil` si se sale.
    public static func template(from image: GrayImage, center: Point2D, radius: Int) -> GrayImage? {
        let cx = Int(center.x.rounded()), cy = Int(center.y.rounded())
        let side = 2 * radius + 1
        guard cx - radius >= 0, cy - radius >= 0, cx + radius < image.width, cy + radius < image.height
        else { return nil }
        var pixels = [UInt8]()
        pixels.reserveCapacity(side * side)
        for y in (cy - radius)...(cy + radius) {
            let row = y * image.width
            pixels.append(contentsOf: image.pixels[(row + cx - radius)...(row + cx + radius)])
        }
        return GrayImage(width: side, height: side, pixels: pixels)
    }

    /// Busca el parche alrededor de `center` y devuelve el mejor centro con su parecido (−1 a 1).
    /// La correlación normalizada no se deja engañar por un cambio de luz entre fotogramas.
    public static func find(_ template: GrayImage, in image: GrayImage, around center: Point2D,
                            searchRadius: Int) -> (center: Point2D, score: Double)? {
        let side = template.width
        let radius = side / 2
        let n = Double(side * side)
        let templateValues = template.pixels.map(Double.init)
        let templateMean = templateValues.reduce(0, +) / n
        let templateDeviation = templateValues.map { $0 - templateMean }
        let templateNorm = templateDeviation.map { $0 * $0 }.reduce(0, +).squareRoot()
        guard templateNorm > 1e-9 else { return nil }

        let cx = Int(center.x.rounded()), cy = Int(center.y.rounded())
        var best: (center: Point2D, score: Double)?
        for oy in -searchRadius...searchRadius {
            for ox in -searchRadius...searchRadius {
                let px = cx + ox, py = cy + oy
                guard px - radius >= 0, py - radius >= 0,
                      px + radius < image.width, py + radius < image.height else { continue }
                // Media y correlación del parche candidato.
                var sum = 0.0
                for y in 0..<side {
                    let row = (py - radius + y) * image.width + px - radius
                    for x in 0..<side { sum += Double(image.pixels[row + x]) }
                }
                let mean = sum / n
                var dot = 0.0
                var norm = 0.0
                for y in 0..<side {
                    let row = (py - radius + y) * image.width + px - radius
                    for x in 0..<side {
                        let value = Double(image.pixels[row + x]) - mean
                        dot += value * templateDeviation[y * side + x]
                        norm += value * value
                    }
                }
                guard norm > 1e-9 else { continue }
                let score = dot / (norm.squareRoot() * templateNorm)
                if best == nil || score > best!.score {
                    best = (Point2D(Double(px), Double(py)), score)
                }
            }
        }
        return best
    }
}
