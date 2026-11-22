import AVFAudio
import GolfCore
import SwiftUI
import UIKit

/// Vista previa del guion (docs/00, etapa 7): reproduce la voz con los subtítulos palabra a
/// palabra sobre el fotograma de cada fase, antes de generar el vídeo. Lo que se oye aquí es
/// exactamente la pista que llevará el vídeo (misma síntesis y mismos silencios).
struct ScriptPreviewView: View {
    let analysis: SwingAnalysis
    /// El clip real; `nil` en la demo de las capturas.
    var clipURL: URL?
    var demoImage: UIImage?

    @Environment(\.dismiss) private var dismiss
    @State private var model = ScriptPreviewModel()

    var body: some View {
        ZStack {
            Color.escenario.ignoresSafeArea()
            GeometryReader { proxy in
                if let image = model.backgroundImage ?? demoImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .opacity(0.85)
                }
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 17, weight: .regular)) }
                        .buttonStyle(.crystal)
                        .accessibilityLabel("Cerrar")
                    Spacer()
                    if let block = model.currentBlockName {
                        Chip(title: block, surface: .video)
                    }
                    Spacer()
                    Color.clear.frame(width: Size.glassButton, height: Size.glassButton)
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.cardMargin)
            .padding(.top, Spacing.s)

            // Subtítulos hacia el 75 % de la altura (docs/02).
            VStack {
                Spacer()
                subtitle
                    .padding(.horizontal, Spacing.cardMargin)
                Spacer().frame(height: 120)
                controls
                    .padding(.bottom, Spacing.l)
            }

            if model.isPreparing {
                VStack(spacing: Spacing.m) {
                    ProgressView().tint(.white).controlSize(.large)
                    Text("Preparando la voz…").typeStyle(.cuerpo).foregroundStyle(.white)
                }
                .padding(Spacing.xl)
                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            }
        }
        .preferredColorScheme(.dark)
        .task { await model.prepare(analysis: analysis, clipURL: clipURL) }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private var subtitle: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { _ in
            let (said, pending) = model.currentWords()
            if !said.isEmpty || !pending.isEmpty {
                (Text(said).foregroundStyle(.white)
                    + Text(pending).foregroundStyle(.white.opacity(0.42)))
                    .font(Typography.fixedFont(for: .tituloTarjeta, size: 26))
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(said + pending)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: Spacing.l) {
            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 19, weight: .semibold))
            }
            .buttonStyle(.crystal)
            .disabled(model.isPreparing)
            .accessibilityLabel(model.isPlaying ? "Pausa" : "Reproducir")
        }
    }
}

/// Prepara la pista (síntesis de todas las frases), la reproduce y dice qué palabra suena.
@MainActor
@Observable
final class ScriptPreviewModel {
    var isPreparing = true
    var isPlaying = false
    var backgroundImage: UIImage?
    private(set) var track: VoiceTrack?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var frames: [ScriptBlockKind: UIImage] = [:]
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var backgroundTask: Task<Void, Never>?

    func prepare(analysis: SwingAnalysis, clipURL: URL?) async {
        guard track == nil else { return }
        let script = analysis.script()
        var rendered: [(block: ScriptBlockKind, rendered: RenderedLine)] = []
        let voiceID = VoiceSynthesizer.voice()?.identifier
        for block in script.blocks {
            for line in block.lines {
                if let spoken = try? await VoiceSynthesizer.render(line, voiceIdentifier: voiceID) {
                    rendered.append((block.kind, spoken))
                }
            }
        }
        let built = VoiceTrackBuilder.build(lines: rendered)
        track = built
        let url = MediaStore.temporaryURL(extension: "caf")
        try? VoiceTrackBuilder.writeFile(built, to: url)
        fileURL = url
        player = try? AVAudioPlayer(contentsOf: url)
        // Fotograma de cada fase, para cambiar el fondo con la narración.
        if let clipURL {
            for position in SwingPosition.allCases {
                let time = analysis.poses[analysis.phases[position].frameIndex].time
                if let data = try? await FrameGrabber.jpeg(from: clipURL, at: time, exact: false) {
                    frames[Self.blockFor(position)] = UIImage(data: data)
                }
            }
            backgroundImage = frames[.address]
        }
        isPreparing = false
        togglePlayback()
        // El fondo sigue al bloque que suena (fuera del dibujado, que no se puede tocar el estado ahí).
        backgroundTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, let track = self.track, let player = self.player else { continue }
                if let line = track.lines.last(where: { $0.start <= player.currentTime }),
                   let image = self.frames[line.block], image !== self.backgroundImage {
                    self.backgroundImage = image
                }
            }
        }
    }

    private static func blockFor(_ position: SwingPosition) -> ScriptBlockKind {
        switch position {
        case .address: .address
        case .takeaway: .takeaway
        case .midBackswing: .midBackswing
        case .top: .top
        case .transition: .transition
        case .impact: .impact
        case .finish: .finish
        }
    }

    func togglePlayback() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func stop() {
        backgroundTask?.cancel()
        player?.stop()
        if let fileURL { MediaStore.removeIfPresent(fileURL) }
    }

    var currentBlockName: String? {
        guard let track, let player else { return nil }
        let time = player.currentTime
        guard let line = track.lines.last(where: { $0.start <= time + 0.05 }) else { return nil }
        switch line.block {
        case .hook: return "¿Qué nota le pones?"
        case .slowMotion: return "A cámara lenta"
        case .tempo: return "Ritmo"
        case .score: return "Tu nota"
        case .report: return "Informe"
        case .improveIntro, .improve1, .improve2, .improve3, .improveSummary: return "A mejorar"
        case .address, .takeaway, .midBackswing, .top, .transition, .impact, .finish:
            return SwingPosition(rawValue: blockPosition(line.block))?.title
        }
    }

    private func blockPosition(_ kind: ScriptBlockKind) -> Int {
        switch kind {
        case .address: 1
        case .takeaway: 2
        case .midBackswing: 3
        case .top: 4
        case .transition: 5
        case .impact: 6
        case .finish: 7
        default: 1
        }
    }

    /// El texto de la frase que suena, partido en lo ya dicho y lo que falta.
    func currentWords() -> (said: String, pending: String) {
        guard let track, let player, isPlaying || player.currentTime > 0 else { return ("", "") }
        let time = player.currentTime
        guard let lineIndex = track.lines.lastIndex(where: { $0.start <= time && time <= $0.end + 0.4 })
        else { return ("", "") }
        let words = track.words.filter { $0.line == lineIndex }
        let said = words.filter { $0.time <= time }.map(\.text).joined(separator: " ")
        let pending = words.filter { $0.time > time }.map(\.text).joined(separator: " ")
        return (said.isEmpty ? "" : said + (pending.isEmpty ? "" : " "), pending)
    }
}
