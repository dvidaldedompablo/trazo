import GolfCore
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Elegir vídeo: abre el selector de Fotos y trae el vídeo a "Tus vídeos".
///
/// Con acceso a Fotos se copia el archivo original: un vídeo a cámara lenta llega a sus 240 fps
/// con los tiempos reales (docs/01). Sin acceso, se importa la copia que da el selector y se avisa
/// de que, si era a cámara lenta, puede venir estirado. Si el vídeo tiene varios golpes,
/// se proponen clips como al grabar con "Corte auto".
struct ImportScreen: View {
    let mode: CaptureMode

    enum Step: Equatable {
        case picking
        case importing
        case done(String)
        case failed(String)
    }

    @State private var item: PhotosPickerItem?
    @State private var showsPicker = false
    @State private var step = Step.picking
    @State private var pending: PendingRecording?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Elegir vídeo")
                .typeStyle(.tituloPantalla)
                .foregroundStyle(Color.pino)
                .accessibilityAddTraits(.isHeader)
            switch step {
            case .picking:
                Text(mode == .tracer ? "Elige el vídeo de un golpe." : "Elige el vídeo de un swing.")
                    .typeStyle(.sub)
                    .foregroundStyle(Color.texto2)
                Button { showsPicker = true } label: { Label("Abrir Fotos", systemImage: "photo.on.rectangle") }
                    .buttonStyle(.principal)
            case .importing:
                HStack(spacing: Spacing.m) {
                    ProgressView()
                    Text("Preparando el vídeo…").typeStyle(.sub).foregroundStyle(Color.texto2)
                }
            case let .done(text):
                Text(text).typeStyle(.sub).foregroundStyle(Color.texto2)
                NavigationLink(value: HomeDestination.library) { Label("Ver Tus vídeos", systemImage: "film.stack") }
                    .buttonStyle(.principal)
            case let .failed(text):
                Label(text, systemImage: "exclamationmark.triangle")
                    .typeStyle(.sub)
                    .foregroundStyle(Color.pino)
                Button { showsPicker = true } label: { Text("Elegir otro vídeo") }
                    .buttonStyle(.secundario)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.textMargin)
        .padding(.top, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bola)
        .navigationBarTitleDisplayMode(.inline)
        // `photoLibrary: .shared()` hace que el elemento elegido traiga su identificador de Fotos,
        // con el que se puede pedir el archivo original.
        .photosPicker(isPresented: $showsPicker, selection: $item, matching: .videos,
                      preferredItemEncoding: .current, photoLibrary: .shared())
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task { await importVideo(newItem) }
        }
        .onChange(of: showsPicker) { _, isShown in
            // Si se cierra el selector sin elegir nada nada más entrar, se vuelve atrás.
            if !isShown, item == nil, step == .picking { dismiss() }
        }
        .task {
            // El selector se abre un instante después de entrar: abrirlo a la vez que la animación
            // de la navegación puede hacer que iOS no lo enseñe.
            guard step == .picking, item == nil else { return }
            try? await Task.sleep(for: .milliseconds(400))
            showsPicker = true
        }
        .sheet(item: $pending) { pending in
            ClipPickerView(pending: pending) { selection, keepFull in
                self.pending = nil
                Task { await save(pending, selection: selection, keepFull: keepFull) }
            }
            .interactiveDismissDisabled()
        }
    }

    private func importVideo(_ item: PhotosPickerItem) async {
        step = .importing
        do {
            let (url, isOriginal) = try await copyVideo(item)
            var analyzed = try await RecordingAnalyzer.analyze(url, mode: mode, origin: .imported)
            analyzed.mayBeStretched = !isOriginal && analyzed.info.nominalFrameRate <= 61
            if analyzed.windows.count >= 2 {
                pending = analyzed
            } else {
                try await ClipSaver.saveWhole(analyzed, in: context)
                step = .done(doneText(count: 1, stretched: analyzed.mayBeStretched))
            }
        } catch {
            step = .failed("No se ha podido importar el vídeo: \(error.localizedDescription)")
        }
        self.item = nil
    }

    /// Trae el vídeo a la carpeta temporal: el original de Fotos si hay permiso; si no, la copia del selector.
    private func copyVideo(_ item: PhotosPickerItem) async throws -> (URL, isOriginal: Bool) {
        if let identifier = item.itemIdentifier {
            let access = await PhotoLibrary.readAccess()
            if access == .authorized || access == .limited {
                let destination = MediaStore.temporaryURL(extension: "mov")
                if (try? await PhotoLibrary.copyOriginalVideo(localIdentifier: identifier, to: destination)) != nil {
                    return (destination, true)
                }
            }
        }
        guard let movie = try await item.loadTransferable(type: MovieFile.self) else {
            throw PhotoLibraryError.assetNotFound
        }
        return (movie.url, false)
    }

    private func save(_ pending: PendingRecording, selection: [Bool], keepFull: Bool) async {
        guard selection.contains(true) || keepFull else {
            MediaStore.removeIfPresent(pending.sourceURL)
            step = .picking
            return
        }
        step = .importing
        do {
            let clips = try await ClipSaver.save(pending, selection: selection, keepFullRecording: keepFull, in: context)
            step = .done(doneText(count: clips.count, stretched: pending.mayBeStretched))
        } catch {
            step = .failed("No se han podido guardar los clips: \(error.localizedDescription)")
        }
    }

    private func doneText(count: Int, stretched: Bool) -> String {
        var text = count == 1 ? "Listo: el vídeo está en Tus vídeos." : "Listo: \(count) vídeos en Tus vídeos."
        if stretched {
            text += " Sin acceso a Fotos, un vídeo a cámara lenta llega con la cámara lenta aplicada y las duraciones pueden salir mal."
        }
        return text
    }
}

/// Un vídeo que llega del selector de Fotos como archivo. El sistema lo deja en una carpeta
/// que borra enseguida, así que se copia a la carpeta temporal de la app.
struct MovieFile: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = MediaStore.temporaryURL(extension: ext)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return MovieFile(url: destination)
        }
    }
}
