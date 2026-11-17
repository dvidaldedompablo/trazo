import Foundation
import GolfCore

// Herramienta del laboratorio (docs/10, Fase 1): pasa vídeos del banco de pruebas por la lógica
// real de GolfCore y escribe el resultado en JSON. No cambia nada de la lógica: solo la llama.
// La app no la usa; se compila con Docker (imagen de Swift para Linux) desde lab/picos.py.
//
// Uso:
//   GolfLab picos <audio.f32> <duracion-del-video-en-s>
// El audio va en PCM float32 little-endian, mono, a 48 kHz: el formato que da AudioExtractor en la app.

/// Lo que se escribe por cada impacto: lo que da el detector y lo que haría con él el corte automático.
struct PeakReport: Encodable {
    let time: Double
    let strength: Double
    let prominence: Double
    /// Fuerza dividida entre la del impacto más fuerte del clip (lo que compara el corte automático).
    let relativeStrength: Double
    /// El corte automático (modo Swing) lo propone como golpe.
    let suggested: Bool
    let tooShort: Bool
}

struct PeaksReport: Encodable {
    let sampleRate: Double
    let audioSeconds: Double
    let videoSeconds: Double
    /// `ClipPlanner.isShotSeries`: si es falso, el corte automático no propone ningún clip.
    let isShotSeries: Bool
    let suggestionFraction: Double
    let peaks: [PeakReport]
}

enum LabError: Error, CustomStringConvertible {
    case usage
    case unreadable(String)

    var description: String {
        switch self {
        case .usage: "Uso: GolfLab picos <audio.f32> <duracion-del-video-en-s>"
        case .unreadable(let path): "No puedo leer \(path)"
        }
    }
}

/// Lee un archivo de float32 little-endian (lo que escribe `ffmpeg -f f32le`).
func readSamples(_ path: String) throws -> [Float] {
    guard let data = FileManager.default.contents(atPath: path) else { throw LabError.unreadable(path) }
    let count = data.count / MemoryLayout<Float>.size
    return data.withUnsafeBytes { raw in
        (0..<count).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) }
    }
}

func peaks(audioPath: String, videoSeconds: Double) throws -> PeaksReport {
    let sampleRate = 48_000.0
    let samples = try readSamples(audioPath)
    // Igual que la app: todos los impactos del detector y la propuesta del corte automático en modo Swing.
    let impacts = ImpactDetector.detect(samples: samples, sampleRate: sampleRate)
    let proposal = ClipPlanner.propose(for: impacts, recordingDuration: videoSeconds, mode: .swing)
    let strongest = impacts.map(\.strength).max() ?? 0
    let reports = impacts.map { impact in
        // Si no parece una tanda de golpes, `windows` está vacío y nada queda propuesto.
        let window = proposal.windows.first { $0.impactTime == impact.time }
        return PeakReport(time: impact.time, strength: impact.strength, prominence: impact.prominence,
                          relativeStrength: strongest > 0 ? impact.strength / strongest : 0,
                          suggested: window?.isSuggested ?? false, tooShort: window?.isTooShort ?? false)
    }
    return PeaksReport(sampleRate: sampleRate, audioSeconds: Double(samples.count) / sampleRate,
                       videoSeconds: videoSeconds, isShotSeries: proposal.isShotSeries,
                       suggestionFraction: ClipPlanner.suggestionFraction, peaks: reports)
}

do {
    let arguments = CommandLine.arguments
    guard arguments.count == 4, arguments[1] == "picos", let seconds = Double(arguments[3]) else { throw LabError.usage }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(try peaks(audioPath: arguments[2], videoSeconds: seconds))
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
