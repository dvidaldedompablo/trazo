@preconcurrency import AVFoundation
import Foundation

/// Copia un trozo de un vídeo a otro archivo sin recodificar ("passthrough"):
/// se conservan el códec, la calidad y los fps reales (240 fps siguen siendo 240 fps).
enum ClipExporter {
    /// - Parameter range: segundos de la grabación que se copian; `nil` copia el vídeo entero.
    static func export(from source: URL, range: ClosedRange<Double>?, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw MediaError.exportFailed("sin sesión de exportación")
        }
        if let range {
            // Escala de tiempo de 48 000: múltiplo de 240, 120, 60 y de la frecuencia del audio.
            let start = CMTime(seconds: range.lowerBound, preferredTimescale: 48_000)
            let end = CMTime(seconds: range.upperBound, preferredTimescale: 48_000)
            session.timeRange = CMTimeRange(start: start, end: end)
        }
        MediaStore.removeIfPresent(destination)
        do {
            // API asíncrona de iOS 18: espera a que termine y lanza un error si falla.
            try await session.export(to: destination, as: .mov)
        } catch {
            throw MediaError.exportFailed(error.localizedDescription)
        }
    }
}
