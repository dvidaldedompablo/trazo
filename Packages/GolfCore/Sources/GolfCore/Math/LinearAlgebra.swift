import Foundation

/// Álgebra lineal mínima para los ajustes por mínimos cuadrados.
/// Los sistemas de GolfCore son diminutos (de 2x2 a 4x4), así que basta con eliminación de Gauss
/// escrita a mano: se entiende leyéndola y no hace falta ninguna librería.
enum LinearAlgebra {
    /// Resuelve A·x = b. `a` va por filas (n×n). Devuelve `nil` si la matriz es (casi) singular,
    /// por ejemplo al ajustar una parábola con menos de tres instantes distintos.
    static func solve(_ a: [Double], _ b: [Double]) -> [Double]? {
        let n = b.count
        guard n > 0, a.count == n * n else { return nil }
        var m = a
        var rhs = b
        let scale = m.reduce(0) { max($0, abs($1)) }
        guard scale > 0 else { return nil }

        for col in 0..<n {
            // Pivote parcial: se elige la fila con el valor más grande en esta columna.
            // Dividir por números muy pequeños dispara los errores de redondeo.
            var pivotRow = col
            for row in (col + 1)..<n where abs(m[row * n + col]) > abs(m[pivotRow * n + col]) {
                pivotRow = row
            }
            let pivot = m[pivotRow * n + col]
            if abs(pivot) <= 1e-12 * scale { return nil }
            if pivotRow != col {
                for k in 0..<n { m.swapAt(col * n + k, pivotRow * n + k) }
                rhs.swapAt(col, pivotRow)
            }
            // Eliminación: se deja a cero la columna por debajo del pivote.
            for row in (col + 1)..<n {
                let factor = m[row * n + col] / pivot
                if factor == 0 { continue }
                for k in col..<n { m[row * n + k] -= factor * m[col * n + k] }
                rhs[row] -= factor * rhs[col]
            }
        }
        // Sustitución hacia atrás, de la última incógnita a la primera.
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = rhs[row]
            for k in (row + 1)..<n { sum -= m[row * n + k] * x[k] }
            x[row] = sum / m[row * n + row]
        }
        return x
    }

    /// Ajusta un polinomio c0 + c1·t + c2·t² + … de grado `degree` a los pares (t, v)
    /// minimizando Σ peso·(p(t) − v)². Sin pesos, todos valen 1.
    /// Devuelve `nil` si no hay datos suficientes para fijar todos los coeficientes.
    static func fitPolynomial(times: [Double], values: [Double], weights: [Double]? = nil, degree: Int) -> [Double]? {
        let terms = degree + 1
        guard degree >= 0, times.count == values.count, times.count >= terms else { return nil }
        // Ecuaciones normales: (Aᵀ·W·A)·c = Aᵀ·W·v, con A la matriz de potencias de t.
        var normal = [Double](repeating: 0, count: terms * terms)
        var rhs = [Double](repeating: 0, count: terms)
        var powers = [Double](repeating: 1, count: 2 * terms - 1)
        for i in times.indices {
            let w = weights?[i] ?? 1
            powers[0] = 1
            for k in 1..<powers.count { powers[k] = powers[k - 1] * times[i] }
            for r in 0..<terms {
                rhs[r] += w * powers[r] * values[i]
                for c in 0..<terms { normal[r * terms + c] += w * powers[r + c] }
            }
        }
        return solve(normal, rhs)
    }

    /// Valor del polinomio en t (regla de Horner: menos multiplicaciones y menos redondeo).
    static func evaluatePolynomial(_ coefficients: [Double], at t: Double) -> Double {
        var result = 0.0
        for c in coefficients.reversed() { result = result * t + c }
        return result
    }

    /// Mediana de una lista (la media de los dos centrales si hay un número par). 0 si está vacía.
    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// Potencia entera sin pasar por `pow` (más rápida y exacta para exponentes pequeños).
    static func power(_ x: Double, _ k: Int) -> Double {
        var result = 1.0
        for _ in 0..<max(k, 0) { result *= x }
        return result
    }
}
