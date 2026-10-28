import Foundation
import GolfCore
import SwiftData

/// De dónde salió un clip.
enum ClipOrigin: String, Codable {
    /// Grabado con la cámara de la app.
    case recorded
    /// Importado de Fotos.
    case imported
}

/// Un vídeo de "Tus vídeos". El archivo vive en la carpeta de clips del contenedor de la app
/// (ver `MediaStore`); aquí se guardan sus datos con SwiftData.
///
/// `@Model` convierte la clase en algo que SwiftData sabe guardar: cada propiedad guardada es una
/// columna. Por eso el modo y el origen se guardan como texto y se leen con propiedades calculadas.
@Model
final class Clip {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var modeRaw: String
    var originRaw: String
    /// Nombre del archivo dentro de la carpeta de clips. Se guarda el nombre y no la ruta completa:
    /// al reinstalar la app con Sideloadly la ruta del contenedor puede cambiar.
    var fileName: String
    /// Nombre de la miniatura (JPEG) en la misma carpeta. Si empieza por "demo:", es una imagen del paquete.
    var thumbnailName: String?
    /// fps reales del archivo y duración (s).
    var frameRate: Double
    var duration: Double
    /// Tamaño del vídeo ya girado (vertical: el ancho es menor que el alto).
    var width: Int
    var height: Int
    /// Instante del impacto dentro del clip (s), si se oyó.
    var impactTime: Double?

    init(id: UUID = UUID(), createdAt: Date = .now, mode: CaptureMode, origin: ClipOrigin, fileName: String,
         thumbnailName: String?, frameRate: Double, duration: Double, width: Int, height: Int, impactTime: Double?) {
        self.id = id
        self.createdAt = createdAt
        modeRaw = mode.rawValue
        originRaw = origin.rawValue
        self.fileName = fileName
        self.thumbnailName = thumbnailName
        self.frameRate = frameRate
        self.duration = duration
        self.width = width
        self.height = height
        self.impactTime = impactTime
    }

    var mode: CaptureMode { CaptureMode(rawValue: modeRaw) ?? .tracer }
    var origin: ClipOrigin { ClipOrigin(rawValue: originRaw) ?? .recorded }
    /// Los clips de demostración (capturas del CI) no tienen archivo de vídeo.
    var isDemo: Bool { thumbnailName?.hasPrefix(MediaStore.demoPrefix) == true }
    var fileURL: URL { MediaStore.url(forFile: fileName) }
}
