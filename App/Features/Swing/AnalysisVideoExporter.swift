import AVFoundation
import Foundation
import GolfCore
import UIKit

/// Monta y exporta el vídeo del análisis (docs/04, punto 10): gancho a velocidad real, cámara
/// lenta con líneas, pausas por fase, ritmo, nota, informe y cierre, con la voz y los subtítulos.
/// Sale en 1080 x 1920 a 30 fps, H.264 con AAC, y todo se hace en el iPhone. Termina con la sección
/// "A mejorar" (ImprovementPlan) y se recomprime para que pese menos de 16 MB (VideoCompressor).
enum AnalysisVideoExporter {
    /// Lo que sale: el vídeo en 1080p de menos de 16 MB y, si para caber ha tenido que bajar mucho la
    /// calidad, también una versión ligera en 720p. `missingClips`: ejercicios que salen con imagen fija.
    struct Output: Sendable {
        let main: URL
        let light: URL?
        let missingClips: [String]
    }

    @concurrent
    static func export(clipURL: URL, analysis: SwingAnalysis, short: Bool, subtitles: Bool,
                       progress: @escaping @Sendable (ExportProgress) -> Void) async throws -> Output {
        // 1. Guion, nota y bloques.
        progress(ExportProgress(stepName: "Escribiendo el guion", fraction: 0.02))
        let measurements = analysis.measurements()
        let score = Scoring.score(measurements)
        let script = ScriptWriter.write(measurements: measurements, score: score)
        // Los fallos de la sección "A mejorar" (los mismos que el guion, en el mismo orden).
        let improvementItems = ImprovementPlan.items(score)
        let kinds = AnalysisTimeline.blockKinds(short: short,
                                                importantPhases: AnalysisTimeline.importantPhases(of: score))

        // 2. La voz de cada frase (su duración manda en la línea de tiempo).
        var rendered: [(block: ScriptBlockKind, rendered: RenderedLine)] = []
        let voiceID = VoiceSynthesizer.voice()?.identifier
        let linesToSpeak = script.blocks.filter { kinds.contains($0.kind) }
        let totalLines = max(linesToSpeak.reduce(0) { $0 + $1.lines.count }, 1)
        for block in linesToSpeak {
            for line in block.lines {
                progress(ExportProgress(stepName: "Poniendo la voz (\(rendered.count + 1) de \(totalLines))",
                                        fraction: 0.05 + 0.3 * Double(rendered.count) / Double(totalLines)))
                let spoken = try await VoiceSynthesizer.render(line, voiceIdentifier: voiceID)
                rendered.append((block.kind, spoken))
            }
        }
        var narration: [ScriptBlockKind: Double] = [:]
        for kind in kinds {
            let lines = rendered.filter { $0.block == kind }
            guard !lines.isEmpty else { continue }
            narration[kind] = lines.reduce(0) { $0 + $1.rendered.duration }
                + Double(lines.count - 1) * VoiceTrackBuilder.pauseWithinBlock
        }

        // 3. La línea de tiempo y la pista de voz colocada en ella.
        let phases = analysis.phases
        let swingStart = max(phases.backswingStartTime - 0.4, 0)
        let clipDuration = try await AVURLAsset(url: clipURL).load(.duration).seconds
        let swingEnd = min(phases[.finish].time + 0.3, clipDuration)
        let slowMotionFactor = short ? 2.0 : 4.0
        let blocks = AnalysisTimeline.build(kinds: kinds, narration: narration,
                                            swingDuration: swingEnd - swingStart,
                                            slowMotionFactor: slowMotionFactor)
        let total = blocks.last?.end ?? 0
        var blockStarts: [ScriptBlockKind: Double] = [:]
        for block in blocks { if let kind = block.scriptKind { blockStarts[kind] = block.start } }
        let voice = VoiceTrackBuilder.build(lines: rendered, blockStarts: blockStarts)
        let voiceURL = MediaStore.temporaryURL(extension: "caf")
        try VoiceTrackBuilder.writeFile(voice, to: voiceURL)
        defer { MediaStore.removeIfPresent(voiceURL) }

        // 4. El montaje: los trozos del clip (reales, a cámara lenta o congelados) y la voz.
        progress(ExportProgress(stepName: "Montando el vídeo", fraction: 0.38))
        let composition = AVMutableComposition()
        var exerciseTrack: AVMutableCompositionTrack?
        var exerciseTransforms: [(CMTime, CGAffineTransform)] = []
        var missingClips: [String] = []
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw MediaError.exportFailed("montaje") }
        let asset = AVURLAsset(url: clipURL)
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first
        else { throw MediaError.noVideoTrack }
        let preferredTransform = try await sourceVideo.load(.preferredTransform)
        let timescale: CMTimeScale = 48_000
        func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: timescale) }

        /// Congela el fotograma `at` del clip durante `duration` s a partir de `start` del montaje.
        func freeze(at clipTime: Double, start: Double, duration: Double) throws {
            let snippet = CMTimeRange(start: time(min(clipTime, clipDuration - 0.05)), duration: time(1.0 / 30))
            try videoTrack.insertTimeRange(snippet, of: sourceVideo, at: time(start))
            videoTrack.scaleTimeRange(CMTimeRange(start: time(start), duration: snippet.duration),
                                      toDuration: time(duration))
        }

        for block in blocks {
            switch block.kind {
            case .script(.hook):
                // El swing a velocidad real; si la narración es más larga, el final se congela.
                let segment = min(swingEnd - swingStart, block.duration)
                try videoTrack.insertTimeRange(CMTimeRange(start: time(swingStart), duration: time(segment)),
                                               of: sourceVideo, at: time(block.start))
                if block.duration - segment > 0.05 {
                    try freeze(at: swingStart + segment - 0.05, start: block.start + segment,
                               duration: block.duration - segment)
                }
            case .script(.slowMotion):
                let scaled = (swingEnd - swingStart) * slowMotionFactor
                try videoTrack.insertTimeRange(CMTimeRange(start: time(swingStart), duration: time(swingEnd - swingStart)),
                                               of: sourceVideo, at: time(block.start))
                videoTrack.scaleTimeRange(CMTimeRange(start: time(block.start), duration: time(swingEnd - swingStart)),
                                          toDuration: time(scaled))
                if block.duration - scaled > 0.05 {
                    try freeze(at: swingEnd - 0.05, start: block.start + scaled, duration: block.duration - scaled)
                }
            case .script(.improveIntro), .script(.improveSummary):
                // Tarjetas de la sección "A mejorar": a pantalla completa, sin vídeo debajo.
                videoTrack.insertEmptyTimeRange(CMTimeRange(start: time(block.start), duration: time(block.duration)))
            case let .script(kind) where Self.improvementIndex(kind) != nil:
                // Un fallo de "A mejorar": el clip del ejercicio en bucle, en su propia pista.
                videoTrack.insertEmptyTimeRange(CMTimeRange(start: time(block.start), duration: time(block.duration)))
                guard let index = Self.improvementIndex(kind), index < improvementItems.count else { break }
                let exercise = improvementItems[index].exercise
                guard exercise.hasClip, let url = ExerciseAssets.url(exercise.clipFile),
                      let source = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first
                else {
                    missingClips.append(exercise.id)
                    break
                }
                if exerciseTrack == nil {
                    exerciseTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
                }
                guard let track = exerciseTrack else { break }
                let sourceDuration = try await AVURLAsset(url: url).load(.duration).seconds
                let size = try await source.load(.naturalSize)
                // A lo ancho del vídeo, debajo de la banda del título (sirve también si el usuario
                // pone un clip suyo de otro tamaño).
                let scale = ImprovementCards.clipSide / max(size.width, 1)
                exerciseTransforms.append((time(block.start), CGAffineTransform(scaleX: scale, y: scale)
                    .concatenating(CGAffineTransform(translationX: 0, y: ImprovementCards.clipTop))))
                if track.timeRange.duration < time(block.start) {
                    track.insertEmptyTimeRange(CMTimeRange(start: track.timeRange.duration, end: time(block.start)))
                }
                var cursor = block.start
                while cursor < block.end - 0.05, sourceDuration > 0.1 {
                    let piece = min(sourceDuration, block.end - cursor)
                    try track.insertTimeRange(CMTimeRange(start: .zero, duration: time(piece)), of: source, at: time(cursor))
                    cursor += piece
                }
            case let .script(kind):
                if let position = Self.position(for: kind) {
                    try freeze(at: analysis.poses[phases[position].frameIndex].time,
                               start: block.start, duration: block.duration)
                } else {
                    // Ritmo, nota e informe: tarjeta a pantalla completa, sin vídeo debajo.
                    videoTrack.insertEmptyTimeRange(CMTimeRange(start: time(block.start), duration: time(block.duration)))
                }
            case .closing:
                videoTrack.insertEmptyTimeRange(CMTimeRange(start: time(block.start), duration: time(block.duration)))
            }
        }

        let voiceAsset = AVURLAsset(url: voiceURL)
        if let voiceTrack = try await voiceAsset.loadTracks(withMediaType: .audio).first {
            let voiceDuration = try await voiceAsset.load(.duration)
            try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeMinimum(voiceDuration, time(total))),
                                           of: voiceTrack, at: .zero)
        }

        // 5. Los gráficos encima (telestrador, chips, subtítulos y tarjetas).
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(x: 0, y: 0, width: VideoLayers.width, height: VideoLayers.height)
        let overlay = try Self.overlayLayer(analysis: analysis, measurements: measurements, score: score,
                                            script: script, blocks: blocks, voice: voice, total: total,
                                            swingStart: swingStart, slowMotionFactor: slowMotionFactor,
                                            subtitles: subtitles, improvementItems: improvementItems,
                                            missingClips: missingClips)
        let parent = CALayer()
        parent.frame = videoLayer.frame
        parent.isGeometryFlipped = true
        parent.addSublayer(videoLayer)
        parent.addSublayer(overlay)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: VideoLayers.width, height: VideoLayers.height)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: time(total))
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        // El vídeo grabado lleva su giro en el transform: se aplica para verlo derecho.
        layerInstruction.setTransform(preferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        if let exerciseTrack {
            // La pista de los ejercicios va encima de la del swing.
            let exerciseLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: exerciseTrack)
            for (at, transform) in exerciseTransforms { exerciseLayer.setTransform(transform, at: at) }
            instruction.layerInstructions = [exerciseLayer, layerInstruction]
        }
        videoComposition.instructions = [instruction]

        // 6. Exportar en H.264 con AAC.
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw MediaError.exportFailed("sesión de exportación") }
        session.videoComposition = videoComposition
        let outputURL = MediaStore.temporaryURL(extension: "mp4")
        MediaStore.removeIfPresent(outputURL)
        // La secuencia de estados es Sendable; la sesión no. Se saca fuera para que la tarea
        // del avance no capture la sesión (Swift 6 no la dejaría cruzar a otra tarea).
        let states = session.states(updateInterval: 0.4)
        let monitor = Task {
            for await state in states {
                if case let .exporting(exportProgress) = state {
                    progress(ExportProgress(stepName: "Exportando el vídeo",
                                            fraction: 0.45 + 0.55 * exportProgress.fractionCompleted))
                }
            }
        }
        defer { monitor.cancel() }
        try await session.export(to: outputURL, as: .mp4)

        // 7. Que quepa para reenviarlo: H.264 + AAC, 1080p, menos de 16 MB. Si para caber la calidad
        //    baja mucho, también una versión ligera en 720p (petición del usuario, 22-11-2026).
        progress(ExportProgress(stepName: "Ajustando el tamaño para enviarlo", fraction: 0.97))
        defer { MediaStore.removeIfPresent(outputURL) }
        let compressed = try await VideoCompressor.compress(outputURL, width: Int(VideoLayers.width),
                                                            height: Int(VideoLayers.height))
        var light: URL?
        if compressed.videoBitRate < VideoCompressor.comfortableBitRate1080 {
            light = try await VideoCompressor.compress(outputURL, width: 720, height: 1280).url
        }
        progress(ExportProgress(stepName: "Vídeo listo", fraction: 1))
        return Output(main: compressed.url, light: light, missingClips: missingClips)
    }

    /// 0, 1 o 2 para los bloques de los fallos de "A mejorar".
    static func improvementIndex(_ kind: ScriptBlockKind) -> Int? {
        switch kind {
        case .improve1: 0
        case .improve2: 1
        case .improve3: 2
        default: nil
        }
    }

    private static func position(for kind: ScriptBlockKind) -> SwingPosition? {
        switch kind {
        case .address: .address
        case .takeaway: .takeaway
        case .midBackswing: .midBackswing
        case .top: .top
        case .transition: .transition
        case .impact: .impact
        case .finish: .finish
        default: nil
        }
    }

    /// Todos los gráficos del vídeo, cada uno visible solo en su bloque.
    private static func overlayLayer(analysis: SwingAnalysis, measurements: SwingMeasurements,
                                     score: SwingScore, script: SwingScript, blocks: [TimelineBlock],
                                     voice: VoiceTrack, total: Double, swingStart: Double,
                                     slowMotionFactor: Double, subtitles: Bool,
                                     improvementItems: [ImprovementPlan.Item], missingClips: [String]) throws -> CALayer {
        let overlay = CALayer()
        overlay.frame = CGRect(x: 0, y: 0, width: VideoLayers.width, height: VideoLayers.height)
        let now = Date.now

        for block in blocks {
            switch block.kind {
            case .script(.hook):
                let phrase = script[.hook]?.lines.first ?? ""
                overlay.addSublayer(AnalysisCards.hookOverlay(phrase: phrase, blockStart: block.start,
                                                              blockEnd: block.end, total: total))
            case .script(.slowMotion):
                overlay.addSublayer(AnalysisCards.slowMotionOverlay(analysis: analysis, block: block,
                                                                    swingStart: swingStart,
                                                                    factor: slowMotionFactor, total: total))
            case .script(.tempo):
                overlay.addSublayer(AnalysisCards.tempoCard(analysis: analysis, block: block, total: total))
            case .script(.score):
                overlay.addSublayer(AnalysisCards.scoreCard(score: score, block: block, total: total))
            case .script(.report):
                overlay.addSublayer(AnalysisCards.reportCard(analysis: analysis, score: score, block: block,
                                                             total: total, date: now))
            case .closing:
                overlay.addSublayer(AnalysisCards.closingCard(block: block, total: total, date: now))
            case .script(.improveIntro):
                overlay.addSublayer(ImprovementCards.listCard(title: ImprovementPlan.introTitle(count: improvementItems.count),
                                                              items: improvementItems, block: block, total: total))
            case .script(.improveSummary):
                overlay.addSublayer(ImprovementCards.listCard(title: ImprovementPlan.summaryTitle,
                                                              items: improvementItems, block: block, total: total))
            case let .script(kind) where Self.improvementIndex(kind) != nil:
                guard let index = Self.improvementIndex(kind), index < improvementItems.count else { break }
                let item = improvementItems[index]
                // Si el clip falta, la imagen fija con el texto (y se avisa al terminar).
                let fallback = missingClips.contains(item.exercise.id) ? ExerciseAssets.image(item.exercise) : nil
                overlay.addSublayer(ImprovementCards.itemOverlay(item: item, count: improvementItems.count, block: block,
                                                                 total: total, fallbackImage: fallback))
            case let .script(kind):
                guard let position = Self.position(for: kind) else { break }
                // Pausa de fase: telestrador, chip "n/7", estado y las medidas de su fase.
                let telestrator = VideoLayers.telestrator(analysis: analysis, position: position)
                VideoLayers.show(telestrator, from: block.start, to: block.end, total: total)
                overlay.addSublayer(telestrator)
                let chip = VideoLayers.phaseChip(position.rawValue, title: position.title)
                VideoLayers.show(chip, from: block.start, to: block.end, total: total)
                overlay.addSublayer(chip)
                let frameIndex = analysis.phases[position].frameIndex
                let counter = "F\(analysis.clipFrameNumber(at: frameIndex)), \(SpanishFormat.seconds(analysis.poses[frameIndex].time, decimals: 2))"
                let badge = VideoLayers.stateBadge("Pausa", counter: counter)
                VideoLayers.show(badge, from: block.start, to: block.end, total: total)
                overlay.addSublayer(badge)
                let items = measurements.items
                    .filter { $0.phase.rawValue == position.rawValue && $0.value != nil }
                    .map { (name: $0.kind.title, value: Self.valueText($0)) }
                overlay.addSublayer(VideoLayers.measureLabels(items, blockStart: block.start,
                                                              blockEnd: block.end, total: total))
            }
        }
        if subtitles {
            overlay.addSublayer(VideoLayers.subtitles(track: voice, total: total))
        }
        return overlay
    }

    private static func valueText(_ item: MetricResult) -> String {
        guard let value = item.value else { return "—" }
        switch item.kind.unit {
        case .degrees: return "\(SpanishFormat.number(value))°"
        case .centimeters: return "~\(SpanishFormat.number(value)) cm"
        case .seconds: return SpanishFormat.seconds(value, decimals: 2)
        case .ratio: return "\(SpanishFormat.number(value, decimals: 1)) : 1"
        case .trunkFraction: return SpanishFormat.number(value, decimals: 2)
        case .yesNo: return value > 0.5 ? "Sí" : "No"
        }
    }
}
