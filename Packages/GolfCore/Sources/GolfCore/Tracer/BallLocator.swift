import Foundation

/// Una posible bola en un fotograma (coordenadas de la imagen).
public struct BallCandidate: Sendable, Equatable, Codable {
    public var center: Point2D
    /// Radio aproximado (px).
    public var radius: Double
    /// Cuánto más clara es que lo que la rodea (niveles de gris, de 0 a 255).
    public var contrast: Double
    /// Contraste pesado por la cercanía a donde se esperaba la bola.
    public var score: Double
}

/// Rectángulo de píxeles (para decir dónde buscar).
public struct PixelRect: Sendable, Equatable, Codable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// El rectángulo recortado a una imagen de ese tamaño.
    public func clamped(width imageWidth: Int, height imageHeight: Int) -> PixelRect {
        let x0 = min(max(x, 0), imageWidth)
        let y0 = min(max(y, 0), imageHeight)
        let x1 = min(max(x + width, 0), imageWidth)
        let y1 = min(max(y + height, 0), imageHeight)
        return PixelRect(x: x0, y: y0, width: max(x1 - x0, 0), height: max(y1 - y0, 0))
    }
}

/// Dónde y cómo buscar la bola.
public struct BallSearch: Sendable {
    /// Zona de búsqueda en la imagen.
    public var region: PixelRect
    /// Donde se espera la bola ("Bola aquí" de la guía de la cámara), si se sabe.
    public var prior: Point2D?
    /// Cuánto se aleja como mucho de lo esperado sin perder puntuación (desviación típica, px).
    public var priorSpread: Double
    public var radii = TracerConstants.ballRadii
    public var minimumBrightness = TracerConstants.ballMinimumBrightness
    public var minimumContrast = TracerConstants.ballMinimumContrast

    public init(region: PixelRect, prior: Point2D? = nil, priorSpread: Double = 150) {
        self.region = region
        self.prior = prior
        self.priorSpread = priorSpread
    }
}

/// Resultado de buscar la bola: las mejores candidatas y si hay confianza en la primera.
public struct BallLocation: Sendable, Equatable {
    /// Ordenadas de mejor a peor.
    public var candidates: [BallCandidate]
    /// La primera es clara y destaca sobre la segunda: no hace falta pedir un toque.
    public var isConfident: Bool

    public var best: BallCandidate? { candidates.first }
}

/// Busca la bola antes del impacto (docs/03, paso 3): una mancha pequeña, clara y redonda
/// cerca de donde la guía de la cámara dice "Bola aquí".
///
/// Para cada posible centro y radio se compara el brillo medio de un cuadrado dentro de la bola con
/// el del lado más claro de un anillo alrededor (arriba, abajo, izquierda o derecha): una bola blanca
/// sobre la hierba da mucho contraste por los cuatro lados; el extremo de algo alargado (un cartel, el palo)
/// tiene un lado claro, porque sigue hacia allí, y casi no da contraste. Así se mide también la redondez.
/// Las medias salen de una imagen integral (sumas acumuladas por filas y columnas): la suma de
/// cualquier rectángulo se lee con 4 accesos, así que probar miles de centros y radios es barato.
public enum BallLocator {
    public static func locate(in image: GrayImage, search: BallSearch, maximumCandidates: Int = 5) -> BallLocation {
        let region = search.region.clamped(width: image.width, height: image.height)
        guard region.width > 0, region.height > 0, let maxRadius = search.radii.max() else {
            return BallLocation(candidates: [], isConfident: false)
        }
        let integral = IntegralImage(image)
        // Para cada centro, el mejor radio. Se deja un margen para que el anillo quepa en la imagen.
        let margin = maxRadius + 3
        let xStart = max(region.x, margin), xEnd = min(region.x + region.width, image.width - margin)
        let yStart = max(region.y, margin), yEnd = min(region.y + region.height, image.height - margin)
        guard xStart < xEnd, yStart < yEnd else { return BallLocation(candidates: [], isConfident: false) }
        var best: [BallCandidate] = []
        for cy in yStart..<yEnd {
            for cx in xStart..<xEnd {
                var bestHere: BallCandidate?
                for r in search.radii {
                    let inner = max(1, Int((Double(r) * 0.7).rounded()))
                    let core = integral.mean(cx - inner, cy - inner, cx + inner, cy + inner)
                    guard core >= search.minimumBrightness else { continue }
                    let ring = integral.brightestSideMean(cx: cx, cy: cy, innerHalf: r + 1, outerHalf: r + 3)
                    let contrast = core - ring
                    guard contrast >= search.minimumContrast else { continue }
                    if bestHere == nil || contrast > bestHere!.contrast {
                        bestHere = BallCandidate(center: Point2D(Double(cx), Double(cy)), radius: Double(r),
                                                 contrast: contrast, score: contrast)
                    }
                }
                if var candidate = bestHere {
                    if let prior = search.prior {
                        let d = candidate.center.distance(to: prior)
                        candidate.score = candidate.contrast * exp(-d * d / (2 * search.priorSpread * search.priorSpread))
                    }
                    best.append(candidate)
                }
            }
        }
        // Una bola da contraste en varios centros vecinos: se queda el mejor de cada zona.
        var accepted: [BallCandidate] = []
        for candidate in best.sorted(by: { $0.score > $1.score }) {
            let isNear = accepted.contains { $0.center.distance(to: candidate.center) < 2 * max($0.radius, candidate.radius) + 2 }
            if !isNear { accepted.append(candidate) }
            if accepted.count == maximumCandidates { break }
        }
        let confident: Bool = {
            guard let first = accepted.first, first.contrast >= TracerConstants.ballConfidentContrast else { return false }
            guard accepted.count > 1 else { return true }
            return first.score >= TracerConstants.ballConfidentLead * accepted[1].score
        }()
        return BallLocation(candidates: accepted, isConfident: confident)
    }

    /// Nitidez alrededor de un punto: diferencia media entre píxeles vecinos en un cuadrado de 4 radios.
    /// Un fotograma movido tiene los bordes borrosos y da menos. Sirve para elegir el fotograma más nítido.
    public static func sharpness(of image: GrayImage, around center: Point2D, radius: Double) -> Double {
        let half = max(Int((2 * radius).rounded()), 3)
        let cx = Int(center.x.rounded())
        let cy = Int(center.y.rounded())
        let x0 = max(cx - half, 0), x1 = min(cx + half, image.width - 2)
        let y0 = max(cy - half, 0), y1 = min(cy + half, image.height - 2)
        guard x0 < x1, y0 < y1 else { return 0 }
        var sum = 0.0
        var count = 0
        for y in y0...y1 {
            for x in x0...x1 {
                let here = Int(image[x, y])
                sum += Double(abs(Int(image[x + 1, y]) - here) + abs(Int(image[x, y + 1]) - here))
                count += 1
            }
        }
        return sum / Double(count)
    }

    /// Contraste de la bola en `center` con radio `radius`: brillo del centro menos el del anillo.
    /// Cuando la bola se va, el centro se queda como el fondo y el contraste cae a casi cero.
    public static func coreContrast(in image: GrayImage, center: Point2D, radius: Double) -> Double {
        let r = max(Int(radius.rounded()), 1)
        let inner = max(1, Int((Double(r) * 0.7).rounded()))
        let cx = Int(center.x.rounded())
        let cy = Int(center.y.rounded())
        guard cx - r - 3 >= 0, cy - r - 3 >= 0, cx + r + 3 < image.width, cy + r + 3 < image.height else { return 0 }
        // Se recorre solo el cuadrado de fuera: es un punto, no hace falta la imagen integral.
        // Lados del anillo: 0 arriba, 1 abajo, 2 izquierda, 3 derecha (como en `brightestSideMean`).
        var core = 0.0, coreCount = 0.0
        var sides = [Double](repeating: 0, count: 4), sideCounts = [Double](repeating: 0, count: 4)
        for y in (cy - r - 3)...(cy + r + 3) {
            for x in (cx - r - 3)...(cx + r + 3) {
                let dx = x - cx, dy = y - cy
                let value = Double(image[x, y])
                if abs(dx) <= inner && abs(dy) <= inner {
                    core += value
                    coreCount += 1
                } else if max(abs(dx), abs(dy)) > r + 1 {
                    let side = dy < -(r + 1) ? 0 : dy > r + 1 ? 1 : dx < 0 ? 2 : 3
                    sides[side] += value
                    sideCounts[side] += 1
                }
            }
        }
        let brightest = zip(sides, sideCounts).map { $1 > 0 ? $0 / $1 : 0 }.max() ?? 0
        return core / coreCount - brightest
    }
}

/// Imagen integral: `sums[(y + 1) * (w + 1) + (x + 1)]` es la suma de todos los píxeles por encima
/// y a la izquierda de (x, y), incluidos. La suma de un rectángulo sale de cuatro esquinas.
struct IntegralImage {
    let width: Int
    let height: Int
    private let sums: [Double]

    init(_ image: GrayImage) {
        width = image.width
        height = image.height
        var sums = [Double](repeating: 0, count: (width + 1) * (height + 1))
        for y in 0..<height {
            var row = 0.0
            for x in 0..<width {
                row += Double(image.pixels[y * width + x])
                sums[(y + 1) * (width + 1) + (x + 1)] = sums[y * (width + 1) + (x + 1)] + row
            }
        }
        self.sums = sums
    }

    /// Suma del rectángulo de x0 a x1 y de y0 a y1, incluidos (recortado a la imagen).
    func sum(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Double {
        let a = max(x0, 0), b = max(y0, 0)
        let c = min(x1, width - 1), d = min(y1, height - 1)
        guard a <= c, b <= d else { return 0 }
        let w = width + 1
        return sums[(d + 1) * w + (c + 1)] - sums[b * w + (c + 1)] - sums[(d + 1) * w + a] + sums[b * w + a]
    }

    func mean(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Double {
        let area = Double(max(min(x1, width - 1) - max(x0, 0) + 1, 0) * max(min(y1, height - 1) - max(y0, 0) + 1, 0))
        return area > 0 ? sum(x0, y0, x1, y1) / area : 0
    }

    /// Media del lado más claro del anillo cuadrado entre dos medios lados: franjas de arriba y de abajo
    /// (todo el ancho) y de la izquierda y la derecha (entre ellas).
    func brightestSideMean(cx: Int, cy: Int, innerHalf i: Int, outerHalf o: Int) -> Double {
        let top = mean(cx - o, cy - o, cx + o, cy - i - 1)
        let bottom = mean(cx - o, cy + i + 1, cx + o, cy + o)
        let left = mean(cx - o, cy - i, cx - i - 1, cy + i)
        let right = mean(cx + i + 1, cy - i, cx + o, cy + i)
        return max(top, bottom, left, right)
    }
}
