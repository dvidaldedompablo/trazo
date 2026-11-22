import GolfCore
import SwiftData
import SwiftUI
import UIKit

/// Tus vídeos (docs/02, pantalla 10): rejilla de miniaturas verticales con el tipo, la fecha y la duración.
/// Los golpes del Tracer llevan su estado: "En proceso" con el avance, "Listo" o "Falló".
/// Al mantener pulsado un clip: "Guardar original en Fotos", el tracer y "Borrar".
/// "Seleccionar" (como en la galería del iPhone): se tocan varios vídeos y abajo salen Compartir,
/// cuántos hay, Guardar en Fotos y Borrar.
struct LibraryView: View {
    // @Query lee de SwiftData y vuelve a dibujar la vista cuando cambia la biblioteca.
    @Query(sort: \Clip.createdAt, order: .reverse) private var clips: [Clip]
    @Query private var tracers: [TracerResult]
    @Query private var swings: [SwingResult]
    @Environment(\.modelContext) private var context
    @Environment(TracerQueue.self) private var queue
    @Environment(\.homeNavigator) private var navigator
    @State private var message: String?
    @State private var clipToDelete: Clip?
    /// Clip abierto: es una pantalla de vídeo (negra) y se abre a pantalla completa por encima.
    @State private var openClip: Clip?
    /// Tracer listo abierto (también a pantalla completa).
    @State private var openTracer: UUID?
    /// "Tu análisis" de un swing analizado.
    @State private var openSwingResult: UUID?
    /// Golpe que falló y se ha tocado: se enseña el motivo y qué hacer.
    @State private var failedClip: Clip?
    /// Modo "Seleccionar" y los vídeos elegidos (por su id, que no cambia aunque cambie la lista).
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var asksToDeleteSelection = false
    @State private var isSavingSelection = false

    /// Capturas del CI: abre en modo "Seleccionar" con los dos primeros elegidos.
    var demoSelecting = false

    // Deslizar para seleccionar (como en Fotos). Los marcos de cada miniatura se guardan en el espacio
    // del contenido, que no se mueve al desplazar; el dedo se mide en el de la pantalla (viewport).
    @State private var itemFrames: [UUID: CGRect] = [:]
    @State private var contentOrigin: CGPoint = .zero
    @State private var viewportHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var maximumScrollOffset: CGFloat = 0
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var swipe: SwipeSelection?
    @State private var autoScroll: Task<Void, Never>?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: LibraryLayout.gap), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(alignment: .firstTextBaseline) {
                    Text(isSelecting ? selectionTitle : "Tus vídeos")
                        .typeStyle(.tituloPantalla)
                        .foregroundStyle(Color.pino)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Spacing.s)
                    if !clips.isEmpty {
                        Button(isSelecting ? "Cancelar" : "Seleccionar") {
                            isSelecting.toggle()
                            selection = []
                        }
                        .buttonStyle(SelectCapsuleStyle())
                    }
                }
                .padding(.horizontal, Spacing.textMargin - Spacing.cardMargin)
                if isSelecting {
                    Button(selection.count == clips.count ? "Quitar la selección" : "Seleccionar todo") {
                        selection = selection.count == clips.count ? [] : Set(clips.map(\.id))
                    }
                    .typeStyle(.etiqueta)
                    .foregroundStyle(Color.texto2)
                    .padding(.horizontal, Spacing.textMargin - Spacing.cardMargin)
                }
                if clips.isEmpty {
                    Text("Aún no hay vídeos. Graba tu primer golpe desde Inicio.")
                        .typeStyle(.sub)
                        .foregroundStyle(Color.texto2)
                        .padding(.horizontal, Spacing.textMargin - Spacing.cardMargin)
                } else {
                    LazyVGrid(columns: columns, spacing: LibraryLayout.gap) {
                        ForEach(clips) { clip in
                            Button { isSelecting ? toggle(clip) : open(clip) } label: {
                                ClipThumbnail(clip: clip, tracer: tracer(for: clip), swing: swing(for: clip),
                                              progress: queue.activeClipID == clip.id ? queue.live.progress : nil)
                                    .overlay { if isSelecting { SelectionMark(isSelected: selection.contains(clip.id)) } }
                            }
                            .buttonStyle(.plain)
                            .contextMenu { if !isSelecting { menu(for: clip) } }
                            .accessibilityAddTraits(isSelecting && selection.contains(clip.id) ? .isSelected : [])
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.contentSpace)) } action: { frame in
                                itemFrames[clip.id] = frame
                            }
                        }
                    }
                    // Solo en "Seleccionar"; un toque sigue siendo un toque (hace falta mover 10 pt).
                    .simultaneousGesture(swipeGesture, including: isSelecting ? .all : .subviews)
                }
            }
            .padding(.horizontal, Spacing.cardMargin)
            .padding(.vertical, Spacing.s)
            .coordinateSpace(.named(Self.contentSpace))
            .onGeometryChange(for: CGPoint.self) { $0.frame(in: .named(Self.viewportSpace)).origin } action: { origin in
                contentOrigin = origin
            }
        }
        .coordinateSpace(.named(Self.viewportSpace))
        .scrollPosition($scrollPosition)
        // Mientras se selecciona deslizando, el dedo no mueve la lista (lo hace el desplazamiento automático).
        .scrollDisabled(swipe?.isActive == true)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in
            scrollOffset = offset
        }
        .onScrollGeometryChange(for: CGFloat.self) { max($0.contentSize.height - $0.containerSize.height + $0.contentInsets.bottom, 0) } action: { _, value in
            maximumScrollOffset = value
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            viewportHeight = height
        }
        .onChange(of: isSelecting) { _, selecting in
            if !selecting { endSwipe() }
        }
        .background(Color.bola)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if isSelecting { selectionBar }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .onAppear {
            if demoSelecting, selection.isEmpty {
                isSelecting = true
                selection = Set(clips.prefix(2).map(\.id))
            }
        }
        .onChange(of: clips.map(\.id)) { _, ids in
            // Si un vídeo desaparece (borrado), sale también de la selección.
            selection.formIntersection(ids)
        }
        .confirmationDialog(selection.count == 1 ? "¿Borrar este vídeo?" : "¿Borrar \(selection.count) vídeos?",
                            isPresented: $asksToDeleteSelection, titleVisibility: .visible) {
            Button(selection.count == 1 ? "Borrar 1 vídeo" : "Borrar \(selection.count) vídeos", role: .destructive) {
                deleteSelection()
            }
        } message: {
            Text("Se borran de Trazo con sus tracers y análisis. Lo que guardaste en Fotos sigue allí.")
        }
        .fullScreenCover(item: $openClip) { clip in
            ClipDetailView(clip: clip)
        }
        .fullScreenCover(item: Binding(get: { openTracer.map(TracerSheet.init) }, set: { openTracer = $0?.id })) { sheet in
            TracerReviewView(clipID: sheet.id)
        }
        .fullScreenCover(item: Binding(get: { openSwingResult.map(TracerSheet.init) }, set: { openSwingResult = $0?.id })) { sheet in
            SwingResultView(clipID: sheet.id)
        }
        .confirmationDialog(failedClip.flatMap { tracer(for: $0)?.failureReason } ?? "El tracer ha fallado.",
                            isPresented: Binding(get: { failedClip != nil }, set: { if !$0 { failedClip = nil } }),
                            titleVisibility: .visible, presenting: failedClip) { clip in
            let result = tracer(for: clip)
            if result?.needsBall == true {
                Button("Tocar la bola") { navigator.open(.tracerProcessing(clip.id)) }
            }
            if result?.analysis != nil {
                Button("Abrir en Ajusta el vuelo") { openTracer = clip.id }
            }
            Button("Volver a intentar") {
                queue.retry(clip.id, manualBall: nil)
                navigator.open(.tracerProcessing(clip.id))
            }
            Button("Ver el vídeo") { openClip = clip }
        }
        .confirmationDialog("¿Borrar este vídeo?", isPresented: Binding(get: { clipToDelete != nil }, set: { if !$0 { clipToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                if let clip = clipToDelete { ClipSaver.delete(clip, in: context) }
                clipToDelete = nil
            }
        } message: {
            Text("Se borra de Trazo. Si lo guardaste en Fotos, allí sigue.")
        }
        .overlay(alignment: .bottom) { Toast(message: $message) }
    }

    // MARK: Seleccionar

    private var selectionTitle: String {
        switch selection.count {
        case 0: "Selecciona vídeos"
        case 1: "1 vídeo"
        default: "\(selection.count) vídeos"
        }
    }

    private var selectedClips: [Clip] { clips.filter { selection.contains($0.id) } }

    /// Los archivos que se pueden compartir o guardar (los de demostración no tienen archivo propio).
    private var selectedFiles: [URL] { selectedClips.filter { !$0.isDemo }.map(\.fileURL) }

    // MARK: Deslizar para seleccionar

    private static let contentSpace = "library-content"
    private static let viewportSpace = "library-viewport"

    /// Un deslizamiento en curso: con qué selección empezó, desde qué vídeo y si marca o desmarca.
    private struct SwipeSelection {
        var isActive: Bool
        var base: Set<UUID> = []
        var startIndex = 0
        var selects = true
        var lastPoint: CGPoint = .zero
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named(Self.viewportSpace))
            .onChanged { value in swipeChanged(value) }
            .onEnded { _ in endSwipe() }
    }

    /// Como en Fotos: si el dedo sale de lado desde un vídeo, empieza a seleccionar; si sale en
    /// vertical, es un desplazamiento normal y no se toca nada.
    private func swipeChanged(_ value: DragGesture.Value) {
        guard isSelecting else { return }
        if swipe == nil {
            let horizontal = abs(value.translation.width) > abs(value.translation.height)
            guard horizontal, let start = index(at: value.startLocation, nearest: false) else {
                swipe = SwipeSelection(isActive: false)
                return
            }
            swipe = SwipeSelection(isActive: true, base: selection, startIndex: start,
                                   selects: !selection.contains(clips[start].id), lastPoint: value.location)
        }
        guard var current = swipe, current.isActive else { return }
        current.lastPoint = value.location
        swipe = current
        applySwipe(at: value.location)
        updateAutoScroll(for: value.location)
    }

    /// Marca (o desmarca) todos los vídeos entre el primero y el que está bajo el dedo, en el orden de
    /// la rejilla; los que quedan fuera del tramo vuelven a como estaban al empezar.
    private func applySwipe(at viewportPoint: CGPoint) {
        guard let current = swipe, current.isActive, let end = index(at: viewportPoint, nearest: true) else { return }
        var updated = current.base
        let range = min(current.startIndex, end)...max(current.startIndex, end)
        for index in range where clips.indices.contains(index) {
            if current.selects { updated.insert(clips[index].id) } else { updated.remove(clips[index].id) }
        }
        if updated != selection { selection = updated }
    }

    /// El vídeo bajo un punto de la pantalla. Con `nearest`, el más cercano (el dedo puede caer en el
    /// hueco entre dos miniaturas o por debajo de la última).
    private func index(at viewportPoint: CGPoint, nearest: Bool) -> Int? {
        let point = CGPoint(x: viewportPoint.x - contentOrigin.x, y: viewportPoint.y - contentOrigin.y)
        if let hit = clips.firstIndex(where: { itemFrames[$0.id]?.contains(point) == true }) { return hit }
        guard nearest else { return nil }
        func distance(_ rect: CGRect) -> CGFloat {
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            return dx * dx + dy * dy
        }
        return clips.indices
            .filter { itemFrames[clips[$0].id] != nil }
            .min { distance(itemFrames[clips[$0].id]!) < distance(itemFrames[clips[$1].id]!) }
    }

    /// Cerca del borde de arriba o de abajo, la lista se desplaza sola mientras el dedo siga ahí, y la
    /// selección sigue al dedo. Abajo se deja sitio para la barra de Compartir y Borrar.
    private func updateAutoScroll(for viewportPoint: CGPoint) {
        let bottomEdge = viewportHeight - 130
        let speed: CGFloat
        if viewportPoint.y > bottomEdge {
            speed = min((viewportPoint.y - bottomEdge) / 6, 14)
        } else if viewportPoint.y < 90 {
            speed = -min((90 - viewportPoint.y) / 6, 14)
        } else {
            speed = 0
        }
        autoScroll?.cancel()
        autoScroll = nil
        guard speed != 0 else { return }
        autoScroll = Task { @MainActor in
            while !Task.isCancelled, swipe?.isActive == true {
                let target = min(max(scrollOffset + speed, 0), maximumScrollOffset)
                if abs(target - scrollOffset) < 0.5 { break }
                scrollPosition.scrollTo(y: target)
                if let point = swipe?.lastPoint { applySwipe(at: point) }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func endSwipe() {
        autoScroll?.cancel()
        autoScroll = nil
        swipe = nil
    }

    private func toggle(_ clip: Clip) {
        if selection.contains(clip.id) { selection.remove(clip.id) } else { selection.insert(clip.id) }
    }

    /// La barra de abajo del modo "Seleccionar", como en Fotos: Compartir, cuántos, Guardar y Borrar.
    private var selectionBar: some View {
        HStack(spacing: Spacing.l) {
            ShareLink(items: selectedFiles) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 20, weight: .regular))
                    .frame(width: Size.minTouch, height: Size.minTouch)
            }
            .disabled(selectedFiles.isEmpty)
            .accessibilityLabel("Compartir")
            Spacer(minLength: 0)
            Text(selection.isEmpty ? "Toca los vídeos" : selectionTitle)
                .typeStyle(.etiqueta)
                .foregroundStyle(Color.pino)
            Spacer(minLength: 0)
            Button { Task { await saveSelection() } } label: {
                Group {
                    if isSavingSelection {
                        ProgressView().tint(Color.pino)
                    } else {
                        Image(systemName: "arrow.down.to.line").font(.system(size: 20, weight: .regular))
                    }
                }
                .frame(width: Size.minTouch, height: Size.minTouch)
            }
            .disabled(selectedFiles.isEmpty || isSavingSelection)
            .accessibilityLabel("Guardar en Fotos")
            Button { asksToDeleteSelection = true } label: {
                Image(systemName: "trash").font(.system(size: 20, weight: .regular))
                    .frame(width: Size.minTouch, height: Size.minTouch)
            }
            .disabled(selection.isEmpty)
            .foregroundStyle(selection.isEmpty ? Color.texto3 : Color.rojoTrazo)
            .accessibilityLabel("Borrar")
        }
        .foregroundStyle(Color.pino)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.xs)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, Spacing.cardMargin)
        .padding(.bottom, Spacing.s)
    }

    /// Guarda en Fotos los vídeos elegidos, uno detrás de otro, y dice cuántos han ido bien.
    private func saveSelection() async {
        let files = selectedFiles
        isSavingSelection = true
        defer { isSavingSelection = false }
        var saved = 0
        var lastError: String?
        for url in files {
            do {
                try await PhotoLibrary.saveVideo(at: url)
                saved += 1
            } catch {
                lastError = error.localizedDescription
            }
        }
        if let lastError, saved < files.count {
            message = saved == 0 ? lastError : "Guardados \(saved) de \(files.count). \(lastError)"
        } else {
            message = saved == 1 ? "1 vídeo guardado en Fotos" : "\(saved) vídeos guardados en Fotos"
        }
    }

    private func deleteSelection() {
        let doomed = selectedClips
        for clip in doomed { ClipSaver.delete(clip, in: context) }
        message = doomed.count == 1 ? "1 vídeo borrado" : "\(doomed.count) vídeos borrados"
        selection = []
        isSelecting = false
    }

    private func tracer(for clip: Clip) -> TracerResult? {
        tracers.first { $0.clipID == clip.id }
    }

    private func swing(for clip: Clip) -> SwingResult? {
        swings.first { $0.clipID == clip.id }
    }

    /// Al tocar un clip: un tracer en cola se sigue en "Creando tu tracer"; uno listo se abre; uno
    /// que falló dice por qué. Un swing se revisa o, si ya está analizado, abre "Tu análisis".
    private func open(_ clip: Clip) {
        if clip.mode == .swing {
            if swing(for: clip)?.analysis?.reviewed == true {
                openSwingResult = clip.id
            } else if !clip.isDemo {
                navigator.open(.swingReview(clip.id))
            } else {
                openClip = clip
            }
            return
        }
        guard !clip.isDemo || tracer(for: clip) != nil else {
            openClip = clip
            return
        }
        switch tracer(for: clip)?.status {
        case nil: navigator.open(.tracerProcessing(clip.id))
        case .pending?, .processing?: navigator.open(.tracerProcessing(clip.id))
        case .ready?: openTracer = clip.id
        case .failed?: failedClip = clip
        }
    }

    @ViewBuilder
    private func menu(for clip: Clip) -> some View {
        if clip.mode == .tracer && !clip.isDemo {
            Button {
                queue.retry(clip.id, manualBall: nil)
                navigator.open(.tracerProcessing(clip.id))
            } label: {
                Label(tracer(for: clip) == nil ? "Crear tracer" : "Volver a crear el tracer", systemImage: "scope")
            }
            Button { openClip = clip } label: { Label("Ver el vídeo", systemImage: "play.fill") }
        }
        if clip.mode == .swing && !clip.isDemo {
            Button { navigator.open(.swingReview(clip.id)) } label: {
                Label(swing(for: clip) == nil ? "Analizar el swing" : "Revisar las posiciones", systemImage: "figure.golf")
            }
            if swing(for: clip)?.analysis?.reviewed == true {
                Button { openSwingResult = clip.id } label: { Label("Ver el análisis", systemImage: "chart.bar") }
            }
            Button { openClip = clip } label: { Label("Ver el vídeo", systemImage: "play.fill") }
        }
        if !clip.isDemo {
            Button {
                let url = clip.fileURL
                Task {
                    do {
                        try await PhotoLibrary.saveVideo(at: url)
                        message = "Guardado en Fotos"
                    } catch {
                        message = error.localizedDescription
                    }
                }
            } label: {
                Label("Guardar original en Fotos", systemImage: "arrow.down.to.line")
            }
        }
        Button(role: .destructive) {
            clipToDelete = clip
        } label: {
            Label("Borrar", systemImage: "trash")
        }
    }
}

/// El botón "Seleccionar" / "Cancelar" de arriba a la derecha: una cápsula pequeña, como en Fotos.
private struct SelectCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typeStyle(.etiqueta)
            .foregroundStyle(Color.pino)
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: 36)
            .background(Color.niebla, in: Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .frame(minHeight: Size.minTouch)
            .contentShape(Capsule())
    }
}

/// La marca de un vídeo en el modo "Seleccionar": un círculo abajo a la derecha que se llena con un
/// visto al elegirlo, y la miniatura se aclara un poco (como en Fotos).
private struct SelectionMark: View {
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.white.opacity(isSelected ? 0.25 : 0)
            Group {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.pino)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.white)
                }
            }
            .font(.system(size: 24, weight: .regular))
            .background(Circle().fill(isSelected ? Color.white : Color.black.opacity(0.15)).padding(2))
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .padding(Spacing.s)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
        .allowsHitTesting(false)
    }
}

/// Miniatura vertical de un clip con su tipo (punto rojo o amarillo), fecha y duración y, en los golpes
/// del Tracer, su estado.
struct ClipThumbnail: View {
    let clip: Clip
    var tracer: TracerResult?
    var swing: SwingResult?
    /// Avance del que se está procesando ahora (de 0 a 1).
    var progress: Double?

    var body: some View {
        Color.niebla
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay {
                if let image = Thumbnailer.load(named: clip.thumbnailName) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .overlay { statusOverlay }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(clip.mode == .tracer ? Color.rojoTrazo : Color.amarillo)
                            .frame(width: Size.chipDot, height: Size.chipDot)
                        Text(LibraryLayout.dayFormat(clip.createdAt))
                    }
                    Text(RecordScreen.clock(clip.duration))
                        .monospacedDigit()
                        .opacity(0.85)
                }
                .typeStyle(.chip)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .padding(Spacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.5)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(clip.mode.title), \(LibraryLayout.dayFormat(clip.createdAt)), \(Int(clip.duration.rounded())) segundos\(statusText.map { ", \($0)" } ?? "")")
    }

    private var statusText: String? {
        switch tracer?.status {
        case .pending?, .processing?: "en proceso"
        case .ready?: "tracer listo"
        case .failed?: "el tracer ha fallado"
        case nil: nil
        }
    }

    /// Estado del tracer encima de la miniatura (docs/02, Tus vídeos).
    @ViewBuilder
    private var statusOverlay: some View {
        switch tracer?.status {
        case .pending?, .processing?:
            ZStack {
                Color.black.opacity(0.35)
                VStack(spacing: Spacing.s) {
                    if let progress {
                        ProgressView(value: progress).progressViewStyle(.circular).tint(.white)
                    } else {
                        ProgressView().tint(.white)
                    }
                    Text("En proceso").typeStyle(.chip).foregroundStyle(.white)
                }
            }
        case .ready?:
            statusChip("Listo", background: Color.pino)
        case .failed?:
            statusChip("Falló", background: Color.rojoTrazo)
        case nil:
            // En un swing analizado, la nota.
            if let total = swing?.scoreTotal {
                statusChip("\(total)", background: Color.pino)
            } else {
                EmptyView()
            }
        }
    }

    private func statusChip(_ text: String, background: Color) -> some View {
        Text(text)
            .typeStyle(.chip)
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, 3)
            .background(background, in: Capsule())
            .padding(Spacing.s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Para abrir un tracer a pantalla completa con `fullScreenCover(item:)`, que necesita algo `Identifiable`.
private struct TracerSheet: Identifiable {
    let id: UUID
}

/// Aviso corto que aparece abajo y se va solo a los 2,5 s.
struct Toast: View {
    @Binding var message: String?

    var body: some View {
        if let message {
            Text(message)
                .typeStyle(.chip)
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s + 2)
                .background(Color.pino, in: Capsule())
                .padding(.bottom, Spacing.xxl)
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(2.5))
                    self.message = nil
                }
                .accessibilityAddTraits(.isStaticText)
        }
    }
}

enum LibraryLayout {
    /// Separación entre miniaturas.
    static let gap: CGFloat = 8

    /// "27 oct": día y mes abreviado en español, siempre igual en cualquier iPhone.
    static func dayFormat(_ date: Date) -> String {
        let months = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"]
        let parts = Calendar.current.dateComponents([.day, .month], from: date)
        return "\(parts.day ?? 1) \(months[(parts.month ?? 1) - 1])"
    }
}
