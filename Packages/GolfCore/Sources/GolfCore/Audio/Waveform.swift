import Foundation

/// La onda del sonido resumida en barras, para dibujarla (docs/02, componente "Onda").
public enum Waveform {
    /// Divide la señal en `count` trozos iguales y devuelve el pico de cada uno, de 0 a 1
    /// (relativo al pico más alto). Con el pico y no con la media, los golpes se ven aunque duren
    /// unos milisegundos dentro de un trozo de medio segundo.
    public static func bars(samples: [Float], count: Int) -> [Double] {
        guard count > 0 else { return [] }
        guard !samples.isEmpty else { return [Double](repeating: 0, count: count) }
        var peaks = [Double](repeating: 0, count: count)
        for (index, sample) in samples.enumerated() {
            let bar = min(index * count / samples.count, count - 1)
            peaks[bar] = max(peaks[bar], abs(Double(sample)))
        }
        let top = peaks.max() ?? 0
        guard top > 0 else { return peaks }
        return peaks.map { $0 / top }
    }

    /// Índice de la barra en la que cae el instante `time` (s) de una señal de `duration` s.
    public static func barIndex(for time: Double, duration: Double, count: Int) -> Int {
        guard duration > 0, count > 0 else { return 0 }
        return min(max(Int(time / duration * Double(count)), 0), count - 1)
    }
}
