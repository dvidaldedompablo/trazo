import Foundation
import GolfCore
import SwiftData

/// Guarda en la biblioteca lo que el usuario ha elegido de una grabación.
@MainActor
enum ClipSaver {
    /// Corta y guarda los clips elegidos. Con `keepFullRecording`, guarda también el vídeo entero;
    /// si no, lo borra (a 240 fps ocupa mucho). Devuelve los clips guardados.
    @discardableResult
    static func save(_ pending: PendingRecording, selection: [Bool], keepFullRecording: Bool,
                     in context: ModelContext) async throws -> [Clip] {
        try MediaStore.prepareClipsDirectory()
        var clips: [Clip] = []
        for (window, isSelected) in zip(pending.windows, selection) where isSelected {
            let name = MediaStore.newFileName(extension: "mov")
            try await ClipExporter.export(from: pending.sourceURL, range: window.start...window.end, to: MediaStore.url(forFile: name))
            clips.append(try await insertClip(fileName: name, mode: pending.mode, origin: pending.origin,
                                              impactTime: window.impactOffset, in: context))
        }
        if keepFullRecording {
            clips.append(try await saveWhole(pending, in: context))
        } else {
            MediaStore.removeIfPresent(pending.sourceURL)
        }
        try context.save()
        return clips
    }

    /// Guarda el vídeo entero como un clip (sin corte automático, o un vídeo importado con un solo golpe).
    @discardableResult
    static func saveWhole(_ pending: PendingRecording, in context: ModelContext) async throws -> Clip {
        try MediaStore.prepareClipsDirectory()
        let name = MediaStore.newFileName(extension: pending.sourceURL.pathExtension.isEmpty ? "mov" : pending.sourceURL.pathExtension)
        try FileManager.default.moveItem(at: pending.sourceURL, to: MediaStore.url(forFile: name))
        let clip = try await insertClip(fileName: name, mode: pending.mode, origin: pending.origin,
                                        impactTime: pending.strongestImpact, in: context)
        try context.save()
        return clip
    }

    /// Lee los fps reales, hace la miniatura y crea el clip en la biblioteca.
    private static func insertClip(fileName: String, mode: CaptureMode, origin: ClipOrigin,
                                   impactTime: Double?, in context: ModelContext) async throws -> Clip {
        let url = MediaStore.url(forFile: fileName)
        let info = try await VideoInspector.info(of: url, measureFrames: true)
        let thumbnailTime = impactTime ?? min(0.5, info.duration / 2)
        let thumbnail = try? await Thumbnailer.jpeg(from: url, at: thumbnailTime)
        let clip = Clip(mode: mode, origin: origin, fileName: fileName,
                        thumbnailName: try thumbnail.map(Thumbnailer.save),
                        frameRate: info.frameRate, duration: info.duration,
                        width: info.width, height: info.height, impactTime: impactTime)
        context.insert(clip)
        return clip
    }

    /// Borra un clip: su vídeo, su miniatura y su ficha.
    static func delete(_ clip: Clip, in context: ModelContext) {
        if !clip.isDemo {
            MediaStore.removeIfPresent(clip.fileURL)
            if let thumbnail = clip.thumbnailName { MediaStore.removeIfPresent(MediaStore.url(forFile: thumbnail)) }
        }
        context.delete(clip)
        try? context.save()
    }
}
