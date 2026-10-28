@preconcurrency import AVFoundation
import Foundation
import GolfCore
import os

/// Un golpe que hay que convertir en tracer.
struct TracerJob: Sendable {
    let clipID: UUID
    let url: URL
    let origin: ClipOrigin
    /// Impacto que encontró el corte automático (s del clip), si lo hay.
    let knownImpact: Double?
    /// Bola tocada a mano (cuando el automático no la encontró).
    let manualBall: ManualBall?
    var club: ClubCategory = .longIrons
    var handedness: Handedness = .right
}

/// Los cuatro pasos de "Creando tu tracer" (s03).
enum TracerStep: Int, Sendable, Comparable {
    case impact, tracking, drawing, exporting

    static func < (a: TracerStep, b: TracerStep) -> Bool { a.rawValue < b.rawValue }
}

/// Lo que se va sabiendo mientras se crea el tracer: la pantalla s03 lo pinta en directo.
struct TracerLive: Sendable, Equatable {
    var step = TracerStep.impact
    /// Onda alrededor del impacto (de 0 a 1) y la barra del impacto.
    var bars: [Double] = []
    var impactBar: Int?
    var impactTime: Double?
    var impactFrame: Int?
    var impactSource: ImpactChooser.Source?
    /// Fotograma que se está siguiendo dentro de la ventana del vuelo.
    var frame = 0
    var totalFrames = 0
    /// Puntos de la bola encontrados, de 0 a 1 en el vídeo girado (para la miniatura).
    var points: [Point2D] = []
    /// Fotograma del impacto en JPEG (miniatura).
    var thumbnail: Data?
    /// De 0 a 1, para el círculo de "En proceso" en Tus vídeos.
    var progress = 0.0
}

/// Cómo acaba el análisis.
enum TracerPipelineResult: Sendable {
    case finished(TracerAnalysis)
    /// No hay confianza en la bola antes del impacto: hay que pedir un toque en ese fotograma.
    case needsBall(suggestedTime: Double, reason: String)
}

enum TracerError: LocalizedError {
    case noImpact
    case tooShort

    var errorDescription: String? {
        switch self {
        case .noImpact: "No se ha oído el impacto ni se ha visto salir la bola. Arrastra el marcador rojo hasta el momento del golpe."
        case .tooShort: "Este vídeo es demasiado corto. Necesita al menos 1 s antes y 1 s después del golpe."
        }
    }
}

/// El tracer automático (docs/03, pasos 1 a 6).
///
/// 1. Lee el vídeo y el sonido, y estima el impacto por el sonido.
/// 2. Busca la bola 0,3 s antes del impacto (en el más nítido de 11 fotogramas) y mira en qué fotograma
///    desaparece del tee: con eso se confirma el impacto (si el sonido y la imagen discrepan en más de
///    2 fotogramas, manda la imagen) y se sabe cuál de las candidatas es la bola.
/// 3. Lee la ventana del vuelo: fotogramas reducidos en gris para BlobTracker y, a la vez, Vision.
/// 4. Junta los puntos y monta el vuelo con `TracerAssembler`.
/// Todo va en otro hilo (`@concurrent`) y avisa de cada avance por `progress`.
enum TracerPipeline {
    /// Barras de la onda de s03 (1 s antes y 0,6 s después del impacto), como en la maqueta.
    static let waveformBars = 64
    /// Los fotogramas de BlobTracker se reducen a la mitad (540 x 960 desde 1080 x 1920).
    static let reduction = 2

    @concurrent
    static func run(_ job: TracerJob, progress: AsyncStream<TracerLive>.Continuation) async throws -> TracerPipelineResult {
        var live = TracerLive()
        var timings: [StepTiming] = []
        var notes: [String] = []
        var stepStart = ContinuousClock.now
        func lap(_ name: String) {
            let now = ContinuousClock.now
            let elapsed = stepStart.duration(to: now)
            timings.append(StepTiming(name: name, seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18))
            stepStart = now
        }

        // 1. Vídeo y sonido.
        let info = try await VideoInspector.info(of: job.url, measureFrames: true)
        let fps = info.frameRate
        let reader = try await FrameReader.open(job.url, frameRate: fps)
        let geometry = reader.geometry
        let samples = info.hasAudio ? try await AudioExtractor.monoSamples(from: job.url) : []
        let audioImpacts = ImpactDetector.detect(samples: samples, sampleRate: AudioExtractor.sampleRate)
        if !info.hasAudio { notes.append("El vídeo no tiene sonido: el impacto sale del movimiento.") }
        let audioGuess: Double? = {
            if let known = job.knownImpact {
                return audioImpacts.min { abs($0.time - known) < abs($1.time - known) }?.time ?? known
            }
            return audioImpacts.max { $0.strength < $1.strength }?.time
        }()
        if let guess = audioGuess {
            live.bars = waveform(samples, around: guess)
            live.impactBar = barIndex(for: guess, around: guess)
            live.progress = 0.05
            progress.yield(live)
        }
        lap("Vídeo y sonido")

        // 2. Bola antes del impacto y comprobación por movimiento.
        let stage = try await locateBallAndImpact(job: job, reader: reader, info: info, audioImpacts: audioImpacts,
                                                  audioGuess: audioGuess)
        lap("Bola e impacto")
        guard let ball = stage.ball, let impact = stage.impact else {
            return .needsBall(suggestedTime: stage.suggestedTime, reason: stage.reason)
        }
        guard impact.time >= 0.15, info.duration - impact.time >= 0.5 else { throw TracerError.tooShort }
        live.impactTime = impact.time
        live.impactFrame = Int((impact.time * fps).rounded())
        live.impactSource = impact.source
        live.bars = waveform(samples, around: impact.time)
        live.impactBar = barIndex(for: impact.time, around: impact.time)
        live.step = .tracking
        live.thumbnail = try? await FrameGrabber.jpeg(from: job.url, at: impact.time, maximumSize: CGSize(width: 540, height: 960),
                                                      exact: false)
        live.progress = 0.15
        progress.yield(live)

        // 3. Ventana del vuelo: BlobTracker y Vision a la vez.
        let step = max(Int((fps / TracerConstants.analysisFrameRate).rounded()), 1)
        let analysisFps = fps / Double(step)
        let start = impact.time - Double(TracerConstants.backgroundFrameCount + 2) / analysisFps
        let end = min(info.duration, impact.time + TracerConstants.flightAnalysisWindow)
        let total = max(Int((end - impact.time) * analysisFps), 1)
        live.totalFrames = total
        let collector = TrajectoryCollector(geometry: geometry, impactTime: impact.time,
                                            region: TrajectoryCollector.region(around: ball, geometry: geometry))
        var frames: [GrayImage] = []
        var frameTimes: [Double] = []
        var horizon: Double?
        var counter = 0
        try await reader.read(from: start, to: end) { sample, pixels, time in
            counter += 1
            guard (counter - 1) % step == 0 else { return true }
            let gray = LumaSampler.reduced(pixels, geometry: geometry, factor: reduction)
            if horizon == nil {
                horizon = HorizonFinder.find(in: gray).map { $0 * Double(reduction) }
            }
            frames.append(gray)
            frameTimes.append(time)
            if time >= impact.time - 0.5 / fps {
                await collector.process(sample, time: time)
                live.frame = min(Int(((time - impact.time) * analysisFps).rounded()), total)
                if live.frame % 6 == 0 {
                    live.points = normalized(collector.tracks.flatMap { $0.samples.map(\.point) }, geometry: geometry)
                    live.progress = 0.15 + 0.7 * Double(live.frame) / Double(total)
                    progress.yield(live)
                }
            }
            return true
        }
        if let failure = collector.failure {
            notes.append("Vision no ha podido seguir la bola (\(failure)). Sigue BlobTracker.")
        }
        lap("Lectura del vuelo y Vision")

        // BlobTracker sobre los fotogramas reducidos.
        var blobPoints: [SourcedSample] = []
        let impactIndex = frameTimes.firstIndex { $0 >= impact.time - 0.5 / fps } ?? 0
        let factor = Double(reduction)
        if impactIndex > 0, let tracker = BlobTracker(frames: frames, impactFrame: impactIndex, frameRate: analysisFps,
                                                      teePosition: ball / factor) {
            let track = tracker.trackFromBall(at: ball / factor)
            blobPoints = track.points.map { point in
                SourcedSample(TrajectorySample(time: frameTimes[point.frameIndex] - impact.time, point: point.point * factor),
                              source: .blob)
            }
        } else {
            notes.append("No hay fotogramas suficientes antes del impacto para el fondo de BlobTracker.")
        }
        frames.removeAll()
        lap("BlobTracker")

        // 4. Montaje.
        live.step = .drawing
        let visionPoints = TrajectorySelector.select(collector.tracks, ball: ball, imageWidth: Double(geometry.width))
            .flatMap { track in track.samples.map { SourcedSample($0, source: .vision) } }
        live.points = normalized((visionPoints + blobPoints).map(\.sample.point), geometry: geometry)
        live.progress = 0.9
        progress.yield(live)
        var analysis = TracerAnalysis(
            outcome: TracerAssembler.assemble(TracerInput(ball: ball, imageWidth: Double(geometry.width),
                                                          imageHeight: Double(geometry.height), points: [])).outcome,
            impactTime: impact.time, impactSource: impact.source, impactFrame: Int((impact.time * fps).rounded()),
            ball: ball, ballFromTap: job.manualBall != nil, videoWidth: geometry.width, videoHeight: geometry.height,
            frameRate: fps, horizonY: horizon, basePoints: visionPoints + blobPoints, notes: notes + stage.notes)
        var input = analysis.assemblerInput(club: job.club, handedness: job.handedness)
        if job.origin == .recorded {
            input.aimPoint = CaptureGuideGeometry.aim(videoWidth: geometry.width, videoHeight: geometry.height)
        }
        analysis.outcome = TracerAssembler.assemble(input).outcome
        lap("Montaje")
        analysis.timings = timings
        live.progress = 1
        progress.yield(live)
        return .finished(analysis)
    }

    // MARK: Bola e impacto

    struct BallStage {
        var ball: Point2D?
        var impact: ImpactChooser.Choice?
        var suggestedTime: Double
        var reason: String
        var notes: [String] = []
    }

    /// Busca la bola (o usa la tocada) y el fotograma en que desaparece; elige el impacto.
    static func locateBallAndImpact(job: TracerJob, reader: FrameReader, info: VideoInfo, audioImpacts: [Impact],
                                    audioGuess: Double?) async throws -> BallStage {
        let geometry = reader.geometry
        let fps = info.frameRate
        let w = geometry.width, h = geometry.height
        // Dónde está la bola quieta: 0,3 s antes del impacto oído; sin sonido, al principio del vídeo.
        let reference = audioGuess.map { $0 - TracerConstants.ballLookBack } ?? min(0.3, info.duration / 4)
        let scanEnd = audioGuess.map { min($0 + 0.4, info.duration) } ?? min(info.duration, 8)
        let sharpStart = reference - Double(TracerConstants.ballSharpnessFrames) / fps - 0.5 / fps
        let guide = CaptureGuideGeometry.ball(videoWidth: w, videoHeight: h)

        // Zona de búsqueda: alrededor de "Bola aquí" si se grabó con la app; si no, la parte de abajo.
        var region: PixelRect
        var prior: Point2D?
        var spread: Double
        if let manual = job.manualBall {
            region = PixelRect(x: Int(manual.point.x) - 40, y: Int(manual.point.y) - 40, width: 80, height: 80)
            prior = manual.point
            spread = 15
        } else if job.origin == .recorded {
            let half = Int(0.17 * Double(w))
            region = PixelRect(x: Int(guide.x) - half, y: Int(guide.y) - half, width: 2 * half, height: 2 * half)
            prior = guide
            spread = 0.08 * Double(w)
        } else {
            region = PixelRect(x: 0, y: Int(0.3 * Double(h)), width: w, height: h - Int(0.3 * Double(h)))
            prior = guide
            spread = 0.45 * Double(w)
        }
        region = region.clamped(width: w, height: h)
        let origin = Point2D(Double(region.x), Double(region.y))

        var references: [(time: Double, image: GrayImage)] = []
        var candidates: [BallCandidate]?
        var confidentLocation = false
        var chosenTime = reference
        var times: [Double] = []
        var contrasts: [[Double]] = []
        try await reader.read(from: max(sharpStart, 0), to: scanEnd) { _, pixels, time in
            if candidates == nil {
                if let crop = LumaSampler.crop(pixels, geometry: geometry, rect: region) { references.append((time, crop)) }
                guard time >= reference - 0.5 / fps, let current = references.last else { return true }
                // Primera búsqueda en el fotograma de referencia; luego, en el más nítido de los 11.
                var search = BallSearch(region: PixelRect(x: 0, y: 0, width: region.width, height: region.height),
                                        prior: prior.map { $0 - origin }, priorSpread: spread)
                if job.manualBall != nil { search.minimumContrast = 8 }
                let first = BallLocator.locate(in: current.image, search: search)
                guard let best = first.best else {
                    candidates = []
                    return false
                }
                let sharpest = references.max { a, b in
                    BallLocator.sharpness(of: a.image, around: best.center, radius: best.radius)
                        < BallLocator.sharpness(of: b.image, around: best.center, radius: best.radius)
                } ?? current
                let location = BallLocator.locate(in: sharpest.image, search: search)
                candidates = location.candidates.prefix(3).map { candidate in
                    var moved = candidate
                    moved.center = candidate.center + origin
                    return moved
                }
                confidentLocation = location.isConfident
                chosenTime = sharpest.time
                references.removeAll()
                contrasts = Array(repeating: [], count: candidates?.count ?? 0)
                return true
            }
            // Después: el contraste de cada candidata en cada fotograma, para ver cuál desaparece.
            times.append(time)
            for (index, candidate) in (candidates ?? []).enumerated() {
                let r = candidate.radius
                let box = PixelRect(x: Int(candidate.center.x - r) - 6, y: Int(candidate.center.y - r) - 6,
                                    width: Int(2 * r) + 13, height: Int(2 * r) + 13)
                if let crop = LumaSampler.crop(pixels, geometry: geometry, rect: box) {
                    let local = candidate.center - Point2D(Double(box.x), Double(box.y))
                    contrasts[index].append(BallLocator.coreContrast(in: crop, center: local, radius: r))
                } else {
                    contrasts[index].append(0)
                }
            }
            return true
        }

        guard let found = candidates, !found.isEmpty else {
            return BallStage(suggestedTime: reference, reason: "No he encontrado la bola antes del golpe. Tócala para seguir.")
        }
        // Fotogramas que seguro son de antes del impacto (la bola quieta): hasta 0,1 s antes del oído.
        let quietEnd = audioGuess.map { $0 - 0.1 } ?? (reference + 0.2)
        let referenceCount = max(times.filter { $0 < quietEnd }.count, 3)
        var moving: [(candidate: BallCandidate, time: Double)] = []
        for (index, candidate) in found.enumerated() {
            if let frame = BallMotion.disappearanceIndex(contrasts: contrasts[index], referenceCount: referenceCount) {
                moving.append((candidate, times[frame]))
            }
        }
        // La bola es la candidata que desaparece (la más cercana al impacto oído, si lo hay).
        let chosen = moving.min { a, b in
            guard let guess = audioGuess else { return a.time < b.time }
            return abs(a.time - guess) < abs(b.time - guess)
        }
        var notes: [String] = []
        let ball: BallCandidate
        if let chosen {
            ball = chosen.candidate
        } else if confidentLocation || job.manualBall != nil {
            ball = found[0]
            notes.append("La bola no se ha visto salir del tee: el impacto sale solo del sonido.")
        } else {
            return BallStage(suggestedTime: chosenTime,
                             reason: "No estoy seguro de cuál es la bola. Tócala en un fotograma nítido de antes del golpe.")
        }
        guard let impact = ImpactChooser.choose(audio: audioImpacts, motionTime: chosen?.time, frameDuration: 1 / fps) else {
            return BallStage(ball: nil, impact: nil, suggestedTime: chosenTime, reason: TracerError.noImpact.localizedDescription)
        }
        if impact.source == .motion, audioGuess != nil {
            notes.append("El sonido y la imagen no coincidían: manda el movimiento de la bola.")
        }
        return BallStage(ball: job.manualBall?.point ?? ball.center, impact: impact, suggestedTime: chosenTime, reason: "", notes: notes)
    }

    // MARK: Toque de refuerzo

    /// Vuelve a seguir la bola desde un toque (docs/03, paso 4 bis): BlobTracker hacia delante y hacia
    /// atrás desde ese fotograma, con la velocidad que ya se conocía, y Vision con una zona de interés
    /// centrada en el toque. Devuelve los puntos nuevos junto al toque (punto fijo).
    @concurrent
    static func reinforce(url: URL, analysis: TracerAnalysis, tap: TrajectorySample, velocity: Point2D) async throws -> Reinforcement {
        let fps = analysis.frameRate
        let reader = try await FrameReader.open(url, frameRate: fps)
        let geometry = reader.geometry
        let step = max(Int((fps / TracerConstants.analysisFrameRate).rounded()), 1)
        let analysisFps = fps / Double(step)
        let impact = analysis.impactTime
        let tapTime = impact + tap.time
        let start = impact - Double(TracerConstants.backgroundFrameCount + 2) / analysisFps
        let info = try await VideoInspector.info(of: url, measureFrames: false)
        let end = min(info.duration, impact + TracerConstants.flightAnalysisWindow)
        let collector = TrajectoryCollector(geometry: geometry, impactTime: impact,
                                            region: TrajectoryCollector.region(centeredOn: tap.point, geometry: geometry))
        var frames: [GrayImage] = []
        var frameTimes: [Double] = []
        var counter = 0
        try await reader.read(from: start, to: end) { sample, pixels, time in
            counter += 1
            guard (counter - 1) % step == 0 else { return true }
            frames.append(LumaSampler.reduced(pixels, geometry: geometry, factor: reduction))
            frameTimes.append(time)
            if time >= tapTime - 0.3, time <= tapTime + 1.0 {
                await collector.process(sample, time: time)
            }
            return true
        }
        let factor = Double(reduction)
        var added: [SourcedSample] = []
        let impactIndex = frameTimes.firstIndex { $0 >= impact - 0.5 / fps } ?? 0
        if impactIndex > 0, let seedFrame = frameTimes.indices.min(by: { abs(frameTimes[$0] - tapTime) < abs(frameTimes[$1] - tapTime) }),
           let tracker = BlobTracker(frames: frames, impactFrame: impactIndex, frameRate: analysisFps, teePosition: analysis.ball / factor) {
            let track = tracker.track(fromSeed: tap.point / factor, atFrame: seedFrame, velocity: velocity / factor)
            added += track.points.filter { !$0.isSeed }.map { point in
                SourcedSample(TrajectorySample(time: frameTimes[point.frameIndex] - impact, point: point.point * factor), source: .blob)
            }
        }
        // De Vision, las trayectorias que pasan cerca del toque (a menos del 4 % del ancho y 0,15 s).
        let near = collector.tracks.filter { track in
            track.samples.contains { abs($0.time - tap.time) <= 0.15 && $0.point.distance(to: tap.point) <= 0.04 * Double(geometry.width) }
        }
        added += near.flatMap { track in track.samples.map { SourcedSample($0, source: .vision) } }
        var fixed = tap
        fixed.isFixed = true
        return Reinforcement(tap: fixed, added: added)
    }

    // MARK: Ayudantes

    /// La onda de 1 s antes a 0,6 s después de `center` (para s03).
    static func waveform(_ samples: [Float], around center: Double) -> [Double] {
        let rate = AudioExtractor.sampleRate
        let from = max(Int((center - 1.0) * rate), 0)
        let to = min(Int((center + 0.6) * rate), samples.count)
        guard from < to else { return [] }
        return Waveform.bars(samples: Array(samples[from..<to]), count: waveformBars)
    }

    static func barIndex(for time: Double, around center: Double) -> Int {
        Waveform.barIndex(for: time - (center - 1.0), duration: 1.6, count: waveformBars)
    }

    static func normalized(_ points: [Point2D], geometry: VideoGeometry) -> [Point2D] {
        points.map { Point2D($0.x / Double(geometry.width), $0.y / Double(geometry.height)) }
    }
}
