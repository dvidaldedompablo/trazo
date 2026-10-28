@preconcurrency import AVFoundation
import GolfCore
import SwiftData
import SwiftUI
import UIKit

/// Un clip a pantalla completa (fondo negro): se reproduce en bucle; arriba sus datos y abajo
/// "Guardar original en Fotos" y "Borrar". En modo diagnóstico, un panel con fps reales,
/// duración e impacto encontrado.
struct ClipDetailView: View {
    let clip: Clip

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.diagnostics) private var diagnostics = false
    @State private var player: AVPlayer?
    @State private var report: DiagnosticReport?
    @State private var message: String?
    @State private var confirmsDelete = false

    var body: some View {
        ZStack {
            Color.escenario
            if clip.isDemo {
                if let image = Thumbnailer.load(named: clip.thumbnailName) {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            } else if let player {
                PlayerLayerView(player: player)
                    .onTapGesture { player.timeControlStatus == .playing ? player.pause() : player.play() }
            }
            VStack(spacing: Spacing.m) {
                topBar
                if diagnostics { diagnosticsPanel }
                Spacer()
                actions
            }
            .padding(.horizontal, Spacing.cardMargin)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.l)
            .overlay(alignment: .bottom) { Toast(message: $message).padding(.bottom, 70) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task { await prepare() }
        .onDisappear { player?.pause() }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { _ in
            // En bucle: al acabar, vuelve al principio.
            player?.seek(to: .zero)
            player?.play()
        }
        .confirmationDialog("¿Borrar este vídeo?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                ClipSaver.delete(clip, in: context)
                dismiss()
            }
        } message: {
            Text("Se borra de Trazo. Si lo guardaste en Fotos, allí sigue.")
        }
    }

    private var topBar: some View {
        HStack(spacing: Spacing.s) {
            Button { dismiss() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.crystal)
                .accessibilityLabel("Atrás")
            Spacer(minLength: 0)
            Chip(title: clip.mode.title, dotColor: clip.mode == .tracer ? .rojoTrazo : .amarillo, surface: .video)
            Chip(title: "\(Int(clip.frameRate.rounded())) fps", surface: .video)
            Chip(title: RecordScreen.clock(clip.duration), surface: .video)
        }
    }

    private var actions: some View {
        HStack(spacing: Spacing.m) {
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
                .buttonStyle(CrystalButtonStyle(outline: .capsule))
            }
            Spacer(minLength: 0)
            Button { confirmsDelete = true } label: { Image(systemName: "trash") }
                .buttonStyle(.crystal)
                .accessibilityLabel("Borrar")
        }
    }

    @ViewBuilder
    private var diagnosticsPanel: some View {
        let lines: [String] = {
            guard let report else { return ["Midiendo…"] }
            let info = report.info
            var lines = [
                "fps reales: \(info.measuredFrameRate.map { SpanishFormat.number($0, decimals: 2) } ?? "?") (declarados \(SpanishFormat.number(info.nominalFrameRate, decimals: 2)))",
                "Fotogramas: \(info.frameCount.map(String.init) ?? "?") · duración \(SpanishFormat.seconds(info.duration, decimals: 3))",
                "\(info.width) x \(info.height) · \(info.codec) · audio \(info.hasAudio ? "sí" : "no")",
            ]
            if !info.hasAudio {
                lines.append("Sin audio: no se puede buscar el impacto.")
            } else if report.impacts.isEmpty {
                lines.append("No se ha oído el impacto.")
            } else {
                let strongest = report.impacts.max { $0.strength < $1.strength }
                for impact in report.impacts {
                    let mark = impact == strongest ? " (el más fuerte)" : ""
                    lines.append("Impacto a \(SpanishFormat.seconds(impact.time, decimals: 3)), \(SpanishFormat.number(impact.prominence)) MAD\(mark)")
                }
            }
            return lines
        }()
        Text(lines.joined(separator: "\n"))
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.m)
            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.thumbnail))
            .accessibilityLabel("Diagnóstico")
            .accessibilityValue(lines.joined(separator: ". "))
    }

    private func prepare() async {
        guard !clip.isDemo else { return }
        let url = clip.fileURL
        let newPlayer = AVPlayer(url: url)
        newPlayer.isMuted = false
        player = newPlayer
        newPlayer.play()
        if diagnostics {
            report = try? await DiagnosticReport.measure(url)
        }
    }
}

/// Lo que enseña el modo diagnóstico de un clip: el archivo medido y los impactos encontrados.
struct DiagnosticReport: Sendable {
    let info: VideoInfo
    let impacts: [Impact]

    @concurrent
    static func measure(_ url: URL) async throws -> DiagnosticReport {
        let info = try await VideoInspector.info(of: url, measureFrames: true)
        let samples = info.hasAudio ? try await AudioExtractor.monoSamples(from: url) : []
        return DiagnosticReport(info: info, impacts: ImpactDetector.detect(samples: samples, sampleRate: AudioExtractor.sampleRate))
    }
}

/// Vídeo sin controles del sistema (los nuestros van encima): una capa `AVPlayerLayer`.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.playerLayer.player = player
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
