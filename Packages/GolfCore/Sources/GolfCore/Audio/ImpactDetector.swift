import Foundation

/// Un impacto encontrado en el audio.
public struct Impact: Sendable, Equatable {
    /// Segundos desde el principio del audio.
    public let time: Double
    /// Flujo espectral del pico: cuánto creció de golpe el sonido en la banda del impacto.
    /// Sirve para elegir el golpe más fuerte cuando se oyen otros jugadores.
    public let strength: Double
    /// Cuántas MAD sobresale el pico de la mediana local. Un golpe claro da cientos.
    public let prominence: Double

    public init(time: Double, strength: Double, prominence: Double) {
        self.time = time
        self.strength = strength
        self.prominence = prominence
    }
}

/// Opciones del detector. Los valores por defecto salen de `TracerConstants` (docs/03, paso 2).
public struct ImpactDetectorOptions: Sendable {
    public var bandLow = TracerConstants.impactBandLow
    public var bandHigh = TracerConstants.impactBandHigh
    public var windowSize = TracerConstants.impactWindowSize
    public var hopSize = TracerConstants.impactHopSize
    public var medianWindow = TracerConstants.impactMedianWindow
    public var madFactor = TracerConstants.impactMADFactor
    public var minimumMedianRatio = TracerConstants.impactMinimumMedianRatio
    public var refractoryPeriod = TracerConstants.impactRefractoryPeriod
    public var refineRadius = TracerConstants.impactRefineRadius
    public var minimumPeakAmplitude = TracerConstants.impactMinimumPeakAmplitude

    public init() {}
}

/// Encuentra los impactos de bola en una señal de audio mono (PCM en coma flotante, de −1 a 1).
///
/// Pasos:
/// 1. Paso banda de 1,5 a 7 kHz, hacia delante y hacia atrás para no retrasar nada.
/// 2. Espectro en ventanas de 256 muestras cada 64 (a 48 kHz, cada 1,3 ms).
/// 3. Flujo espectral: en cada ventana, la suma de lo que ha crecido cada frecuencia de la banda
///    respecto a la ventana anterior. Un golpe seco es un salto brusco en muchas frecuencias a la vez.
/// 4. Umbral adaptativo: mediana del flujo en 500 ms alrededor más 6 veces su MAD (desviación
///    absoluta mediana), y además 4 veces la mediana. Así se adapta al ruido de fondo de cada sitio.
/// 5. Picos que pasan el umbral; entre dos a menos de 400 ms se queda el más fuerte.
/// 6. Instante fino: el máximo de la envolvente del sonido filtrado en ±5 ms alrededor del pico.
public enum ImpactDetector {
    /// Todos los impactos, ordenados por tiempo.
    public static func detect(samples: [Float], sampleRate: Double,
                              options: ImpactDetectorOptions = .init()) -> [Impact] {
        let n = samples.count
        let windowSize = options.windowSize
        let hop = max(options.hopSize, 1)
        guard sampleRate > 0, n >= windowSize, let fft = FFT(size: windowSize) else { return [] }

        // 1. Paso banda (la banda alta nunca por encima del 45 % de la frecuencia de muestreo).
        var filtered = samples.map(Double.init)
        let bandHigh = min(options.bandHigh, 0.45 * sampleRate)
        Biquad.highPass(cutoff: options.bandLow, sampleRate: sampleRate).applyZeroPhase(to: &filtered)
        Biquad.lowPass(cutoff: bandHigh, sampleRate: sampleRate).applyZeroPhase(to: &filtered)

        // 2 y 3. Espectro con ventana de Hann (suaviza los bordes de cada trozo) y flujo espectral.
        let hann = (0..<windowSize).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(windowSize)) }
        let binWidth = sampleRate / Double(windowSize)
        let lowBin = max(Int((options.bandLow / binWidth).rounded(.up)), 1)
        let highBin = min(Int((bandHigh / binWidth).rounded(.down)), windowSize / 2)
        guard lowBin <= highBin else { return [] }
        let frameCount = (n - windowSize) / hop + 1
        var flux = [Double](repeating: 0, count: frameCount)
        var previous: [Double]?
        var window = [Double](repeating: 0, count: windowSize)
        for frame in 0..<frameCount {
            let start = frame * hop
            for i in 0..<windowSize { window[i] = filtered[start + i] * hann[i] }
            let band = Array(fft.magnitudes(of: window)[lowBin...highBin])
            if let previous {
                var sum = 0.0
                for k in band.indices { sum += max(0, band[k] - previous[k]) }
                flux[frame] = sum
            }
            previous = band
        }

        // 4. Umbral adaptativo. La mediana y la MAD se calculan cada 8 ventanas (~10 ms) y cada pico
        // usa la más cercana: el ruido de fondo no cambia tan deprisa y así se ordena mucho menos.
        let halfWindow = max(Int((options.medianWindow * sampleRate / Double(hop) / 2).rounded()), 1)
        let stride = 8
        var localStats: [(median: Double, mad: Double)] = []
        for center in Swift.stride(from: 0, to: frameCount, by: stride) {
            let slice = Array(flux[max(0, center - halfWindow)...min(frameCount - 1, center + halfWindow)])
            let median = LinearAlgebra.median(slice)
            let mad = LinearAlgebra.median(slice.map { abs($0 - median) })
            localStats.append((median, mad))
        }

        // 5. Picos locales que superan el umbral.
        var candidates: [(frame: Int, flux: Double, prominence: Double)] = []
        if frameCount >= 3 {
            for i in 1..<(frameCount - 1) where flux[i] > 0 && flux[i] >= flux[i - 1] && flux[i] > flux[i + 1] {
                let stats = localStats[min((i + stride / 2) / stride, localStats.count - 1)]
                let threshold = stats.median + options.madFactor * stats.mad
                guard flux[i] > threshold, flux[i] >= options.minimumMedianRatio * stats.median else { continue }
                let prominence = (flux[i] - stats.median) / max(stats.mad, 1e-12)
                candidates.append((i, flux[i], prominence))
            }
        }
        // Periodo refractario: de más fuerte a más débil, se acepta un pico si no hay otro ya aceptado cerca.
        let refractoryFrames = options.refractoryPeriod * sampleRate / Double(hop)
        var accepted: [(frame: Int, flux: Double, prominence: Double)] = []
        for candidate in candidates.sorted(by: { $0.flux > $1.flux })
        where accepted.allSatisfy({ Double(abs($0.frame - candidate.frame)) >= refractoryFrames }) {
            accepted.append(candidate)
        }

        // 6. Instante fino con la envolvente: valor absoluto del sonido filtrado con una media
        // centrada de 0,5 ms (centrada para no retrasar el máximo). Se calcula con sumas acumuladas.
        let smoothing = max(Int((0.0005 * sampleRate).rounded()), 1)
        var prefix = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + abs(filtered[i]) }
        func envelope(_ i: Int) -> Double {
            let a = max(0, i - smoothing / 2)
            let b = min(n, i + smoothing / 2 + 1)
            return (prefix[b] - prefix[a]) / Double(b - a)
        }
        let refine = Int((options.refineRadius * sampleRate).rounded())
        var impacts: [Impact] = []
        for peak in accepted {
            let center = peak.frame * hop + windowSize / 2
            var bestIndex = center
            var bestValue = -1.0
            for i in max(0, center - refine)...min(n - 1, center + refine) {
                let value = envelope(i)
                if value > bestValue {
                    bestValue = value
                    bestIndex = i
                }
            }
            // Casi silencio: un "impacto" tan flojo no es un golpe.
            guard bestValue >= options.minimumPeakAmplitude else { continue }
            impacts.append(Impact(time: Double(bestIndex) / sampleRate, strength: peak.flux, prominence: peak.prominence))
        }
        return impacts.sorted { $0.time < $1.time }
    }

    /// El impacto más fuerte (el golpe propio suele ser el que más suena cerca del micrófono).
    public static func strongest(samples: [Float], sampleRate: Double,
                                 options: ImpactDetectorOptions = .init()) -> Impact? {
        detect(samples: samples, sampleRate: sampleRate, options: options).max { $0.strength < $1.strength }
    }
}
