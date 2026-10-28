@preconcurrency import AVFoundation
import GolfCore
import Vision

/// Detector A del tracer (docs/03, paso 4 A): trayectorias de Vision.
///
/// `DetectTrajectoriesRequest` (API de Swift de iOS 18) es una petición con estado: hay que darle los
/// fotogramas en orden y con la misma petición. Vision busca objetos que se mueven en parábola y,
/// fotograma a fotograma, devuelve las trayectorias que lleva vistas; las que tienen el mismo `uuid`
/// crecen con cada fotograma, así que de cada una se guarda la última (la más larga).
/// Solo funciona en un iPhone de verdad: en el simulador falla y el tracer sigue con BlobTracker.
final class TrajectoryCollector {
    private let request: DetectTrajectoriesRequest
    private let geometry: VideoGeometry
    private let impactTime: Double
    /// Instantes de los fotogramas analizados, para fechar cada punto.
    private var analyzedTimes: [Double] = []
    private var latest: [UUID: TrajectoryObservation] = [:]
    /// Primer error de Vision (en el simulador, que no tiene detección de trayectorias).
    private(set) var failure: String?

    /// - Parameters:
    ///   - region: zona de interés en coordenadas del vídeo girado (px).
    init(geometry: VideoGeometry, impactTime: Double, region: CGRect) {
        self.geometry = geometry
        self.impactTime = impactTime
        request = DetectTrajectoriesRequest(trajectoryLength: TracerConstants.trajectoryLength, nil, frameAnalysisSpacing: nil)
        request.objectMinimumNormalizedRadius = Float(TracerConstants.minimumNormalizedRadius)
        request.objectMaximumNormalizedRadius = Float(TracerConstants.maximumNormalizedRadius)
        // Vision cuenta de 0 a 1 y desde abajo a la izquierda: se convierte la zona a mano.
        let w = CGFloat(geometry.width), h = CGFloat(geometry.height)
        request.regionOfInterest = NormalizedRect(x: region.minX / w, y: 1 - region.maxY / h,
                                                  width: region.width / w, height: region.height / h)
    }

    /// Zona de interés de docs/03: desde un poco por debajo de la bola hasta arriba, ±35 % del ancho.
    static func region(around ball: Point2D, geometry: VideoGeometry) -> CGRect {
        let w = Double(geometry.width)
        let halfWidth = TracerConstants.regionOfInterestHalfWidth * w
        let x0 = max(ball.x - halfWidth, 0), x1 = min(ball.x + halfWidth, w)
        let bottom = min(ball.y + 0.02 * Double(geometry.height), Double(geometry.height))
        return CGRect(x: x0, y: 0, width: x1 - x0, height: bottom)
    }

    /// Una zona cuadrada alrededor de un toque (para volver a lanzar Vision desde él).
    static func region(centeredOn point: Point2D, geometry: VideoGeometry, fraction: Double = 0.4) -> CGRect {
        let side = fraction * Double(min(geometry.width, geometry.height))
        let rect = CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
        return rect.intersection(CGRect(x: 0, y: 0, width: geometry.width, height: geometry.height))
    }

    /// Analiza un fotograma (en orden). Devuelve los puntos vistos hasta ahora (para ir pintándolos).
    func process(_ sample: CMSampleBuffer, time: Double) async {
        guard failure == nil else { return }
        analyzedTimes.append(time)
        do {
            let observations = try await request.perform(on: sample, orientation: geometry.visionOrientation)
            for observation in observations {
                let previous = latest[observation.uuid]
                if previous == nil || observation.detectedPoints.count >= previous!.detectedPoints.count {
                    latest[observation.uuid] = observation
                }
            }
        } catch {
            failure = error.localizedDescription
        }
    }

    /// Las trayectorias en píxeles del vídeo girado y con el tiempo desde el impacto.
    var tracks: [VisionTrack] {
        let size = CGSize(width: geometry.width, height: geometry.height)
        return latest.values.enumerated().map { index, observation in
            let points = observation.detectedPoints.map { $0.toImageCoordinates(size, origin: .upperLeft) }
            let times = pointTimes(for: observation, count: points.count)
            let samples = zip(points, times).map { point, time in
                TrajectorySample(time: time - impactTime, point: Point2D(Double(point.x), Double(point.y)))
            }
            return VisionTrack(id: index, samples: samples, confidence: Double(observation.confidence))
        }
    }

    /// Instante de cada punto: repartidos en el intervalo de la observación si lo trae;
    /// si no, los últimos fotogramas analizados.
    private func pointTimes(for observation: TrajectoryObservation, count: Int) -> [Double] {
        if let range = observation.timeRange, count > 1, range.duration.seconds > 0 {
            let start = range.start.seconds
            let step = range.duration.seconds / Double(count - 1)
            return (0..<count).map { start + Double($0) * step }
        }
        return Array(analyzedTimes.suffix(count))
    }
}
