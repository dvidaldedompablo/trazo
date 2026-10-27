import SwiftUI

/// Vista previa en vivo del Tracer: la ventana de la tarjeta en Inicio.
/// Enseña el trazo con el color elegido y, si la distancia está activada, la etiqueta del palo.
/// Se dibuja en las coordenadas de la maqueta (358 x 180) y se escala al ancho de la tarjeta.
struct TracerPreview: View {
    let color: Color
    let colorName: String
    let showsDistance: Bool
    let club: String
    /// Parte del vuelo ya dibujada, de 0 a 1.
    var progress: CGFloat = 1
    /// La bola ya ha caído: se ven el punto de caída y, si toca, la etiqueta.
    var hasLanded = true
    /// Cifra de la etiqueta. En la animación de arranque cuenta desde 0.
    var distance: Double
    var unit = "m"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScaledToWidth(size: PreviewScene.size) {
            ZStack(alignment: .topLeading) {
                PreviewScenery()
                TracerStroke(points: PreviewScene.flight, color: color, progress: progress)
                    // Al cambiar de color, el trazo funde del color anterior al nuevo en 0,2 s.
                    .animation(.easeInOut(duration: 0.2), value: color)
                LandingMarker()
                    .opacity(hasLanded ? 1 : 0)
                // La etiqueta ya existe (invisible) antes de que caiga la bola: así, al caer,
                // SwiftUI puede animar la cifra desde 0. El interruptor la quita y la pone.
                if showsDistance {
                    DistanceLabel(club: club, distance: distance, unit: unit)
                        .scaleEffect(hasLanded || reduceMotion ? 1 : 0.5, anchor: landingAnchor)
                        .opacity(hasLanded ? 1 : 0)
                        .transition(labelTransition)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vista previa del trazo")
        .accessibilityValue(accessibilityDescription)
    }

    /// La etiqueta crece desde el punto de caída y aparece con un fundido.
    /// Con "Reducir movimiento" solo funde, sin cambiar de tamaño.
    private var labelTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.5, anchor: landingAnchor).combined(with: .opacity)
    }

    /// El punto de caída en proporción a la ventana (0 a 1), para crecer desde ahí.
    private var landingAnchor: UnitPoint {
        UnitPoint(
            x: PreviewScene.landing.x / PreviewScene.size.width,
            y: PreviewScene.landing.y / PreviewScene.size.height
        )
    }

    private var accessibilityDescription: String {
        showsDistance ? "\(colorName), con la distancia: \(club), \(Int(distance)) \(unit)" : "\(colorName), sin distancia"
    }
}

/// Dibuja un contenido de tamaño fijo y lo escala para llenar el ancho disponible sin deformarlo.
/// En el iPhone 17e la tarjeta mide justo 358 pt y la escala es 1.
struct ScaledToWidth<Content: View>: View {
    let size: CGSize
    @ViewBuilder var content: Content

    var body: some View {
        Color.clear
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    content
                        .frame(width: size.width, height: size.height, alignment: .topLeading)
                        .scaleEffect(proxy.size.width / size.width, anchor: .topLeading)
                }
            }
            // Lo que se sale de la ventana (como el halo del trazo junto al borde) se corta.
            .clipped()
    }
}

/// El paisaje fijo: cielo, sol, arboleda, calle con franjas de corte y carteles de distancia.
/// Un `Canvas` dibuja todo de una vez, como el `<svg>` de la maqueta.
private struct PreviewScenery: View {
    var body: some View {
        // Las fuentes se crean fuera del dibujo: Typography vive en el hilo principal.
        let boardFonts = PreviewScene.boards.map { Typography.fixedFont(for: .displayM, size: $0.fontSize) }
        Canvas { context, _ in
            SceneryPainter.draw(in: &context, boardFonts: boardFonts)
        }
        .frame(width: PreviewScene.size.width, height: PreviewScene.size.height)
    }
}

/// Las instrucciones de dibujo del paisaje, en el orden de la maqueta (lo de atrás primero).
/// @MainActor porque crea textos de SwiftUI; el Canvas dibuja en el hilo principal.
@MainActor
private enum SceneryPainter {
    static func draw(in context: inout GraphicsContext, boardFonts: [Font]) {
        let width = PreviewScene.size.width
        let height = PreviewScene.size.height

        // Cielo: degradado de azul a casi blanco en el horizonte.
        context.fill(
            Path(CGRect(x: 0, y: 0, width: width, height: PreviewScene.skyBottom)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: SceneColors.skyTop, location: 0),
                    .init(color: SceneColors.skyMiddle, location: 0.62),
                    .init(color: SceneColors.skyHorizon, location: 1),
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: PreviewScene.skyBottom)
            )
        )

        // Sol: un resplandor circular que se desvanece hacia fuera.
        let sun = PreviewScene.sunCenter
        let radius = PreviewScene.sunRadius
        context.fill(
            Path(ellipseIn: CGRect(x: sun.x - radius, y: sun.y - radius, width: radius * 2, height: radius * 2)),
            with: .radialGradient(
                Gradient(colors: [SceneColors.sun.opacity(0.9), SceneColors.sun.opacity(0)]),
                center: sun, startRadius: 0, endRadius: radius
            )
        )

        // Arboleda: la fila de atrás, más clara, y la de delante.
        context.fill(treePath(PreviewScene.backTrees), with: .color(SceneColors.treesBack))
        context.fill(treePath(PreviewScene.frontTrees), with: .color(SceneColors.treesFront))

        // Calle.
        let grassTop = PreviewScene.grassTop
        context.fill(
            Path(CGRect(x: 0, y: grassTop, width: width, height: height - grassTop)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: SceneColors.grassTop, location: 0),
                    .init(color: SceneColors.grassMiddle, location: 0.35),
                    .init(color: SceneColors.grassBottom, location: 1),
                ]),
                startPoint: CGPoint(x: 0, y: grassTop),
                endPoint: CGPoint(x: 0, y: height)
            )
        )

        // Franjas de corte: triángulos muy claros que salen del punto de fuga.
        for start in PreviewScene.stripeStarts {
            var stripe = Path()
            stripe.move(to: PreviewScene.stripesVanishingPoint)
            stripe.addLine(to: CGPoint(x: start, y: height))
            stripe.addLine(to: CGPoint(x: start + PreviewScene.stripeWidth, y: height))
            stripe.closeSubpath()
            context.fill(stripe, with: .color(.white.opacity(0.07)))
        }

        // Carteles de distancia con su poste.
        for (board, font) in zip(PreviewScene.boards, boardFonts) {
            var post = Path()
            post.move(to: CGPoint(x: board.frame.midX, y: board.frame.maxY))
            post.addLine(to: CGPoint(x: board.frame.midX, y: board.postBottom))
            context.stroke(post, with: .color(SceneColors.boardPost), lineWidth: board.postWidth)
            context.fill(Path(roundedRect: board.frame, cornerRadius: board.cornerRadius), with: .color(SceneColors.board))

            // El texto se coloca por su línea base, como en el SVG.
            let text = context.resolve(Text(board.text).font(font).foregroundStyle(Color.pino))
            let size = text.measure(in: CGSize(width: width, height: height))
            let baseline = text.firstBaseline(in: size)
            context.draw(text, in: CGRect(
                x: board.frame.midX - size.width / 2,
                y: board.baseline - baseline,
                width: size.width,
                height: size.height
            ))
        }
    }

    /// Una fila de árboles: cada copa es una curva cuadrática.
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

/// Punto de caída: punto blanco y un anillo fino.
private struct LandingMarker: View {
    var body: some View {
        let landing = PreviewScene.landing
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(Color.white)
                .frame(width: PreviewScene.landingDotRadius * 2, height: PreviewScene.landingDotRadius * 2)
                .position(landing)
            Circle()
                .stroke(Color.white.opacity(0.7), lineWidth: PreviewScene.hairline)
                .frame(width: PreviewScene.landingRingRadius * 2, height: PreviewScene.landingRingRadius * 2)
                .position(landing)
        }
        .frame(width: PreviewScene.size.width, height: PreviewScene.size.height)
    }
}

/// Etiqueta de palo y distancia con la línea fina hasta la caída.
/// Ocupa toda la ventana para que la animación pueda crecer desde el punto de caída.
private struct DistanceLabel: View {
    let club: String
    let distance: Double
    let unit: String

    var body: some View {
        let label = PreviewScene.label
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: PreviewScene.landing)
                path.addLine(to: PreviewScene.leaderEnd)
            }
            .stroke(Color.white.opacity(0.85), lineWidth: PreviewScene.hairline)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: PreviewScene.labelCornerRadius, style: .continuous)
                    .fill(Color.pino.opacity(0.88))
                    .frame(width: label.width, height: label.height)
                Text(club)
                    .font(Typography.fixedFont(for: .chip, size: PreviewScene.labelClubFontSize))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .placedAt(baseline: PreviewScene.labelClubBaseline, leading: PreviewScene.labelPadding)
                CountingDistanceText(
                    value: distance,
                    unit: unit,
                    font: Typography.fixedFont(for: .displayM, size: PreviewScene.labelDistanceFontSize)
                )
                .foregroundStyle(Color.white)
                .placedAt(baseline: PreviewScene.labelDistanceBaseline, leading: PreviewScene.labelPadding)
            }
            .offset(x: label.minX, y: label.minY)
        }
        .frame(width: PreviewScene.size.width, height: PreviewScene.size.height, alignment: .topLeading)
    }
}

/// La distancia como número entero que cuenta al animarse ("0 m" … "150 m").
/// `Animatable`: durante una animación SwiftUI pasa por todos los valores intermedios de `value`
/// y la vista se redibuja con cada uno.
struct CountingDistanceText: View, Animatable {
    var value: Double
    let unit: String
    let font: Font

    nonisolated var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(verbatim: "\(Int(value.rounded())) \(unit)")
            .font(font)
            .monospacedDigit()
    }
}

private extension View {
    /// Coloca un texto por su línea base y su borde izquierdo dentro de un `ZStack(alignment: .topLeading)`.
    /// Las guías de alineación dicen qué punto de la vista se alinea con la esquina del ZStack.
    func placedAt(baseline: CGFloat, leading: CGFloat) -> some View {
        alignmentGuide(.top) { $0[.firstTextBaseline] - baseline }
            .alignmentGuide(.leading) { $0[.leading] - leading }
    }
}
