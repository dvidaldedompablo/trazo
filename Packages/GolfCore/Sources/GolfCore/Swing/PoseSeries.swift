import Foundation

/// Limpieza de la serie de poses (docs/04, punto 1): huecos cortos rellenos por interpolación
/// y suavizado Savitzky-Golay por articulación. Los puntos con confianza baja (< 0,3) ya no
/// llegan aquí: se descartan al leer la pose de Vision.
public enum PoseSeries {
    /// - Parameters:
    ///   - frames: la pose de cada fotograma, en orden de tiempo.
    ///   - maximumGap: un hueco de hasta estos fotogramas se rellena por interpolación lineal;
    ///     uno más largo se queda vacío (mejor sin dato que con un dato inventado).
    ///   - window: ventana del Savitzky-Golay (docs/04: 9). El orden es 3.
    /// - Returns: la misma serie con los huecos cortos rellenos y las posiciones suavizadas.
    public static func process(_ frames: [PoseFrame], maximumGap: Int = 4,
                               window: Int = 9, order: Int = 3) -> [PoseFrame] {
        guard frames.count >= 3 else { return frames }
        var result = frames
        for joint in Joint.allCases {
            let seen = frames.indices.filter { frames[$0].joints[joint] != nil }
            guard seen.count >= 3 else { continue }

            // Relleno de huecos cortos entre dos apariciones seguidas de la articulación.
            var series: [(index: Int, point: Point2D)] = seen.map { ($0, frames[$0].joints[joint]!) }
            for (a, b) in zip(seen, seen.dropFirst()) where b - a > 1 && b - a <= maximumGap + 1 {
                let pa = frames[a].joints[joint]!
                let pb = frames[b].joints[joint]!
                for i in (a + 1)..<b {
                    series.append((i, Point2D.lerp(pa, pb, Double(i - a) / Double(b - a))))
                }
            }
            series.sort { $0.index < $1.index }

            // Cada tramo seguido (tras el relleno) se suaviza por su cuenta: suavizar a través
            // de un hueco largo mezclaría posiciones que no van seguidas en el tiempo.
            var run: [(index: Int, point: Point2D)] = []
            func smoothRun() {
                guard !run.isEmpty else { return }
                let smoothed = Smoothing.savitzkyGolay(run.map(\.point), window: window, order: order)
                for (k, item) in run.enumerated() { result[item.index].joints[joint] = smoothed[k] }
                run = []
            }
            for item in series {
                if let last = run.last, item.index != last.index + 1 { smoothRun() }
                run.append(item)
            }
            smoothRun()
        }
        return result
    }
}
