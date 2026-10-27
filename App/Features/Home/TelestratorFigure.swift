import SwiftUI

/// La figura de la tarjeta de Análisis: un golfista en la preparación con las líneas del telestrador
/// (columna, ángulo de 30°, pierna, articulaciones y círculo de la cabeza), como en `design/maqueta.html`.
/// Se dibuja en las coordenadas del SVG de la maqueta (un recorte de 270 x 380 que empieza en 96, 440)
/// y se escala al tamaño de la vista.
struct TelestratorFigure: View {
    var body: some View {
        // La fuente se crea fuera del dibujo: Typography vive en el hilo principal.
        let angleFont = Typography.fixedFont(for: .displayM, size: FigureDrawing.angleFontSize)
        Canvas { context, size in
            FigureDrawing.draw(in: &context, size: size, angleFont: angleFont)
        }
        .accessibilityHidden(true)
    }
}

@MainActor
private enum FigureDrawing {
    static let viewBox = CGRect(x: 96, y: 440, width: 270, height: 380)
    static let angleFontSize: CGFloat = 22

    static func draw(in context: inout GraphicsContext, size: CGSize, angleFont: Font) {
        // Escala sin deformar y centra, como hace un SVG por defecto.
        let scale = min(size.width / viewBox.width, size.height / viewBox.height)
        context.translateBy(x: (size.width - viewBox.width * scale) / 2, y: (size.height - viewBox.height * scale) / 2)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -viewBox.minX, y: -viewBox.minY)

        drawBody(in: &context)
        drawTelestrator(in: &context, angleFont: angleFont)
    }

    /// La silueta: pierna de atrás más oscura, pierna de delante, tronco, brazos, cabeza, gorra y palo.
    private static func drawBody(in context: inout GraphicsContext) {
        func stroke(_ points: [CGPoint], _ color: Color, _ width: CGFloat) {
            context.stroke(polyline(points), with: .color(color),
                           style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        stroke([P(176, 648), P(194, 716), P(184, 790)], SceneColors.figureBack, 22)
        stroke([P(184, 790), P(207, 800)], SceneColors.figureBack, 11)
        stroke([P(184, 646), P(206, 712), P(196, 788)], SceneColors.figure, 25)
        stroke([P(196, 788), P(222, 798)], SceneColors.figure, 12)
        stroke([P(179, 636), P(232, 562)], SceneColors.figure, 44)
        context.fill(circle(P(178, 640), 23), with: .color(SceneColors.figure))
        stroke([P(232, 566), P(241, 614), P(247, 666)], SceneColors.figure, 13)
        context.fill(circle(P(248, 526), 19), with: .color(SceneColors.figure))
        // Visera de la gorra: una elipse girada 18°.
        let visor = Path(ellipseIn: CGRect(x: 250, y: 513.4, width: 22, height: 7.2))
            .applying(rotation(degrees: 18, around: P(261, 517)))
        context.fill(visor, with: .color(SceneColors.figure))
        stroke([P(247, 666), P(318, 776)], SceneColors.clubShaft, 3.2)
        let clubHead = Path(roundedRect: CGRect(x: 311, y: 773, width: 15, height: 6), cornerRadius: 2.5)
            .applying(rotation(degrees: 8, around: P(318, 776)))
        context.fill(clubHead, with: .color(SceneColors.clubHead))
    }

    /// Las líneas amarillas. Cada una lleva debajo una línea negra translúcida más gruesa
    /// para que se lea sobre cualquier fondo (igual que en los vídeos del análisis).
    private static func drawTelestrator(in context: inout GraphicsContext, angleFont: Font) {
        let shadow = Color.escenario.opacity(0.28)
        let hip = P(182, 640)

        // Vertical de referencia, discontinua.
        let vertical = polyline([hip, P(182, 530)])
        context.stroke(vertical, with: .color(shadow), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, dash: [3, 5]))
        context.stroke(vertical, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))

        // Columna: de la cadera al cuello.
        let spine = polyline([hip, P(244.54, 531.44)])
        context.stroke(spine, with: .color(shadow), style: StrokeStyle(lineWidth: 6.4, lineCap: .round))
        context.stroke(spine, with: .color(.amarillo), style: StrokeStyle(lineWidth: 3.4, lineCap: .round))

        // Arco del ángulo entre la vertical y la columna (de -90° a -60°, centrado en la cadera).
        var arc = Path()
        arc.addRelativeArc(center: hip, radius: 52, startAngle: .degrees(-90), delta: .degrees(30))
        context.stroke(arc, with: .color(.amarillo), lineWidth: 2.4)

        // "30°" con un contorno oscuro: el texto en negro un poco desplazado en ocho direcciones,
        // todo en una capa al 35 %, y encima el texto amarillo.
        let label = Text(verbatim: "30°").font(angleFont)
        let baselineLeft = P(138, 582)
        context.drawLayer { layer in
            layer.opacity = 0.35
            let dark = layer.resolve(label.foregroundStyle(Color.escenario))
            for step in 0..<8 {
                let angle = Double(step) * .pi / 4
                drawText(dark, in: &layer, baselineLeft: P(baselineLeft.x + 1.5 * cos(angle), baselineLeft.y + 1.5 * sin(angle)))
            }
        }
        drawText(context.resolve(label.foregroundStyle(Color.amarillo)), in: &context, baselineLeft: baselineLeft)

        // Pierna de delante.
        let leg = polyline([hip, P(206, 712), P(196, 788)])
        context.stroke(leg, with: .color(shadow), style: StrokeStyle(lineWidth: 6, lineJoin: .round))
        context.stroke(leg, with: .color(.amarillo), style: StrokeStyle(lineWidth: 3, lineJoin: .round))

        // Articulaciones: cadera, rodilla, tobillo y hombro.
        for joint in [hip, P(206, 712), P(196, 788), P(235, 548)] {
            context.fill(circle(joint, 5.8), with: .color(Color.escenario.opacity(0.25)))
            context.fill(circle(joint, 4.2), with: .color(.white))
            context.stroke(circle(joint, 4.2), with: .color(.amarillo), lineWidth: 2.2)
        }

        // Círculo de la cabeza, discontinuo.
        let head = circle(P(248, 526), 31)
        context.stroke(head, with: .color(Color.escenario.opacity(0.25)), style: StrokeStyle(lineWidth: 5, dash: [6, 6]))
        context.stroke(head, with: .color(.amarillo), style: StrokeStyle(lineWidth: 2.4, dash: [6, 6]))
    }

    /// Dibuja un texto con su línea base empezando en `baselineLeft`, como `<text x y>` en SVG.
    private static func drawText(_ text: GraphicsContext.ResolvedText, in context: inout GraphicsContext, baselineLeft: CGPoint) {
        let size = text.measure(in: CGSize(width: 200, height: 100))
        let baseline = text.firstBaseline(in: size)
        context.draw(text, in: CGRect(x: baselineLeft.x, y: baselineLeft.y - baseline, width: size.width, height: size.height))
    }

    private static func polyline(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        return path
    }

    private static func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    /// Giro alrededor de un punto: llevar el punto al origen, girar y devolverlo a su sitio.
    private static func rotation(degrees: CGFloat, around center: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -center.x, y: -center.y)
    }

    private static func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x, y: y)
    }
}
