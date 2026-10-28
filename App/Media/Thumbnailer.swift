@preconcurrency import AVFoundation
import UIKit

/// Miniaturas de los vídeos para "Tus vídeos" y la pantalla de elegir golpes.
/// Se pasan como JPEG (`Data`): así viajan sin problemas del trabajo en segundo plano a la interfaz.
enum Thumbnailer {
    /// Fotograma en el instante `seconds`, reducido (360 x 640 como mucho) y en JPEG.
    static func jpeg(from url: URL, at seconds: Double) async throws -> Data {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        // Gira el fotograma como se ve el vídeo (vertical).
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 640)
        // Un poco de margen para no tener que decodificar desde el fotograma clave anterior.
        let tolerance = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let time = CMTime(seconds: max(seconds, 0), preferredTimescale: 600)
        let cgImage = try await generator.image(at: time).image
        guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8) else {
            throw MediaError.exportFailed("miniatura")
        }
        return data
    }

    /// Guarda la miniatura en la carpeta de clips y devuelve su nombre.
    static func save(_ data: Data) throws -> String {
        let name = MediaStore.newFileName(extension: "jpg")
        try data.write(to: MediaStore.url(forFile: name), options: .atomic)
        return name
    }

    /// Carga una miniatura guardada (o la de demostración del paquete).
    static func load(named name: String?) -> UIImage? {
        guard let name else { return nil }
        if name.hasPrefix(MediaStore.demoPrefix) {
            return UIImage(named: String(name.dropFirst(MediaStore.demoPrefix.count)))
        }
        return UIImage(contentsOfFile: MediaStore.url(forFile: name).path(percentEncoded: false))
    }
}
