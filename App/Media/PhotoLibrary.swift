@preconcurrency import Photos
import Foundation

enum PhotoLibraryError: LocalizedError {
    case denied
    case assetNotFound
    case noOriginal

    var errorDescription: String? {
        switch self {
        case .denied: "Trazo no tiene permiso para usar Fotos. Puedes darlo en Ajustes > Trazo > Fotos."
        case .assetNotFound: "No se encuentra el vídeo en Fotos."
        case .noOriginal: "Fotos no tiene el vídeo original."
        }
    }
}

/// Lo que la app hace con Fotos: guardar vídeos y leer el original de un vídeo elegido.
enum PhotoLibrary {
    /// Guarda el archivo tal cual en Fotos (sin recodificar: mismos fps y calidad).
    /// Solo pide permiso para añadir, no para ver la fototeca.
    static func saveVideo(at url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw PhotoLibraryError.denied }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .video, fileURL: url, options: nil)
        }
    }

    /// Permiso para leer la fototeca (lo pide si todavía no se ha preguntado).
    static func readAccess() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else { return current }
        return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Copia el archivo original de un vídeo de Fotos a `destination`.
    ///
    /// Con un vídeo a cámara lenta, el original es el archivo a 240 fps con los tiempos reales:
    /// la cámara lenta es solo una marca que Fotos aplica al reproducir. docs/01 propone pedirlo con
    /// `requestAVAsset(.original)`; copiar el recurso original con `PHAssetResourceManager` da el
    /// mismo archivo y se escribe directamente donde queremos (también si está en iCloud).
    static func copyOriginalVideo(localIdentifier: String, to destination: URL) async throws {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else {
            throw PhotoLibraryError.assetNotFound
        }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let original = resources.first(where: { $0.type == .video }) ?? resources.first(where: { $0.type == .fullSizeVideo })
        else { throw PhotoLibraryError.noOriginal }
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        MediaStore.removeIfPresent(destination)
        try await PHAssetResourceManager.default().writeData(for: original, toFile: destination, options: options)
    }
}
