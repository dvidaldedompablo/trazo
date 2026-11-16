import AVFoundation
import Foundation
import GolfCore
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

enum SwingError: LocalizedError {
    case nobodyVisible
    case tooShort

    var errorDescription: String? {
        switch self {
        case .nobodyVisible:
            "No se ve a nadie en el vídeo. Graba con el cuerpo entero y el palo dentro del encuadre."
        case .tooShort:
            "Este vídeo es demasiado corto. Necesita al menos 1 s antes y 1 s después del golpe."
        }
    }
}

/// El análisis del swing (docs/04, puntos 1 a 3): pose de Vision a ~120 fps, limpieza y suavizado,
/// impacto por el sonido y las 7 posiciones con `PhaseDetector`. El palo llega después, desde la
/// pantalla de revisión (toque del usuario, seguimiento y líneas propuestas).
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

    /// Analiza el clip entero. `knownImpact` es el instante del corte automático, si lo hubo.
    @concurrent
    static func analyze(url: URL, knownImpact: Double?, handedness: Handedness, heightCentimeters: Double,
                        progress: AsyncStream<SwingLive>.Continuation) async throws -> SwingAnalysis {
        var live = SwingLive()
        var timings: [StepTiming] = []
        var notes: [String] = []
        var stepStart = ContinuousClock.now
        func lap(_ name: String) {
            let now = ContinuousClock.now
            let elapsed = stepStart.duration(to: now)
            timings.append(StepTiming(name: name, seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18))
            stepStart = now
        }

        // 1. Vídeo y sonido: fps reales y el impacto por el sonido.
        let info = try await VideoInspector.info(of: url, measureFrames: true)
        guard info.duration >= 1.5 else { throw SwingError.tooShort }
        let fps = info.frameRate
        let reader = try await FrameReader.open(url, frameRate: fps)
        let geometry = reader.geometry
        var impactTime: Double?
        if let knownImpact {
            impactTime = knownImpact
        } else if info.hasAudio {
            let samples = try await AudioExtractor.monoSamples(from: url)
            let impacts = ImpactDetector.detect(samples: samples, sampleRate: AudioExtractor.sampleRate)
            // En un clip de swing solo debería sonar un golpe: el más fuerte.
            impactTime = impacts.max { $0.strength < $1.strength }?.time
        }
        if impactTime == nil {
            notes.append("No se oyó el impacto: salió del movimiento de las manos.")
        }
        lap("Vídeo y sonido")

        // 2. Pose por fotograma, a la mitad de fps si el vídeo va a 180 o más (docs/04: 120 de 240).
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
        try await reader.read(from: 0, to: info.duration) { sample, _, time in
            defer { frameIndex += 1 }
            guard frameIndex % step == 0 else { return true }
            let observations = try await request.perform(on: sample, orientation: geometry.visionOrientation)
            // Si Vision ve a más de una persona, la del cuerpo más grande (el jugador llena el encuadre).
            var joints: [GolfCore.Joint: Point2D] = [:]
            var bestStature = 0.0
            for observation in observations {
                var candidate: [GolfCore.Joint: Point2D] = [:]
                for (visionName, joint) in Self.jointNames {
                    guard let seen = observation.joint(for: visionName), seen.confidence >= Self.minimumJointConfidence
                    else { continue }
                    let p = seen.location.toImageCoordinates(size, origin: .upperLeft)
                    candidate[joint] = Point2D(Double(p.x), Double(p.y))
                }
                let frame = PoseFrame(time: time, joints: candidate)
                let stature = frame.staturePixels(handedness: handedness) ?? 0
                if candidate.count > joints.count || stature > bestStature {
                    joints = candidate
                    bestStature = stature
                }
            }
            if joints.count >= 4 { found += 1 }
            frames.append(PoseFrame(time: time, joints: joints))
            if frames.count % 10 == 0 {
                live.frame = frames.count
                live.posesFound = found
                live.progress = 0.05 + 0.8 * Double(frames.count) / Double(max(live.totalFrames, 1))
                progress.yield(live)
            }
            return true
        }
        lap("Pose")
        // En menos de un tercio de los fotogramas hay alguien: no se puede analizar.
        guard found >= max(frames.count / 3, 10) else { throw SwingError.nobodyVisible }

        // 3. Limpieza, suavizado y las 7 posiciones.
        live.step = .phases
        live.progress = 0.9
        progress.yield(live)
        let smoothed = PoseSeries.process(frames)
        guard let phases = PhaseDetector.detect(frames: smoothed, impactTime: impactTime, handedness: handedness)
        else { throw SwingError.nobodyVisible }
        lap("Posiciones")

        live.progress = 1
        progress.yield(live)
        return SwingAnalysis(videoWidth: geometry.width, videoHeight: geometry.height,
                             frameRate: fps, analysisFrameRate: analysisFps,
                             impactTime: impactTime ?? phases[.impact].time, impactFromSound: impactTime != nil,
                             poses: smoothed, phases: phases, handedness: handedness,
                             heightCentimeters: heightCentimeters,
                             notes: notes, timings: timings)
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
