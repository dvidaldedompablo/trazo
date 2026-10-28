import Foundation

/// Una trayectoria de Vision ya pasada a píxeles y a tiempo desde el impacto.
public struct VisionTrack: Sendable, Equatable {
    /// Identificador de Vision (el `uuid` de la observación, como número para compararlo fácil).
    public var id: Int
    public var samples: [TrajectorySample]
    public var confidence: Double

    public init(id: Int, samples: [TrajectorySample], confidence: Double) {
        self.id = id
        self.samples = samples.sorted { $0.time < $1.time }
        self.confidence = confidence
    }
}

/// Elige qué trayectorias de Vision son la bola (docs/03, paso 4 A).
///
/// Vision encuentra cualquier cosa que se mueva en parábola: el palo, un pájaro, otra bola. Se quedan las
/// que empiezan a menos del 8 % (del ancho) de la bola, en los primeros 150 ms tras el impacto, suben y
/// tienen una confianza de más de 0,8. Después se añaden las que siguen a una elegida (empiezan cerca de
/// donde acaba y poco después): Vision a veces parte el vuelo en dos trayectorias.
public enum TrajectorySelector {
    public static func select(_ tracks: [VisionTrack], ball: Point2D, imageWidth: Double) -> [VisionTrack] {
        let usable = tracks.filter { $0.samples.count >= 2 && rises($0) && $0.confidence > TracerConstants.visionMinimumConfidence }
        var chosen = usable.filter { track in
            let first = track.samples[0]
            return first.point.distance(to: ball) <= TracerConstants.visionStartDistance * imageWidth
                && first.time <= TracerConstants.visionStartWindow
        }
        var added = true
        while added {
            added = false
            for track in usable where !chosen.contains(where: { $0.id == track.id }) {
                let first = track.samples[0]
                let continues = chosen.contains { previous in
                    guard let last = previous.samples.last else { return false }
                    let gap = first.time - last.time
                    return gap >= -0.05 && gap <= TracerConstants.visionChainGap
                        && first.point.distance(to: last.point) <= TracerConstants.visionChainDistance * imageWidth
                }
                if continues {
                    chosen.append(track)
                    added = true
                }
            }
        }
        return chosen.sorted { $0.samples[0].time < $1.samples[0].time }
    }

    /// Sube: el último punto está más arriba (menos y) que el primero.
    static func rises(_ track: VisionTrack) -> Bool {
        guard let first = track.samples.first, let last = track.samples.last else { return false }
        return last.point.y < first.point.y
    }
}
