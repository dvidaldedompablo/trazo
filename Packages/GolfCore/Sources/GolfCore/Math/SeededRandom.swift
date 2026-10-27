import Foundation

/// Generador de números pseudoaleatorios con semilla (algoritmo SplitMix64).
///
/// Con la misma semilla da siempre la misma secuencia. Por eso el RANSAC del ajuste
/// y los datos sintéticos de los tests salen igual en cada ejecución: si un test falla,
/// vuelve a fallar igual y se puede investigar.
/// Cumple `RandomNumberGenerator`, así que vale para `Int.random(in:using:)` y compañía.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        // Los operadores con & (&+, &*) dejan que el número dé la vuelta en vez de dar error:
        // aquí ese desbordamiento es justo lo que mezcla los bits.
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Número uniforme en [0, 1).
    public mutating func nextUnit() -> Double {
        // 53 bits llenan exactamente la precisión de un Double.
        Double(next() >> 11) * 0x1.0p-53
    }

    /// Número con distribución normal de media 0 y desviación 1 (método de Box-Muller).
    public mutating func nextGaussian() -> Double {
        let u1 = max(nextUnit(), 1e-300)
        let u2 = nextUnit()
        return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
    }
}
