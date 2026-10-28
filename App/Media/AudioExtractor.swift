@preconcurrency import AVFoundation
import Foundation

/// Saca el audio de un vídeo como muestras PCM en coma flotante, mono y a 48 kHz:
/// el formato que espera `ImpactDetector` (GolfCore).
enum AudioExtractor {
    static let sampleRate = 48_000.0

    /// Devuelve las muestras, o una lista vacía si el vídeo no tiene audio.
    static func monoSamples(from url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return [] }
        return try read(asset: asset, tracks: tracks)
    }

    private static func read(asset: AVAsset, tracks: [AVAssetTrack]) throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        // La salida de mezcla junta los canales en uno y cambia la frecuencia de muestreo:
        // da igual si el micrófono grabó en estéreo o a 44,1 kHz.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw MediaError.unreadable("sin salida de audio") }
        reader.add(output)
        guard reader.startReading() else { throw MediaError.unreadable(reader.error?.localizedDescription ?? "audio") }

        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let count = length / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            var chunk = [Float](repeating: 0, count: count)
            let status = chunk.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                                           destination: raw.baseAddress!)
            }
            if status == kCMBlockBufferNoErr { samples += chunk }
        }
        if reader.status == .failed {
            throw MediaError.unreadable(reader.error?.localizedDescription ?? "audio")
        }
        return samples
    }
}
