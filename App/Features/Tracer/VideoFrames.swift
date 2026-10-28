@preconcurrency import AVFoundation
import CoreVideo
import GolfCore
import UIKit

/// Cómo están guardados los fotogramas y cómo se ven: el iPhone graba en horizontal y marca un giro
/// (`preferredTransform`) para enseñar el vídeo en vertical. Todo el tracer trabaja en el vídeo ya girado.
struct VideoGeometry: Sendable, Equatable {
    /// Giro en el sentido de las agujas del reloj: 0, 90, 180 o 270 grados.
    let rotation: Int
    /// Tamaño del fotograma tal como está guardado.
    let bufferWidth: Int
    let bufferHeight: Int

    /// Tamaño del vídeo ya girado (como se ve).
    var width: Int { rotation % 180 == 0 ? bufferWidth : bufferHeight }
    var height: Int { rotation % 180 == 0 ? bufferHeight : bufferWidth }

    /// La misma orientación en el formato de Vision.
    var visionOrientation: CGImagePropertyOrientation {
        switch rotation {
        case 90: .right
        case 180: .down
        case 270: .left
        default: .up
        }
    }

    init(rotation: Int, bufferWidth: Int, bufferHeight: Int) {
        self.rotation = rotation
        self.bufferWidth = bufferWidth
        self.bufferHeight = bufferHeight
    }

    init(transform: CGAffineTransform, naturalSize: CGSize) {
        // El ángulo del giro, redondeado a un múltiplo de 90°.
        let degrees = atan2(transform.b, transform.a) * 180 / .pi
        let quarter = Int((degrees / 90).rounded())
        self.init(rotation: ((quarter % 4) + 4) % 4 * 90,
                  bufferWidth: Int(naturalSize.width.rounded()), bufferHeight: Int(naturalSize.height.rounded()))
    }

    /// Píxel del fotograma guardado que se ve en el píxel (x, y) del vídeo girado.
    /// Con 90° (vertical normal del iPhone) el fotograma se gira a la derecha: la columna de la izquierda
    /// pasa a ser la fila de arriba.
    @inline(__always)
    func bufferPoint(_ x: Int, _ y: Int) -> (x: Int, y: Int) {
        switch rotation {
        case 90: (y, bufferHeight - 1 - x)
        case 180: (bufferWidth - 1 - x, bufferHeight - 1 - y)
        case 270: (bufferWidth - 1 - y, x)
        default: (x, y)
        }
    }
}

/// Imágenes en gris a partir del brillo (el plano Y) de un fotograma 420f, ya giradas.
enum LumaSampler {
    /// El vídeo entero reducido `factor` veces (cada píxel es la media de factor x factor).
    /// BlobTracker trabaja con estas (a 1080 de ancho y factor 2, 540 x 960).
    static func reduced(_ pixelBuffer: CVPixelBuffer, geometry: VideoGeometry, factor: Int) -> GrayImage {
        let width = geometry.width / factor
        let height = geometry.height / factor
        var pixels = [UInt8](repeating: 0, count: width * height)
        withLuma(pixelBuffer) { base, stride in
            let area = factor * factor
            for oy in 0..<height {
                for ox in 0..<width {
                    var sum = 0
                    for dy in 0..<factor {
                        for dx in 0..<factor {
                            let p = geometry.bufferPoint(ox * factor + dx, oy * factor + dy)
                            sum += Int(base[p.y * stride + p.x])
                        }
                    }
                    pixels[oy * width + ox] = UInt8(sum / area)
                }
            }
        }
        return GrayImage(width: width, height: height, pixels: pixels)
    }

    /// Un trozo a resolución completa, en coordenadas del vídeo girado (para buscar la bola).
    static func crop(_ pixelBuffer: CVPixelBuffer, geometry: VideoGeometry, rect: PixelRect) -> GrayImage? {
        let r = rect.clamped(width: geometry.width, height: geometry.height)
        guard r.width > 0, r.height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: r.width * r.height)
        withLuma(pixelBuffer) { base, stride in
            for y in 0..<r.height {
                for x in 0..<r.width {
                    let p = geometry.bufferPoint(r.x + x, r.y + y)
                    pixels[y * r.width + x] = base[p.y * stride + p.x]
                }
            }
        }
        return GrayImage(width: r.width, height: r.height, pixels: pixels)
    }

    /// Da acceso al plano de brillo mientras dura `body` (el búfer se bloquea solo para leer).
    private static func withLuma(_ pixelBuffer: CVPixelBuffer, _ body: (UnsafePointer<UInt8>, Int) -> Void) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let address = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return }
        body(address.assumingMemoryBound(to: UInt8.self), CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0))
    }
}

/// Lee los fotogramas de un vídeo entre dos instantes, en orden, sin guardar más que lo que se pida.
struct FrameReader {
    let url: URL
    let geometry: VideoGeometry
    let frameRate: Double

    static func open(_ url: URL, frameRate: Double) async throws -> FrameReader {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw MediaError.noVideoTrack }
        let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
        return FrameReader(url: url, geometry: VideoGeometry(transform: transform, naturalSize: size), frameRate: frameRate)
    }

    /// Llama a `body` con cada fotograma entre `start` y `end` (s del vídeo). Si `body` devuelve `false`, para.
    func read(from start: Double, to end: Double,
              _ body: (_ sample: CMSampleBuffer, _ pixels: CVPixelBuffer, _ time: Double) async throws -> Bool) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw MediaError.noVideoTrack }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw MediaError.unreadable("sin salida de fotogramas") }
        reader.add(output)
        let from = CMTime(seconds: max(start, 0), preferredTimescale: 48_000)
        reader.timeRange = CMTimeRange(start: from, end: CMTime(seconds: max(end, start), preferredTimescale: 48_000))
        guard reader.startReading() else { throw MediaError.unreadable(reader.error?.localizedDescription ?? "fotogramas") }
        defer { reader.cancelReading() }
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard time >= start - 0.5 / frameRate else { continue }
            if try await !body(sample, pixels, time) { break }
        }
    }
}

/// Un fotograma concreto como imagen (la pantalla "Toca la bola" y la miniatura de "Creando tu tracer").
enum FrameGrabber {
    /// JPEG del fotograma más cercano a `time`, girado como se ve. Con `exact`, sin margen de tiempo
    /// (más lento, pero es justo ese fotograma: hace falta para tocar la bola).
    static func jpeg(from url: URL, at time: Double, maximumSize: CGSize = CGSize(width: 1080, height: 1920),
                     exact: Bool = true) async throws -> Data {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        let tolerance = exact ? CMTime.zero : CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let image = try await generator.image(at: CMTime(seconds: max(time, 0), preferredTimescale: 48_000)).image
        guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else { throw MediaError.exportFailed("fotograma") }
        return data
    }
}

/// Dónde estaban "Bola aquí" y la línea del golpe de la guía de Grabar, en píxeles del vídeo.
///
/// La guía se dibuja sobre la pantalla (390 x 844 en la maqueta) y la cámara la llena recortando los
/// lados del vídeo (9:16). Deshaciendo ese recorte se sabe dónde caía cada punto de la guía en el vídeo.
enum CaptureGuideGeometry {
    static func videoPoint(forScreen point: CGPoint, videoWidth: Int, videoHeight: Int) -> Point2D {
        let screen = CaptureScene.size
        let scale = max(screen.width / CGFloat(videoWidth), screen.height / CGFloat(videoHeight))
        let shownWidth = CGFloat(videoWidth) * scale
        let shownHeight = CGFloat(videoHeight) * scale
        let x = (point.x + (shownWidth - screen.width) / 2) / scale
        let y = (point.y + (shownHeight - screen.height) / 2) / scale
        return Point2D(Double(x), Double(y))
    }

    /// "Bola aquí".
    static func ball(videoWidth: Int, videoHeight: Int) -> Point2D {
        videoPoint(forScreen: CaptureScene.ball, videoWidth: videoWidth, videoHeight: videoHeight)
    }

    /// Hacia dónde va la línea del golpe (su punto de fuga en la guía).
    static func aim(videoWidth: Int, videoHeight: Int) -> Point2D {
        videoPoint(forScreen: CGPoint(x: 206, y: 270), videoWidth: videoWidth, videoHeight: videoHeight)
    }
}
