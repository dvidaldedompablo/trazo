import GolfCore
import SwiftData
import SwiftUI
import UIKit

/// Estado de "Revisa las posiciones": corre el análisis si hace falta, guarda las correcciones
/// y pide las propuestas del palo (seguimiento del takeaway y líneas en 3 y 5).
@MainActor
@Observable
final class SwingReviewModel {
    enum Phase: Equatable {
        case loading
        case analyzing
        case ready
        case failed(String)
    }

    let clipID: UUID
    var phase: Phase = .loading
    var live = SwingLive()
    var analysis: SwingAnalysis?
    var selected: SwingPosition = .address
    /// Imagen del fotograma que se ve y miniaturas de la tira (por posición).
    var frameImage: UIImage?
    var thumbnails: [SwingPosition: UIImage] = [:]
    var message: String?
    /// Mientras se sigue la cabeza del palo tras el toque.
    var isTrackingClub = false

    @ObservationIgnored var clip: Clip?
    @ObservationIgnored var result: SwingResult?
    @ObservationIgnored var context: ModelContext?
    @ObservationIgnored var demoImage: UIImage?
    @ObservationIgnored private var frameTask: Task<Void, Never>?

    init(clipID: UUID) {
        self.clipID = clipID
    }

    var isDemo: Bool { demoImage != nil }

    func start() async {
        guard analysis == nil else { return }
        if let demoImage {
            analysis = DemoData.swingAnalysis()
            frameImage = demoImage
            for position in SwingPosition.allCases { thumbnails[position] = demoImage }
            phase = .ready
            return
        }
        guard let context else { return }
        clip = try? context.fetch(FetchDescriptor<Clip>(predicate: #Predicate { $0.id == clipID })).first
        result = try? context.fetch(FetchDescriptor<SwingResult>(predicate: #Predicate { $0.clipID == clipID })).first
        guard let clip else {
            phase = .failed("No se encuentra el vídeo.")
            return
        }
        if let saved = result?.analysis {
            analysis = saved
            phase = .ready
            await loadImages()
            return
        }
        // Análisis nuevo: pose, impacto y posiciones, con el avance en pantalla.
        phase = .analyzing
        let (stream, continuation) = AsyncStream.makeStream(of: SwingLive.self)
        let listener = Task { [weak self] in
            for await value in stream { self?.live = value }
        }
        do {
            let handedness = Handedness(rawValue: UserDefaults.standard.string(forKey: SettingsKey.handedness) ?? "") ?? .right
            var height = UserDefaults.standard.double(forKey: SettingsKey.heightCentimeters)
            if height < 100 { height = 175 }
            let analyzed = try await SwingAnalyzer.analyze(url: clip.fileURL, knownImpact: clip.impactTime,
                                                          handedness: handedness, heightCentimeters: height,
                                                          progress: continuation)
            continuation.finish()
            analysis = analyzed
            save()
            phase = .ready
            await loadImages()
        } catch {
            continuation.finish()
            phase = .failed(error.localizedDescription)
        }
        listener.cancel()
    }

    /// Guarda el análisis (con las correcciones) en SwiftData.
    func save() {
        guard !isDemo, let context, let analysis else { return }
        if result == nil {
            let created = SwingResult(clipID: clipID)
            context.insert(created)
            result = created
        }
        result?.analysis = analysis
        try? context.save()
    }

    // MARK: Fotogramas

    var currentIndex: Int {
        analysis?.phases[selected].frameIndex ?? 0
    }

    func select(_ position: SwingPosition) {
        selected = position
        reloadFrame()
        proposeLineIfNeeded()
    }

    /// Mueve la posición elegida un fotograma del análisis (docs/04, punto 4).
    func step(_ delta: Int) {
        guard var analysis else { return }
        let index = analysis.phases[selected].frameIndex + delta
        guard analysis.poses.indices.contains(index) else { return }
        analysis.move(selected, to: index)
        self.analysis = analysis
        reloadFrame()
    }

    private func reloadFrame() {
        guard !isDemo else { return }
        frameTask?.cancel()
        guard let clip, let analysis else { return }
        let time = analysis.poses[analysis.phases[selected].frameIndex].time
        frameTask = Task { [weak self] in
            if let data = try? await FrameGrabber.jpeg(from: clip.fileURL, at: time) {
                guard !Task.isCancelled else { return }
                self?.frameImage = UIImage(data: data)
            }
        }
    }

    private func loadImages() async {
        guard let clip, let analysis else { return }
        reloadFrame()
        for position in SwingPosition.allCases {
            let time = analysis.poses[analysis.phases[position].frameIndex].time
            if let data = try? await FrameGrabber.jpeg(from: clip.fileURL, at: time,
                                                       maximumSize: CGSize(width: 180, height: 320), exact: false) {
                thumbnails[position] = UIImage(data: data)
            }
        }
    }

    // MARK: El palo

    /// Toque en la imagen: en la preparación marca la cabeza del palo (y arranca el seguimiento
    /// hasta el takeaway); en el takeaway la corrige a mano.
    func tapped(_ point: Point2D) {
        guard var analysis else { return }
        switch selected {
        case .address:
            analysis.clubHeadAtAddress = point
            self.analysis = analysis
            save()
            trackClub(from: point)
        case .takeaway:
            analysis.clubHeadAtTakeaway = point
            self.analysis = analysis
            save()
        default:
            break
        }
    }

    func dragLineHead(to point: Point2D) {
        guard var analysis else { return }
        switch selected {
        case .midBackswing:
            if var line = analysis.clubLineAtMidBackswing {
                line.head = point
                analysis.clubLineAtMidBackswing = line
            }
        case .transition:
            if var line = analysis.clubLineAtTransition {
                line.head = point
                analysis.clubLineAtTransition = line
            }
        default:
            return
        }
        self.analysis = analysis
    }

    private func trackClub(from point: Point2D) {
        guard !isDemo, let clip, let analysis else { return }
        isTrackingClub = true
        Task { [weak self] in
            let found = try? await SwingAnalyzer.trackClubHead(url: clip.fileURL, analysis: analysis, addressPoint: point)
            guard let self else { return }
            isTrackingClub = false
            if var updated = self.analysis {
                updated.clubHeadAtTakeaway = found ?? updated.clubHeadAtTakeaway
                self.analysis = updated
                save()
            }
            if found == nil {
                message = "No he podido seguir la cabeza del palo. Márcala tú en el takeaway."
            }
        }
    }

    /// Al entrar en 3 o 5 sin línea, la app propone una (bordes y votación de rectas).
    private func proposeLineIfNeeded() {
        guard !isDemo, let clip, let analysis else { return }
        let missing = (selected == .midBackswing && analysis.clubLineAtMidBackswing == nil)
            || (selected == .transition && analysis.clubLineAtTransition == nil)
        guard missing else { return }
        let position = selected
        Task { [weak self] in
            guard let line = try? await SwingAnalyzer.proposeClubLine(url: clip.fileURL, analysis: analysis, position: position)
            else { return }
            guard let self, var updated = self.analysis else { return }
            if position == .midBackswing, updated.clubLineAtMidBackswing == nil {
                updated.clubLineAtMidBackswing = line
            } else if position == .transition, updated.clubLineAtTransition == nil {
                updated.clubLineAtTransition = line
            }
            self.analysis = updated
            save()
        }
    }

    /// "Generar análisis": deja el análisis como revisado y guarda. La pantalla abre el resultado.
    func generate() {
        guard var analysis else { return }
        analysis.reviewed = true
        self.analysis = analysis
        save()
    }
}

/// Revisa las posiciones (docs/02, pantalla s06): el fotograma grande con el telestrador, la tira
/// de 7 posiciones, pasos de fotograma y las correcciones del palo.
struct SwingReviewView: View {
    @State private var model: SwingReviewModel
    @Environment(\.modelContext) private var context
    @Environment(\.homeNavigator) private var navigator
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.diagnostics) private var diagnostics = false
    @State private var showsResult = false
    @State private var showsMetricsTable = false
    @State private var draggedHead: Point2D?

    init(clipID: UUID, demoImage: UIImage? = nil) {
        let model = SwingReviewModel(clipID: clipID)
        model.demoImage = demoImage
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            switch model.phase {
            case .loading, .analyzing:
                progressCard
            case let .failed(reason):
                failureCard(reason)
            case .ready:
                reviewContent
            }
        }
        .padding(.horizontal, Spacing.textMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bola)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) { Toast(message: $model.message) }
        .task {
            model.context = context
            await model.start()
        }
        .onDisappear { model.save() }
        .fullScreenCover(isPresented: $showsResult, onDismiss: { dismiss() }) {
            SwingResultView(clipID: model.clipID, demoImage: model.demoImage)
        }
        .sheet(isPresented: $showsMetricsTable) {
            if let analysis = model.analysis {
                SwingMetricsTable(measurements: analysis.measurements())
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                dismiss()
            } label: {
                Label("Atrás", systemImage: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
            }
            .foregroundStyle(Color.pino)
            .frame(height: Size.minTouch)
            Text("Revisa las posiciones")
                .typeStyle(.tituloPantalla)
                .foregroundStyle(Color.pino)
                .accessibilityAddTraits(.isHeader)
            Text("Encontradas automáticamente. Toca una para corregirla.")
                .typeStyle(.leadText)
                .foregroundStyle(Color.texto2)
                .padding(.top, 6)
        }
    }

    // MARK: Análisis en marcha

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            ProgressView(value: model.live.progress)
                .tint(Color.pino)
            Text(progressText)
                .typeStyle(.sub)
                .foregroundStyle(Color.texto2)
                .monospacedDigit()
        }
        .padding(Spacing.l)
        .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .padding(.top, Spacing.l)
    }

    private var progressText: String {
        switch model.live.step {
        case .audio: "Escuchando el golpe…"
        case .pose: "Buscando tu cuerpo: fotograma \(model.live.frame) de \(model.live.totalFrames)"
        case .phases: "Colocando las 7 posiciones…"
        }
    }

    private func failureCard(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label(reason, systemImage: "exclamationmark.triangle")
                .typeStyle(.sub)
                .foregroundStyle(Color.pino)
            Button { dismiss() } label: { Text("Volver") }
                .buttonStyle(.secundario)
        }
        .padding(Spacing.l)
        .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .padding(.top, Spacing.l)
    }

    // MARK: Revisión

    @ViewBuilder
    private var reviewContent: some View {
        if let analysis = model.analysis {
            frameCard(analysis)
                .padding(.top, Spacing.m)
            thumbnailStrip(analysis)
                .padding(.top, Spacing.m)
            caption(analysis)
                .padding(.top, Spacing.s)
            Spacer(minLength: Spacing.s)
            Button {
                model.generate()
                showsResult = true
            } label: {
                Text("Generar análisis")
            }
            .buttonStyle(.principal)
            .padding(.bottom, Spacing.l)
        }
    }

    private func frameCard(_ analysis: SwingAnalysis) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let mapping = FillMapping(video: CGSize(width: analysis.videoWidth, height: analysis.videoHeight), view: size)
            ZStack(alignment: .top) {
                Group {
                    if let image = model.frameImage {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Color.niebla
                    }
                }
                .frame(width: size.width, height: size.height)
                SwingOverlayView(analysis: analysis, position: model.selected,
                                 frameIndex: analysis.phases[model.selected].frameIndex,
                                 draggedLineHead: draggedHead)
                if model.selected == .address && analysis.clubHeadAtAddress == nil {
                    tapPill("Toca la cabeza del palo")
                } else if model.isTrackingClub {
                    tapPill("Siguiendo la cabeza del palo…")
                } else if model.selected == .takeaway && analysis.clubHeadAtTakeaway == nil {
                    tapPill("Toca la cabeza del palo en este fotograma")
                }
            }
            .contentShape(Rectangle())
            .gesture(cardGesture(mapping: mapping))
            .overlay(alignment: .bottom) { frameControls(analysis) }
        }
        .aspectRatio(0.62, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func tapPill(_ text: String) -> some View {
        Text(text)
            .typeStyle(.etiqueta)
            .foregroundStyle(Color.pino)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, 10)
            .background(Color.papel, in: Capsule())
            .padding(.top, Spacing.l)
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }

    /// Toque: marca la cabeza del palo. Arrastre: mueve el extremo de la línea en 3 y 5.
    private func cardGesture(mapping: FillMapping) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard model.selected == .midBackswing || model.selected == .transition else { return }
                let line = model.selected == .midBackswing
                    ? model.analysis?.clubLineAtMidBackswing : model.analysis?.clubLineAtTransition
                guard let line else { return }
                // Solo si el dedo empieza cerca del extremo (o ya está arrastrando).
                let headInView = mapping.view(line.head)
                let grabDistance = hypot(headInView.x - value.startLocation.x, headInView.y - value.startLocation.y)
                if draggedHead != nil || grabDistance < 44 {
                    draggedHead = mapping.video(value.location)
                }
            }
            .onEnded { value in
                if let draggedHead {
                    model.dragLineHead(to: draggedHead)
                    model.save()
                    self.draggedHead = nil
                } else if value.translation.width.magnitude < 10, value.translation.height.magnitude < 10 {
                    model.tapped(mapping.video(value.location))
                }
            }
    }

    private func frameControls(_ analysis: SwingAnalysis) -> some View {
        HStack {
            Button { model.step(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.crystal)
                .accessibilityLabel("Fotograma anterior")
            Spacer()
            Text("Fotograma \(analysis.clipFrameNumber(at: analysis.phases[model.selected].frameIndex))")
                .typeStyle(.etiqueta)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 3)
                .monospacedDigit()
            Spacer()
            Button { model.step(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.crystal)
                .accessibilityLabel("Fotograma siguiente")
        }
        .padding(Spacing.m)
    }

    private func thumbnailStrip(_ analysis: SwingAnalysis) -> some View {
        HStack(spacing: Spacing.s) {
            ForEach(SwingPosition.allCases, id: \.rawValue) { position in
                Button { model.select(position) } label: {
                    ZStack(alignment: .topLeading) {
                        Group {
                            if let image = model.thumbnails[position] {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                Color.niebla
                            }
                        }
                        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnailSmall, style: .continuous))
                        Text("\(position.rawValue)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.pino)
                            .padding(4)
                        if analysis.phases[position].isDoubtful {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.amarillo, Color.pino)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(3)
                        }
                    }
                    .overlay {
                        if model.selected == position {
                            RoundedRectangle(cornerRadius: Radius.thumbnailSmall, style: .continuous)
                                .strokeBorder(Color.amarillo, lineWidth: 3)
                                .overlay {
                                    RoundedRectangle(cornerRadius: Radius.thumbnailSmall, style: .continuous)
                                        .inset(by: 3)
                                        .strokeBorder(Color.pino, lineWidth: 1.5)
                                }
                        }
                    }
                }
                .accessibilityLabel("\(position.rawValue) de 7, \(position.title)")
                .accessibilityAddTraits(model.selected == position ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var thumbnailSize: CGSize { CGSize(width: 44, height: 66) }

    private func caption(_ analysis: SwingAnalysis) -> some View {
        Group {
            Text("\(model.selected.rawValue) de 7, \(model.selected.title). ").bold()
                + Text(captionHint(analysis))
        }
        .typeStyle(.sub)
        .foregroundStyle(Color.texto2)
        .onTapGesture(count: 2) {
            if diagnostics || model.isDemo { showsMetricsTable = true }
        }
    }

    private func captionHint(_ analysis: SwingAnalysis) -> String {
        if analysis.phases[model.selected].isDoubtful {
            return "No sigue el orden de un swing: muévela con las flechas."
        }
        switch model.selected {
        case .address where analysis.clubHeadAtAddress == nil:
            return "Toca la cabeza del palo para dibujar su línea."
        case .takeaway:
            return "Comprueba la marca de la cabeza del palo."
        case .midBackswing, .transition:
            return "Arrastra el extremo de la línea si no cae sobre el palo."
        default:
            return "Toca otra posición para revisarla."
        }
    }
}

/// Tabla de medidas del modo diagnóstico (docs/00, etapa 6, punto 6).
struct SwingMetricsTable: View {
    let measurements: SwingMeasurements

    var body: some View {
        NavigationStack {
            List(measurements.items, id: \.kind) { item in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.kind.title).typeStyle(.filaTitulo)
                        Text(item.phase.title).typeStyle(.filaSub).foregroundStyle(Color.texto3)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(valueText(item)).typeStyle(.valor).monospacedDigit()
                        Text(statusText(item)).typeStyle(.filaSub)
                            .foregroundStyle(statusColor(item.status))
                    }
                }
            }
            .navigationTitle("Medidas")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func valueText(_ item: MetricResult) -> String {
        guard let value = item.value else { return "—" }
        switch item.kind.unit {
        case .degrees: return "\(SpanishFormat.number(value, decimals: 0))°"
        case .centimeters: return "~\(SpanishFormat.number(value, decimals: 0)) cm"
        case .seconds: return SpanishFormat.seconds(value, decimals: 2)
        case .ratio: return SpanishFormat.number(value, decimals: 2)
        case .trunkFraction: return SpanishFormat.number(value, decimals: 2)
        case .yesNo: return value > 0.5 ? "Sí" : "No"
        }
    }

    private func statusText(_ item: MetricResult) -> String {
        switch item.status {
        case .good: "Bien"
        case .informative: "Informativa"
        case .low, .high: item.fault.map { FaultLibrary.fault($0).name } ?? "Fuera de rango"
        case .unavailable: "Sin datos"
        }
    }

    private func statusColor(_ status: MeasurementStatus) -> Color {
        switch status {
        case .good: Color.bien
        case .low, .high: Color.rojoTrazo
        case .informative, .unavailable: Color.texto3
        }
    }
}
