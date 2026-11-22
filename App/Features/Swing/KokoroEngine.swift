import Foundation
import os
import GolfCore
import SherpaOnnxC

/// La voz Kokoro-82M en el iPhone (petición del usuario del 22-11-2026: voz ef_dora, velocidad 0,95).
///
/// Usa sherpa-onnx 1.13.8 (librería de terceros aceptada por el usuario: CLAUDE.md pide preguntar
/// antes). Es la última versión que trae espeak-ng dentro para pasar el texto a fonemas; desde la 2.0
/// hay que hacerlo aparte. El modelo (`kokoro-int8-multi-lang-v1_0`, comprimido a int8) va dentro de
/// la app, en la carpeta `Kokoro`: funciona sin red. Lo descarga `scripts/descargar-kokoro.sh` en el CI.
///
/// Es un actor: el motor no se puede usar desde dos hilos a la vez y cargarlo tarda (unos 100 MB),
/// así que se carga una vez y las frases van de una en una.
actor KokoroEngine {
    static let shared = KokoroEngine()

    /// ef_dora en la tabla de voces del modelo (`speaker2id` de los metadatos del .onnx).
    static let speakerID: Int32 = 28
    static let speed: Float = 0.95

    private var tts: OpaquePointer?
    private var failed = false
    private static let logger = Logger(subsystem: "io.github.dvidaldedompablo.trazo", category: "Kokoro")

    /// Sintetiza una frase. `nil` si el modelo no está o no se puede cargar: la app usa entonces la
    /// voz del iPhone (el plan B) y lo dice en el registro.
    func render(_ text: String) -> (samples: [Float], sampleRate: Double)? {
        guard let tts = loaded() else { return nil }
        let spoken = SpeechText.forSpeech(text)
        guard !spoken.isEmpty, let audio = SherpaOnnxOfflineTtsGenerate(tts, spoken, Self.speakerID, Self.speed) else { return nil }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }
        let result = audio.pointee
        guard result.n > 0, let samples = result.samples else { return nil }
        return (Array(UnsafeBufferPointer(start: samples, count: Int(result.n))), Double(result.sample_rate))
    }

    /// ¿Está el modelo dentro de la app? (Para Ajustes: decir qué voz se va a oír.)
    nonisolated static var isInstalled: Bool { modelFolder != nil }

    private nonisolated static var modelFolder: URL? {
        guard let folder = Bundle.main.url(forResource: "Kokoro", withExtension: nil),
              FileManager.default.fileExists(atPath: folder.appending(path: "model.int8.onnx").path(percentEncoded: false))
        else { return nil }
        return folder
    }

    private func loaded() -> OpaquePointer? {
        if let tts { return tts }
        guard !failed, let folder = Self.modelFolder else { return nil }
        // Las rutas se pasan como cadenas de C; sherpa-onnx las copia al crear el motor, así que se
        // pueden liberar justo después.
        var owned: [UnsafeMutablePointer<CChar>] = []
        func c(_ text: String) -> UnsafePointer<CChar>? {
            guard let copy = strdup(text) else { return nil }
            owned.append(copy)
            return UnsafePointer(copy)
        }
        defer { owned.forEach { free($0) } }
        func path(_ name: String) -> String { folder.appending(path: name).path(percentEncoded: false) }

        var config = SherpaOnnxOfflineTtsConfig()
        config.model.kokoro.model = c(path("model.int8.onnx"))
        config.model.kokoro.voices = c(path("voices.bin"))
        config.model.kokoro.tokens = c(path("tokens.txt"))
        config.model.kokoro.data_dir = c(path("espeak-ng-data"))
        config.model.kokoro.lang = c("es")
        config.model.kokoro.length_scale = 1
        config.model.num_threads = 2
        config.model.provider = c("cpu")
        config.max_num_sentences = 1
        guard let created = SherpaOnnxCreateOfflineTts(&config) else {
            failed = true
            Self.logger.error("No se ha podido cargar Kokoro")
            return nil
        }
        tts = created
        return tts
    }
}
