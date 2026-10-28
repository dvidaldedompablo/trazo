import Foundation
import os

/// Dónde viven los archivos de vídeo y miniaturas, dentro del contenedor de la app.
///
/// Los clips van en Application Support/Clips: no se ven en la app Archivos y no se borran solos.
/// La carpeta se excluye de la copia de iCloud (los vídeos a 240 fps pesan mucho y la app no usa iCloud).
/// Las grabaciones sin cortar van primero a la carpeta temporal y se borran al guardar los clips.
enum MediaStore {
    /// Prefijo de las miniaturas de demostración (imágenes del paquete, para las capturas del CI).
    static let demoPrefix = "demo:"

    static var clipsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Clips", directoryHint: .isDirectory)
    }

    /// Crea la carpeta de clips si no existe y la deja fuera de la copia de seguridad.
    static func prepareClipsDirectory() throws {
        var directory = clipsDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    static func url(forFile name: String) -> URL {
        clipsDirectory.appending(path: name, directoryHint: .notDirectory)
    }

    /// Nombre nuevo para un archivo de la carpeta de clips.
    static func newFileName(extension ext: String) -> String {
        "\(UUID().uuidString).\(ext)"
    }

    /// Archivo temporal nuevo (grabaciones sin cortar, vídeos recién importados).
    static func temporaryURL(extension ext: String) -> URL {
        URL.temporaryDirectory.appending(path: "\(UUID().uuidString).\(ext)", directoryHint: .notDirectory)
    }

    /// Borra un archivo si existe. Un fallo al borrar no es grave: se apunta y se sigue.
    static func removeIfPresent(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logger.error("No se ha podido borrar \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Espacio libre en el iPhone (bytes) para avisar antes de grabar si no queda.
    static var availableCapacity: Int64? {
        let values = try? URL.applicationSupportDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private static let logger = Logger(subsystem: "io.github.dvidaldedompablo.trazo", category: "MediaStore")
}
