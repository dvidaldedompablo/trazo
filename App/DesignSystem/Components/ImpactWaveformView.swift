import SwiftUI

/// La onda alrededor del impacto (s03, docs/02 "Onda"): barras de 3 pt cada 5 pt en Pino al 28 %; el
/// pico del impacto en rojo con una línea vertical punteada y la etiqueta "Impacto 1,84 s".
/// Se dibuja en las coordenadas de la maqueta (340 x 120) y se escala al ancho disponible.
struct ImpactWaveformView: View {
    /// Alto de cada barra, de 0 a 1.
    let bars: [Double]
    /// Barra del impacto (se pinta en rojo con sus dos vecinas).
    let impactBar: Int?
    /// Texto de la etiqueta ("Impacto 1,84 s").
    let label: String?

    static let size = CGSize(width: 340, height: 120)

    var body: some View {
        let font = Font.system(size: 11.5, weight: .bold)
        Canvas { context, size in
            let scale = size.width / Self.size.width
            context.scaleBy(x: scale, y: scale)
            let middle = Self.size.height / 2
            for (index, value) in bars.enumerated() {
                let isImpact = impactBar.map { abs(index - $0) <= 1 } ?? false
                // Entre 6 y 100 de alto: el silencio también se ve y el golpe casi llena el panel.
                let height = max(6, min(100, CGFloat(value) * 100))
                let rect = CGRect(x: 14 + CGFloat(index) * 5, y: middle - height / 2, width: 3, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5),
                             with: .color(isImpact ? Color.rojoTrazo : Color.pino.opacity(0.28)))
            }
            guard let impactBar else { return }
            let x = 14 + CGFloat(impactBar) * 5 + 1.5
            var line = Path()
            line.move(to: CGPoint(x: x, y: 6))
            line.addLine(to: CGPoint(x: x, y: 114))
            context.stroke(line, with: .color(Color.rojoTrazo), style: StrokeStyle(lineWidth: 1.2, dash: [2, 3]))
            guard let label else { return }
            // Etiqueta a la derecha de la línea; si no cabe, a la izquierda.
            let text = context.resolve(Text(label).font(font).foregroundStyle(.white))
            let textSize = text.measure(in: Self.size)
            let pillWidth = max(98, textSize.width + 22)
            let pillX = x + 9.5 + pillWidth <= Self.size.width ? x + 9.5 : x - 9.5 - pillWidth
            let pill = CGRect(x: pillX, y: 6, width: pillWidth, height: 24)
            context.fill(Path(roundedRect: pill, cornerRadius: 12), with: .color(Color.rojoTrazo))
            context.draw(text, at: CGPoint(x: pill.midX, y: pill.midY), anchor: .center)
        }
        .aspectRatio(Self.size.width / Self.size.height, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.map { "Onda del sonido. \($0)" } ?? "Onda del sonido")
    }
}
