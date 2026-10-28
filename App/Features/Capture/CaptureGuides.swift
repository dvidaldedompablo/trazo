import GolfCore
import SwiftUI

// Guías de la pantalla Grabar (s02), con las medidas de `design/maqueta.html`.
// Todo se coloca en el sistema de la maqueta (pantalla de 390 x 844 puntos) y se escala al ancho
// del iPhone con `DesignSpace`: en el iPhone 17e la escala es 1.

/// Coloca su contenido en coordenadas de la maqueta (390 x 844) y lo escala al ancho de la pantalla.
struct DesignSpace<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            content
                .frame(width: CaptureScene.size.width, height: CaptureScene.size.height, alignment: .topLeading)
                .scaleEffect(proxy.size.width / CaptureScene.size.width, anchor: .topLeading)
        }
    }
}

/// La silueta fantasma del golfista en la preparación, de perfil (vista desde detrás, mirando a la bola).
/// Son trazos gruesos con puntas redondas, como en la maqueta.
private enum GhostFigure {
    /// Pierna de atrás (más oscura) y cuerpo, en coordenadas de pantalla de la maqueta.
    static func draw(in context: inout GraphicsContext) {
        let dark = GraphicsContext.Shading.color(SceneColors.figureBack)
        let light = GraphicsContext.Shading.color(.white)
        stroke(&context, [P(176, 538), P(194, 606), P(184, 680)], dark, 22)
        stroke(&context, [P(184, 680), P(207, 690)], dark, 11)
        stroke(&context, [P(184, 536), P(206, 602), P(196, 678)], light, 25)
        stroke(&context, [P(196, 678), P(222, 688)], light, 12)
        stroke(&context, [P(179, 526), P(232, 452)], light, 44)
        context.fill(Circle().path(in: CGRect(x: 155, y: 507, width: 46, height: 46)), with: light)
        stroke(&context, [P(232, 456), P(241, 504), P(247, 556)], light, 13)
        context.fill(Circle().path(in: CGRect(x: 229, y: 397, width: 38, height: 38)), with: light)
        // Visera de la gorra: elipse girada 18°.
        var brim = context
        brim.translateBy(x: 261, y: 407)
        brim.rotate(by: .degrees(18))
        brim.fill(Ellipse().path(in: CGRect(x: -11, y: -3.6, width: 22, height: 7.2)), with: light)
    }

    private static func stroke(_ context: inout GraphicsContext, _ points: [CGPoint],
                               _ shading: GraphicsContext.Shading, _ width: CGFloat) {
        var path = Path()
        path.addLines(points)
        context.stroke(path, with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}

/// Guías del modo Tracer: "Tú aquí", la línea del golpe hacia el objetivo y "Bola aquí".
struct TracerGuides: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            // La opacidad del 30 % va sobre la figura entera (como el grupo del SVG):
            // donde se solapan dos trazos no se ve más claro.
            Canvas { context, _ in GhostFigure.draw(in: &context) }
                .opacity(0.3)
            Canvas { context, _ in
                var line = Path()
                line.move(to: CaptureScene.ball)
                line.addLine(to: P(206, 270))
                context.stroke(line, with: .color(Color.rojoTrazo.opacity(0.9)),
                               style: StrokeStyle(lineWidth: 2, dash: [6, 7]))
                let ring = CGRect(x: CaptureScene.ball.x - 16, y: CaptureScene.ball.y - 16, width: 32, height: 32)
                context.stroke(Circle().path(in: ring), with: .color(.white), style: StrokeStyle(lineWidth: 2, dash: [3, 4]))
            }
            GuideLabel(text: "Tú aquí").offset(x: 150, y: 396)
            GuideLabel(text: "Bola aquí").offset(x: 296, y: 692)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Guía: ponte en la silueta y deja la bola en el círculo, con la línea del golpe hacia el objetivo.")
    }
}

/// Guías del modo Swing: la silueta de perfil, algo más pequeña (el móvil va a 3 o 4 m) y con
/// la línea del palo hasta la bola, para que entren el cuerpo entero y el palo.
struct SwingGuides: View {
    /// La silueta del Tracer reducida al 90 % alrededor de los pies y algo más a la izquierda.
    private static let transform = CGAffineTransform(translationX: 190, y: 700)
        .scaledBy(x: 0.9, y: 0.9)
        .translatedBy(x: -200, y: -690)
    private static let hands = P(247, 556).applying(transform)
    private static let ball = P(300, 688).applying(transform)

    var body: some View {
        // Copias locales: el dibujo del Canvas no lee propiedades de la vista.
        let transform = Self.transform
        let hands = Self.hands
        let ball = Self.ball
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                context.concatenate(transform)
                GhostFigure.draw(in: &context)
            }
            .opacity(0.3)
            Canvas { context, _ in
                var club = Path()
                club.move(to: hands)
                club.addLine(to: ball)
                context.stroke(club, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 2, dash: [6, 7]))
                let ring = CGRect(x: ball.x - 12, y: ball.y - 12, width: 24, height: 24)
                context.stroke(Circle().path(in: ring), with: .color(.white), style: StrokeStyle(lineWidth: 2, dash: [3, 4]))
            }
            GuideLabel(text: "Tú aquí, de perfil").offset(x: 128, y: 418)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Guía: ponte de perfil en la silueta, con el cuerpo entero y el palo dentro.")
    }
}

/// Rótulo de las guías: blanco, en negrita y con sombra para leerse sobre cualquier fondo.
private struct GuideLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1)
            .fixedSize()
    }
}

/// Nivel de la cámara: dos rayas que se mantienen horizontales con el mundo y un círculo.
/// Si el móvil está recto, el círculo se pone verde y aparece "Nivelado".
struct LevelIndicator: View {
    /// Giro del móvil en grados (positivo = la parte de arriba hacia la derecha).
    let roll: Double
    let isLevel: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                HStack(spacing: 28) {
                    Capsule().frame(width: 32, height: 2)
                    Capsule().frame(width: 32, height: 2)
                }
                .foregroundStyle(.white)
                // Las rayas giran al revés que el móvil: así marcan el horizonte de verdad.
                .rotationEffect(.degrees(-roll))
                Circle()
                    .stroke(isLevel ? Color.nivelado : .white, lineWidth: 2)
                    .frame(width: 10, height: 10)
            }
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            .position(x: 195, y: 300)
            if isLevel {
                Text("Nivelado")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Color.nivelado)
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                    .frame(width: CaptureScene.size.width)
                    .offset(y: 312)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLevel ? "Móvil nivelado" : "Móvil inclinado \(Int(abs(roll).rounded())) grados")
    }
}

/// Fondo de demostración (sin cámara): el campo de prácticas de s02.
struct DemoCameraBackground: View {
    /// En modo Swing la bola va a los pies de la silueta: la del Tracer sobraría.
    var showsBall = true

    var body: some View {
        // Los carteles usan Archivo; las fuentes se preparan aquí, fuera del dibujo.
        let fonts = CaptureScene.boards.map { board in
            Typography.fixedFont(for: TypeStyle(family: .archivo(width: 70, weight: 800), size: board.fontSize))
        }
        Canvas { context, size in
            // Por debajo de la maqueta (pantallas más altas) sigue la hierba.
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(SceneColors.grassBottom))
            CaptureScenePainter.draw(in: &context, boardFonts: fonts, showsBall: showsBall)
        }
    }
}

/// Dibuja el campo de s02 con las coordenadas de `CaptureScene`.
private enum CaptureScenePainter {
    static func draw(in context: inout GraphicsContext, boardFonts: [Font], showsBall: Bool) {
        let width = CaptureScene.size.width
        // Cielo con el sol arriba a la derecha.
        let sky = CGRect(x: 0, y: CaptureScene.skyTop, width: width, height: CaptureScene.skyBottom - CaptureScene.skyTop)
        context.fill(Path(sky), with: .linearGradient(
            Gradient(stops: [.init(color: SceneColors.skyTop, location: 0),
                             .init(color: SceneColors.skyMiddle, location: 0.62),
                             .init(color: SceneColors.skyHorizon, location: 1)]),
            startPoint: CGPoint(x: 0, y: sky.minY), endPoint: CGPoint(x: 0, y: sky.maxY)))
        let sun = CGRect(x: CaptureScene.sunCenter.x - CaptureScene.sunRadius, y: CaptureScene.sunCenter.y - CaptureScene.sunRadius,
                         width: 2 * CaptureScene.sunRadius, height: 2 * CaptureScene.sunRadius)
        context.fill(Circle().path(in: sun), with: .radialGradient(
            Gradient(colors: [SceneColors.sun.opacity(0.9), SceneColors.sun.opacity(0)]),
            center: CaptureScene.sunCenter, startRadius: 0, endRadius: CaptureScene.sunRadius))

        // Arboleda: dos filas, la de atrás más clara.
        context.fill(treePath(CaptureScene.backTrees), with: .color(SceneColors.treesBack))
        context.fill(treePath(CaptureScene.frontTrees), with: .color(SceneColors.treesFront))

        // Calle con su degradado y las franjas de corte que salen del punto de fuga.
        let grass = CGRect(x: 0, y: CaptureScene.grassTop, width: width, height: CaptureScene.grassBottom - CaptureScene.grassTop)
        context.fill(Path(grass), with: .linearGradient(
            Gradient(stops: [.init(color: SceneColors.grassTop, location: 0),
                             .init(color: SceneColors.grassMiddle, location: 0.35),
                             .init(color: SceneColors.grassBottom, location: 1)]),
            startPoint: CGPoint(x: 0, y: grass.minY), endPoint: CGPoint(x: 0, y: grass.maxY)))
        for start in CaptureScene.stripeStarts {
            var stripe = Path()
            stripe.move(to: CaptureScene.stripesVanishingPoint)
            stripe.addLine(to: CGPoint(x: start, y: grass.maxY))
            stripe.addLine(to: CGPoint(x: start + CaptureScene.stripeWidth, y: grass.maxY))
            stripe.closeSubpath()
            context.fill(stripe, with: .color(.white.opacity(0.07)))
        }

        // Carteles de distancia con su poste; el texto se coloca por su línea base, como en el SVG.
        for (board, font) in zip(CaptureScene.boards, boardFonts) {
            var post = Path()
            post.move(to: CGPoint(x: board.frame.midX, y: board.frame.maxY))
            post.addLine(to: CGPoint(x: board.frame.midX, y: board.postBottom))
            context.stroke(post, with: .color(SceneColors.boardPost), lineWidth: board.postWidth)
            context.fill(Path(roundedRect: board.frame, cornerRadius: board.cornerRadius), with: .color(SceneColors.board))
            let text = context.resolve(Text(board.text).font(font).foregroundStyle(Color.pino))
            let size = text.measure(in: CGSize(width: width, height: 100))
            context.draw(text, in: CGRect(x: board.frame.midX - size.width / 2, y: board.baseline - text.firstBaseline(in: size),
                                          width: size.width, height: size.height))
        }

        // Alfombra de la zona de golpeo y la bola con su sombra.
        var tee = Path()
        tee.addLines(CaptureScene.teeBox)
        tee.closeSubpath()
        context.fill(tee, with: .color(SceneColors.teeBox))
        context.stroke(tee, with: .color(SceneColors.teeBoxEdge.opacity(0.35)), lineWidth: 1.2)
        guard showsBall else { return }
        context.fill(Ellipse().path(in: CaptureScene.ballShadow), with: .color(.black.opacity(0.25)))
        let r = CaptureScene.ballRadius
        context.fill(Circle().path(in: CGRect(x: CaptureScene.ball.x - r, y: CaptureScene.ball.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(SceneColors.ball))
        let h = CaptureScene.ballHighlight
        context.fill(Circle().path(in: CGRect(x: h.x - 1.6, y: h.y - 1.6, width: 3.2, height: 3.2)), with: .color(.white))
    }

    private static func treePath(_ line: TreeLine) -> Path {
        var path = Path()
        path.move(to: line.start)
        path.addLine(to: line.firstBase)
        for i in stride(from: 0, to: line.crowns.count - 1, by: 2) {
            path.addQuadCurve(to: line.crowns[i + 1], control: line.crowns[i])
        }
        path.addLine(to: line.end)
        path.closeSubpath()
        return path
    }
}

/// Sombreados de la maqueta sobre la imagen de la cámara, para que se lean los controles:
/// oscuro arriba (hasta el 22 % de la altura) y abajo (desde el 55 %).
struct CaptureShade: View {
    var body: some View {
        ZStack {
            LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0), .init(color: .black.opacity(0), location: 0.22)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [.init(color: .black.opacity(0), location: 0.55), .init(color: .black.opacity(0.55), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
    }
}

private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: y)
}
