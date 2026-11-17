import AVFAudio
import Foundation
import GolfCore

/// Una palabra con su instante dentro de la pista de voz (para los subtítulos palabra a palabra).
struct SubtitleWord: Sendable, Equatable {
    var text: String
    /// Segundos desde el principio de la pista.
    var time: Double
    /// A qué frase pertenece (índice dentro de `VoiceTrack.lines`).
    var line: Int
}

/// Una frase ya colocada en la pista: su bloque, su texto y cuándo suena.
struct SpokenLine: Sendable, Equatable {
    var block: ScriptBlockKind
    var text: String
    var start: Double
    var end: Double
}

/// La pista de voz entera: muestras mono, frases y palabras con sus tiempos.
struct VoiceTrack: Sendable {
    var samples: [Float]
    var sampleRate: Double
    var lines: [SpokenLine]
    var words: [SubtitleWord]
    /// Cuándo empieza la narración de cada bloque y cuánto dura.
    var blocks: [ScriptBlockKind: (start: Double, duration: Double)]

    var duration: Double { Double(samples.count) / sampleRate }
}

/// Una frase sintetizada, aún sin colocar: muestras y palabras relativas al principio de la frase.
struct RenderedLine: Sendable {
    var text: String
    var samples: [Float]
    var sampleRate: Double
    /// (rango de la palabra en el texto, segundos desde el principio de la frase)
    var wordTimes: [(range: NSRange, time: Double)]

    var duration: Double { Double(samples.count) / sampleRate }
}

/// Voz del análisis (docs/04, punto 9): cada frase se sintetiza por separado con
/// `AVSpeechSynthesizer.write(_:toBufferCallback:toMarkerCallback:)`, que da el audio y el
/// instante de cada palabra. Después `VoiceTrackBuilder` monta la pista con los silencios.
enum VoiceSynthesizer {
    /// Velocidad elegida para rondar las 155 palabras por minuto de docs/04 (a afinar oyéndola).
    static let rate: Float = 0.5

    /// La voz elegida en Ajustes o, si no hay, la mejor de español de España que esté instalada.
    static func voice() -> AVSpeechSynthesisVoice? {
        let chosen = UserDefaults.standard.string(forKey: SettingsKey.analysisVoice) ?? ""
        if !chosen.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: chosen) { return voice }
        return bestSpanishVoice()
    }

    /// Voces que tiene sentido ofrecer para narrar. Fuera las de broma (Bubbles, Zarvox…) y las
    /// Eloquence (Eddy, Flo, Grandma…): son sintéticas a propósito y es lo que suena a robot.
    static func isNarrationVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        !voice.voiceTraits.contains(.isNoveltyVoice) && !voice.identifier.contains("eloquence")
    }

    /// Las voces en español para narrar: es-ES primero y, dentro, de más a menos calidad.
    static func spanishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("es") && isNarrationVoice($0) && !$0.voiceTraits.contains(.isPersonalVoice) }
            .sorted { a, b in
                if (a.language == "es-ES") != (b.language == "es-ES") { return a.language == "es-ES" }
                if a.quality != b.quality { return a.quality.rawValue > b.quality.rawValue }
                return a.name < b.name
            }
    }

    /// Las voces personales del usuario (las crea él en Ajustes de iOS leyendo frases).
    /// Solo aparecen si ha dado permiso a la app.
    static func personalVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.voiceTraits.contains(.isPersonalVoice) }
    }

    /// Español de España primero; a igual región, la de más calidad (premium > mejorada > normal).
    static func bestSpanishVoice() -> AVSpeechSynthesisVoice? {
        spanishVoices().max { a, b in
            let regionA = a.language == "es-ES" ? 1 : 0
            let regionB = b.language == "es-ES" ? 1 : 0
            if regionA != regionB { return regionA < regionB }
            return a.quality.rawValue < b.quality.rawValue
        }
    }

    /// Sintetiza una frase y devuelve sus muestras y los instantes de sus palabras.
    @concurrent
    static func render(_ text: String, voiceIdentifier: String?) async throws -> RenderedLine {
        let utterance = AVSpeechUtterance(string: text)
        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "es-ES")
        }
        utterance.rate = rate

        let collector = Collector()
        let synthesizer = AVSpeechSynthesizer()
        return try await withCheckedThrowingContinuation { continuation in
            synthesizer.write(utterance) { buffer in
                // Un búfer sin fotogramas marca el final de la frase.
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    // Solo el primer búfer vacío cierra la frase (por si llegara más de uno).
                    if let result = collector.finish(text: text) { continuation.resume(with: result) }
                } else {
                    collector.add(pcm)
                }
            } toMarkerCallback: { markers in
                collector.add(markers)
            }
        }
    }

    /// Junta los búferes y los marcadores que van llegando de la síntesis (en su cola interna).
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var samples: [Float] = []
        private var sampleRate = 22050.0
        private var bytesPerFrame = 4
        private var markers: [(range: NSRange, byteOffset: Int)] = []

        func add(_ buffer: AVAudioPCMBuffer) {
            lock.lock()
            defer { lock.unlock() }
            sampleRate = buffer.format.sampleRate
            bytesPerFrame = max(Int(buffer.format.streamDescription.pointee.mBytesPerFrame), 1)
            let count = Int(buffer.frameLength)
            // La voz llega en float32 o en int16 según la voz instalada: se pasa todo a float.
            if let floats = buffer.floatChannelData {
                samples.append(contentsOf: UnsafeBufferPointer(start: floats[0], count: count))
            } else if let ints = buffer.int16ChannelData {
                samples.append(contentsOf: UnsafeBufferPointer(start: ints[0], count: count).map { Float($0) / 32768 })
            }
        }

        func add(_ incoming: [AVSpeechSynthesisMarker]) {
            lock.lock()
            defer { lock.unlock() }
            for marker in incoming where marker.mark == .word {
                markers.append((marker.textRange, marker.byteSampleOffset))
            }
        }

        private var finished = false

        func finish(text: String) -> Result<RenderedLine, Error>? {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return nil }
            finished = true
            guard !samples.isEmpty else {
                return .failure(MediaError.exportFailed("la voz no ha producido audio"))
            }
            let duration = Double(samples.count) / sampleRate
            let wordTimes = markers.map { marker in
                // El marcador trae un desplazamiento en bytes dentro del audio.
                var time = Double(marker.byteOffset) / Double(bytesPerFrame) / sampleRate
                // Red de seguridad por si alguna voz lo diera ya en muestras.
                if time > duration * 1.2 { time = Double(marker.byteOffset) / sampleRate }
                return (marker.range, min(max(time, 0), duration))
            }
            return .success(RenderedLine(text: text, samples: samples, sampleRate: sampleRate, wordTimes: wordTimes))
        }
    }
}

/// Monta la pista de voz: las frases de cada bloque en su sitio, con los silencios de docs/04
/// (0,45 s entre frases del mismo bloque) y normalizada a −16 LUFS con pico real ≤ −1 dBTP.
enum VoiceTrackBuilder {
    static let pauseWithinBlock = 0.45
    static let pauseBetweenBlocks = 1.2

    /// Coloca cada bloque donde diga `blockStarts` (si falta, seguido del anterior con la pausa larga).
    static func build(lines: [(block: ScriptBlockKind, rendered: RenderedLine)],
                      blockStarts: [ScriptBlockKind: Double] = [:]) -> VoiceTrack {
        let sampleRate = lines.first?.rendered.sampleRate ?? 22050
        var spoken: [SpokenLine] = []
        var words: [SubtitleWord] = []
        var blocks: [ScriptBlockKind: (start: Double, duration: Double)] = [:]
        var cursor = 0.0
        var currentBlock: ScriptBlockKind?
        var totalSamples = 0

        // Primera pasada: tiempos.
        var placed: [(start: Double, rendered: RenderedLine)] = []
        for line in lines {
            if line.block != currentBlock {
                if let start = blockStarts[line.block] {
                    cursor = max(cursor, start)
                } else if currentBlock != nil {
                    cursor += pauseBetweenBlocks
                }
                currentBlock = line.block
                blocks[line.block] = (cursor, 0)
            } else {
                cursor += pauseWithinBlock
            }
            let start = cursor
            placed.append((start, line.rendered))
            let lineIndex = spoken.count
            spoken.append(SpokenLine(block: line.block, text: line.rendered.text,
                                     start: start, end: start + line.rendered.duration))
            let text = line.rendered.text as NSString
            for (range, time) in line.rendered.wordTimes where range.location + range.length <= text.length {
                words.append(SubtitleWord(text: text.substring(with: range).trimmingCharacters(in: .whitespaces),
                                          time: start + time, line: lineIndex))
            }
            cursor += line.rendered.duration
            if let info = blocks[line.block] {
                blocks[line.block] = (info.start, cursor - info.start)
            }
            totalSamples = Int(cursor * sampleRate) + 1
        }

        // Segunda pasada: las muestras en su sitio, con silencio digital entre frases (docs/08).
        var samples = [Float](repeating: 0, count: totalSamples)
        for item in placed {
            let offset = Int(item.start * sampleRate)
            for (i, value) in item.rendered.samples.enumerated() where offset + i < samples.count {
                samples[offset + i] = value
            }
        }

        // Normalización (docs/04: −16 LUFS integrados, pico real ≤ −1 dBTP).
        if let integrated = Loudness.integratedLoudness(mono: samples, sampleRate: sampleRate) {
            let peak = Loudness.truePeak(samples)
            let gain = Loudness.linearGain(decibels: Loudness.normalizationGain(integrated: integrated, truePeak: peak))
            if gain.isFinite, gain > 0 {
                for i in samples.indices { samples[i] *= Float(gain) }
            }
        }

        return VoiceTrack(samples: samples, sampleRate: sampleRate, lines: spoken, words: words, blocks: blocks)
    }

    /// Escribe la pista en un archivo PCM (.caf) para reproducirla o montarla en el vídeo.
    static func writeFile(_ track: VoiceTrack, to url: URL) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: track.sampleRate,
                                         channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(track.samples.count))
        else { throw MediaError.exportFailed("formato de audio") }
        buffer.frameLength = AVAudioFrameCount(track.samples.count)
        track.samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: track.samples.count)
        }
        MediaStore.removeIfPresent(url)
        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }
}
