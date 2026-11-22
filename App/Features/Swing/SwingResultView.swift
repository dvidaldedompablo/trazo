import AVKit
import GolfCore
import SwiftData
import SwiftUI
import UIKit

/// Tu análisis (docs/02, pantalla s07): la miniatura con las líneas, la nota, el ritmo y lo primero
/// a trabajar. "Ver informe" abre el informe completo; "Guardar" genera el vídeo del análisis
/// (etapa 8) y lo deja en Fotos.
struct SwingResultView: View {
    let clipID: UUID
    var demoImage: UIImage?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var results: [SwingResult]
    @Query private var clips: [Clip]
    @State private var thumbnail: UIImage?
    @State private var showsReport = false
    @State private var showsPreview = false
    @State private var message: String?
    /// Duración del vídeo del análisis ya generado (s), para la etiqueta "1:18".
    @State private var videoDuration: Double?
    /// Avance de la generación del vídeo (etapa 8); `nil` cuando no está en marcha.
    @State private var exportProgress: ExportProgress?

    init(clipID: UUID, demoImage: UIImage? = nil) {
        self.clipID = clipID
        self.demoImage = demoImage
        let id = clipID
        _results = Query(filter: #Predicate<SwingResult> { $0.clipID == id })
        _clips = Query(filter: #Predicate<Clip> { $0.id == id })
    }

    private var result: SwingResult? { results.first }
    private var clip: Clip? { clips.first }
    private var analysis: SwingAnalysis? { demoImage != nil ? DemoData.swingAnalysis(reviewed: true) : result?.analysis }

    var body: some View {
        let analysis = analysis
        let score = analysis?.score()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                Text("Tu análisis")
                    .typeStyle(.tituloPantalla)
                    .foregroundStyle(Color.pino)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, Spacing.m)
                if let analysis, let score {
                    HStack(alignment: .top, spacing: Spacing.m) {
                        thumbnailCard(analysis)
                        VStack(spacing: Spacing.m) {
                            scoreCard(score)
                            tempoCard(analysis)
                        }
                    }
                    .padding(.top, Spacing.l)
                    priorityCard(score)
                        .padding(.top, Spacing.m)
                    listenRow
                        .padding(.top, Spacing.m)
                }
            }
            .padding(.horizontal, Spacing.textMargin)
            .padding(.bottom, 120)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.bola)
        .preferredColorScheme(.light)
        .safeAreaInset(edge: .bottom) { bottomButtons }
        .overlay { exportOverlay }
        .overlay(alignment: .bottom) { Toast(message: $message).padding(.bottom, 90) }
        .task { await loadThumbnail() }
        .sheet(isPresented: $showsReport) {
            if let analysis {
                SwingReportView(analysis: analysis)
            }
        }
        .fullScreenCover(isPresented: $showsPreview) {
            if let analysis {
                ScriptPreviewView(analysis: analysis, clipURL: demoImage == nil ? clip?.fileURL : nil,
                                  demoImage: demoImage)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 19, weight: .medium)) }
                .foregroundStyle(Color.pino)
                .frame(width: Size.minTouch, height: Size.minTouch, alignment: .leading)
                .accessibilityLabel("Cerrar")
            Spacer()
            if let url = result?.videoURL {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 19, weight: .medium))
                }
                .foregroundStyle(Color.pino)
                .frame(width: Size.minTouch, height: Size.minTouch, alignment: .trailing)
                .accessibilityLabel("Compartir el vídeo")
            }
        }
    }

    // MARK: Tarjetas

    private func thumbnailCard(_ analysis: SwingAnalysis) -> some View {
        ZStack {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    Color.niebla
                }
            }
            SwingOverlayView(analysis: analysis, position: .address,
                             frameIndex: analysis.phases[.address].frameIndex)
            Button { showsPreview = true } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.pino)
                    .frame(width: 64, height: 64)
                    .background(Color.papel.opacity(0.92), in: Circle())
            }
            .accessibilityLabel("Escuchar el análisis con subtítulos")
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if let duration = videoDurationText {
                Text(duration)
                    .typeStyle(.chip)
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .padding(.horizontal, Spacing.s)
                    .padding(.vertical, 4)
                    .background(Color.pino.opacity(0.84), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(Spacing.s)
            }
        }
    }

    /// Duración del vídeo generado ("1:18"), cuando existe.
    private var videoDurationText: String? {
        guard let seconds = videoDuration, seconds.isFinite, seconds > 0 else { return nil }
        return "\(Int(seconds) / 60):" + String(format: "%02d", Int(seconds) % 60)
    }

    private func scoreCard(_ score: SwingScore) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Nota")
                .typeStyle(.etiqueta)
                .foregroundStyle(Color.texto2)
            if let total = score.total {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(total)")
                        .typeStyle(.displayL)
                        .foregroundStyle(Color.pino)
                    Text("/100")
                        .typeStyle(.displayM)
                        .foregroundStyle(Color.texto3)
                }
                // Lato es más ancha que Archivo: la nota nunca se parte en dos líneas; si no cabe,
                // se encoge un poco (un "100/100" en una tarjeta estrecha).
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Text(score.label)
                    .typeStyle(.chip)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, 7)
                    .background(Color.pino, in: Capsule())
            } else {
                Text("Sin nota esta vez")
                    .typeStyle(.sub)
                    .foregroundStyle(Color.texto2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.l)
        .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }

    private func tempoCard(_ analysis: SwingAnalysis) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Ritmo")
                .typeStyle(.etiqueta)
                .foregroundStyle(Color.texto2)
            if let tempo = analysis.phases.tempo {
                Text("\(SpanishFormat.number(tempo, decimals: 1)) : 1")
                    .typeStyle(.displayM)
                    .foregroundStyle(Color.pino)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Subida \(SpanishFormat.seconds(analysis.phases.backswingDuration, decimals: 2))")
                Text("Bajada \(SpanishFormat.seconds(analysis.phases.downswingDuration, decimals: 2))")
            }
            .typeStyle(.sub)
            .foregroundStyle(Color.texto2)
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.l)
        .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }

    private func priorityCard(_ score: SwingScore) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Text("1")
                .typeStyle(.tituloTarjeta)
                .foregroundStyle(Color.pino)
                .frame(width: 44, height: 44)
                .overlay(Rectangle().strokeBorder(Color.pino, lineWidth: 2.5))
            VStack(alignment: .leading, spacing: 4) {
                Text("Lo primero a trabajar")
                    .typeStyle(.filaTitulo)
                    .foregroundStyle(Color.pino)
                Text(priorityText(score))
                    .typeStyle(.sub)
                    .foregroundStyle(Color.texto2)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }

    private func priorityText(_ score: SwingScore) -> String {
        guard let priority = score.priority else {
            return "Nada urgente: sigue puliendo lo que ya haces bien."
        }
        let fault = FaultLibrary.fault(priority)
        return "\(fault.reportLabel). \(fault.exercise)"
    }

    private var listenRow: some View {
        Button { showsPreview = true } label: {
            Label("Escuchar el guion con subtítulos", systemImage: "waveform")
                .typeStyle(.filaTitulo)
                .foregroundStyle(Color.pino)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.l)
                .background(Color.niebla, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        }
    }

    private var bottomButtons: some View {
        HStack(spacing: Spacing.m) {
            Button { showsReport = true } label: { Text("Ver informe") }
                .buttonStyle(.secundario)
            Button { generateVideo() } label: {
                Label(result?.videoFileName == nil ? "Guardar" : "Guardado en Fotos",
                      systemImage: "arrow.down.to.line")
            }
            .buttonStyle(.principal)
            .disabled(exportProgress != nil || demoImage != nil || result?.videoFileName != nil)
        }
        .padding(.horizontal, Spacing.textMargin)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.m)
        .background(Color.bola)
    }

    // MARK: Generar el vídeo (etapa 8)

    @ViewBuilder
    private var exportOverlay: some View {
        if let exportProgress {
            ZStack {
                Color.black.opacity(0.45).ignoresSafeArea()
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text("Creando tu vídeo")
                        .typeStyle(.tituloTarjeta)
                        .foregroundStyle(Color.pino)
                    ProgressView(value: exportProgress.fraction)
                        .tint(Color.pino)
                    Text(exportProgress.stepName)
                        .typeStyle(.sub)
                        .foregroundStyle(Color.texto2)
                }
                .padding(Spacing.xl)
                .frame(maxWidth: 320)
                .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            }
        }
    }

    private func generateVideo() {
        guard exportProgress == nil, let clip, let analysis, let result else { return }
        exportProgress = ExportProgress(stepName: "Preparando el guion", fraction: 0)
        let short = UserDefaults.standard.bool(forKey: SettingsKey.shortAnalysisVideo)
        let subtitles = UserDefaults.standard.object(forKey: SettingsKey.analysisSubtitles) as? Bool ?? true
        Task {
            do {
                let output = try await AnalysisVideoExporter.export(
                    clipURL: clip.fileURL, analysis: analysis, short: short, subtitles: subtitles
                ) { progress in
                    Task { @MainActor in exportProgress = progress }
                }
                let name = "analisis-\(result.id.uuidString).mp4"
                try MediaStore.moveIntoClips(output, named: name)
                result.videoFileName = name
                result.videoIsShort = short
                try? context.save()
                try await PhotoLibrary.saveVideo(at: MediaStore.url(forFile: name))
                videoDuration = try? await AVURLAsset(url: MediaStore.url(forFile: name)).load(.duration).seconds
                message = "Guardado en Fotos"
            } catch {
                message = "No se ha podido crear el vídeo: \(error.localizedDescription)"
            }
            exportProgress = nil
        }
    }

    private func loadThumbnail() async {
        if let url = result?.videoURL {
            videoDuration = try? await AVURLAsset(url: url).load(.duration).seconds
        }
        if let demoImage {
            thumbnail = demoImage
            return
        }
        guard let clip, let analysis else { return }
        let time = analysis.poses[analysis.phases[.address].frameIndex].time
        if let data = try? await FrameGrabber.jpeg(from: clip.fileURL, at: time, exact: false) {
            thumbnail = UIImage(data: data)
        }
    }
}

/// El informe completo (docs/04, puntos 6 y 7): puntos fuertes, a mejorar con ejercicios,
/// la prioridad y el pie de honestidad.
struct SwingReportView: View {
    let analysis: SwingAnalysis
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let measurements = analysis.measurements()
        let score = analysis.score()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if !score.strengths.isEmpty {
                        section("Puntos fuertes") {
                            ForEach(score.strengths, id: \.rawValue) { phase in
                                HStack(spacing: Spacing.m) {
                                    Circle().strokeBorder(Color.pino, lineWidth: 2.5).frame(width: 22, height: 22)
                                    Text(phase.title).typeStyle(.cuerpo).foregroundStyle(Color.pino)
                                }
                            }
                        }
                    }
                    if !score.improvements.isEmpty {
                        section("A mejorar") {
                            ForEach(Array(score.improvements.enumerated()), id: \.offset) { index, item in
                                HStack(alignment: .top, spacing: Spacing.m) {
                                    Text("\(index + 1)")
                                        .typeStyle(.etiqueta)
                                        .foregroundStyle(Color.pino)
                                        .frame(width: 26, height: 26)
                                        .overlay(Rectangle().strokeBorder(Color.pino, lineWidth: 2))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(FaultLibrary.fault(item.fault).reportLabel)
                                            .typeStyle(.filaTitulo)
                                            .foregroundStyle(Color.pino)
                                        Text("Ejercicio: \(FaultLibrary.fault(item.fault).exercise)")
                                            .typeStyle(.sub)
                                            .foregroundStyle(Color.texto2)
                                    }
                                }
                            }
                        }
                    }
                    if let priority = score.priority {
                        section("Prioridad nº 1") {
                            Text(FaultLibrary.fault(priority).reportLabel)
                                .typeStyle(.filaTitulo)
                                .foregroundStyle(Color.pino)
                            if score.priorityEffect != nil {
                                Text("Es la causa de otros fallos de tu swing: al corregirla, caerán con ella.")
                                    .typeStyle(.sub)
                                    .foregroundStyle(Color.texto2)
                            }
                        }
                    }
                    if !measurements.unavailable.isEmpty {
                        section("Sin medir") {
                            Text("No se han podido medir: \(measurements.unavailable.map(\.title).joined(separator: ", ")). No se inventan.")
                                .typeStyle(.sub)
                                .foregroundStyle(Color.texto2)
                        }
                    }
                    Text("Medidas aproximadas, vídeo 2D a \(SpanishFormat.number(analysis.frameRate)) fps. Revisa el informe con tu profesor.")
                        .typeStyle(.nota)
                        .foregroundStyle(Color.texto3)
                }
                .padding(Spacing.textMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.bola)
            .navigationTitle("Informe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hecho") { dismiss() }
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(title)
                .typeStyle(.etiqueta)
                .foregroundStyle(Color.texto2)
            content()
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }
}

/// Avance de la generación del vídeo del análisis.
struct ExportProgress: Sendable, Equatable {
    var stepName: String
    var fraction: Double
}
