import Foundation
import GolfCore
import SwiftData
import UIKit

/// Datos de demostración para las capturas del CI (`-UITestScreen`): sin cámara ni vídeos de verdad.
/// Las fechas son fijas para que las capturas salgan siempre iguales.
@MainActor
enum DemoData {
    /// 27 de octubre de 2026, 18:30 en Madrid (17:30 UTC; el horario de invierno empezó el 25).
    static let referenceDate = Date(timeIntervalSince1970: 1_793_122_200)

    /// Clips de ejemplo en "Tus vídeos": golpes y swings con las escenas de `DemoData/`.
    static func populateLibrary(in context: ModelContext) {
        let samples: [(CaptureMode, Double, Double)] = [
            (.tracer, 9.0, 0), (.swing, 4.5, 0.4), (.tracer, 9.0, 1), (.tracer, 8.2, 1.1),
            (.swing, 4.5, 2), (.tracer, 9.0, 3), (.swing, 4.5, 4),
        ]
        for (index, sample) in samples.enumerated() {
            let (mode, duration, daysAgo) = sample
            let clip = Clip(createdAt: referenceDate.addingTimeInterval(-daysAgo * 86_400 - Double(index) * 600),
                            mode: mode, origin: .recorded, fileName: "demo-\(index).mov",
                            thumbnailName: MediaStore.demoPrefix + (mode == .tracer ? "escena_tracer" : "escena_swing"),
                            frameRate: 240, duration: duration, width: 1080, height: 1920,
                            impactTime: mode == .tracer ? 1 : 2.5)
            context.insert(clip)
            // Estado del tracer en algunos golpes: uno en proceso, uno listo y uno que falló.
            if mode == .tracer, index < 4 {
                let result = TracerResult(clipID: clip.id, createdAt: clip.createdAt)
                switch index {
                case 0: result.status = .processing
                case 2:
                    result.status = .ready
                    result.analysis = reviewAnalysis()
                default:
                    result.status = .failed
                    result.needsBall = true
                    result.failureReason = "No he encontrado la bola antes del golpe. Tócala para seguir."
                }
                context.insert(result)
            }
        }
        try? context.save()
    }

    /// Bola de la escena de demostración (`escena_tracer`, 1080 x 1920).
    static let sceneBall = Point2D(903, 1740)

    /// "Creando tu tracer" a mitad del seguimiento, como en s03: impacto en el fotograma 441 (1,84 s),
    /// siguiendo el 212 de 480 y 13 puntos de la bola.
    static func processingLive() -> TracerLive {
        var rng = SeededRandom(seed: 9)
        var live = TracerLive()
        live.step = .tracking
        live.bars = (0..<TracerPipeline.waveformBars).map { _ in 0.07 + rng.nextUnit() * 0.11 }
        live.bars[37] = 1
        live.bars[36] = 0.5
        live.bars[38] = 0.5
        live.impactBar = 37
        live.impactTime = 1.84
        live.impactFrame = 441
        live.impactSource = .sound
        live.frame = 212
        live.totalFrames = 480
        live.points = (0..<13).map { i in
            let t = Double(i) / 12
            return Point2D((sceneBall.x - 60 * t) / 1080, (sceneBall.y - 560 * t) / 1920)
        }
        live.thumbnail = UIImage(named: "escena_tracer")?.jpegData(compressionQuality: 0.8)
        live.progress = 0.55
        return live
    }

    /// Toca la bola en el fotograma de 0,3 s antes del impacto.
    static func ballTapRequest() -> BallTapRequest {
        BallTapRequest(url: MediaStore.temporaryURL(extension: "mov"), time: 1.54, frameRate: 240, videoWidth: 1080,
                       videoHeight: 1920, title: "Toca la bola",
                       hint: "No he encontrado la bola antes del golpe. Busca un fotograma nítido y tócala.")
    }

    /// Un tracer con puntos de Vision y BlobTracker, dos descartados y un toque, perdido a los 0,4 s.
    static func reviewAnalysis() -> TracerAnalysis {
        func point(_ t: Double) -> Point2D { Point2D(sceneBall.x - 70 * t, sceneBall.y - 1500 * t + 600 * t * t) }
        var points: [SourcedSample] = []
        for i in 1...48 {
            let t = Double(i) / 120
            points.append(SourcedSample(TrajectorySample(time: t, point: point(t) + Point2D(0.8, -0.5)), source: .vision))
            if i % 2 == 0 {
                points.append(SourcedSample(TrajectorySample(time: t + 0.002, point: point(t + 0.002) + Point2D(-0.6, 0.7)), source: .blob))
            }
        }
        points.append(SourcedSample(TrajectorySample(time: 0.21, point: Point2D(640, 900)), source: .blob))
        points.append(SourcedSample(TrajectorySample(time: 0.33, point: Point2D(980, 1100)), source: .vision))
        let tap = TrajectorySample(time: 0.25, point: point(0.25), isFixed: true)
        let input = TracerInput(ball: sceneBall, imageWidth: 1080, imageHeight: 1920, points: points + [SourcedSample(tap, source: .tap)],
                                horizonY: 760)
        var outcome = TracerAssembler.assemble(input).outcome
        // Para la captura: que se vea el aviso de pérdida.
        outcome.needsReview = true
        outcome.lostAt = outcome.trackedDuration
        return TracerAnalysis(outcome: outcome, impactTime: 1.84, impactSource: .sound, impactFrame: 441, ball: sceneBall,
                              ballFromTap: false, videoWidth: 1080, videoHeight: 1920, frameRate: 240, horizonY: 760,
                              basePoints: points, reinforcements: [Reinforcement(tap: tap, added: [])],
                              timings: [StepTiming(name: "Vídeo y sonido", seconds: 0.4), StepTiming(name: "Bola e impacto", seconds: 0.9),
                                        StepTiming(name: "Vuelo y Vision", seconds: 3.2), StepTiming(name: "BlobTracker", seconds: 1.1)],
                              notes: ["Datos de demostración."])
    }

    /// Una grabación de 38 s con tres golpes (el tercero, flojo: de otro jugador) para la hoja de elegir golpes.
    static func pendingRecording() -> PendingRecording {
        let duration = 38.0
        let impacts = [Impact(time: 6.2, strength: 900, prominence: 310), Impact(time: 19.8, strength: 760, prominence: 260),
                       Impact(time: 31.4, strength: 120, prominence: 40)]
        let windows = ClipPlanner.windows(for: impacts, recordingDuration: duration, mode: .tracer)
        // Onda inventada: ruido bajo con un pico en cada golpe.
        var rng = SeededRandom(seed: 3)
        var bars = (0..<RecordingAnalyzer.barCount).map { _ in 0.06 + rng.nextUnit() * 0.08 }
        for impact in impacts {
            let index = Waveform.barIndex(for: impact.time, duration: duration, count: bars.count)
            bars[index] = impact.strength / 900
        }
        let thumbnail = UIImage(named: "escena_tracer")?.jpegData(compressionQuality: 0.7)
        let info = VideoInfo(duration: duration, nominalFrameRate: 240, measuredFrameRate: 240, frameCount: 9120,
                             width: 1080, height: 1920, codec: "hvc1", hasAudio: true)
        return PendingRecording(sourceURL: MediaStore.temporaryURL(extension: "mov"), mode: .tracer, origin: .recorded,
                                info: info, bars: bars, windows: windows,
                                thumbnails: windows.map { _ in thumbnail }, strongestImpact: impacts[0].time,
                                isShotSeries: ClipPlanner.isShotSeries(impacts))
    }

    /// Un vídeo narrado de 95 s sin golpes (como el de referencia): la voz da sonidos secos cada
    /// medio segundo y el control de sensatez no la reconoce como una tanda de golpes.
    static func pendingVoiceRecording() -> PendingRecording {
        let duration = 95.0
        var rng = SeededRandom(seed: 5)
        var impacts: [Impact] = []
        var t = 0.4
        while t < duration - 0.5 {
            impacts.append(Impact(time: t, strength: 200 + rng.nextUnit() * 400, prominence: 30))
            t += 0.42 + rng.nextUnit() * 0.6
        }
        let proposal = ClipPlanner.propose(for: impacts, recordingDuration: duration, mode: .swing)
        let bars = (0..<RecordingAnalyzer.barCount).map { _ in 0.25 + rng.nextUnit() * 0.75 }
        let info = VideoInfo(duration: duration, nominalFrameRate: 30, measuredFrameRate: 30, frameCount: 2850,
                             width: 1080, height: 1920, codec: "avc1", hasAudio: true)
        return PendingRecording(sourceURL: MediaStore.temporaryURL(extension: "mov"), mode: .swing, origin: .imported,
                                info: info, bars: bars, windows: proposal.windows, thumbnails: [],
                                strongestImpact: nil, isShotSeries: proposal.isShotSeries)
    }
}
