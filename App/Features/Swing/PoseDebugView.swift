import GolfCore
import SwiftUI
import UIKit

/// El esqueleto completo de una pose (modo diagnóstico): todas las articulaciones que Vision dio
/// con confianza suficiente, unidas por sus huesos. Sirve para ver de un vistazo si el detector
/// está viendo al jugador y dónde.
struct SkeletonView: View {
    let pose: PoseFrame
    let videoSize: CGSize
    /// `true` si el vídeo llena el marco recortando (aspect fill); `false` si va encajado (aspect fit).
    var fill: Bool

    private static let bones: [(GolfCore.Joint, GolfCore.Joint)] = [
        (.nose, .neck), (.neck, .root),
        (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.root, .leftHip), (.root, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    var body: some View {
        Canvas { context, size in
            let scale = fill
                ? max(size.width / videoSize.width, size.height / videoSize.height)
                : min(size.width / videoSize.width, size.height / videoSize.height)
            let offset = CGPoint(x: (size.width - videoSize.width * scale) / 2, y: (size.height - videoSize.height * scale) / 2)
            func view(_ p: Point2D) -> CGPoint { CGPoint(x: offset.x + CGFloat(p.x) * scale, y: offset.y + CGFloat(p.y) * scale) }
            for (a, b) in Self.bones {
                guard let pa = pose.joints[a], let pb = pose.joints[b] else { continue }
                var path = Path()
                path.move(to: view(pa))
                path.addLine(to: view(pb))
                context.stroke(path, with: .color(DiagnosticColors.vision), lineWidth: 2.5)
            }
            for point in pose.joints.values {
                let c = view(point)
                context.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)), with: .color(.white))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Visor de la pose detectada fotograma a fotograma (modo diagnóstico, cuando el análisis falla):
/// el fotograma, el esqueleto encima y la línea del registro de ese fotograma.
struct PoseDebugView: View {
    let debug: PoseDebug
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: Spacing.m) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 17, weight: .regular)) }
                    .buttonStyle(.crystal)
                    .accessibilityLabel("Cerrar")
                Spacer()
                Chip(title: "Pose detectada", systemImage: "figure.stand", surface: .video)
                Spacer()
                Color.clear.frame(width: Size.glassButton, height: Size.glassButton)
            }
            .padding(.horizontal, Spacing.cardMargin)
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                }
                if debug.frames.indices.contains(index) {
                    SkeletonView(pose: debug.frames[index],
                                 videoSize: CGSize(width: debug.videoWidth, height: debug.videoHeight), fill: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(logLine)
                .font(.lato(11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.cardMargin)
            if debug.frames.count > 1 {
                Slider(value: Binding(get: { Double(index) }, set: { index = Int($0.rounded()) }),
                       in: 0...Double(debug.frames.count - 1), step: 1)
                    .tint(.white)
                    .padding(.horizontal, Spacing.cardMargin)
            }
            ShareLink(item: debug.text, preview: SharePreview("Registro del análisis")) {
                Label("Compartir el registro", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(CrystalButtonStyle(outline: .capsule))
            .padding(.bottom, Spacing.l)
        }
        .padding(.top, Spacing.s)
        .background(Color.escenario)
        .preferredColorScheme(.dark)
        .task(id: index) { await loadFrame() }
    }

    /// La línea del registro de este fotograma (las primeras líneas son de vídeo y sonido).
    private var logLine: String {
        guard debug.frames.indices.contains(index) else { return "" }
        let prefix = String(format: "%7.3f s", debug.frames[index].time)
        return debug.lines.first { $0.hasPrefix(prefix) } ?? prefix
    }

    private func loadFrame() async {
        guard debug.frames.indices.contains(index) else { return }
        if let data = try? await FrameGrabber.jpeg(from: url, at: debug.frames[index].time,
                                                   maximumSize: CGSize(width: 720, height: 1280)) {
            image = UIImage(data: data)
        }
    }
}
