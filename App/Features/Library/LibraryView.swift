import GolfCore
import SwiftData
import SwiftUI
import UIKit

/// Tus vídeos (docs/02, pantalla 10): rejilla de miniaturas verticales con el tipo, la fecha y la duración.
/// Los golpes del Tracer llevan su estado: "En proceso" con el avance, "Listo" o "Falló".
/// Al mantener pulsado un clip: "Guardar original en Fotos", el tracer y "Borrar".
struct LibraryView: View {
    // @Query lee de SwiftData y vuelve a dibujar la vista cuando cambia la biblioteca.
    @Query(sort: \Clip.createdAt, order: .reverse) private var clips: [Clip]
    @Query private var tracers: [TracerResult]
    @Environment(\.modelContext) private var context
    @Environment(TracerQueue.self) private var queue
    @Environment(\.homeNavigator) private var navigator
    @State private var message: String?
    @State private var clipToDelete: Clip?
    /// Clip abierto: es una pantalla de vídeo (negra) y se abre a pantalla completa por encima.
    @State private var openClip: Clip?
    /// Tracer listo abierto (también a pantalla completa).
    @State private var openTracer: UUID?
    /// Golpe que falló y se ha tocado: se enseña el motivo y qué hacer.
    @State private var failedClip: Clip?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: LibraryLayout.gap), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("Tus vídeos")
                    .typeStyle(.tituloPantalla)
                    .foregroundStyle(Color.pino)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, Spacing.textMargin - Spacing.cardMargin)
                if clips.isEmpty {
                    Text("Aún no hay vídeos. Graba tu primer golpe desde Inicio.")
                        .typeStyle(.sub)
                        .foregroundStyle(Color.texto2)
                        .padding(.horizontal, Spacing.textMargin - Spacing.cardMargin)
                } else {
                    LazyVGrid(columns: columns, spacing: LibraryLayout.gap) {
                        ForEach(clips) { clip in
                            Button { open(clip) } label: {
                                ClipThumbnail(clip: clip, tracer: tracer(for: clip),
                                              progress: queue.activeClipID == clip.id ? queue.live.progress : nil)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { menu(for: clip) }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.cardMargin)
            .padding(.vertical, Spacing.s)
        }
        .background(Color.bola)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $openClip) { clip in
            ClipDetailView(clip: clip)
        }
        .fullScreenCover(item: Binding(get: { openTracer.map(TracerSheet.init) }, set: { openTracer = $0?.id })) { sheet in
            TracerReviewView(clipID: sheet.id)
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

    private func tracer(for clip: Clip) -> TracerResult? {
        tracers.first { $0.clipID == clip.id }
    }

    /// Al tocar un clip: los de Swing (y los de Tracer sin tracer) se ven; un tracer en cola se sigue en
    /// "Creando tu tracer"; uno listo se abre; uno que falló dice por qué.
    private func open(_ clip: Clip) {
        guard clip.mode == .tracer, !clip.isDemo || tracer(for: clip) != nil else {
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

/// Miniatura vertical de un clip con su tipo (punto rojo o amarillo), fecha y duración y, en los golpes
/// del Tracer, su estado.
struct ClipThumbnail: View {
    let clip: Clip
    var tracer: TracerResult?
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
            EmptyView()
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
