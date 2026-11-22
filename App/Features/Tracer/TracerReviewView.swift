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
    /// En la captura de "Ajusta el vuelo" sin diagnóstico, false.
    var demoDiagnostics = true

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.diagnostics) private var diagnostics = false
    @Query private var results: [TracerResult]
    @Query private var clips: [Clip]
    @State private var player: AVPlayer?
    @State private var tapRequest: BallTapRequest?
    @State private var isReinforcing = false
    @State private var message: String?
    // Etapa 5: el ajuste, el estilo y el vídeo final. Los valores por defecto salen de Ajustes.
    @AppStorage(SettingsKey.tracerColor) private var defaultColor: TracerColorChoice = .rojoTV
    @AppStorage(SettingsKey.tracerCustomColor) private var defaultCustomHex = Int(TracerPalette.customDefaultHex)
    @AppStorage(SettingsKey.tracerShowsDistance) private var defaultShowsDistance = true
    @AppStorage(SettingsKey.units) private var units = "m"
    @AppStorage(SettingsKey.tracerWatermark) private var watermark = false
    @Query(sort: \Club.order) private var clubs: [Club]
    @State private var edit: TracerEdit?
    @State private var isExporting = false
    @State private var finished: FinishedVideo?

    /// El vídeo ya creado, para la pantalla "Vídeo listo".
    struct FinishedVideo: Identifiable {
        let id = UUID()
        let url: URL?
        let duration: Double
    }

    init(clipID: UUID, demo: (analysis: TracerAnalysis, image: UIImage?)? = nil, demoDiagnostics: Bool = true) {
        self.clipID = clipID
        self.demo = demo
        self.demoDiagnostics = demoDiagnostics
        let id = clipID
        _results = Query(filter: #Predicate<TracerResult> { $0.clipID == id })
        _clips = Query(filter: #Predicate<Clip> { $0.id == id })
    }

    private var result: TracerResult? { results.first }
    private var clip: Clip? { clips.first }
    private var analysis: TracerAnalysis? { demo?.analysis ?? result?.analysis }
    private var showsDiagnostics: Bool { diagnostics || (demo != nil && demoDiagnostics) }

    var body: some View {
        // Como en s04: la barra de arriba, el aviso y los botones van sobre el negro, y el vídeo entre ellos.
        VStack(spacing: Spacing.s) {
            topBar
                .padding(.horizontal, Spacing.cardMargin)
            if let lostAt = analysis?.outcome.lostAt, analysis?.outcome.needsReview == true {
                Chip(title: "Perdí la bola a los \(SpanishFormat.number(lostAt, decimals: 1)) s",
                     systemImage: "exclamationmark.triangle", surface: .video)
            }
            videoArea
                .overlay(alignment: .top) {
                    if showsDiagnostics, let analysis {
                        DiagnosticsPanel(analysis: analysis).padding(.horizontal, Spacing.cardMargin)
                    }
                }
            bottomBar
                .padding(.horizontal, Spacing.cardMargin)
        }
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.l)
        .background(Color.escenario)
        .overlay {
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
        .task {
            startEditing()
            prepare()
        }
        .fullScreenCover(item: $finished) { video in
            TracerVideoResultView(url: video.url, duration: video.duration,
                                  demoImage: video.url == nil ? demo?.image : nil) {
                // "Editar": se vuelve a "Ajusta el vuelo" con todo lo que había.
                finished = nil
            }
        }
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

    /// El vídeo encajado en el hueco que dejan los controles, con el trazo encima.
    private var videoArea: some View {
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
                    if showsDiagnostics {
                        TracerOverlay(analysis: analysis)
                            .frame(width: fit.width, height: fit.height)
                            .position(x: fit.midX, y: fit.midY)
                            .allowsHitTesting(false)
                    }
                    if let edit {
                        TracerStyledPath(curve: edit.curve, videoSize: videoSize,
                                         color: edit.color.color(custom: Color(hex: UInt32(edit.customColorHex))),
                                         label: label(for: edit))
                            .frame(width: fit.width, height: fit.height)
                            .position(x: fit.midX, y: fit.midY)
                            .allowsHitTesting(false)
                        TracerHandles(curve: Binding(get: { self.edit?.curve ?? edit.curve },
                                                     set: { self.edit?.curve = $0 }),
                                      videoSize: videoSize)
                            .frame(width: fit.width, height: fit.height)
                            .position(x: fit.midX, y: fit.midY)
                    }
                }
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
            if let analysis {
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
            if edit != nil {
                TracerAdjustPanel(edit: Binding(get: { edit ?? .placeholder }, set: { edit = $0 }),
                                  clubs: clubs, units: units, isExporting: isExporting) {
                    Task { await createVideo() }
                }
            }
        }
    }

    // MARK: Ajuste y vídeo final (etapa 5)

    /// Empieza con lo guardado (si ya se editó) o con la curva propuesta y los valores de Ajustes.
    private func startEditing() {
        guard edit == nil, let analysis else { return }
        edit = result?.edit ?? TracerEdit(curve: analysis.outcome.curve, colorRaw: defaultColor.rawValue,
                                          customColorHex: defaultCustomHex, showsDistance: defaultShowsDistance,
                                          manualDistanceMeters: nil,
                                          clubName: demo != nil ? "Hierro 7" : nil,
                                          clubDistanceMeters: demo != nil ? 150 : nil)
    }

    /// La etiqueta de la caída, si la distancia está activada y hay un número (escrito o del palo).
    private func label(for edit: TracerEdit) -> (club: String?, distance: String)? {
        guard edit.showsDistance, let meters = edit.distanceMeters else { return nil }
        return (edit.clubName, TracerEdit.distanceText(meters, units: units))
    }

    /// Guarda el ajuste con el tracer y monta el vídeo. En las capturas del CI no hay vídeo: se enseña
    /// "Vídeo listo" con la imagen de demostración.
    private func createVideo() async {
        guard let edit, let analysis else { return }
        if demo != nil {
            finished = FinishedVideo(url: nil, duration: analysis.impactTime + edit.curve.flightTime + TracerVideoExporter.holdAfterLanding)
            return
        }
        guard let clip, let result else { return }
        result.edit = edit
        try? context.save()
        player?.pause()
        isExporting = true
        defer { isExporting = false }
        do {
            if let warning = BackgroundWork.heatWarning { message = warning }
            let clipURL = clip.fileURL, impactTime = analysis.impactTime, units = units, watermark = watermark
            let video = try await BackgroundWork.run(.tracerVideo) {
                try await TracerVideoExporter.export(clipURL: clipURL, impactTime: impactTime,
                                                     edit: edit, units: units, watermark: watermark)
            }
            finished = FinishedVideo(url: video.url, duration: video.duration)
        } catch {
            message = "No se ha podido crear el vídeo: \(error.localizedDescription)"
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
            // La curva nueva sustituye a la del ajuste (el color y la distancia se quedan).
            edit?.curve = analysis.outcome.curve
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
        edit?.curve = analysis.outcome.curve
        try? context.save()
        message = "Toque deshecho"
    }
}

/// Modo diagnóstico: los puntos vistos y la curva ajustada sobre ellos (el trazo con estilo va aparte,
/// en TracerStyledPath). Se dibuja en el tamaño del vídeo encajado.
private struct TracerOverlay: View {
    let analysis: TracerAnalysis

    var body: some View {
        let assembly = TracerAssembler.assemble(analysis.assemblerInput())
        let width = Double(analysis.videoWidth)
        let height = Double(analysis.videoHeight)
        Canvas { context, size in
            let sx = size.width / width, sy = size.height / height
            func view(_ p: Point2D) -> CGPoint { CGPoint(x: p.x * sx, y: p.y * sy) }

            // Curva ajustada sobre lo visto: blanca y discontinua.
            if let fit = assembly.fit {
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
/// Al tocarlo se pliega a una línea, para ver el trazo que queda debajo.
private struct DiagnosticsPanel: View {
    let analysis: TracerAnalysis
    @State private var isExpanded = true

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
        let shown = isExpanded ? lines : [lines[0] + " · toca para ver más"]
        return Text(shown.joined(separator: "\n"))
            .font(.lato(11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.s)
            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.thumbnailSmall))
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.toggle() }
            .accessibilityLabel("Diagnóstico del tracer")
            .accessibilityAddTraits(.isButton)
    }
}
