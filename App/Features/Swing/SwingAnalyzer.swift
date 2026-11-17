import AVFoundation
import Foundation
import GolfCore
import os
@preconcurrency import Vision

/// Avance en directo del análisis del swing (lo enseña "Revisa las posiciones" mientras trabaja).
struct SwingLive: Sendable, Equatable {
    enum Step: Sendable, Equatable {
        case audio, pose, phases
    }

    var step: Step = .audio
    var frame = 0
    var totalFrames = 0
    /// Fotogramas en los que Vision ha visto a alguien.
    var posesFound = 0
    var progress: Double = 0
}

/// Lo que vio el detector en cada fotograma: para el registro de depuración y para dibujar el
/// esqueleto encima del vídeo cuando algo falla (modo diagnóstico).
struct PoseDebug: Sendable {
    var videoWidth: Int
    var videoHeight: Int
    /// Tamaño del búfer que entra a Vision y la orientación que se le pasa.
    var bufferSize: String
    var orientation: String
    /// Pose de cada fotograma analizado (ya en píxeles del vídeo girado), sin suavizar.
    var frames: [PoseFrame]
    /// Una línea por fotograma y las conclusiones del final.
    var lines: [String]

    /// El registro como texto, para compartirlo desde la app.
    var text: String { lines.joined(separator: "\n") }
}

enum SwingError: LocalizedError {
    /// Vision no ve a nadie (o casi nunca): falla la comprobación de la persona.
    case nobodyVisible(PoseDebug)
    /// Se ve al jugador, pero no se reconoce un swing completo (subida, top e impacto).
    case noSwing(PoseDebug)
    case tooShort

    var errorDescription: String? {
        switch self {
        case .nobodyVisible:
            "No se ve a nadie en el vídeo. Graba con el cuerpo entero y el palo dentro del encuadre."
        case .noSwing:
            "Te veo, pero no encuentro un swing completo en este vídeo (la subida, el top y el impacto). Comprueba que el clip incluye el swing entero."
        case .tooShort:
            "Este vídeo es demasiado corto. Necesita al menos 1 s antes y 1 s después del golpe."
        }
    }

    var debug: PoseDebug? {
        switch self {
        case let .nobodyVisible(debug), let .noSwing(debug): debug
        case .tooShort: nil
        }
    }
}

/// El análisis del swing (docs/04, puntos 1 a 3): pose de Vision a ~120 fps, limpieza y suavizado,
/// impacto por el sonido contrastado con el movimiento (`SwingImpactChooser`) y las 7 posiciones.
/// El palo llega después, desde la pantalla de revisión (toque del usuario, seguimiento y líneas).
///
/// Ojo: aquí no se comprueba el palo. "Hay alguien" y "hay un swing" son dos comprobaciones
/// distintas, con mensajes distintos (antes las dos acababan en "No se ve a nadie").
enum SwingAnalyzer {
    /// Correspondencia entre los nombres de Vision y los de GolfCore (son los mismos).
    private static let jointNames: [(HumanBodyPoseObservation.JointName, GolfCore.Joint)] = [
        (.nose, .nose), (.leftEye, .leftEye), (.rightEye, .rightEye), (.leftEar, .leftEar), (.rightEar, .rightEar),
        (.neck, .neck), (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow), (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.root, .root), (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee), (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
    ]

    /// Confianza mínima de una articulación (docs/04, punto 1).
    static let minimumJointConfidence: Float = 0.3
    /// Un fotograma "tiene persona" con al menos estas articulaciones fiables.
    static let minimumJointsForPerson = 4

    private static let logger = Logger(subsystem: "io.github.dvidaldedompablo.trazo", category: "SwingAnalyzer")

    /// Analiza el clip entero. `knownImpact` es el instante del corte automático, si lo hubo:
    /// se trata como un candidato más, porque puede ser un pico de música y no el palo.
    @concurrent
    static func analyze(url: URL, knownImpact: Double?, handedness: Handedness, heightCentimeters: Double,
                        progress: AsyncStream<SwingLive>.Continuation) async throws -> SwingAnalysis {
        var live = SwingLive()
        var timings: [StepTiming] = []
        var notes: [String] = []
        var log: [String] = []
        var stepStart = ContinuousClock.now
        func lap(_ name: String) {
            let now = ContinuousClock.now
            let elapsed = stepStart.duration(to: now)
            timings.append(StepTiming(name: name, seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18))
            stepStart = now
        }

        // 1. Vídeo y sonido: fps reales y todos los candidatos a impacto del sonido.
        let info = try await VideoInspector.info(of: url, measureFrames: true)
        guard info.duration >= 1.5 else { throw SwingError.tooShort }
        let fps = info.frameRate
        let reader = try await FrameReader.open(url, frameRate: fps)
        let geometry = reader.geometry
        var soundCandidates: [Impact] = []
        if info.hasAudio {
            let samples = try await AudioExtractor.monoSamples(from: url)
            soundCandidates = ImpactDetector.detect(samples: samples, sampleRate: AudioExtractor.sampleRate)
        }
        if let knownImpact, !soundCandidates.contains(where: { abs($0.time - knownImpact) < 0.05 }) {
            soundCandidates.append(Impact(time: knownImpact, strength: 1, prominence: 1))
        }
        log.append("Vídeo: \(geometry.width) x \(geometry.height) girado, \(String(format: "%.2f", info.duration)) s, "
                   + "\(String(format: "%.1f", info.nominalFrameRate)) fps nominales, \(String(format: "%.1f", fps)) fps medidos, "
                   + "rotación \(geometry.rotation)°, orientación para Vision \(geometry.visionOrientation.rawValue), códec \(info.codec)")
        log.append("Sonido: \(soundCandidates.count) candidatos a impacto: "
                   + soundCandidates.map { String(format: "%.2f s (fuerza %.1f)", $0.time, $0.strength) }.joined(separator: ", "))
        lap("Vídeo y sonido")

        // 2. Pose por fotograma, a la mitad de fps si el vídeo va a 180 o más (docs/04: 120 de 240).
        //    Los instantes son los reales de cada fotograma (el vídeo puede ser de frecuencia variable).
        let step = fps >= 180 ? 2 : 1
        let analysisFps = fps / Double(step)
        live.step = .pose
        live.totalFrames = max(Int(info.duration * analysisFps), 1)
        progress.yield(live)

        let request = DetectHumanBodyPoseRequest()
        let size = CGSize(width: geometry.width, height: geometry.height)
        var frames: [PoseFrame] = []
        var found = 0
        var frameIndex = 0
        var bufferSize = "?"
        try await reader.read(from: 0, to: info.duration) { sample, pixels, time in
            defer { frameIndex += 1 }
            guard frameIndex % step == 0 else { return true }
            bufferSize = "\(CVPixelBufferGetWidth(pixels)) x \(CVPixelBufferGetHeight(pixels))"
            let observations = try await request.perform(on: sample, orientation: geometry.visionOrientation)
            // Si Vision ve a más de una persona, la del cuerpo más grande (el jugador llena el encuadre).
            var joints: [GolfCore.Joint: Point2D] = [:]
            var confidences: [String] = []
            var bestStature = -1.0
            for observation in observations {
                var candidate: [GolfCore.Joint: Point2D] = [:]
                var candidateConfidences: [String] = []
                for (visionName, joint) in Self.jointNames {
                    guard let seen = observation.joint(for: visionName) else { continue }
                    candidateConfidences.append("\(joint.rawValue)=\(String(format: "%.2f", seen.confidence))")
                    guard seen.confidence >= Self.minimumJointConfidence else { continue }
                    let p = seen.location.toImageCoordinates(size, origin: .upperLeft)
                    candidate[joint] = Point2D(Double(p.x), Double(p.y))
                }
                let stature = PoseFrame(time: time, joints: candidate).staturePixels(handedness: handedness) ?? Double(candidate.count)
                if stature > bestStature {
                    joints = candidate
                    confidences = candidateConfidences
                    bestStature = stature
                }
            }
            let hasPerson = joints.count >= Self.minimumJointsForPerson
            if hasPerson { found += 1 }
            frames.append(PoseFrame(time: time, joints: joints))
            log.append(String(format: "%7.3f s", time) + " búfer \(bufferSize) personas=\(observations.count) "
                       + "fiables=\(joints.count) \(hasPerson ? "persona" : "SIN PERSONA (< \(Self.minimumJointsForPerson) articulaciones)") "
                       + "manos=\(PoseFrame(time: time, joints: joints).hands == nil ? "no" : "sí") | "
                       + confidences.joined(separator: " "))
            if frames.count % 10 == 0 {
                live.frame = frames.count
                live.posesFound = found
                live.progress = 0.05 + 0.8 * Double(frames.count) / Double(max(live.totalFrames, 1))
                progress.yield(live)
            }
            return true
        }
        lap("Pose")

        var debug = PoseDebug(videoWidth: geometry.width, videoHeight: geometry.height, bufferSize: bufferSize,
                              orientation: "\(geometry.visionOrientation.rawValue)", frames: frames, lines: log)
        func finishLog(_ line: String) {
            debug.lines.append(line)
            logger.info("\(line, privacy: .public)")
        }

        // Comprobación 1: hay una persona. Se ignoran los fotogramas sin nadie (la cámara que se
        // va con la bola, por ejemplo); basta con que se vea en un tercio de ellos.
        let needed = max(frames.count / 3, 10)
        finishLog("Comprobación de la persona: \(found) de \(frames.count) fotogramas con persona (hacen falta \(needed)) → \(found >= needed ? "pasa" : "FALLA")")
        guard found >= needed else { throw SwingError.nobodyVisible(debug) }

        // Comprobación 2: hay un swing, con el impacto contrastado entre sonido y manos.
        live.step = .phases
        live.progress = 0.9
        progress.yield(live)
        let smoothed = PoseSeries.process(frames)
        let choice: SwingImpactChooser.Choice
        switch SwingImpactChooser.choose(frames: smoothed, soundCandidates: soundCandidates, handedness: handedness) {
        case let .success(chosen):
            choice = chosen
        case let .failure(reason):
            finishLog("Comprobación del swing: FALLA (\(reason == .noHands ? "no se ven las manos" : "ningún instante da subida, top e impacto"))")
            throw SwingError.noSwing(debug)
        }
        let phases = choice.phases
        finishLog("Comprobación del swing: pasa. Impacto " + (choice.soundTime.map { String(format: "%.2f s por el sonido", $0) } ?? "por el movimiento de las manos")
                  + (knownImpact.map { String(format: " (el corte automático decía %.2f s)", $0) } ?? ""))
        finishLog("Posiciones: " + phases.positions.map { String(format: "%@ %.2f s%@", $0.position.title, $0.time, $0.isDoubtful ? " (dudosa)" : "") }.joined(separator: ", "))
        finishLog("El palo no se comprueba aquí: se marca después, en Revisa las posiciones.")
        if choice.soundTime == nil {
            notes.append("No se oyó el impacto del palo: salió del movimiento de las manos.")
        } else if let knownImpact, let soundTime = choice.soundTime, abs(soundTime - knownImpact) > 0.1 {
            notes.append(String(format: "El sonido más fuerte (%.2f s) no era el palo: el impacto es el de %.2f s.", knownImpact, soundTime))
        }
        lap("Posiciones")

        live.progress = 1
        progress.yield(live)
        var analysis = SwingAnalysis(videoWidth: geometry.width, videoHeight: geometry.height,
                                     frameRate: fps, analysisFrameRate: analysisFps,
                                     impactTime: choice.soundTime ?? phases[.impact].time, impactFromSound: choice.soundTime != nil,
                                     poses: smoothed, phases: phases, handedness: handedness,
                                     heightCentimeters: heightCentimeters,
                                     notes: notes, timings: timings)
        analysis.debugLog = debug.text
        return analysis
    }

    // MARK: El palo (docs/04, punto 4)

    /// Sigue la cabeza del palo desde el toque en la preparación hasta el takeaway, con un parche
    /// y correlación normalizada. Si el parecido cae, devuelve `nil` y la coloca el usuario.
    @concurrent
    static func trackClubHead(url: URL, analysis: SwingAnalysis, addressPoint: Point2D) async throws -> Point2D? {
        let reader = try await FrameReader.open(url, frameRate: analysis.frameRate)
        let geometry = reader.geometry
        let start = analysis.poses[analysis.phases[.address].frameIndex].time
        let end = analysis.poses[analysis.phases[.takeaway].frameIndex].time
        guard end > start else { return nil }

        var template: GrayImage?
        var center = addressPoint
        var score = 1.0
        try await reader.read(from: start, to: end + 0.5 / analysis.frameRate) { _, pixels, _ in
            // Recorte a resolución completa alrededor de la última posición conocida.
            let rect = PixelRect(x: Int(center.x) - 80, y: Int(center.y) - 80, width: 160, height: 160)
                .clamped(width: geometry.width, height: geometry.height)
            guard let crop = LumaSampler.crop(pixels, geometry: geometry, rect: rect) else { return false }
            let local = Point2D(center.x - Double(rect.x), center.y - Double(rect.y))
            if let template {
                guard let found = TemplateTracker.find(template, in: crop, around: local, searchRadius: 26) else { return false }
                score = min(score, found.score)
                center = Point2D(found.center.x + Double(rect.x), found.center.y + Double(rect.y))
            } else {
                template = TemplateTracker.template(from: crop, center: local, radius: 13)
            }
            return score > 0.35
        }
        // Un parecido bajo en algún fotograma = seguimiento perdido: mejor no proponer nada.
        return score > 0.35 ? center : nil
    }

    /// Propone la línea del palo en la mitad de subida o la transición (bordes y votación de rectas).
    @concurrent
    static func proposeClubLine(url: URL, analysis: SwingAnalysis, position: SwingPosition) async throws -> ClubLine? {
        guard let hands = analysis.poses[analysis.phases[position].frameIndex].hands else { return nil }
        let reader = try await FrameReader.open(url, frameRate: analysis.frameRate)
        let geometry = reader.geometry
        let time = analysis.poses[analysis.phases[position].frameIndex].time
        var line: ClubLine?
        try await reader.read(from: time - 0.5 / analysis.frameRate, to: time + 0.5 / analysis.frameRate) { _, pixels, _ in
            // A media resolución sobra para la varilla y va cuatro veces más rápido.
            let gray = LumaSampler.reduced(pixels, geometry: geometry, factor: 2)
            if let found = ClubLineFinder.find(in: gray, hands: hands / 2,
                                               maximumLength: Double(geometry.height) * 0.35 / 2) {
                line = ClubLine(grip: found.grip * 2, head: found.head * 2)
            }
            return false
        }
        return line
    }
}
