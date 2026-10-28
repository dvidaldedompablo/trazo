import Foundation
import Testing
@testable import GolfCore

/// Imágenes sintéticas para buscar la bola: hierba con textura, bolas blancas y una barra clara (un cartel).
enum SyntheticBallScene {
    static func image(width: Int = 400, height: Int = 400, balls: [(Point2D, Double)], bar: Bool = true, seed: UInt64 = 2) -> GrayImage {
        var rng = SeededRandom(seed: seed)
        var pixels = (0..<(width * height)).map { _ in UInt8(min(max(95 + rng.nextGaussian() * 6, 0), 255)) }
        if bar {
            for y in 116...123 { for x in 80...110 { pixels[y * width + x] = 230 } }
        }
        for (center, radius) in balls {
            for y in Int(center.y - radius - 1)...Int(center.y + radius + 1) {
                for x in Int(center.x - radius - 1)...Int(center.x + radius + 1)
                where (Double(x) - center.x) * (Double(x) - center.x) + (Double(y) - center.y) * (Double(y) - center.y) <= radius * radius {
                    pixels[y * width + x] = 235
                }
            }
        }
        return GrayImage(width: width, height: height, pixels: pixels)
    }

    /// La misma imagen difuminada (media de 5 x 5): como un fotograma movido.
    static func blurred(_ image: GrayImage) -> GrayImage {
        var out = image
        for y in 2..<(image.height - 2) {
            for x in 2..<(image.width - 2) {
                var sum = 0
                for dy in -2...2 { for dx in -2...2 { sum += Int(image[x + dx, y + dy]) } }
                out[x, y] = UInt8(sum / 25)
            }
        }
        return out
    }
}

struct BallLocatorTests {
    let fullImage = PixelRect(x: 0, y: 0, width: 400, height: 400)

    @Test("Encuentra la bola (mancha clara y redonda) y no el cartel alargado")
    func findsBall() throws {
        let image = SyntheticBallScene.image(balls: [(Point2D(250, 300), 5)])
        let location = BallLocator.locate(in: image, search: BallSearch(region: fullImage))
        let best = try #require(location.best)
        #expect(best.center.distance(to: Point2D(250, 300)) <= 1.5)
        #expect(best.radius >= 3 && best.radius <= 6)
        #expect(location.isConfident)
    }

    @Test("Con dos bolas iguales no hay confianza, salvo que una esté donde dice la guía")
    func twoBallsNeedPrior() throws {
        let image = SyntheticBallScene.image(balls: [(Point2D(250, 300), 5), (Point2D(80, 330), 5)])
        #expect(!BallLocator.locate(in: image, search: BallSearch(region: fullImage)).isConfident)
        let guided = BallLocator.locate(in: image, search: BallSearch(region: fullImage, prior: Point2D(240, 290), priorSpread: 60))
        #expect(guided.isConfident)
        #expect(try #require(guided.best).center.distance(to: Point2D(250, 300)) <= 1.5)
    }

    @Test("Sin bola no se inventa ninguna")
    func noBall() {
        let image = SyntheticBallScene.image(balls: [], bar: false)
        #expect(BallLocator.locate(in: image, search: BallSearch(region: fullImage)).best == nil)
    }

    @Test("Un fotograma movido es menos nítido y la bola contrasta menos")
    func sharpnessAndContrast() {
        let sharp = SyntheticBallScene.image(balls: [(Point2D(250, 300), 5)], bar: false)
        let blurred = SyntheticBallScene.blurred(sharp)
        #expect(BallLocator.sharpness(of: sharp, around: Point2D(250, 300), radius: 5)
                > 1.5 * BallLocator.sharpness(of: blurred, around: Point2D(250, 300), radius: 5))
        let withBall = BallLocator.coreContrast(in: sharp, center: Point2D(250, 300), radius: 5)
        let empty = SyntheticBallScene.image(balls: [], bar: false)
        #expect(withBall > 100)
        #expect(abs(BallLocator.coreContrast(in: empty, center: Point2D(250, 300), radius: 5)) < 10)
    }
}

struct ImpactMotionTests {
    @Test("La bola desaparece cuando su contraste cae y no vuelve")
    func disappearance() {
        let contrasts = [Double](repeating: 100, count: 24) + [30, 8, 5, 6, 7, 5, 4, 6]
        #expect(BallMotion.disappearanceIndex(contrasts: contrasts, referenceCount: 10) == 24)
        // El palo tapa la bola un par de fotogramas y la bola sigue ahí: no es el impacto.
        let occluded = [Double](repeating: 100, count: 15) + [20, 20] + [Double](repeating: 100, count: 15)
        #expect(BallMotion.disappearanceIndex(contrasts: occluded, referenceCount: 10) == nil)
        // Si la bola no se veía bien antes, no se puede decir nada.
        #expect(BallMotion.disappearanceIndex(contrasts: [Double](repeating: 5, count: 30), referenceCount: 10) == nil)
    }

    @Test("Sonido y movimiento: dentro de 2 fotogramas manda el sonido; si no, el movimiento")
    func chooseImpact() {
        let frame = 1.0 / 240
        let audio = [Impact(time: 0.98, strength: 900, prominence: 300), Impact(time: 1.30, strength: 200, prominence: 80)]
        // Otro jugador da el golpe fuerte; el propio coincide con la bola que se va.
        #expect(ImpactChooser.choose(audio: audio, motionTime: 1.296, frameDuration: frame)
                == ImpactChooser.Choice(time: 1.30, source: .sound))
        #expect(ImpactChooser.choose(audio: audio, motionTime: 1.25, frameDuration: frame)
                == ImpactChooser.Choice(time: 1.25, source: .motion))
        #expect(ImpactChooser.choose(audio: audio, motionTime: nil, frameDuration: frame)
                == ImpactChooser.Choice(time: 0.98, source: .sound))
        #expect(ImpactChooser.choose(audio: [], motionTime: 2, frameDuration: frame)?.source == .motion)
        #expect(ImpactChooser.choose(audio: [], motionTime: nil, frameDuration: frame) == nil)
    }

    @Test("El horizonte es el paso del cielo claro al suelo oscuro; sin él, nada")
    func horizon() throws {
        var rng = SeededRandom(seed: 6)
        let pixels = (0..<(200 * 400)).map { i -> UInt8 in
            let y = i / 200
            return UInt8(min(max((y < 176 ? 200 : 90) + rng.nextGaussian() * 5, 0), 255))
        }
        let y = try #require(HorizonFinder.find(in: GrayImage(width: 200, height: 400, pixels: pixels)))
        #expect(abs(y - 176) <= 3)
        #expect(HorizonFinder.find(in: GrayImage(width: 200, height: 400, value: 120)) == nil)
    }
}

struct TrajectorySelectorTests {
    static let ball = Point2D(540, 1700)

    static func track(_ id: Int, from start: Point2D, startTime: Double, velocity: Point2D, count: Int = 12,
                      confidence: Double = 0.95) -> VisionTrack {
        VisionTrack(id: id, samples: (0..<count).map { i in
            let t = startTime + Double(i) / 120
            return TrajectorySample(time: t, point: start + velocity * (t - startTime))
        }, confidence: confidence)
    }

    @Test("Se queda la trayectoria que sale de la bola y su continuación; descarta el resto")
    func selectsBallTrajectory() {
        let ball = Self.ball
        let good = Self.track(1, from: ball + Point2D(5, -20), startTime: 0.02, velocity: Point2D(30, -900))
        let goodEnd = good.samples.last!
        let continuation = Self.track(2, from: goodEnd.point + Point2D(10, -15), startTime: goodEnd.time + 0.1, velocity: Point2D(25, -700))
        let far = Self.track(3, from: Point2D(100, 600), startTime: 0.03, velocity: Point2D(400, -100))
        let late = Self.track(4, from: ball + Point2D(0, -30), startTime: 0.5, velocity: Point2D(0, -800))
        let falling = Self.track(5, from: ball + Point2D(0, -10), startTime: 0.01, velocity: Point2D(0, 600))
        let unsure = Self.track(6, from: ball + Point2D(2, -10), startTime: 0.02, velocity: Point2D(10, -900), confidence: 0.6)
        let chosen = TrajectorySelector.select([far, continuation, late, falling, unsure, good], ball: ball, imageWidth: 1080)
        #expect(chosen.map(\.id) == [1, 2])
    }
}

struct TracerAssemblerTests {
    static let ball = Point2D(540, 1700)
    static let size = (width: 1080.0, height: 1920.0)

    /// Bola que sube y frena en la imagen (vista desde detrás), sin llegar al vértice en lo visto.
    static func rising(until end: Double, step: Double = 1.0 / 120, source: PointSource = .vision) -> [SourcedSample] {
        stride(from: step, through: end, by: step).map { t in
            SourcedSample(TrajectorySample(time: t, point: Point2D(540 + 40 * t, 1700 - 1500 * t + 500 * t * t)), source: source)
        }
    }

    @Test("Un vuelo bien seguido: confianza alta, sin aviso y la curva sale de la bola hacia lo visto")
    func goodFlight() {
        let input = TracerInput(ball: Self.ball, imageWidth: Self.size.width, imageHeight: Self.size.height,
                                points: Self.rising(until: 1.2))
        let outcome = TracerAssembler.assemble(input).outcome
        #expect(outcome.confidence >= 0.8)
        #expect(!outcome.needsReview)
        #expect(outcome.lostAt == nil)
        #expect(outcome.usesObservations)
        #expect(outcome.curve.launch == Self.ball)
        // Aún subía al perderla: el vértice queda por encima del último punto visto y la caída en el horizonte.
        let lastY = 1700 - 1500 * 1.2 + 500 * 1.44
        #expect(outcome.curve.apex.y < lastY)
        #expect(abs(outcome.curve.landing.y - 0.44 * Self.size.height) < 1e-9)
        #expect(outcome.curve.flightTime == ClubCategory.longIrons.typicalFlightTime)
        #expect(abs(outcome.trackedDuration - 1.2) < 0.01)
    }

    @Test("Vision y BlobTracker separados 2 px: no se descarta ninguno; un punto a 40 px, sí")
    func twoSourcesAgree() {
        func position(_ t: Double) -> Point2D { Point2D(540 + 40 * t, 1700 - 1500 * t + 500 * t * t) }
        var points: [SourcedSample] = []
        for sample in Self.rising(until: 0.6) {
            let t = sample.sample.time
            points.append(SourcedSample(TrajectorySample(time: t, point: position(t) + Point2D(1, -0.6)), source: .vision))
            points.append(SourcedSample(TrajectorySample(time: t + 0.002, point: position(t + 0.002) + Point2D(-0.7, 0.8)), source: .blob))
        }
        points.append(SourcedSample(TrajectorySample(time: 0.3, point: Point2D(540 + 40 * 0.3 + 40, 1700 - 1500 * 0.3 + 45)), source: .blob))
        let input = TracerInput(ball: Self.ball, imageWidth: Self.size.width, imageHeight: Self.size.height, points: points)
        let outcome = TracerAssembler.assemble(input).outcome
        let discarded = outcome.points.filter(\.isOutlier)
        #expect(discarded.count == 1)
        #expect(discarded.first?.time == 0.3)
        #expect(outcome.points.filter { $0.source == .blob && !$0.isOutlier }.count == 72)
    }

    @Test("Seguida menos de 0,5 s: aviso de pérdida con el instante")
    func lostEarly() throws {
        let input = TracerInput(ball: Self.ball, imageWidth: Self.size.width, imageHeight: Self.size.height,
                                points: Self.rising(until: 0.3))
        let outcome = TracerAssembler.assemble(input).outcome
        #expect(outcome.needsReview)
        #expect(abs(try #require(outcome.lostAt) - 0.3) < 0.01)
    }

    @Test("Sin puntos: la propuesta inicial, confianza 0 y aviso en 0 s")
    func noPoints() {
        let input = TracerInput(ball: Self.ball, imageWidth: Self.size.width, imageHeight: Self.size.height, points: [],
                                horizonY: 800)
        let outcome = TracerAssembler.assemble(input).outcome
        #expect(outcome.confidence == 0)
        #expect(outcome.needsReview)
        #expect(outcome.lostAt == 0)
        #expect(!outcome.usesObservations)
        #expect(outcome.curve == TracerCurve.proposal(ball: Self.ball, imageWidth: 1080, imageHeight: 1920, club: .longIrons,
                                                      horizonY: 800))
    }

    @Test("Si se ve el vértice, la curva pasa por él y cae donde la parábola corta el horizonte")
    func observedApex() throws {
        // Vista más de lado: la bola sube, hace el vértice en t = 1 s (600, 900) y baja.
        let points = stride(from: 1.0 / 120, through: 1.6, by: 1.0 / 120).map { t in
            SourcedSample(TrajectorySample(time: t, point: Point2D(300 + 300 * t, 1500 - 1200 * t + 600 * t * t)), source: .blob)
        }
        let input = TracerInput(ball: Point2D(300, 1500), imageWidth: 1080, imageHeight: 1920, points: points, horizonY: 1300)
        let outcome = TracerAssembler.assemble(input).outcome
        #expect(outcome.curve.apex.distance(to: Point2D(600, 900)) < 4)
        // 600 t² − 1200 t + 200 = 0 → t ≈ 1,8165 s, x ≈ 845.
        #expect(outcome.curve.landing.distance(to: Point2D(845, 1300)) < 10)
        #expect(abs(outcome.curve.flightTime - 1.8165) < 0.05)
    }

    @Test("Atípicos y puntos de varios orígenes: se descartan los malos y el toque se respeta")
    func mixedSources() throws {
        var points = Self.rising(until: 1.0, step: 1.0 / 60, source: .vision) + Self.rising(until: 1.0, step: 1.0 / 50, source: .blob)
        // Un pájaro que BlobTracker confundió con la bola.
        points.append(SourcedSample(TrajectorySample(time: 0.505, point: Point2D(900, 400)), source: .blob))
        // Un toque del usuario a 0,8 s, sobre la bola.
        let tapTime = 0.8
        points.append(SourcedSample(TrajectorySample(time: tapTime, point: Point2D(540 + 40 * tapTime, 1700 - 1500 * tapTime + 500 * tapTime * tapTime),
                                                     isFixed: true), source: .tap))
        let outcome = TracerAssembler.assemble(TracerInput(ball: Self.ball, imageWidth: 1080, imageHeight: 1920, points: points)).outcome
        let bird = try #require(outcome.points.first { $0.point == Point2D(900, 400) })
        #expect(bird.isOutlier)
        let tap = try #require(outcome.points.first { $0.source == .tap })
        #expect(!tap.isOutlier)
        #expect(outcome.points.filter { $0.source == .vision }.count == 60)
        #expect(outcome.confidence > 0.6)
    }

    @Test("Algo que baja desde el principio no es la bola: confianza baja")
    func notRising() {
        let points = stride(from: 1.0 / 120, through: 1.0, by: 1.0 / 120).map { t in
            SourcedSample(TrajectorySample(time: t, point: Point2D(540, 1000 + 400 * t)), source: .vision)
        }
        let outcome = TracerAssembler.assemble(TracerInput(ball: Self.ball, imageWidth: 1080, imageHeight: 1920, points: points)).outcome
        #expect(outcome.confidence < TracerConstants.minimumConfidence)
        #expect(outcome.needsReview)
    }

    @Test("La velocidad para un toque de refuerzo sale del ajuste (o de la curva si no hay)")
    func seedVelocity() {
        let assembly = TracerAssembler.assemble(TracerInput(ball: Self.ball, imageWidth: 1080, imageHeight: 1920, points: Self.rising(until: 1.0)))
        // Derivada de y = 1700 − 1500 t + 500 t² en t = 0,5: −1000 px/s.
        #expect(assembly.velocity(at: 0.5).distance(to: Point2D(40, -1000)) < 15)
        let empty = TracerAssembler.assemble(TracerInput(ball: Self.ball, imageWidth: 1080, imageHeight: 1920, points: []))
        #expect(empty.velocity(at: 0.2).y < 0)
    }
}
