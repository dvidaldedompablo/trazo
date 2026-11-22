import Foundation
import Testing
@testable import GolfCore

/// Piezas nuevas de la etapa 6: limpieza de la pose, línea del palo y seguidor de plantilla.
struct PoseSeriesTests {
    /// Una muñeca que se mueve en línea recta con ruido y un hueco corto.
    private func frames(gap: Range<Int>?) -> [PoseFrame] {
        var rng = SeededRandom(seed: 5)
        return (0..<60).map { i in
            var joints: [Joint: Point2D] = [:]
            if gap == nil || !gap!.contains(i) {
                let noise = Point2D(rng.nextUnit() * 4 - 2, rng.nextUnit() * 4 - 2)
                joints[.leftWrist] = Point2D(100 + 5 * Double(i), 800 - 3 * Double(i)) + noise
            }
            joints[.neck] = Point2D(300, 300)
            return PoseFrame(time: Double(i) / 120, joints: joints)
        }
    }

    @Test("El suavizado quita el ruido sin torcer un movimiento recto")
    func smoothsNoise() {
        let processed = PoseSeries.process(frames(gap: nil))
        // Error frente a la recta verdadera: con ruido de ±2 px, tras suavizar queda muy por debajo.
        let errors = processed.indices.compactMap { i -> Double? in
            guard let p = processed[i].joints[.leftWrist] else { return nil }
            return p.distance(to: Point2D(100 + 5 * Double(i), 800 - 3 * Double(i)))
        }
        #expect(errors.count == 60)
        #expect(errors.reduce(0, +) / Double(errors.count) < 1.2)
    }

    @Test("Un hueco de 3 fotogramas se rellena; uno de 10 se queda vacío")
    func fillsShortGaps() {
        let short = PoseSeries.process(frames(gap: 20..<23))
        #expect((20..<23).allSatisfy { short[$0].joints[.leftWrist] != nil })
        let long = PoseSeries.process(frames(gap: 20..<30))
        #expect((20..<30).allSatisfy { long[$0].joints[.leftWrist] == nil })
        // Y lo demás sigue ahí.
        #expect(long[5].joints[.leftWrist] != nil && long[45].joints[.leftWrist] != nil)
    }

    @Test("La pose y las posiciones van y vuelven de JSON (para guardarlas en el iPhone)")
    func poseRoundTripsThroughJSON() throws {
        let original = frames(gap: 20..<23)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([PoseFrame].self, from: data)
        #expect(decoded == original)
    }
}

struct ClubLineFinderTests {
    /// Campo gris con una varilla oscura desde las manos hacia abajo a la derecha.
    private func scene(angle degrees: Double, length: Double) -> (GrayImage, Point2D) {
        var image = GrayImage(width: 240, height: 240, value: 128)
        // Algo de textura para que el umbral de bordes no se quede sin mediana.
        var rng = SeededRandom(seed: 3)
        for i in image.pixels.indices { image.pixels[i] = UInt8(120 + Int(rng.nextUnit() * 16)) }
        let hands = Point2D(70, 60)
        let radians = degrees * .pi / 180
        for step in stride(from: 0.0, through: length, by: 0.5) {
            let x = Int((hands.x + cos(radians) * step).rounded())
            let y = Int((hands.y + sin(radians) * step).rounded())
            for dy in -1...1 {
                for dx in -1...1 where x + dx >= 0 && x + dx < 240 && y + dy >= 0 && y + dy < 240 {
                    image.pixels[(y + dy) * 240 + (x + dx)] = 25
                }
            }
        }
        return (image, hands)
    }

    @Test("Encuentra la varilla: el ángulo sale a menos de 4° y la cabeza cerca de la punta")
    func findsShaft(  ) throws {
        let (image, hands) = scene(angle: 52, length: 150)
        let line = try #require(ClubLineFinder.find(in: image, hands: hands))
        let angle = atan2(line.head.y - line.grip.y, line.head.x - line.grip.x) * 180 / .pi
        #expect(abs(angle - 52) < 4)
        let trueHead = Point2D(70 + cos(52 * .pi / 180) * 150, 60 + sin(52 * .pi / 180) * 150)
        #expect(line.head.distance(to: trueHead) < 15)
    }

    @Test("Sin varilla (solo ruido) no se inventa ninguna línea")
    func noLineInNoise() {
        var image = GrayImage(width: 240, height: 240, value: 128)
        var rng = SeededRandom(seed: 9)
        for i in image.pixels.indices { image.pixels[i] = UInt8(100 + Int(rng.nextUnit() * 56)) }
        #expect(ClubLineFinder.find(in: image, hands: Point2D(120, 120)) == nil)
    }
}

struct TemplateTrackerTests {
    /// Una mancha clara con degradado sobre fondo con textura, desplazada entre fotogramas.
    private func frame(blobAt center: Point2D) -> GrayImage {
        var image = GrayImage(width: 160, height: 160, value: 90)
        var rng = SeededRandom(seed: 11)
        for i in image.pixels.indices { image.pixels[i] = UInt8(80 + Int(rng.nextUnit() * 20)) }
        for y in 0..<160 {
            for x in 0..<160 {
                let d = Point2D(Double(x), Double(y)).distance(to: center)
                if d < 9 { image.pixels[y * 160 + x] = UInt8(max(230 - d * 12, 120)) }
            }
        }
        return image
    }

    @Test("La mancha desplazada 6,4 px se encuentra a 1,5 px o menos, con parecido alto")
    func tracksBlob() throws {
        let start = Point2D(60, 90)
        let moved = Point2D(66, 94)
        let template = try #require(TemplateTracker.template(from: frame(blobAt: start), center: start, radius: 12))
        let found = try #require(TemplateTracker.find(template, in: frame(blobAt: moved), around: start, searchRadius: 14))
        #expect(found.center.distance(to: moved) <= 1.5)
        #expect(found.score > 0.6)
    }

    @Test("Si la mancha ya no está, el parecido se queda bajo")
    func lowScoreWhenMissing() throws {
        let start = Point2D(60, 90)
        let template = try #require(TemplateTracker.template(from: frame(blobAt: start), center: start, radius: 12))
        var empty = GrayImage(width: 160, height: 160, value: 90)
        var rng = SeededRandom(seed: 12)
        for i in empty.pixels.indices { empty.pixels[i] = UInt8(80 + Int(rng.nextUnit() * 20)) }
        let found = TemplateTracker.find(template, in: empty, around: start, searchRadius: 14)
        #expect((found?.score ?? 0) < 0.45)
    }
}

/// El swing de demostración de punta a punta: posiciones, medidas, nota y guion.
/// Las capturas del CI dependen de que esto nunca devuelva nil.
struct DemoSwingTests {
    @Test("PhaseDetector reconoce el swing de demostración con ritmo 2,8 y en orden")
    func demoSwingDetects() throws {
        let frames = PoseSeries.process(DemoSwing.frames())
        let phases = try #require(PhaseDetector.detect(frames: frames, impactTime: DemoSwing.impactTime))
        #expect(phases.isOrdered)
        #expect(abs(phases[.impact].time - DemoSwing.impactTime) < 0.05)
        let tempo = try #require(phases.tempo)
        #expect(abs(tempo - 2.8) < 0.4)
    }

    @Test("Del swing de demostración salen medidas, una nota y el takeaway por dentro como prioridad")
    func demoSwingScores() throws {
        let frames = PoseSeries.process(DemoSwing.frames())
        let phases = try #require(PhaseDetector.detect(frames: frames, impactTime: DemoSwing.impactTime))
        let input = SwingMetricsInput(frames: frames, phases: phases, heightCentimeters: 175,
                                      clubHeadAtAddress: DemoSwing.clubHeadAtAddress,
                                      clubHeadAtTakeaway: DemoSwing.clubHeadAtTakeaway,
                                      clubLineAtMidBackswing: DemoSwing.clubLineAtMidBackswing,
                                      clubLineAtTransition: DemoSwing.clubLineAtTransition)
        let measurements = SwingMetrics.measure(input)
        let score = Scoring.score(measurements)
        let total = try #require(score.total)
        #expect(total > 40 && total < 95)
        #expect(score.phases.first { $0.phase == .takeaway }?.faults.contains(.takeawayInside) == true)
        let script = ScriptWriter.write(measurements: measurements, score: score)
        #expect(script.allLines.count >= 10)
        #expect(script[.score]?.lines.first?.contains("\(total) sobre 100") == true)
    }
}

struct AnalysisTimelineTests {
    @Test("Cada bloque dura el máximo entre su mínimo visual y su narración + 0,6 s, sin huecos")
    func buildsSequentially() {
        let kinds = AnalysisTimeline.blockKinds(short: false, importantPhases: [])
        #expect(kinds == [.hook, .slowMotion, .address, .takeaway, .midBackswing, .top, .transition, .impact, .finish, .tempo, .score, .report] + AnalysisTimeline.improvementKinds)
        let narration: [ScriptBlockKind: Double] = [.hook: 4.1, .address: 1.0, .score: 2.0]
        let blocks = AnalysisTimeline.build(kinds: kinds, narration: narration, swingDuration: 1.6, slowMotionFactor: 4)
        // El gancho manda su narración (4,1 + 0,6 > 3); la preparación, su mínimo (2,5 > 1,6).
        #expect(abs(blocks[0].duration - 4.7) < 1e-9)
        #expect(abs(blocks[1].duration - 6.4) < 1e-9)
        #expect(blocks[2].duration == 2.5)
        // Sin huecos ni solapes, y el cierre de 2 s al final.
        for (a, b) in zip(blocks, blocks.dropFirst()) { #expect(abs(a.end - b.start) < 1e-9) }
        #expect(blocks.last?.kind == .closing && blocks.last?.duration == 2)
    }

    @Test("Los bloques de \"A mejorar\" sin frases no salen (con dos fallos no hay tercer ejercicio)")
    func skipsSilentImprovementBlocks() {
        let kinds = AnalysisTimeline.blockKinds(short: true, importantPhases: [.takeaway])
        let narration: [ScriptBlockKind: Double] = [.improveIntro: 3, .improve1: 9, .improve2: 9, .improveSummary: 3]
        let blocks = AnalysisTimeline.build(kinds: kinds, narration: narration, swingDuration: 1.6, slowMotionFactor: 2)
        let shown = blocks.compactMap(\.scriptKind)
        #expect(shown.contains(.improve2))
        #expect(!shown.contains(.improve3))
        // Sin ningún fallo con ejercicio, no hay sección.
        let none = AnalysisTimeline.build(kinds: kinds, narration: [:], swingDuration: 1.6, slowMotionFactor: 2)
        #expect(none.compactMap(\.scriptKind).allSatisfy { !AnalysisTimeline.improvementKinds.contains($0) })
    }

    @Test("La versión corta lleva gancho, cámara lenta, 3 fases, nota e informe")
    func shortVersion() {
        let kinds = AnalysisTimeline.blockKinds(short: true, importantPhases: [.takeaway, .impact, .midBackswing, .top])
        #expect(kinds == [.hook, .slowMotion, .takeaway, .midBackswing, .top, .score, .report] + AnalysisTimeline.improvementKinds)
    }
}

/// Caso real del 17-11-2026: una story con música. El sonido más fuerte del clip no era el palo
/// y el análisis fallaba con "No se ve a nadie" (y con algunos instantes, se colgaba).
struct SwingImpactChooserTests {
    private let frames = PoseSeries.process(DemoSwing.frames())

    @Test("PhaseDetector no se cuelga con ningún instante de impacto, aunque esté mal")
    func detectorNeverCrashes() {
        // Antes: con el takeaway en el mismo top, `(takeaway + 1)..<top` era un rango imposible.
        for step in 0...66 {
            _ = PhaseDetector.detect(frames: frames, impactTime: Double(step) * 0.05)
        }
    }

    @Test("Con un pico de música más fuerte en el final, elige el impacto del palo")
    func ignoresLouderMusicPeak() throws {
        let candidates = [
            Impact(time: 0.30, strength: 20, prominence: 10), // música durante la preparación
            Impact(time: DemoSwing.impactTime, strength: 5, prominence: 10), // el palo
            Impact(time: 2.60, strength: 40, prominence: 10), // música en el final
        ]
        let choice = try SwingImpactChooser.choose(frames: frames, soundCandidates: candidates).get()
        #expect(choice.soundTime == DemoSwing.impactTime)
        #expect(abs(choice.phases[.impact].time - DemoSwing.impactTime) < 0.02)
    }

    @Test("Si ningún sonido encaja, el impacto sale del movimiento de las manos")
    func fallsBackToMotion() throws {
        let candidates = [Impact(time: 2.9, strength: 30, prominence: 10)]
        let choice = try SwingImpactChooser.choose(frames: frames, soundCandidates: candidates).get()
        #expect(choice.soundTime == nil)
        #expect(abs(choice.phases[.impact].time - DemoSwing.impactTime) < 0.1)
    }

    @Test("Un ruido cuando el jugador ya ha bajado los brazos tras el final no cuenta como impacto")
    func ignoresNoiseAfterRelaxing() throws {
        // Caso real (driver, 30 fps): tras el final las manos vuelven a la altura de la preparación.
        // Estar cerca de la preparación no basta: la bajada duraría segundos.
        let last = frames.last!.time
        let relaxed = frames + (1...120).map { PoseFrame(time: last + Double($0) / DemoSwing.sampleRate, joints: frames[0].joints) }
        let candidates = [
            Impact(time: DemoSwing.impactTime, strength: 5, prominence: 10),
            Impact(time: last + 0.8, strength: 50, prominence: 10),
        ]
        let choice = try SwingImpactChooser.choose(frames: PoseSeries.process(relaxed), soundCandidates: candidates).get()
        #expect(choice.soundTime == DemoSwing.impactTime)
    }

    @Test("Con el sonido desfasado de la imagen, el impacto se ajusta a las manos y se dice cuánto")
    func correctsLateSound() throws {
        // Caso real (story de Instagram): el "clac" 0,09 s después de que las manos llegaran abajo.
        // Final tres veces más rápido que en la demo: a los 0,08 s las manos ya han subido mucho.
        let fast = DemoSwing.frames().map { f in
            f.time > DemoSwing.impactTime
                ? PoseFrame(time: DemoSwing.impactTime + (f.time - DemoSwing.impactTime) / 3, joints: f.joints) : f
        }
        let frames = PoseSeries.process(fast)
        let late = DemoSwing.impactTime + 0.08
        #expect(PhaseDetector.detect(frames: frames, impactTime: late).flatMap {
            SwingImpactChooser.returnFraction($0, hands: PhaseDetector.completeHands(frames)!,
                                              stature: PhaseDetector.estimateStature(frames, handedness: .right))
        } == nil, "el sonido tal cual no debe encajar, si no el test no prueba el ajuste")
        let choice = try SwingImpactChooser.choose(frames: frames, soundCandidates: [Impact(time: late, strength: 10, prominence: 10)]).get()
        #expect(choice.soundTime == late)
        #expect(abs(choice.phases[.impact].time - DemoSwing.impactTime) < 0.03)
        #expect(abs(choice.syncOffset + 0.08) < 0.03)
    }

    @Test("Un jugador quieto (sin swing) se dice como 'sin swing', no como 'no se ve a nadie'")
    func stillPlayerIsNoSwing() {
        let still = frames.map { PoseFrame(time: $0.time, joints: frames[0].joints) }
        #expect(SwingImpactChooser.choose(frames: still, soundCandidates: []) == .failure(.noSwing))
    }
}
