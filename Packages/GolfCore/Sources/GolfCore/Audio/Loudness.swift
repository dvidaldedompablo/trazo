import Foundation

/// Sonoridad según la recomendación ITU-R BS.1770 (la de los LUFS de la tele y de las plataformas).
///
/// Se usa para que la voz del análisis suene siempre igual de fuerte (docs/04: −16 LUFS
/// integrados y pico real como mucho −1 dBTP). Pasos de la norma:
/// 1. Ponderación K: dos filtros que imitan cómo oye el oído (realza agudos, quita graves).
/// 2. Bloques de 400 ms que se solapan un 75 % (uno cada 100 ms) y su energía media.
/// 3. Puerta absoluta: fuera los bloques por debajo de −70 LUFS (silencio).
/// 4. Puerta relativa: fuera los bloques 10 LU por debajo de la media de los que quedan
///    (las pausas entre frases no bajan la cifra).
/// 5. Sonoridad integrada = −0,691 + 10·log10(energía media de los bloques que pasan).
public enum Loudness {
    /// Sonoridad integrada en LUFS de una señal con uno o varios canales del mismo tamaño.
    /// Devuelve `nil` si dura menos de un bloque (400 ms) o si todo es silencio.
    public static func integratedLoudness(channels: [[Float]], sampleRate: Double) -> Double? {
        guard let length = channels.first?.count, sampleRate > 0,
              channels.allSatisfy({ $0.count == length }) else { return nil }
        let blockSize = Int((0.4 * sampleRate).rounded())
        let step = Int((0.1 * sampleRate).rounded())
        guard length >= blockSize, step > 0 else { return nil }

        // 1. Ponderación K y cuadrado de cada muestra, con sumas acumuladas para sacar
        // la energía de cada bloque sin volver a recorrerlo.
        let stages = kWeighting(sampleRate: sampleRate)
        var cumulative: [[Double]] = []
        for channel in channels {
            var x = channel.map(Double.init)
            for stage in stages { stage.apply(to: &x) }
            var sums = [Double](repeating: 0, count: length + 1)
            for i in 0..<length { sums[i + 1] = sums[i] + x[i] * x[i] }
            cumulative.append(sums)
        }

        // 2. Energía de cada bloque, sumando los canales con su peso
        // (1 para izquierdo, derecho y central; 1,41 para los envolventes).
        var blockPowers: [Double] = []
        var start = 0
        while start + blockSize <= length {
            var power = 0.0
            for (index, sums) in cumulative.enumerated() {
                let weight = index < 3 ? 1.0 : 1.41
                power += weight * (sums[start + blockSize] - sums[start]) / Double(blockSize)
            }
            blockPowers.append(power)
            start += step
        }

        // 3 y 4. Puertas absoluta y relativa.
        let aboveAbsolute = blockPowers.filter { loudness(ofPower: $0) > -70 }
        guard !aboveAbsolute.isEmpty else { return nil }
        let relativeGate = loudness(ofPower: mean(aboveAbsolute)) - 10
        let gated = aboveAbsolute.filter { loudness(ofPower: $0) > relativeGate }
        guard !gated.isEmpty else { return nil }
        // 5.
        return loudness(ofPower: mean(gated))
    }

    /// Sonoridad integrada de una señal mono.
    public static func integratedLoudness(mono samples: [Float], sampleRate: Double) -> Double? {
        integratedLoudness(channels: [samples], sampleRate: sampleRate)
    }

    /// Pico de muestra en dBFS (0 dBFS = amplitud 1).
    public static func samplePeak(_ samples: [Float]) -> Double {
        decibels(amplitude: samples.reduce(0) { max($0, abs(Double($1))) })
    }

    /// Pico real (dBTP) estimado con sobremuestreo x4, como pide BS.1770.
    ///
    /// Entre dos muestras la onda puede subir más que cualquiera de ellas; al convertir a
    /// analógico (o a AAC) ese pico escondido puede saturar. Se reconstruyen 3 puntos intermedios
    /// entre cada par de muestras con un filtro sinc de 12 coeficientes por fase (ventana de Hann).
    public static func truePeak(_ samples: [Float]) -> Double {
        let n = samples.count
        guard n > 0 else { return -.infinity }
        let taps = 12
        let half = taps / 2
        let phases = 4
        var filters: [[Double]] = []
        for phase in 1..<phases {
            let fraction = Double(phase) / Double(phases)
            var coefficients: [Double] = []
            for m in 0..<taps {
                // Muestra m de la ventana: posición relativa al instante interpolado.
                let distance = Double(m - (half - 1)) - fraction
                let sinc = distance == 0 ? 1 : sin(Double.pi * distance) / (Double.pi * distance)
                let window = 0.5 * (1 + cos(Double.pi * distance / (Double(half) + 0.5)))
                coefficients.append(sinc * window)
            }
            filters.append(coefficients)
        }
        var peak = 0.0
        for i in 0..<n {
            peak = max(peak, abs(Double(samples[i])))
            for coefficients in filters {
                var sum = 0.0
                for m in 0..<taps {
                    let index = i + m - (half - 1)
                    if index >= 0 && index < n { sum += coefficients[m] * Double(samples[index]) }
                }
                peak = max(peak, abs(sum))
            }
        }
        return decibels(amplitude: peak)
    }

    /// Ganancia (dB) para llevar la sonoridad `integrated` al objetivo.
    public static func gainToTarget(integrated: Double, target: Double = -16) -> Double {
        target - integrated
    }

    /// Ganancia (dB) para llegar al objetivo sin que el pico real pase del techo:
    /// la menor de las dos. Si el techo manda, la voz queda algo más baja que el objetivo.
    public static func normalizationGain(integrated: Double, truePeak: Double,
                                         target: Double = -16, peakCeiling: Double = -1) -> Double {
        min(target - integrated, peakCeiling - truePeak)
    }

    /// Factor por el que se multiplican las muestras para aplicar una ganancia en dB.
    public static func linearGain(decibels: Double) -> Double {
        pow(10, decibels / 20)
    }

    /// Los dos filtros de la ponderación K para cualquier frecuencia de muestreo.
    /// A 48 kHz dan exactamente los coeficientes de la tabla de la norma (lo comprueba un test).
    /// Las constantes son las de los parámetros analógicos que publica libebur128.
    static func kWeighting(sampleRate: Double) -> [Biquad] {
        // Etapa 1: estante de agudos (+4 dB por encima de unos 1,7 kHz): el efecto de la cabeza.
        var f0 = 1681.974450955533
        let gain = 3.999843853973347
        var q = 0.7071752369554196
        var k = tan(Double.pi * f0 / sampleRate)
        let vh = pow(10, gain / 20)
        let vb = pow(vh, 0.4996667741545416)
        var a0 = 1 + k / q + k * k
        let shelf = Biquad(b0: (vh + vb * k / q + k * k) / a0,
                           b1: 2 * (k * k - vh) / a0,
                           b2: (vh - vb * k / q + k * k) / a0,
                           a1: 2 * (k * k - 1) / a0,
                           a2: (1 - k / q + k * k) / a0)
        // Etapa 2: paso alto RLB a unos 38 Hz: los graves cuentan poco para el oído.
        f0 = 38.13547087602444
        q = 0.5003270373238773
        k = tan(Double.pi * f0 / sampleRate)
        a0 = 1 + k / q + k * k
        let highPass = Biquad(b0: 1, b1: -2, b2: 1,
                              a1: 2 * (k * k - 1) / a0,
                              a2: (1 - k / q + k * k) / a0)
        return [shelf, highPass]
    }

    static func loudness(ofPower power: Double) -> Double {
        -0.691 + 10 * log10(max(power, 1e-30))
    }

    static func decibels(amplitude: Double) -> Double {
        amplitude > 0 ? 20 * log10(amplitude) : -.infinity
    }

    private static func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }
}
