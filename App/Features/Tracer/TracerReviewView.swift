@preconcurrency import AVFoundation
import GolfCore
import SwiftData
import SwiftUI
import UIKit

/// Ajusta el vuelo, versión provisional (etapa 4): el vídeo con la curva propuesta y, si la app perdió
/// la bola, "Perdí la bola a los X s" y el vídeo en ese fotograma. Las asas, la forma y el vídeo final
/// llegan en la etapa 5.
///
/// En modo diagnóstico pinta encima lo que encontró cada detector (Vision en cian, BlobTracker en magenta,
/// toques en blanco con anillo, descartados en gris y la curva ajustada en blanco discontinuo), los datos
/// del análisis y "Tocar la bola" para probar el toque de refuerzo (docs/03, paso 4 bis).
struct TracerReviewView: View {
    let clipID: UUID
    /// Capturas del CI: el análisis y la imagen de demostración, sin vídeo.
    var demo: (analysis: TracerAnalysis, image: UIImage?)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.diagnostics) private var diagnostics = false
    @Query private var results: [TracerResult]
    @Query private var clips: [Clip]
    @State private var player: AVPlayer?
    @State private var tapRequest: BallTapRequest?
    @State private var isReinforcing = false
    @State private var message: String?

    init(clipID: UUID, demo: (analysis: TracerAnalysis, image: UIImage?)? = nil) {
        self.clipID = clipID
        self.demo = demo
        let id = clipID
        _results = Query(filter: #Predicate<TracerResult> { $0.clipID == id })
        _clips = Query(filter: #Predicate<Clip> { $0.id == id })
    }

    private var result: TracerResult? { results.first }
    private var clip: Clip? { clips.first }
    private var analysis: TracerAnalysis? { demo?.analysis ?? result?.analysis }
    private var showsDiagnostics: Bool { diagnostics || demo != nil }

    var body: some View {
        ZStack {
            Color.escenario
            GeometryReader { proxy in
                if let analysis {
                    let videoSize = CGSize(width: analysis.videoWidth, height: analysis.videoHeight)
                    let fit = AVMakeRect(aspectRatio: videoSize, insideRect: CGRect(origin: .zero, size: proxy.size))
                    ZStack(alignment: .topLeading) {
                        Group {
                            if let image = demo?.image {
                                Image(uiImage: image).resizable()
                            } else if let player {
                                PlayerLayerView(player: player)
                            }
                        }
                        .frame(width: fit.width, height: fit.height)
                        .position(x: fit.midX, y: fit.midY)
                        TracerOverlay(analysis: analysis, showsDiagnostics: showsDiagnostics)
                            .frame(width: fit.width, height: fit.height)
                            .position(x: fit.midX, y: fit.midY)
                            .allowsHitTesting(false)
                    }
                }
            }
            .ignoresSafeArea()
            VStack(spacing: Spacing.s) {
                topBar
                if let lostAt = analysis?.outcome.lostAt, analysis?.outcome.needsReview == true {
                    Chip(title: "Perdí la bola a los \(SpanishFormat.number(lostAt, decimals: 1)) s",
                         systemImage: "exclamationmark.triangle", surface: .video)
                }
                if showsDiagnostics, let analysis { DiagnosticsPanel(analysis: analysis) }
                Spacer()
                bottomBar
            }
            .padding(.horizontal, Spacing.cardMargin)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.l)
            if isReinforcing {
                Color.black.opacity(0.5).ignoresSafeArea()
                VStack(spacing: Spacing.m) {
                    ProgressView().tint(.white).controlSize(.large)
                    Text("Siguiendo la bola desde tu toque…").typeStyle(.cuerpo).foregroundStyle(.white)
                }
            }
        }
        .overlay(alignment: .bottom) { Toast(message: $message).padding(.bottom, 120) }
        .preferredColorScheme(.dark)
        .task { prepare() }
        .onDisappear { player?.pause() }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { _ in
            player?.seek(to: .zero)
            player?.play()
        }
        .fullScreenCover(item: $tapRequest) { request in
            BallTapView(request: request) { time, point in
                Task { await reinforce(time: time, point: point) }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: Spacing.s) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 17, weight: .regular)) }
                .buttonStyle(.crystal)
                .accessibilityLabel("Cerrar")
            Spacer(minLength: 0)
            Chip(title: "Ajusta el vuelo", dotColor: .rojoTrazo, surface: .video)
            Spacer(minLength: 0)
            Color.clear.frame(width: Size.glassButton, height: Size.glassButton)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: Spacing.m) {
            if showsDiagnostics, let analysis {
                HStack(spacing: Spacing.m) {
                    Button { startTap() } label: { Label("Tocar la bola", systemImage: "scope") }
                        .buttonStyle(CrystalButtonStyle(outline: .capsule))
                        .disabled(analysis.reinforcements.count >= TracerConstants.maximumReinforcementTaps || isReinforcing)
                    if !analysis.reinforcements.isEmpty {
                        Button { undoLastTap() } label: { Label("Deshacer", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(CrystalButtonStyle(outline: .capsule))
                    }
                    Spacer(minLength: 0)
                }
            }
            Text("Ajustar el vuelo a mano (salida, altura y caída), elegir la forma y crear el vídeo llega en la etapa 5.")
                .typeStyle(.nota)
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.m)
                .glassEffect(.clear.tint(Color.pino.opacity(0.55)), in: RoundedRectangle(cornerRadius: CaptureLayout.tipRadius, style: .continuous))
        }
    }

    // MARK: Vídeo

    /// Prepara el vídeo; si se perdió la bola, empieza en ese fotograma (docs/02, "Ajusta el vuelo").
    private func prepare() {
        guard demo == nil, player == nil, let clip, let analysis else { return }
        let newPlayer = AVPlayer(url: clip.fileURL)
        player = newPlayer
        if analysis.outcome.needsReview, let lostAt = analysis.outcome.lostAt {
            newPlayer.seek(to: CMTime(seconds: analysis.impactTime + lostAt, preferredTimescale: 48_000),
                           toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            newPlayer.play()
        }
    }

    // MARK: Toque de refuerzo

    private func startTap() {
        guard let clip, let analysis else { return }
        player?.pause()
        let current = player?.currentTime().seconds ?? (analysis.impactTime + (analysis.outcome.lostAt ?? 0.5))
        tapRequest = BallTapRequest(url: clip.fileURL, time: max(current, analysis.impactTime + 0.05),
                                    frameRate: analysis.frameRate, videoWidth: analysis.videoWidth,
                                    videoHeight: analysis.videoHeight, title: "Tocar la bola",
                                    hint: "Busca un fotograma en el que veas la bola y tócala. La app la vuelve a seguir desde ahí.")
    }

    /// Vuelve a seguir la bola desde el toque, junta los puntos y repite el ajuste. Si el error medio
    /// sube en vez de bajar, avisa (docs/03): puede que no fuera la bola.
    private func reinforce(time: Double, point: Point2D) async {
        guard let clip, let result, var analysis = result.analysis else { return }
        let tapTime = time - analysis.impactTime
        guard tapTime > 0 else {
            message = "Toca la bola en un fotograma de después del golpe."
            return
        }
        isReinforcing = true
        defer { isReinforcing = false }
        let tap = TrajectorySample(time: tapTime, point: point, isFixed: true)
        let velocity = TracerAssembler.assemble(analysis.assemblerInput()).velocity(at: tapTime)
        do {
            let reinforcement = try await TracerPipeline.reinforce(url: clip.fileURL, analysis: analysis, tap: tap, velocity: velocity)
            let before = analysis.outcome.meanError
            analysis.reinforcements.append(reinforcement)
            analysis.outcome = TracerAssembler.assemble(analysis.assemblerInput()).outcome
            result.analysis = analysis
            try? context.save()
            if let before, let after = analysis.outcome.meanError, after > before + 0.25 {
                message = "Ese toque no encaja con el resto. ¿Seguro que es la bola?"
            } else {
                message = "Seguida desde tu toque: \(reinforcement.added.count) puntos nuevos"
            }
        } catch {
            message = "No se ha podido seguir desde el toque: \(error.localizedDescription)"
        }
    }

    private func undoLastTap() {
        guard let result, var analysis = result.analysis, !analysis.reinforcements.isEmpty else { return }
        analysis.reinforcements.removeLast()
        analysis.outcome = TracerAssembler.assemble(analysis.assemblerInput()).outcome
        result.analysis = analysis
        try? context.save()
        message = "Toque deshecho"
    }
}

/// La curva propuesta y, en modo diagnóstico, los puntos y la curva ajustada.
/// Se dibuja en el tamaño del vídeo encajado: cada píxel del vídeo se escala a la vista.
private struct TracerOverlay: View {
    let analysis: TracerAnalysis
    let showsDiagnostics: Bool

    var body: some View {
        let flight = analysis.outcome.curve.makeFlight()
        let assembly = showsDiagnostics ? TracerAssembler.assemble(analysis.assemblerInput()) : nil
        let width = Double(analysis.videoWidth)
        let height = Double(analysis.videoHeight)
        Canvas { context, size in
            let sx = size.width / width, sy = size.height / height
            func view(_ p: Point2D) -> CGPoint { CGPoint(x: p.x * sx, y: p.y * sy) }

            // Curva propuesta (aún sin el estilo final de la etapa 5).
            var curve = Path()
            curve.addLines(flight.points.map(view))
            context.stroke(curve, with: .color(Color.rojoTrazo), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            let launch = view(analysis.outcome.curve.launch)
            context.stroke(Path(ellipseIn: CGRect(x: launch.x - 8, y: launch.y - 8, width: 16, height: 16)), with: .color(.white), lineWidth: 2)
            let landing = view(analysis.outcome.curve.landing)
            context.fill(Path(ellipseIn: CGRect(x: landing.x - 4, y: landing.y - 4, width: 8, height: 8)), with: .color(.white))

            guard showsDiagnostics else { return }
            // Curva ajustada sobre lo visto: blanca y discontinua.
            if let fit = assembly?.fit {
                var fitted = Path()
                let samples = stride(from: 0.0, through: analysis.outcome.trackedDuration, by: 1.0 / 120).map { view(fit.position(at: $0)) }
                fitted.addLines(samples)
                context.stroke(fitted, with: .color(.white), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
            }
            for point in analysis.outcome.points {
                let p = view(point.point)
                let color: Color = point.isOutlier ? DiagnosticColors.discarded
                    : point.source == .vision ? DiagnosticColors.vision
                    : point.source == .blob ? DiagnosticColors.blob : .white
                let radius: CGFloat = point.source == .tap ? 4 : 2.2
                let dot = Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: 2 * radius, height: 2 * radius))
                context.fill(dot, with: .color(color))
                if point.source == .tap {
                    context.stroke(Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)), with: .color(.white), lineWidth: 1.5)
                }
            }
        }
    }
}

/// Datos del análisis para el modo diagnóstico (docs/03): confianza, puntos, tiempos, fps e instante de pérdida.
private struct DiagnosticsPanel: View {
    let analysis: TracerAnalysis

    var body: some View {
        let outcome = analysis.outcome
        let count = { (source: PointSource) in outcome.points.filter { $0.source == source }.count }
        let discarded = outcome.points.filter(\.isOutlier).count
        var lines = [
            "Confianza \(SpanishFormat.number(outcome.confidence, decimals: 2)) · \(outcome.needsReview ? "pide ajuste" : "sin ajuste")",
            "Puntos: Vision \(count(.vision)) · BlobTracker \(count(.blob)) · toques \(count(.tap)) · descartados \(discarded)",
            "Impacto \(analysis.impactSource == .sound ? "por el sonido" : "por el movimiento"), F\(analysis.impactFrame) (\(SpanishFormat.seconds(analysis.impactTime, decimals: 3)))",
            "Seguida hasta \(SpanishFormat.seconds(outcome.trackedDuration)) · error medio \(outcome.meanError.map { SpanishFormat.number($0, decimals: 1) + " px" } ?? "—")",
            "\(SpanishFormat.number(analysis.frameRate, decimals: 1)) fps · \(analysis.videoWidth) x \(analysis.videoHeight) · horizonte \(analysis.horizonY.map { SpanishFormat.number($0) } ?? "44 %")",
        ]
        if !analysis.timings.isEmpty {
            lines.append(analysis.timings.map { "\($0.name) \(SpanishFormat.seconds($0.seconds, decimals: 1))" }.joined(separator: " · "))
        }
        lines += analysis.notes
        return Text(lines.joined(separator: "\n"))
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.s)
            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.thumbnailSmall))
            .accessibilityLabel("Diagnóstico del tracer")
    }
}
