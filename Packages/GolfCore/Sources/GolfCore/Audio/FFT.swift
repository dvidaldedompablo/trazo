import Foundation

/// Transformada rápida de Fourier (FFT) de base 2, escrita a mano.
///
/// Convierte una ventana de audio en las intensidades de cada frecuencia (el "espectro").
/// Para ventanas de 256 muestras es de sobra rápida y así GolfCore no depende de Accelerate
/// y se puede probar en cualquier sitio. Algoritmo de Cooley-Tukey: reordena las muestras
/// por "bits invertidos" y combina mariposas de tamaño 2, 4, 8… hasta el total.
struct FFT: Sendable {
    let size: Int
    private let cosTable: [Double]
    private let sinTable: [Double]
    private let bitReversed: [Int]

    /// `size` tiene que ser potencia de 2 (64, 128, 256…).
    init?(size: Int) {
        guard size >= 2, size & (size - 1) == 0 else { return nil }
        self.size = size
        var bits = 0
        while (1 << bits) < size { bits += 1 }
        cosTable = (0..<(size / 2)).map { cos(2 * Double.pi * Double($0) / Double(size)) }
        sinTable = (0..<(size / 2)).map { sin(2 * Double.pi * Double($0) / Double(size)) }
        bitReversed = (0..<size).map { index in
            var reversed = 0
            var value = index
            for _ in 0..<bits {
                reversed = (reversed << 1) | (value & 1)
                value >>= 1
            }
            return reversed
        }
    }

    /// Módulo de cada frecuencia, de 0 (continua) a size/2 (Nyquist): size/2 + 1 valores.
    /// La frecuencia k está en k·fs/size Hz.
    func magnitudes(of input: [Double]) -> [Double] {
        precondition(input.count == size, "La ventana debe tener \(size) muestras")
        var re = [Double](repeating: 0, count: size)
        var im = [Double](repeating: 0, count: size)
        for i in 0..<size { re[bitReversed[i]] = input[i] }

        var length = 2
        while length <= size {
            let half = length / 2
            let step = size / length
            var start = 0
            while start < size {
                for k in 0..<half {
                    // Factor de giro e^(−2πik/length).
                    let wr = cosTable[k * step]
                    let wi = -sinTable[k * step]
                    let i = start + k
                    let j = i + half
                    let tr = wr * re[j] - wi * im[j]
                    let ti = wr * im[j] + wi * re[j]
                    re[j] = re[i] - tr
                    im[j] = im[i] - ti
                    re[i] += tr
                    im[i] += ti
                }
                start += length
            }
            length *= 2
        }
        return (0...(size / 2)).map { (re[$0] * re[$0] + im[$0] * im[$0]).squareRoot() }
    }
}
