import GolfCore
import SwiftUI

/// La onda del sonido (docs/02, "Onda"): barras de 3 pt cada 5 pt en Pino al 28 %, con las de los
/// impactos en rojo. Encima, unas pocas marcas de tiempo repartidas (como mucho 5, a intervalos
/// redondos): no una etiqueta por golpe, que con muchos golpes se pisarían y no se leerían.
struct WaveformView: View {
    /// Alto de cada barra, de 0 a 1.
    let bars: [Double]
    /// Barras en las que hay un impacto (se pintan en rojo).
    var highlighted: Set<Int> = []
    /// Duración del sonido (s), para las marcas de tiempo.
    let duration: Double

    var body: some View {
        // Las marcas y sus textos se preparan fuera del dibujo.
        let ticks = Waveform.timeTicks(duration: duration).map { (time: $0, label: RecordScreen.clock($0)) }
        Canvas { context, size in
            guard !bars.isEmpty else { return }
            let labelSpace: CGFloat = 18
            let step = size.width / CGFloat(bars.count)
            let barWidth = min(3, step * 0.6)
            let middle = labelSpace + (size.height - labelSpace) / 2
            let maxHalf = (size.height - labelSpace) / 2

            for tick in ticks {
                let x = duration > 0 ? size.width * CGFloat(tick.time / duration) : 0
                var line = Path()
                line.move(to: CGPoint(x: x, y: labelSpace - 3))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(Color.linea), lineWidth: 1)
                // La primera marca se alinea por la izquierda para no salirse del panel.
                let text = context.resolve(Text(tick.label).font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.texto3))
                context.draw(text, at: CGPoint(x: x, y: 0), anchor: tick.time == 0 ? .topLeading : .top)
            }
            for (index, value) in bars.enumerated() {
                // Al menos 1,5 pt de alto: el silencio también se ve como una línea.
                let half = max(CGFloat(value) * maxHalf, 1.5)
                let x = step * (CGFloat(index) + 0.5) - barWidth / 2
                let bar = Path(roundedRect: CGRect(x: x, y: middle - half, width: barWidth, height: 2 * half),
                               cornerRadius: barWidth / 2)
                context.fill(bar, with: .color(highlighted.contains(index) ? Color.rojoTrazo : Color.pino.opacity(0.28)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(highlighted.isEmpty ? "Onda del sonido, sin golpes marcados" : "Onda del sonido con los golpes en rojo")
    }
}
