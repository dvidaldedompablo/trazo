import Foundation

/// Filtro biquad (segundo orden) en forma directa I:
/// y[n] = b0·x[n] + b1·x[n−1] + b2·x[n−2] − a1·y[n−1] − a2·y[n−2]   (con a0 = 1).
///
/// Encadenando biquads se hacen los filtros de audio de GolfCore: el paso banda del detector
/// de impacto y la ponderación K de la sonoridad. Las fórmulas de paso alto y paso bajo son
/// las del "Audio EQ Cookbook" de Robert Bristow-Johnson, las que usa casi todo el software de audio.
struct Biquad: Sendable, Equatable {
    var b0: Double
    var b1: Double
    var b2: Double
    var a1: Double
    var a2: Double

    /// Paso alto: deja pasar lo que está por encima de `cutoff` (Hz).
    /// Con q = 1/√2 (Butterworth) la respuesta es plana, sin joroba en el corte.
    static func highPass(cutoff: Double, q: Double = 0.5.squareRoot(), sampleRate: Double) -> Biquad {
        let w = 2 * Double.pi * cutoff / sampleRate
        let cosW = cos(w)
        let alpha = sin(w) / (2 * q)
        let a0 = 1 + alpha
        return Biquad(b0: (1 + cosW) / 2 / a0, b1: -(1 + cosW) / a0, b2: (1 + cosW) / 2 / a0,
                      a1: -2 * cosW / a0, a2: (1 - alpha) / a0)
    }

    /// Paso bajo: deja pasar lo que está por debajo de `cutoff` (Hz).
    static func lowPass(cutoff: Double, q: Double = 0.5.squareRoot(), sampleRate: Double) -> Biquad {
        let w = 2 * Double.pi * cutoff / sampleRate
        let cosW = cos(w)
        let alpha = sin(w) / (2 * q)
        let a0 = 1 + alpha
        return Biquad(b0: (1 - cosW) / 2 / a0, b1: (1 - cosW) / a0, b2: (1 - cosW) / 2 / a0,
                      a1: -2 * cosW / a0, a2: (1 - alpha) / a0)
    }

    /// Filtra la señal en su sitio, de la primera muestra a la última.
    func apply(to x: inout [Double]) {
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in x.indices {
            let input = x[i]
            let output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = input
            y2 = y1
            y1 = output
            x[i] = output
        }
    }

    /// Filtra hacia delante y luego hacia atrás. Un filtro normal retrasa la señal un poco
    /// (y distinto según la frecuencia); al pasar también al revés, ese retraso se deshace:
    /// el impacto se queda exactamente donde estaba. A cambio, el filtro corta el doble.
    func applyZeroPhase(to x: inout [Double]) {
        apply(to: &x)
        x.reverse()
        apply(to: &x)
        x.reverse()
    }
}
