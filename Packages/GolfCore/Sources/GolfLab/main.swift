import Foundation
import GolfCore

// Herramienta del laboratorio (docs/10, Fase 1): pasa vídeos del banco de pruebas por la lógica
// real de GolfCore y escribe el resultado en JSON. No cambia nada de la lógica: solo la llama.
// La app no la usa; se compila con Docker (imagen de Swift para Linux) desde lab/picos.py y
// scripts/evaluar.py.
//
// Uso:
//   GolfLab picos <audio.f32> <duracion-del-video-en-s>
//   GolfLab swing <poses.json> <audio.f32> <right|left>
//   GolfLab linea <imagen.pgm> <manos-x> <manos-y> <largo-maximo>
//   GolfLab seguir <x> <y> <fotograma1.pgm> <fotograma2.pgm> ...
// El audio va en PCM float32 little-endian, mono, a 48 kHz: el formato que da AudioExtractor en la app.
// Las imágenes van en PGM binario (P5, gris de 8 bits): la luminancia, como la lee la app.

// MARK: - Entrada

enum LabError: Error, CustomStringConvertible {
    case usage
    case unreadable(String)

    var description: String {
        switch self {
        case .usage:
            """
            Uso:
              GolfLab picos <audio.f32> <duracion-del-video-en-s>
              GolfLab swing <poses.json> <audio.f32> <right|left>
              GolfLab linea <imagen.pgm> <manos-x> <manos-y> <largo-maximo>
              GolfLab seguir <x> <y> <fotograma1.pgm> <fotograma2.pgm> ...
            """
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

/// Lee un PGM binario sin comentarios ("P5\n<ancho> <alto>\n255\n" y los píxeles), el que escribe OpenCV.
func readPGM(_ path: String) throws -> GrayImage {
    guard let data = FileManager.default.contents(atPath: path) else { throw LabError.unreadable(path) }
    let bytes = [UInt8](data)
    var fields: [String] = []
    var index = 0
    var current = ""
    // Cabecera: cuatro campos separados por espacios o saltos de línea; después, un separador y los datos.
    while fields.count < 4, index < bytes.count {
        let c = bytes[index]
        index += 1
        if c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 {
            if !current.isEmpty { fields.append(current); current = "" }
        } else {
            current.append(Character(UnicodeScalar(c)))
        }
    }
    guard fields.count == 4, fields[0] == "P5", let width = Int(fields[1]), let height = Int(fields[2]),
          fields[3] == "255", bytes.count - index >= width * height
    else { throw LabError.unreadable(path) }
    return GrayImage(width: width, height: height, pixels: Array(bytes[index..<(index + width * height)]))
}

/// Recorte de una imagen en gris (lo que hace `LumaSampler.crop` en la app con el búfer del vídeo).
func crop(_ image: GrayImage, _ rect: PixelRect) -> GrayImage? {
    guard rect.width > 0, rect.height > 0 else { return nil }
    var pixels = [UInt8]()
    pixels.reserveCapacity(rect.width * rect.height)
    for y in rect.y..<(rect.y + rect.height) {
        let row = y * image.width
        pixels.append(contentsOf: image.pixels[(row + rect.x)..<(row + rect.x + rect.width)])
    }
    return GrayImage(width: rect.width, height: rect.height, pixels: pixels)
}

func write<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(value))
    FileHandle.standardOutput.write(Data("\n".utf8))
}

// MARK: - picos: el detector de audio y el corte automático

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

// MARK: - swing: las posiciones con el mismo camino que SwingAnalyzer.analyze en la app

/// Una pose leída del JSON del laboratorio (MediaPipe en el PC en lugar de Vision).
struct PoseInput: Decodable {
    struct Point: Decodable { let x: Double; let y: Double }
    let time: Double
    let joints: [String: Point]
}

struct PositionReport: Encodable {
    let position: String
    let frameIndex: Int
    let time: Double
    let usedAlternative: Bool
    let doubtful: Bool
    /// Las manos (suavizadas) en ese fotograma: lo que usa la app para buscar la línea del palo.
    let hands: [Double]?
}

struct SwingReport: Encodable {
    let frames: Int
    let framesWithPerson: Int
    let soundCandidates: [[Double]]   // [instante, fuerza]
    let ok: Bool
    let failure: String?
    let soundTime: Double?
    let syncOffset: Double
    /// El impacto que guarda la app (`SwingAnalysis.impactTime`).
    let impactTime: Double?
    let backswingStartTime: Double?
    let positions: [PositionReport]
}

func swing(posesPath: String, audioPath: String, handedness: Handedness) throws -> SwingReport {
    guard let data = FileManager.default.contents(atPath: posesPath) else { throw LabError.unreadable(posesPath) }
    let input = try JSONDecoder().decode([PoseInput].self, from: data)
    let frames = input.map { pose in
        PoseFrame(time: pose.time, joints: Dictionary(uniqueKeysWithValues: pose.joints.compactMap { name, p in
            Joint(rawValue: name).map { ($0, Point2D(x: p.x, y: p.y)) }
        }))
    }
    // Igual que la app: todos los candidatos del sonido (sin impacto conocido del corte automático).
    let soundCandidates = ImpactDetector.detect(samples: try readSamples(audioPath), sampleRate: 48_000)
    // La app exige 4 articulaciones fiables para contar a una persona (SwingAnalyzer.minimumJointsForPerson).
    let withPerson = frames.filter { $0.joints.count >= 4 }.count
    let smoothed = PoseSeries.process(frames)
    let candidates = soundCandidates.map { [$0.time, $0.strength] }
    switch SwingImpactChooser.choose(frames: smoothed, soundCandidates: soundCandidates, handedness: handedness) {
    case let .failure(reason):
        return SwingReport(frames: frames.count, framesWithPerson: withPerson, soundCandidates: candidates, ok: false,
                           failure: reason == .noHands ? "noHands" : "noSwing", soundTime: nil, syncOffset: 0,
                           impactTime: nil, backswingStartTime: nil, positions: [])
    case let .success(choice):
        let phases = choice.phases
        let positions = phases.positions.map { p in
            PositionReport(position: "\(p.position)", frameIndex: p.frameIndex, time: p.time,
                           usedAlternative: p.usedAlternative, doubtful: p.isDoubtful,
                           hands: smoothed[p.frameIndex].hands.map { [$0.x, $0.y] })
        }
        let impact = choice.syncOffset == 0 ? (choice.soundTime ?? phases[.impact].time) : phases[.impact].time
        return SwingReport(frames: frames.count, framesWithPerson: withPerson, soundCandidates: candidates, ok: true,
                           failure: nil, soundTime: choice.soundTime, syncOffset: choice.syncOffset,
                           impactTime: impact, backswingStartTime: phases.backswingStartTime, positions: positions)
    }
}

// MARK: - linea: la línea del palo (SwingAnalyzer.proposeClubLine)

struct LineReport: Encodable {
    let grip: [Double]?
    let head: [Double]?
}

func line(imagePath: String, hands: Point2D, maximumLength: Double) throws -> LineReport {
    let image = try readPGM(imagePath)
    guard let found = ClubLineFinder.find(in: image, hands: hands, maximumLength: maximumLength) else {
        return LineReport(grip: nil, head: nil)
    }
    return LineReport(grip: [found.grip.x, found.grip.y], head: [found.head.x, found.head.y])
}

// MARK: - seguir: la cabeza del palo de la preparación al takeaway (SwingAnalyzer.trackClubHead)

struct TrackReport: Encodable {
    /// Dónde acaba la cabeza del palo; `nil` si el seguimiento se perdió (la app no propone nada).
    let found: [Double]?
    let minimumScore: Double
    let centers: [[Double]]
}

func track(start: Point2D, paths: [String]) throws -> TrackReport {
    // Mismos números que la app: recorte de 160 px, parche de radio 13, búsqueda de ±26 px y
    // seguimiento perdido si el parecido baja de 0,35 en algún fotograma.
    var template: GrayImage?
    var center = start
    var score = 1.0
    var centers: [[Double]] = []
    for path in paths {
        let image = try readPGM(path)
        let rect = PixelRect(x: Int(center.x) - 80, y: Int(center.y) - 80, width: 160, height: 160)
            .clamped(width: image.width, height: image.height)
        guard let piece = crop(image, rect) else { score = -1; break }
        let local = Point2D(x: center.x - Double(rect.x), y: center.y - Double(rect.y))
        if let template {
            guard let found = TemplateTracker.find(template, in: piece, around: local, searchRadius: 26) else {
                score = -1
                break
            }
            score = min(score, found.score)
            center = Point2D(x: found.center.x + Double(rect.x), y: found.center.y + Double(rect.y))
        } else {
            template = TemplateTracker.template(from: piece, center: local, radius: 13)
        }
        centers.append([center.x, center.y])
        if !(score > 0.35) { break }
    }
    return TrackReport(found: score > 0.35 ? [center.x, center.y] : nil, minimumScore: score, centers: centers)
}

// MARK: - Arranque

do {
    let a = CommandLine.arguments
    switch a.count > 1 ? a[1] : "" {
    case "picos":
        guard a.count == 4, let seconds = Double(a[3]) else { throw LabError.usage }
        try write(try peaks(audioPath: a[2], videoSeconds: seconds))
    case "swing":
        guard a.count == 5, let handedness = Handedness(rawValue: a[4]) else { throw LabError.usage }
        try write(try swing(posesPath: a[2], audioPath: a[3], handedness: handedness))
    case "linea":
        guard a.count == 6, let x = Double(a[3]), let y = Double(a[4]), let length = Double(a[5]) else { throw LabError.usage }
        try write(try line(imagePath: a[2], hands: Point2D(x: x, y: y), maximumLength: length))
    case "seguir":
        guard a.count >= 5, let x = Double(a[2]), let y = Double(a[3]) else { throw LabError.usage }
        try write(try track(start: Point2D(x: x, y: y), paths: Array(a[4...])))
    default:
        throw LabError.usage
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
