import GolfCore
import SwiftData
import SwiftUI
import UIKit

/// Tus vídeos (docs/02, pantalla 10): rejilla de miniaturas verticales con el tipo, la fecha y la duración.
/// Al mantener pulsado un clip: "Guardar original en Fotos" y "Borrar".
struct LibraryView: View {
    // @Query lee de SwiftData y vuelve a dibujar la vista cuando cambia la biblioteca.
    @Query(sort: \Clip.createdAt, order: .reverse) private var clips: [Clip]
    @Environment(\.modelContext) private var context
    @State private var message: String?
    @State private var clipToDelete: Clip?

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
                            NavigationLink(value: clip) {
                                ClipThumbnail(clip: clip)
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
        .navigationDestination(for: Clip.self) { clip in
            ClipDetailView(clip: clip)
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

    @ViewBuilder
    private func menu(for clip: Clip) -> some View {
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

/// Miniatura vertical de un clip con su tipo (punto rojo o amarillo), fecha y duración.
struct ClipThumbnail: View {
    let clip: Clip

    var body: some View {
        Color.niebla
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay {
                if let image = Thumbnailer.load(named: clip.thumbnailName) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
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
            .accessibilityLabel("\(clip.mode.title), \(LibraryLayout.dayFormat(clip.createdAt)), \(Int(clip.duration.rounded())) segundos")
    }
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
