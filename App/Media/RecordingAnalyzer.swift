import Foundation
import GolfCore

/// Una grabación (o un vídeo importado) ya analizada, a la espera de que el usuario elija qué guardar.
struct PendingRecording: Identifiable, Sendable {
    let id = UUID()
    /// Archivo sin cortar, en la carpeta temporal.
    let sourceURL: URL
    let mode: CaptureMode
    let origin: ClipOrigin
    let info: VideoInfo
    /// La onda resumida en barras (de 0 a 1) para dibujarla.
    let bars: [Double]
    /// Un clip propuesto por golpe, con su miniatura en el instante del impacto (JPEG).
    let windows: [ClipWindow]
    let thumbnails: [Data?]
    /// El impacto más fuerte (s en la grabación), por si se guarda el vídeo entero.
    let strongestImpact: Double?
    /// Importado sin acceso a Fotos: si era a cámara lenta, puede venir estirado (docs/01).
    var mayBeStretched = false
}

/// Busca los golpes de una grabación con `ImpactDetector` y propone un clip por golpe (`ClipPlanner`).
enum RecordingAnalyzer {
    static let barCount = 64

    /// `@concurrent`: se ejecuta fuera del hilo principal aunque se llame desde la interfaz.
    /// Leer el audio y buscar impactos en varios minutos de grabación lleva un rato.
    @concurrent
    static func analyze(_ url: URL, mode: CaptureMode, origin: ClipOrigin) async throws -> PendingRecording {
        let info = try await VideoInspector.info(of: url, measureFrames: false)
        let samples = info.hasAudio ? try await AudioExtractor.monoSamples(from: url) : []
        let impacts = ImpactDetector.detect(samples: samples, sampleRate: AudioExtractor.sampleRate)
        let windows = ClipPlanner.windows(for: impacts, recordingDuration: info.duration, mode: mode)
        var thumbnails: [Data?] = []
        for window in windows {
            thumbnails.append(try? await Thumbnailer.jpeg(from: url, at: window.impactTime))
        }
        let strongest = impacts.max { $0.strength < $1.strength }?.time
        return PendingRecording(sourceURL: url, mode: mode, origin: origin, info: info,
                                bars: Waveform.bars(samples: samples, count: barCount),
                                windows: windows, thumbnails: thumbnails, strongestImpact: strongest)
    }
}
