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
        }
        try? context.save()
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
                                thumbnails: windows.map { _ in thumbnail }, strongestImpact: impacts[0].time)
    }
}
