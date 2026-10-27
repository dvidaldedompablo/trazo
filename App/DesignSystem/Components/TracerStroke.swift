import SwiftUI

/// El trazo del tracer como en la tele (docs/02): un halo difuminado del color, la línea de color
/// (con un borde suave) y un núcleo blanco. Adelgaza hacia el final, como si la bola se alejara.
///
/// `progress` (0 a 1) es la parte del vuelo ya dibujada. Se puede animar: SwiftUI va cambiando
/// el número poco a poco y cada capa se vuelve a dibujar hasta ese punto.
struct TracerStroke: View {
    /// Puntos del vuelo, de la salida a la caída, en el sistema de coordenadas de la vista.
    let points: [CGPoint]
    let color: Color
    var progress: CGFloat = 1

    var body: some View {
        ZStack {
            ForEach(TraceLayer.all) { layer in
                TaperedTraceShape(points: points, startWidth: layer.startWidth, endWidth: layer.endWidth, progress: progress)
                    .fill(layer.isCore ? Color.white.opacity(layer.opacity) : color.opacity(layer.opacity))
                    .blur(radius: layer.blur)
            }
            // La bola en la punta mientras vuela: halo del color y núcleo blanco.
            // Desaparece sola al llegar al final (la forma queda vacía con progress 0 o 1).
            TraceHeadShape(points: points, radius: TraceLayer.headHaloRadius, progress: progress)
                .fill(color.opacity(0.8))
                .blur(radius: TraceLayer.headHaloRadius / 2)
            TraceHeadShape(points: points, radius: TraceLayer.headCoreRadius, progress: progress)
                .fill(Color.white)
        }
        .allowsHitTesting(false)
    }
}

/// Las capas del trazo con los grosores de la maqueta (en puntos, para una ventana de 358 x 180).
/// Cada capa pasa de `startWidth` en la salida a `endWidth` en la caída.
struct TraceLayer: Identifiable {
    let id: Int
    let startWidth: CGFloat
    let endWidth: CGFloat
    let opacity: Double
    let blur: CGFloat
    var isCore = false

    static let all: [TraceLayer] = [
        // Halo: ancho, transparente y muy difuminado.
        TraceLayer(id: 0, startWidth: 14.66, endWidth: 9.65, opacity: 0.42, blur: 7),
        // Color con el borde suavizado.
        TraceLayer(id: 1, startWidth: 6.35, endWidth: 4.18, opacity: 0.9, blur: 2.2),
        // Color nítido.
        TraceLayer(id: 2, startWidth: 4.11, endWidth: 2.70, opacity: 1, blur: 0),
        // Núcleo blanco.
        TraceLayer(id: 3, startWidth: 1.47, endWidth: 0.97, opacity: 0.95, blur: 0, isCore: true),
    ]

    static let headHaloRadius: CGFloat = 5
    static let headCoreRadius: CGFloat = 2
}

/// El contorno relleno de una línea que adelgaza. Un `stroke` de SwiftUI tiene un solo grosor,
/// así que se calcula el borde izquierdo y el derecho de la línea y se rellena lo de en medio.
struct TaperedTraceShape: Shape {
    let points: [CGPoint]
    let startWidth: CGFloat
    let endWidth: CGFloat
    var progress: CGFloat

    // `animatableData` es lo que SwiftUI interpola durante una animación.
    // `nonisolated`: SwiftUI puede pedirlo fuera del hilo principal (Swift 6 lo exige así).
    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        TraceGeometry.taperedOutline(points: points, startWidth: startWidth, endWidth: endWidth, progress: progress)
    }
}

/// Un círculo en la punta del trazo. Vacío al principio y al final del vuelo.
struct TraceHeadShape: Shape {
    let points: [CGPoint]
    let radius: CGFloat
    var progress: CGFloat

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        guard progress > 0, progress < 1, let tip = TraceGeometry.cut(points, at: progress).last else {
            return Path()
        }
        return Path(ellipseIn: CGRect(x: tip.point.x - radius, y: tip.point.y - radius, width: radius * 2, height: radius * 2))
    }
}

/// Geometría del trazo, sin nada de interfaz.
enum TraceGeometry {
    /// Un punto del trazo y su posición en la lista de puntos (con decimales si cae entre dos).
    /// La posición sirve para el grosor: va bajando de forma lineal de un punto al siguiente.
    struct Sample {
        let point: CGPoint
        let index: CGFloat
    }

    /// Los puntos desde la salida hasta la fracción `progress` de la longitud total.
    /// El último punto se interpola para que el trazo avance suave, no a saltos de punto en punto.
    static func cut(_ points: [CGPoint], at progress: CGFloat) -> [Sample] {
        guard points.count >= 2, progress > 0 else { return [] }
        var lengths: [CGFloat] = [0]
        for i in 1..<points.count {
            lengths.append(lengths[i - 1] + distance(points[i - 1], points[i]))
        }
        let target = min(progress, 1) * lengths[lengths.count - 1]
        var samples = [Sample(point: points[0], index: 0)]
        for i in 1..<points.count {
            if lengths[i] < target {
                samples.append(Sample(point: points[i], index: CGFloat(i)))
            } else {
                let segment = lengths[i] - lengths[i - 1]
                let t = segment > 0 ? (target - lengths[i - 1]) / segment : 0
                let point = CGPoint(
                    x: points[i - 1].x + (points[i].x - points[i - 1].x) * t,
                    y: points[i - 1].y + (points[i].y - points[i - 1].y) * t
                )
                samples.append(Sample(point: point, index: CGFloat(i - 1) + t))
                break
            }
        }
        return samples
    }

    /// Contorno de la línea de grosor variable con las puntas redondeadas.
    static func taperedOutline(points: [CGPoint], startWidth: CGFloat, endWidth: CGFloat, progress: CGFloat) -> Path {
        let samples = cut(points, at: progress)
        guard samples.count >= 2 else { return Path() }
        let lastIndex = CGFloat(points.count - 1)

        var left: [CGPoint] = []
        var right: [CGPoint] = []
        var halfWidths: [CGFloat] = []
        var tangents: [CGVector] = []
        for (i, sample) in samples.enumerated() {
            // Dirección de la línea en este punto: de su vecino anterior al siguiente.
            let before = samples[max(i - 1, 0)].point
            let after = samples[min(i + 1, samples.count - 1)].point
            let tangent = unit(CGVector(dx: after.x - before.x, dy: after.y - before.y))
            // La normal es la tangente girada 90°: hacia ella se aparta cada borde.
            let normal = CGVector(dx: -tangent.dy, dy: tangent.dx)
            let half = (startWidth + (endWidth - startWidth) * sample.index / lastIndex) / 2
            left.append(CGPoint(x: sample.point.x + normal.dx * half, y: sample.point.y + normal.dy * half))
            right.append(CGPoint(x: sample.point.x - normal.dx * half, y: sample.point.y - normal.dy * half))
            halfWidths.append(half)
            tangents.append(tangent)
        }

        var path = Path()
        path.move(to: left[0])
        for point in left.dropFirst() { path.addLine(to: point) }
        // Punta final: media vuelta hacia delante, del borde izquierdo al derecho.
        addCap(to: &path, center: samples[samples.count - 1].point, radius: halfWidths[halfWidths.count - 1], tangent: tangents[tangents.count - 1], forward: true)
        for point in right.reversed() { path.addLine(to: point) }
        // Punta inicial: media vuelta hacia atrás, del borde derecho al izquierdo.
        addCap(to: &path, center: samples[0].point, radius: halfWidths[0], tangent: tangents[0], forward: false)
        path.closeSubpath()
        return path
    }

    private static func addCap(to path: inout Path, center: CGPoint, radius: CGFloat, tangent: CGVector, forward: Bool) {
        let normal = CGVector(dx: -tangent.dy, dy: tangent.dx)
        // Hacia delante va de +normal a -normal pasando por +tangente; hacia atrás, al revés.
        let side: CGFloat = forward ? 1 : -1
        let steps = 10
        for step in 1...steps {
            let angle = CGFloat.pi * CGFloat(step) / CGFloat(steps)
            let along = side * sin(angle)
            let across = side * cos(angle)
            path.addLine(to: CGPoint(
                x: center.x + (normal.dx * across + tangent.dx * along) * radius,
                y: center.y + (normal.dy * across + tangent.dy * along) * radius
            ))
        }
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    private static func unit(_ v: CGVector) -> CGVector {
        let length = hypot(v.dx, v.dy)
        return length > 0 ? CGVector(dx: v.dx / length, dy: v.dy / length) : CGVector(dx: 1, dy: 0)
    }
}
