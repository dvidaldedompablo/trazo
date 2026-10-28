@preconcurrency import AVFoundation
import Foundation

/// Lo que se sabe de un archivo de vídeo.
struct VideoInfo: Sendable, Equatable {
    var duration: Double
    /// fps que declara el archivo.
    var nominalFrameRate: Double
    /// fps medidos con el instante de cada fotograma (el modo diagnóstico los enseña).
    var measuredFrameRate: Double?
    var frameCount: Int?
    /// Tamaño ya girado: un vídeo vertical tiene el ancho menor que el alto.
    var width: Int
    var height: Int
    /// Códec en cuatro letras: "hvc1" (HEVC), "avc1" (H.264)…
    var codec: String
    var hasAudio: Bool

    /// fps para guardar en la biblioteca: los medidos si los hay.
    var frameRate: Double { measuredFrameRate ?? nominalFrameRate }
}

enum MediaError: LocalizedError {
    case noVideoTrack
    case unreadable(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "El archivo no tiene vídeo."
        case let .unreadable(detail): "No se ha podido leer el vídeo (\(detail))."
        case let .exportFailed(detail): "No se ha podido guardar el clip (\(detail))."
        }
    }
}

/// Lee la información de un vídeo con la API asíncrona de AVFoundation (`load`), que no bloquea.
enum VideoInspector {
    /// - Parameter measureFrames: recorre los fotogramas (sin decodificarlos) para medir los fps reales.
    ///   Es rápido, pero en un vídeo largo tarda algo más: se pide solo cuando hace falta.
    static func info(of url: URL, measureFrames: Bool) async throws -> VideoInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw MediaError.noVideoTrack }
        let (nominal, size, transform, formats) = try await track.load(.nominalFrameRate, .naturalSize,
                                                                        .preferredTransform, .formatDescriptions)
        // El tamaño "natural" va sin girar: el giro del vídeo vertical está en `preferredTransform`.
        let oriented = CGRect(origin: .zero, size: size).applying(transform).size
        let codec = formats.first.map { fourCharacterCode(CMFormatDescriptionGetMediaSubType($0)) } ?? "?"
        let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty

        var info = VideoInfo(duration: duration, nominalFrameRate: Double(nominal), measuredFrameRate: nil, frameCount: nil,
                             width: Int(abs(oriented.width).rounded()), height: Int(abs(oriented.height).rounded()),
                             codec: codec, hasAudio: hasAudio)
        if measureFrames, let timing = try? frameTiming(asset: asset, track: track) {
            info.measuredFrameRate = timing.frameRate
            info.frameCount = timing.count
        }
        return info
    }

    /// fps reales: (fotogramas − 1) / (último instante − primero). Se leen solo los tiempos de cada
    /// fotograma comprimido (sin decodificar la imagen), así que va rápido.
    private static func frameTiming(asset: AVAsset, track: AVAssetTrack) throws -> (frameRate: Double, count: Int) {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw MediaError.unreadable("sin salida de fotogramas") }
        reader.add(output)
        guard reader.startReading() else { throw MediaError.unreadable(reader.error?.localizedDescription ?? "lector") }
        var times: [Double] = []
        while let buffer = output.copyNextSampleBuffer() {
            let count = CMSampleBufferGetNumSamples(buffer)
            guard count > 0 else { continue }
            // Un búfer puede llevar varios fotogramas: se lee el instante de cada uno.
            var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
            var used = 0
            if CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: count, arrayToFill: &timing,
                                                      entriesNeededOut: &used) == noErr {
                times += timing.prefix(used).map { $0.presentationTimeStamp.seconds }.filter(\.isFinite)
            }
        }
        reader.cancelReading()
        // Con HEVC los fotogramas llegan en orden de decodificación, no de presentación: se ordenan.
        times.sort()
        guard times.count > 1, let first = times.first, let last = times.last, last > first else {
            throw MediaError.unreadable("sin fotogramas")
        }
        return (Double(times.count - 1) / (last - first), times.count)
    }

    /// Un código de cuatro letras guardado en un número de 32 bits (como 'hvc1') a texto.
    static func fourCharacterCode(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "?"
    }
}
