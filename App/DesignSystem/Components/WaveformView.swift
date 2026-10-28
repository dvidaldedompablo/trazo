import SwiftUI

/// La onda del sonido (docs/02, "Onda"): barras de 3 pt cada 5 pt en Pino al 28 %; los impactos en rojo
/// con una línea vertical punteada y su número encima.
struct WaveformView: View {
    /// Alto de cada barra, de 0 a 1.
    let bars: [Double]
    /// Barras donde hay un impacto, con el número que se enseña encima.
    var markers: [(index: Int, label: String)] = []

    var body: some View {
        Canvas { context, size in
            guard !bars.isEmpty else { return }
            let step = size.width / CGFloat(bars.count)
            let barWidth = min(3, step * 0.6)
            let labelSpace: CGFloat = markers.isEmpty ? 0 : 16
            let middle = labelSpace + (size.height - labelSpace) / 2
            let maxHalf = (size.height - labelSpace) / 2
            let marked = Set(markers.map { $0.index })
            for (index, value) in bars.enumerated() {
                // Al menos 1,5 pt de alto: el silencio también se ve como una línea.
                let half = max(CGFloat(value) * maxHalf, 1.5)
                let x = step * (CGFloat(index) + 0.5) - barWidth / 2
                let bar = Path(roundedRect: CGRect(x: x, y: middle - half, width: barWidth, height: 2 * half),
                               cornerRadius: barWidth / 2)
                context.fill(bar, with: .color(marked.contains(index) ? Color.rojoTrazo : Color.pino.opacity(0.28)))
            }
            for marker in markers {
                let x = step * (CGFloat(marker.index) + 0.5)
                var line = Path()
                line.move(to: CGPoint(x: x, y: labelSpace))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(Color.rojoTrazo), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                let text = context.resolve(Text(marker.label).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.pino))
                context.draw(text, at: CGPoint(x: x, y: 6), anchor: .center)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(markers.isEmpty ? "Onda del sonido, sin golpes" : "Onda del sonido con \(markers.count) golpes marcados")
    }
}
