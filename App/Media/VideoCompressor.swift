@preconcurrency import AVFoundation
import Foundation

/// Recomprime el vídeo del análisis para que se pueda reenviar (petición del usuario, 22-11-2026):
/// H.264 con audio AAC y menos de 16 MB. El caudal se calcula con la duración: lo que quepa en 16 MB
/// (con un 8 % de margen) menos el audio, sin pasar de un máximo que ya se ve bien.
///
/// Se hace con `AVAssetReader` (descodifica) y `AVAssetWriter` (codifica con el caudal pedido), porque
/// `AVAssetExportSession` no deja elegir el caudal. El escritor reescala si se pide otro tamaño (720p).
/// Un error con su dominio, su código y sus causas internas: el mensaje de AVFoundation solo dice
/// "No se ha podido completar la operación" y así no se sabe qué ha fallado.
func describeError(_ error: Error) -> String {
    var parts: [String] = []
    var current: NSError? = error as NSError
    var depth = 0
    while let e = current, depth < 4 {
        parts.append("\(e.domain) \(e.code): \(e.localizedDescription)" + (e.localizedFailureReason.map { " (\($0))" } ?? ""))
        current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        depth += 1
    }
    return parts.joined(separator: " ← ")
}

enum VideoCompressor {
    static let maximumBytes = 16_000_000
    static let audioBitRate = 96_000
    /// Por encima de esto no hace falta más caudal para un vídeo con muchos gráficos quietos.
    static let maximumBitRate = 6_000_000
    /// A 1080 x 1920 y por debajo de este caudal se notan los bloques: se hace también la de 720p.
    static let comfortableBitRate1080 = 1_500_000

    struct Result: Sendable {
        let url: URL
        let videoBitRate: Int
    }

    enum Failure: Error, LocalizedError {
        case noVideo
        case writer(String)

        var errorDescription: String? {
            switch self {
            case .noVideo: "recompresión: el vídeo no tiene imagen"
            case .writer(let detail): "recompresión: \(detail)"
            }
        }
    }

    @concurrent
    static func compress(_ input: URL, width: Int, height: Int) async throws -> Result {
        let asset = AVURLAsset(url: input)
        let duration = max(try await asset.load(.duration).seconds, 1)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.noVideo }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let budget = Double(maximumBytes) * 8 * 0.92 / duration
        let bitRate = min(maximumBitRate, max(300_000, Int(budget) - audioBitRate))

        let output = MediaStore.temporaryURL(extension: "mp4")
        MediaStore.removeIfPresent(output)
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        let videoOut = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        videoOut.alwaysCopiesSampleData = false
        reader.add(videoOut)
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60,
            ],
        ])
        videoIn.expectsMediaDataInRealTime = false
        writer.add(videoIn)

        var audioOut: AVAssetReaderTrackOutput?
        var audioIn: AVAssetWriterInput?
        if let audioTrack {
            let out = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
            reader.add(out)
            let inp = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: audioBitRate,
            ])
            inp.expectsMediaDataInRealTime = false
            writer.add(inp)
            audioOut = out
            audioIn = inp
        }

        guard reader.startReading() else { throw Failure.writer("lectura: " + (reader.error.map(describeError) ?? "?")) }
        guard writer.startWriting() else { throw Failure.writer("escritura: " + (writer.error.map(describeError) ?? "?")) }
        writer.startSession(atSourceTime: .zero)

        // Se alternan vídeo y audio según cuál admita más datos, hasta que se acaben los dos.
        var videoDone = false
        var audioDone = audioIn == nil
        while !videoDone || !audioDone {
            var progressed = false
            if !videoDone, videoIn.isReadyForMoreMediaData {
                if let sample = videoOut.copyNextSampleBuffer() {
                    videoIn.append(sample)
                } else {
                    videoIn.markAsFinished()
                    videoDone = true
                }
                progressed = true
            }
            if !audioDone, let audioIn, let audioOut, audioIn.isReadyForMoreMediaData {
                if let sample = audioOut.copyNextSampleBuffer() {
                    audioIn.append(sample)
                } else {
                    audioIn.markAsFinished()
                    audioDone = true
                }
                progressed = true
            }
            if writer.status == .failed { throw Failure.writer("escritura: " + (writer.error.map(describeError) ?? "?")) }
            if reader.status == .failed { throw Failure.writer("lectura: " + (reader.error.map(describeError) ?? "?")) }
            if !progressed { try await Task.sleep(for: .milliseconds(5)) }
        }
        await writer.finishWriting()
        guard writer.status == .completed else { throw Failure.writer("cierre: " + (writer.error.map(describeError) ?? "?")) }
        return Result(url: output, videoBitRate: bitRate)
    }
}
