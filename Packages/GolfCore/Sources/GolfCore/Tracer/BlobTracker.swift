import Foundation

/// Imagen en escala de grises: un byte por píxel (0 negro, 255 blanco), fila a fila.
/// La app reduce cada fotograma a unos 480 px de ancho antes de pasárselo a `BlobTracker`.
public struct GrayImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(width > 0 && height > 0 && pixels.count == width * height, "Tamaño de imagen incorrecto")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, value: UInt8 = 0) {
        self.init(width: width, height: height, pixels: [UInt8](repeating: value, count: width * height))
    }

    public subscript(x: Int, y: Int) -> UInt8 {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }
}

/// Una mancha: un grupo de píxeles seguidos que han cambiado respecto al fondo.
public struct Blob: Sendable, Equatable {
    /// Centro de la mancha pesado por cuánto ha cambiado cada píxel (más preciso que el centro de la caja).
    public var centroid: Point2D
    public var area: Int
    public var width: Int
    public var height: Int
    /// Suma de las diferencias con el fondo.
    public var strength: Double
}

/// Opciones de `BlobTracker`. Las de docs/03 salen de `TracerConstants`; el resto son valores de partida.
public struct BlobTrackerOptions: Sendable {
    public var backgroundFrameCount = TracerConstants.backgroundFrameCount
    /// Diferencia mínima con el fondo para que un píxel cuente como "cambiado" (de 0 a 255).
    public var minimumDifference = 14
    /// Umbral de cada píxel: el mayor entre `minimumDifference` y este factor por su ruido (MAD × 1,4826).
    public var noiseFactor = 4.0
    public var minimumArea = TracerConstants.blobMinimumArea
    public var maximumArea = TracerConstants.blobMaximumArea
    /// Forma compacta: la caja no es más de 4 veces más larga que ancha…
    public var maximumAspectRatio = 4.0
    /// …y la mancha llena al menos una cuarta parte de su caja.
    public var minimumFillRatio = 0.25
    public var maximumMissedFrames = TracerConstants.maximumMissedFrames
    /// Puerta de búsqueda: 4 desviaciones típicas de la predicción, entre 4 y 60 px.
    public var gateSigmas = 4.0
    public var minimumGateRadius = 4.0
    public var maximumGateRadius = 60.0
    /// Radio de arranque alrededor de la bola en el primer fotograma tras el impacto (fracción del ancho).
    /// Crece con cada fotograma que pasa sin encontrarla.
    public var acquisitionRadiusFraction = 0.08
    /// Fotogramas tras el impacto en los que se busca el arranque.
    public var acquisitionFrames = 12
    /// Radio alrededor del tee que se ignora: ahí queda el "hueco" de la bola que ya no está.
    public var teeExclusionRadius = 4.0
    /// Un toque se ajusta a la mancha más cercana a menos de esta distancia (px).
    public var seedSnapRadius = 6.0
    /// Ruidos del Kalman: aceleración aleatoria (px²/s³) y error de la medida (px).
    public var processNoise = 2e5
    public var measurementNoise = 1.0
    /// Duda sobre la velocidad cuando no se sabe hacia dónde va la bola (px/s).
    public var unknownVelocityStdDev = 600.0

    public init() {}
}

/// Un punto de la bola encontrado por `BlobTracker`.
public struct TrackedBallPoint: Sendable, Equatable {
    public var frameIndex: Int
    public var point: Point2D
    /// Es el toque del usuario (punto fijo para `TrajectoryFit`).
    public var isSeed: Bool
}

/// Por qué terminó el seguimiento hacia delante.
public enum TrackEnd: String, Sendable, Equatable {
    /// No se encontró la bola saliendo del tee.
    case notFound
    /// 12 fotogramas seguidos sin verla: "Perdí la bola a los X s".
    case lost
    /// La predicción salió de la imagen.
    case leftImage
    /// Se acabaron los fotogramas.
    case endOfClip
}

/// Resultado de un seguimiento.
public struct BlobTrack: Sendable, Equatable {
    /// Puntos ordenados por fotograma.
    public var points: [TrackedBallPoint]
    /// Último fotograma en el que se vio la bola hacia delante.
    public var lastSeenFrame: Int?
    public var end: TrackEnd

    /// Los puntos como muestras para `TrajectoryFit` (tiempo desde el impacto; el toque, fijo).
    public func samples(frameRate: Double, impactFrame: Int, scale: Double = 1) -> [TrajectorySample] {
        points.map {
            TrajectorySample(time: Double($0.frameIndex - impactFrame) / frameRate, point: $0.point * scale, isFixed: $0.isSeed)
        }
    }
}

/// Plan B del tracer (docs/03, paso 4 B; clave 4 de la guía): encuentra la bola por diferencia
/// con el fondo, sin entrenar nada, y la sigue con un filtro de Kalman.
///
/// 1. Fondo: mediana, píxel a píxel, de los 15 fotogramas antes del impacto (la cámara está quieta,
///    así que la mediana borra lo que se mueve y deja el cielo, los árboles… y la bola en el tee).
///    De esos mismos fotogramas sale el ruido de cada píxel (su MAD): las hojas que se mueven con
///    el viento piden más diferencia para contar como cambio que el cielo liso.
/// 2. Tras el impacto, cada fotograma se compara con el fondo (diferencia absoluta: la bola puede verse
///    más clara o más oscura que el cielo) y se juntan los píxeles cambiados en manchas.
/// 3. Solo valen manchas pequeñas (1 a 40 px) y compactas: el cuerpo y el palo son grandes o alargados.
/// 4. Kalman: predice dónde estará la bola y se acepta la mancha más cercana dentro de una puerta
///    que crece con la incertidumbre. Si un fotograma no la ve, se sigue con la predicción;
///    tras 12 seguidos sin verla, se para.
/// Solo se buscan manchas cerca de la predicción: así no hace falta recorrer la imagen entera.
public struct BlobTracker: Sendable {
    public let frames: [GrayImage]
    public let impactFrame: Int
    public let frameRate: Double
    public let options: BlobTrackerOptions
    /// Dónde estaba la bola antes del impacto. Si se sabe, se ignora su "hueco" en el tee.
    public var teePosition: Point2D?
    public let background: GrayImage
    /// Umbral de diferencia de cada píxel.
    let thresholds: [UInt8]

    /// - Parameters:
    ///   - frames: fotogramas reducidos y en gris, a ritmo constante, que incluyen al menos uno antes del impacto.
    ///   - impactFrame: índice del fotograma del impacto.
    /// - Returns: `nil` si no hay fotogramas antes del impacto o no miden todos lo mismo.
    public init?(frames: [GrayImage], impactFrame: Int, frameRate: Double, teePosition: Point2D? = nil,
                 options: BlobTrackerOptions = .init()) {
        guard let first = frames.first, impactFrame > 0, impactFrame < frames.count, frameRate > 0,
              frames.allSatisfy({ $0.width == first.width && $0.height == first.height })
        else { return nil }
        self.frames = frames
        self.impactFrame = impactFrame
        self.frameRate = frameRate
        self.options = options
        self.teePosition = teePosition

        let start = max(0, impactFrame - options.backgroundFrameCount)
        let count = impactFrame - start
        let pixelCount = first.width * first.height
        var backgroundPixels = [UInt8](repeating: 0, count: pixelCount)
        var thresholdPixels = [UInt8](repeating: 0, count: pixelCount)
        var values = [Int](repeating: 0, count: count)
        var deviations = [Int](repeating: 0, count: count)
        let sources = frames[start..<impactFrame].map(\.pixels)
        for p in 0..<pixelCount {
            for k in 0..<count { values[k] = Int(sources[k][p]) }
            values.sort()
            let median = values[count / 2]
            for k in 0..<count { deviations[k] = abs(values[k] - median) }
            deviations.sort()
            let mad = Double(deviations[count / 2])
            backgroundPixels[p] = UInt8(median)
            // 1,4826 × MAD estima la desviación típica del ruido si fuera normal.
            let noise = Int((options.noiseFactor * 1.4826 * mad).rounded(.up))
            thresholdPixels[p] = UInt8(min(max(options.minimumDifference, noise), 255))
        }
        background = GrayImage(width: first.width, height: first.height, pixels: backgroundPixels)
        thresholds = thresholdPixels
    }

    /// Arranque automático: la primera mancha que aparece cerca de la bola tras el impacto
    /// y se aleja de ella subiendo; desde ahí, seguimiento hacia delante.
    public func trackFromBall(at ball: Point2D) -> BlobTrack {
        let width = Double(frames[0].width)
        let baseRadius = options.acquisitionRadiusFraction * width
        let lastStart = min(frames.count - 2, impactFrame + options.acquisitionFrames - 1)
        guard impactFrame <= lastStart else { return BlobTrack(points: [], lastSeenFrame: nil, end: .notFound) }

        for f in impactFrame...lastStart {
            let radius = min(baseRadius * Double(f - impactFrame + 1), 0.25 * width)
            let firstCandidates = blobs(inFrame: f, around: ball, radius: radius)
                .filter { $0.centroid.distance(to: ball) > options.teeExclusionRadius }
                .sorted { $0.centroid.distance(to: ball) < $1.centroid.distance(to: ball) }
            for c1 in firstCandidates {
                let d1 = c1.centroid.distance(to: ball)
                let step = 1.5 * baseRadius
                // En el fotograma siguiente: más lejos de la bola, sin bajar y a un salto razonable.
                let c2 = blobs(inFrame: f + 1, around: c1.centroid, radius: step)
                    .filter { $0.centroid.distance(to: ball) > d1 + 0.5 && $0.centroid.y <= c1.centroid.y + 1 }
                    .min { $0.centroid.distance(to: c1.centroid) < $1.centroid.distance(to: c1.centroid) }
                guard let c2 else { continue }
                let velocity = (c2.centroid - c1.centroid) * frameRate
                let kalman = KalmanFilter2D(position: c2.centroid, velocity: velocity,
                                            positionStdDev: options.measurementNoise,
                                            velocityStdDev: max(0.3 * velocity.length, 60),
                                            processNoise: options.processNoise, measurementNoise: options.measurementNoise)
                let forward = follow(kalman, from: f + 1, step: 1, limit: frames.count - 1, tee: ball)
                let start = [TrackedBallPoint(frameIndex: f, point: c1.centroid, isSeed: false),
                             TrackedBallPoint(frameIndex: f + 1, point: c2.centroid, isSeed: false)]
                return BlobTrack(points: start + forward.points, lastSeenFrame: forward.lastSeen ?? f + 1, end: forward.end)
            }
        }
        return BlobTrack(points: [], lastSeenFrame: nil, end: .notFound)
    }

    /// Toque de refuerzo (docs/03, paso 4 bis): sigue hacia delante y hacia atrás desde un punto
    /// tocado en cualquier fotograma posterior al impacto.
    /// - Parameters:
    ///   - point: donde el usuario ve la bola (se ajusta a la mancha más cercana si hay una a menos de 6 px).
    ///   - velocity: velocidad de la bola en ese momento (px/s), de los puntos que ya había o de la curva
    ///     propuesta. Sin ella, el Kalman arranca parado y con mucha duda sobre la velocidad.
    public func track(fromSeed point: Point2D, atFrame seedFrame: Int, velocity: Point2D? = nil) -> BlobTrack {
        guard seedFrame > impactFrame, seedFrame < frames.count else {
            return BlobTrack(points: [], lastSeenFrame: nil, end: .notFound)
        }
        let snapped = blobs(inFrame: seedFrame, around: point, radius: options.seedSnapRadius)
            .filter { $0.centroid.distance(to: point) <= options.seedSnapRadius }
            .min { $0.centroid.distance(to: point) < $1.centroid.distance(to: point) }?.centroid ?? point
        let v = velocity ?? .zero
        let velocityStdDev = velocity.map { max(0.3 * $0.length, 60) } ?? options.unknownVelocityStdDev
        func filter(_ velocity: Point2D) -> KalmanFilter2D {
            KalmanFilter2D(position: snapped, velocity: velocity, positionStdDev: options.measurementNoise,
                           velocityStdDev: velocityStdDev, processNoise: options.processNoise,
                           measurementNoise: options.measurementNoise)
        }
        // Hacia atrás se usa el mismo filtro con la velocidad al revés: el vídeo "rebobinado".
        let forward = follow(filter(v), from: seedFrame, step: 1, limit: frames.count - 1, tee: teePosition)
        let backward = follow(filter(-v), from: seedFrame, step: -1, limit: impactFrame + 1, tee: teePosition)
        let seed = TrackedBallPoint(frameIndex: seedFrame, point: snapped, isSeed: true)
        return BlobTrack(points: Array(backward.points.reversed()) + [seed] + forward.points,
                         lastSeenFrame: forward.lastSeen ?? seedFrame, end: forward.end)
    }

    /// Manchas que parecen una bola cerca de `center` (para el seguimiento y el modo diagnóstico).
    public func blobs(inFrame index: Int, around center: Point2D, radius: Double) -> [Blob] {
        let frame = frames[index]
        let w = frame.width
        let h = frame.height
        // La zona se agranda un margen: una mancha que toca el borde de la zona (y no el de la imagen)
        // es un trozo de algo más grande, como el cuerpo, y se descarta.
        let margin = 6.0
        let x0 = max(0, Int((center.x - radius - margin).rounded(.down)))
        let x1 = min(w - 1, Int((center.x + radius + margin).rounded(.up)))
        let y0 = max(0, Int((center.y - radius - margin).rounded(.down)))
        let y1 = min(h - 1, Int((center.y + radius + margin).rounded(.up)))
        guard x0 <= x1, y0 <= y1 else { return [] }
        let zoneWidth = x1 - x0 + 1
        let zoneHeight = y1 - y0 + 1

        // Píxeles cambiados de la zona y cuánto han cambiado.
        var difference = [Int](repeating: 0, count: zoneWidth * zoneHeight)
        for y in y0...y1 {
            for x in x0...x1 {
                let i = y * w + x
                let d = abs(Int(frame.pixels[i]) - Int(background.pixels[i]))
                if d > Int(thresholds[i]) { difference[(y - y0) * zoneWidth + (x - x0)] = d }
            }
        }

        // Componentes conexas (vecinos en 8 direcciones) con una pila, sin recursión.
        var visited = [Bool](repeating: false, count: difference.count)
        var result: [Blob] = []
        var stack: [Int] = []
        for startIndex in difference.indices where difference[startIndex] > 0 && !visited[startIndex] {
            visited[startIndex] = true
            stack.append(startIndex)
            var area = 0
            var sum = 0.0, sumX = 0.0, sumY = 0.0
            var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
            while let index = stack.popLast() {
                let lx = index % zoneWidth
                let ly = index / zoneWidth
                let d = Double(difference[index])
                area += 1
                sum += d
                sumX += d * Double(lx + x0)
                sumY += d * Double(ly + y0)
                minX = min(minX, lx); maxX = max(maxX, lx)
                minY = min(minY, ly); maxY = max(maxY, ly)
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = lx + dx
                        let ny = ly + dy
                        guard nx >= 0, nx < zoneWidth, ny >= 0, ny < zoneHeight else { continue }
                        let neighbor = ny * zoneWidth + nx
                        if difference[neighbor] > 0 && !visited[neighbor] {
                            visited[neighbor] = true
                            stack.append(neighbor)
                        }
                    }
                }
            }
            let touchesZoneEdge = (minX == 0 && x0 > 0) || (maxX == zoneWidth - 1 && x1 < w - 1)
                || (minY == 0 && y0 > 0) || (maxY == zoneHeight - 1 && y1 < h - 1)
            let boxWidth = maxX - minX + 1
            let boxHeight = maxY - minY + 1
            let aspect = Double(max(boxWidth, boxHeight)) / Double(min(boxWidth, boxHeight))
            let fill = Double(area) / Double(boxWidth * boxHeight)
            guard !touchesZoneEdge, area >= options.minimumArea, area <= options.maximumArea,
                  aspect <= options.maximumAspectRatio, fill >= options.minimumFillRatio
            else { continue }
            result.append(Blob(centroid: Point2D(sumX / sum, sumY / sum), area: area,
                               width: boxWidth, height: boxHeight, strength: sum))
        }
        return result
    }

    /// Sigue con el Kalman fotograma a fotograma en un sentido hasta perder la bola,
    /// salir de la imagen o llegar a `limit` (incluido).
    private func follow(_ start: KalmanFilter2D, from startFrame: Int, step: Int, limit: Int,
                        tee: Point2D?) -> (points: [TrackedBallPoint], lastSeen: Int?, end: TrackEnd) {
        var kalman = start
        var frame = startFrame
        var missed = 0
        var points: [TrackedBallPoint] = []
        var lastSeen: Int?
        let dt = 1 / frameRate
        let width = Double(frames[0].width)
        let height = Double(frames[0].height)
        while true {
            let next = frame + step
            if step > 0 ? next > limit : next < limit { return (points, lastSeen, .endOfClip) }
            frame = next
            kalman.predict(dt: dt)
            let predicted = kalman.position
            let gate = min(max(kalman.gateRadius(sigmas: options.gateSigmas), options.minimumGateRadius),
                           options.maximumGateRadius)
            if predicted.x < -gate || predicted.y < -gate || predicted.x > width + gate || predicted.y > height + gate {
                return (points, lastSeen, .leftImage)
            }
            let best = blobs(inFrame: frame, around: predicted, radius: gate)
                .filter { $0.centroid.distance(to: predicted) <= gate }
                .filter { blob in tee.map { blob.centroid.distance(to: $0) > options.teeExclusionRadius } ?? true }
                .min { $0.centroid.distance(to: predicted) < $1.centroid.distance(to: predicted) }
            if let best {
                kalman.correct(measurement: best.centroid)
                points.append(TrackedBallPoint(frameIndex: frame, point: best.centroid, isSeed: false))
                lastSeen = frame
                missed = 0
            } else {
                missed += 1
                if missed >= options.maximumMissedFrames { return (points, lastSeen, .lost) }
            }
        }
    }
}
