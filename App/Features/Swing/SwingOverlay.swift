import GolfCore
import SwiftUI

/// Cómo se encaja el vídeo en un marco rellenándolo (aspect fill): lo que se sale se recorta.
/// Pasa puntos del vídeo a la vista y al revés, para que las líneas caigan sobre el jugador.
struct FillMapping {
    let scale: CGFloat
    let offset: CGPoint

    init(video: CGSize, view: CGSize) {
        scale = max(view.width / max(video.width, 1), view.height / max(video.height, 1))
        offset = CGPoint(x: (video.width * scale - view.width) / 2, y: (video.height * scale - view.height) / 2)
    }

    func view(_ p: Point2D) -> CGPoint {
        CGPoint(x: CGFloat(p.x) * scale - offset.x, y: CGFloat(p.y) * scale - offset.y)
    }

    func video(_ p: CGPoint) -> Point2D {
        Point2D(Double((p.x + offset.x) / scale), Double((p.y + offset.y) / scale))
    }
}

/// Las líneas del telestrador sobre un fotograma (docs/02, "Gráficos de los vídeos"): esqueleto
/// amarillo con base oscura, círculo de cabeza, línea de cadera, arco del ángulo y el palo.
/// Se dibuja en la pantalla; el vídeo de la etapa 8 usa las mismas medidas en píxeles de vídeo.
struct SwingOverlayView: View {
    let analysis: SwingAnalysis
    let position: SwingPosition
    /// Índice del fotograma del análisis que se está viendo (puede no ser el de la posición).
    let frameIndex: Int
    /// En la mitad de subida y la transición el extremo del palo se puede arrastrar.
    var draggedLineHead: Point2D?

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let mapping = FillMapping(video: CGSize(width: analysis.videoWidth, height: analysis.videoHeight),
                                          view: size)
                // Se dibuja sobre una copia: los métodos de dibujo no cambian el contexto y las
                // funciones anidadas de `draw` no pueden capturar un parámetro inout.
                draw(in: context, mapping: mapping, size: size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(in context: GraphicsContext, mapping: FillMapping, size: CGSize) {
        guard analysis.poses.indices.contains(frameIndex) else { return }
        let pose = analysis.poses[frameIndex]
        let handedness = analysis.handedness
        // Escala de los gráficos: las medidas de docs/02 son para 1080 px de ancho de vídeo.
        let s = mapping.scale * CGFloat(analysis.videoWidth) / 1080

        func stroke(_ points: [Point2D], color: Color, width: CGFloat, dash: [CGFloat] = []) {
            guard points.count >= 2 else { return }
            var path = Path()
            path.addLines(points.map(mapping.view))
            let style = StrokeStyle(lineWidth: width * s, lineCap: .round, lineJoin: .round, dash: dash.map { $0 * s })
            if dash.isEmpty {
                // Base oscura para que la línea se lea sobre cualquier fondo (docs/02).
                context.stroke(path, with: .color(.black.opacity(0.28)), style: StrokeStyle(lineWidth: (width + 8) * s, lineCap: .round, lineJoin: .round))
            }
            context.stroke(path, with: .color(color), style: style)
        }
        func joint(_ p: Point2D) {
            let c = mapping.view(p)
            let outer = Path(ellipseIn: CGRect(x: c.x - 12 * s, y: c.y - 12 * s, width: 24 * s, height: 24 * s))
            context.fill(outer, with: .color(Color.amarillo))
            let inner = Path(ellipseIn: CGRect(x: c.x - 6 * s, y: c.y - 6 * s, width: 12 * s, height: 12 * s))
            context.fill(inner, with: .color(.white))
        }

        // Verticales de referencia discontinuas: la cadera y la cabeza en la preparación.
        let addressPose = analysis.poses[analysis.phases[.address].frameIndex]
        let height = CGFloat(analysis.videoHeight)
        if let hip = addressPose.first(handedness.trailHip, handedness.leadHip) ?? addressPose.joints[.root] {
            let x = hip.x
            stroke([Point2D(x, Double(height) * 0.25), Point2D(x, Double(height) * 0.98)],
                   color: .white.opacity(0.85), width: 5, dash: [5, 14])
        }
        if let head = addressPose.head {
            stroke([Point2D(head.x, max(head.y - 400, 0)), Point2D(head.x, Double(height) * 0.95)],
                   color: .white.opacity(0.85), width: 5, dash: [5, 14])
        }

        // Esqueleto del lado de atrás (el que mejor se ve desde detrás, docs/04).
        if let neck = pose.joints[.neck], let root = pose.joints[.root] {
            var chain = [neck, root]
            if let knee = pose.first(handedness.trailKnee, handedness.leadKnee) {
                chain.append(knee)
                if let ankle = pose.first(handedness.trailAnkle, handedness.leadAnkle) { chain.append(ankle) }
            }
            if let head = pose.head { chain.insert(head, at: 0) }
            stroke(chain, color: Color.amarillo, width: 9)
            for p in chain.dropFirst() { joint(p) }

            // Arco y valor de la inclinación (centro de cadera → cuello frente a la vertical).
            if position == .address || position == .impact {
                let angle = Geometry.angleFromVertical(from: root, to: neck)
                if let angle {
                    let c = mapping.view(root)
                    let radius = 120 * s
                    let spineAngle = atan2(neck.y - root.y, neck.x - root.x)
                    var arc = Path()
                    arc.addArc(center: c, radius: radius, startAngle: .radians(-.pi / 2), endAngle: .radians(spineAngle), clockwise: spineAngle < -.pi / 2)
                    context.stroke(arc, with: .color(Color.amarillo), style: StrokeStyle(lineWidth: 7 * s))
                    let label = context.resolve(Text("\(SpanishFormat.number(angle))°")
                        .font(Typography.fixedFont(for: .displayM, size: 60 * s))
                        .foregroundStyle(Color.amarillo))
                    var labelPoint = CGPoint(x: c.x - radius - 30 * s, y: c.y - radius * 0.5)
                    labelPoint.x = max(labelPoint.x, 60 * s)
                    context.drawLayer { layer in
                        layer.addFilter(.shadow(color: .black.opacity(0.55), radius: 2 * s))
                        layer.draw(label, at: labelPoint, anchor: .trailing)
                    }
                }
            }
        }

        // Círculo de la cabeza, discontinuo (docs/02: radio 85 px).
        if let head = pose.head {
            let c = mapping.view(head)
            let r = 85 * s
            let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            context.stroke(circle, with: .color(Color.amarillo), style: StrokeStyle(lineWidth: 6 * s, dash: [10 * s, 10 * s]))
        }

        // El palo según la posición.
        switch position {
        case .address:
            if let head = analysis.clubHeadAtAddress, let hands = pose.hands {
                stroke([hands, head], color: .white.opacity(0.9), width: 6)
                let c = mapping.view(head)
                context.stroke(Path(ellipseIn: CGRect(x: c.x - 14 * s, y: c.y - 14 * s, width: 28 * s, height: 28 * s)),
                               with: .color(.white), lineWidth: 4 * s)
            }
        case .takeaway:
            if let head = analysis.clubHeadAtTakeaway {
                let c = mapping.view(head)
                context.stroke(Path(ellipseIn: CGRect(x: c.x - 16 * s, y: c.y - 16 * s, width: 32 * s, height: 32 * s)),
                               with: .color(.white), lineWidth: 4 * s)
                context.fill(Path(ellipseIn: CGRect(x: c.x - 4 * s, y: c.y - 4 * s, width: 8 * s, height: 8 * s)),
                             with: .color(Color.rojoTrazo))
            }
        case .midBackswing, .transition:
            let line = position == .midBackswing ? analysis.clubLineAtMidBackswing : analysis.clubLineAtTransition
            if var line {
                if let draggedLineHead { line.head = draggedLineHead }
                stroke([line.grip, line.head], color: .white.opacity(0.9), width: 6)
                let c = mapping.view(line.head)
                // El asa del extremo, como las del tracer: círculo blanco con anillo.
                context.fill(Path(ellipseIn: CGRect(x: c.x - 11 * s, y: c.y - 11 * s, width: 22 * s, height: 22 * s)),
                             with: .color(.white))
                context.stroke(Path(ellipseIn: CGRect(x: c.x - 16 * s, y: c.y - 16 * s, width: 32 * s, height: 32 * s)),
                               with: .color(Color.amarillo), lineWidth: 4 * s)
            }
        default:
            break
        }
    }
}
