import GolfCore
import SwiftData
import SwiftUI
import UIKit

/// Creando tu tracer (s03): la onda del sonido con el impacto, la miniatura con los puntos de la bola
/// apareciendo y los pasos. Enseña en directo lo que hace la cola con este golpe; al terminar abre
/// el resultado y, si no encuentra la bola, pide un toque.
struct TracerProcessingView: View {
    let clipID: UUID
    /// Capturas del CI: estado fijo a mitad del seguimiento, sin cola.
    var demo: TracerLive?

    @Environment(TracerQueue.self) private var queue
    @Environment(\.dismiss) private var dismiss
    @Query private var results: [TracerResult]
    @Query private var clips: [Clip]
    @State private var showsReview = false
    @State private var tapRequest: BallTapRequest?

    init(clipID: UUID, demo: TracerLive? = nil) {
        self.clipID = clipID
        self.demo = demo
        let id = clipID
        _results = Query(filter: #Predicate<TracerResult> { $0.clipID == id })
        _clips = Query(filter: #Predicate<Clip> { $0.id == id })
    }

    private var result: TracerResult? { results.first }
    private var clip: Clip? { clips.first }
    private var live: TracerLive { demo ?? (queue.activeClipID == clipID ? queue.live : TracerLive()) }
    private var status: TracerStatus { demo != nil ? .processing : result?.status ?? .pending }

    var body: some View {
        GeometryReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button("Cancelar") {
                    if demo == nil { queue.cancel(clipID) }
                    dismiss()
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.pino)
                .frame(height: Size.minTouch)
                .padding(.leading, ProcessingLayout.cancelLeading - Spacing.textMargin)
                Text("Creando tu tracer")
                    .typeStyle(.tituloPantalla)
                    .foregroundStyle(Color.pino)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, ProcessingLayout.cancelToTitle)
                Text("Mantén la app abierta. Tarda menos de un minuto.")
                    .typeStyle(.leadText)
                    .foregroundStyle(Color.texto2)
                    .padding(.top, ProcessingLayout.titleToLead)
                soundPanel
                    .padding(.horizontal, Spacing.cardMargin - Spacing.textMargin)
                    .padding(.top, ProcessingLayout.leadToPanel)
                if status == .failed && result?.needsBall == false {
                    failurePanel
                        .padding(.horizontal, Spacing.cardMargin - Spacing.textMargin)
                        .padding(.top, ProcessingLayout.panelToSteps)
                } else {
                    HStack(alignment: .top, spacing: Spacing.l) {
                        trackThumbnail
                        steps
                    }
                    .padding(.horizontal, Spacing.cardMargin - Spacing.textMargin)
                    .padding(.top, ProcessingLayout.panelToSteps)
                }
                Text("Si la bola se pierde, te diré en qué momento. Podrás tocarla en un fotograma posterior para que la siga o ajustar el vuelo a mano.")
                    .typeStyle(.footNote)
                    .foregroundStyle(Color.texto2)
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.niebla, in: RoundedRectangle(cornerRadius: CaptureLayout.tipRadius, style: .continuous))
                    .padding(.top, ProcessingLayout.stepsToNote)
            }
            .padding(.horizontal, Spacing.textMargin)
            // "Cancelar" empieza a 50 pt del borde de arriba, como en la maqueta.
            .padding(.top, max(ProcessingLayout.top - proxy.safeAreaInsets.top, 0))
            .padding(.bottom, Spacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.bola)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // Si este golpe aún no tiene tracer, se pide ahora.
            guard demo == nil, result == nil else { return }
            queue.enqueue([clipID])
        }
        .onChange(of: result?.status) { _, newStatus in react(to: newStatus) }
        .onAppear { react(to: result?.status) }
        .fullScreenCover(isPresented: $showsReview, onDismiss: { dismiss() }) {
            TracerReviewView(clipID: clipID)
        }
        .fullScreenCover(item: $tapRequest) { request in
            BallTapView(request: request) { time, point in
                queue.retry(clipID, manualBall: ManualBall(point: point, time: time))
            }
        }
    }

    /// Al terminar: el resultado; si falta la bola, el toque.
    private func react(to newStatus: TracerStatus?) {
        guard demo == nil, let newStatus, let clip else { return }
        switch newStatus {
        case .ready:
            showsReview = true
        case .failed where result?.needsBall == true:
            tapRequest = BallTapRequest(url: clip.fileURL, time: result?.manualBallTime ?? max((clip.impactTime ?? 1) - TracerConstants.ballLookBack, 0),
                                        frameRate: clip.frameRate, videoWidth: clip.width, videoHeight: clip.height,
                                        title: "Toca la bola",
                                        hint: result?.failureReason ?? "Busca un fotograma nítido de antes del golpe y toca la bola.")
        default:
            break
        }
    }

    // MARK: Sonido

    private var soundPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sonido del golpe")
                    .typeStyle(.panelTitle)
                    .foregroundStyle(Color.pino)
                Spacer(minLength: Spacing.s)
                Text("Así encuentro el impacto")
                    .typeStyle(.nota)
                    .foregroundStyle(Color.texto3)
            }
            ImpactWaveformView(bars: live.bars.isEmpty ? Self.flatBars : live.bars, impactBar: live.impactBar,
                               label: live.impactTime.map { "Impacto \(SpanishFormat.seconds($0))" })
                .padding(.top, 2)
        }
        .padding(.top, 14)
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, 6)
        .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }

    /// Mientras no hay sonido, una línea plana.
    private static let flatBars = [Double](repeating: 0.05, count: TracerPipeline.waveformBars)

    // MARK: Miniatura con los puntos

    private var trackThumbnail: some View {
        let image = live.thumbnail.flatMap { UIImage(data: $0) } ?? Thumbnailer.load(named: clip?.thumbnailName)
        let aspect = image.map { $0.size.width / max($0.size.height, 1) } ?? 9 / 16
        let points = live.points
        return ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.niebla
                }
            }
            .frame(width: ProcessingLayout.thumbnail.width, height: ProcessingLayout.thumbnail.height)
            .overlay {
                // Los puntos encontrados, en rojo con borde blanco. La imagen llena el marco recortando lo
                // que sobra: los puntos se recortan igual para caer sobre la bola.
                Canvas { context, size in
                    let shown = CGSize(width: max(size.width, size.height * aspect), height: max(size.height, size.width / aspect))
                    let offset = CGPoint(x: (shown.width - size.width) / 2, y: (shown.height - size.height) / 2)
                    for point in points {
                        let p = CGPoint(x: point.x * shown.width - offset.x, y: point.y * shown.height - offset.y)
                        let dot = Path(ellipseIn: CGRect(x: p.x - 3.2, y: p.y - 3.2, width: 6.4, height: 6.4))
                        context.fill(dot, with: .color(Color.rojoTrazo))
                        context.stroke(dot, with: .color(.white), lineWidth: 1.2)
                    }
                }
            }
            if !live.points.isEmpty {
                Text(live.points.count == 1 ? "1 punto" : "\(live.points.count) puntos")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.pino.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(8)
            }
        }
        .frame(width: ProcessingLayout.thumbnail.width, height: ProcessingLayout.thumbnail.height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Puntos de la bola encontrados: \(live.points.count)")
    }

    // MARK: Pasos

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            StepRow(title: "Impacto encontrado", detail: impactDetail, state: impactState)
            StepRow(title: "Siguiendo la bola", detail: trackingDetail, state: state(for: .tracking))
            StepRow(title: "Dibujando el trazo", detail: nil, state: state(for: .drawing))
            StepRow(title: "Exportando el vídeo", detail: nil, state: .pending)
        }
        .padding(.top, 4)
    }

    private var impactState: StepRow.State {
        if live.impactTime != nil { return .done }
        return status == .processing ? .active : .pending
    }

    private var impactDetail: String? {
        if let frame = live.impactFrame, let source = live.impactSource {
            return source == .sound ? "Por el sonido, en el fotograma \(frame)" : "Por el movimiento de la bola, en el fotograma \(frame)"
        }
        if status == .pending, let position = queue.position(of: clipID), position > 0 {
            return position == 1 ? "En cola: falta 1 golpe" : "En cola: faltan \(position) golpes"
        }
        return status == .processing ? "Escuchando el golpe" : nil
    }

    private var trackingDetail: String? {
        guard live.step == .tracking, live.totalFrames > 0 else { return nil }
        return "Fotograma \(live.frame) de \(live.totalFrames)"
    }

    private func state(for step: TracerStep) -> StepRow.State {
        if status == .ready || live.step > step { return .done }
        return live.step == step && live.impactTime != nil ? .active : .pending
    }

    // MARK: Fallo

    private var failurePanel: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label(result?.failureReason ?? "No se ha podido crear el tracer.", systemImage: "exclamationmark.triangle")
                .typeStyle(.sub)
                .foregroundStyle(Color.pino)
            Button { queue.retry(clipID, manualBall: nil) } label: { Text("Volver a intentar") }
                .buttonStyle(.principal)
            if result?.analysis != nil {
                Button { showsReview = true } label: { Text("Abrir en Ajusta el vuelo") }
                    .buttonStyle(.secundario)
            }
        }
        .padding(Spacing.l)
        .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }
}

/// Un paso de la lista (docs/02, "ListaPasos"): círculo de 24 pt (vacío, activo con punto rojo,
/// hecho con check sobre Pino), título y detalle.
private struct StepRow: View {
    enum State {
        case pending, active, done
    }

    let title: String
    let detail: String?
    let state: State

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            ZStack {
                switch state {
                case .done:
                    Circle().fill(Color.pino)
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                case .active:
                    Circle().strokeBorder(Color.rojoTrazo, lineWidth: 2.5)
                    Circle().fill(Color.rojoTrazo).frame(width: 8, height: 8)
                case .pending:
                    Circle().strokeBorder(Color.borde, lineWidth: 2)
                }
            }
            .frame(width: 24, height: 24)
            .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .typeStyle(state == .pending ? .stepPending : .panelTitle)
                    .foregroundStyle(state == .pending ? Color.texto3 : Color.pino)
                if let detail {
                    Text(detail)
                        .typeStyle(.nota)
                        .foregroundStyle(Color.texto2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(state == .done ? "Hecho" : state == .active ? "En marcha" : "Pendiente")
    }
}

/// Medidas de s03 sacadas de `design/maqueta.html` (pantalla de 390 x 844).
private enum ProcessingLayout {
    /// Arriba de "Cancelar", desde el borde de la pantalla.
    static let top: CGFloat = 50
    /// "Cancelar" a 12 pt del borde izquierdo (el resto del texto va a 20).
    static let cancelLeading: CGFloat = 12
    /// Del final de "Cancelar" (44 pt de alto, a 50 del borde) al título (a 96).
    static let cancelToTitle: CGFloat = 2
    static let titleToLead: CGFloat = 6
    static let leadToPanel: CGFloat = 6
    static let panelToSteps: CGFloat = 30
    static let stepsToNote: CGFloat = 32
    static let thumbnail = CGSize(width: 112, height: 176)
}
