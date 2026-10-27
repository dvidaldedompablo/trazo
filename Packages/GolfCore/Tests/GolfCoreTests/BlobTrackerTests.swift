import Foundation
import Testing
@testable import GolfCore

struct BlobTrackerTests {
    typealias Flight = SyntheticFlight

    /// Comprueba que el seguimiento cubre al menos el 90 % de los fotogramas del intervalo
    /// y que cada punto está a menos de 1 px de la bola verdadera.
    func expectFollowsBall(_ track: BlobTrack, frames: ClosedRange<Int>, sourceLocation: SourceLocation = #_sourceLocation) {
        let covered = track.points.filter { frames.contains($0.frameIndex) }
        #expect(Double(covered.count) >= 0.9 * Double(frames.count), sourceLocation: sourceLocation)
        for point in track.points {
            let error = point.point.distance(to: Flight.ballCenter(frame: point.frameIndex))
            #expect(error < 1, "Fotograma \(point.frameIndex): error de \(error) px", sourceLocation: sourceLocation)
        }
        let indices = track.points.map(\.frameIndex)
        #expect(indices == indices.sorted(), sourceLocation: sourceLocation)
    }

    @Test("Sigue una bola sintética que sube desde el tee hasta el final del clip")
    func tracksBallFromTee() throws {
        let tracker = try #require(BlobTracker(frames: Flight.frames(), impactFrame: Flight.impactFrame,
                                               frameRate: Flight.frameRate, teePosition: Flight.tee))
        let track = tracker.trackFromBall(at: Flight.tee)
        expectFollowsBall(track, frames: (Flight.impactFrame + 2)...(Flight.frameCount - 1))
        #expect(track.end == .endOfClip)
        #expect(track.points.allSatisfy { !$0.isSeed })
    }

    @Test("Sembrada a mitad de vuelo, sigue hacia delante y hacia atrás (toque de refuerzo)")
    func tracksFromSeedBothWays() throws {
        let tracker = try #require(BlobTracker(frames: Flight.frames(), impactFrame: Flight.impactFrame,
                                               frameRate: Flight.frameRate, teePosition: Flight.tee))
        // El usuario toca casi encima de la bola (con 1 px de error) en el fotograma 50, sin velocidad conocida.
        let seedFrame = 50
        let tap = Flight.ballCenter(frame: seedFrame) + Point2D(0.7, -0.6)
        let track = tracker.track(fromSeed: tap, atFrame: seedFrame)
        expectFollowsBall(track, frames: (Flight.impactFrame + 2)...(Flight.frameCount - 1))
        let seeds = track.points.filter(\.isSeed)
        #expect(seeds.count == 1)
        #expect(seeds.first?.frameIndex == seedFrame)
        #expect(track.points.contains { $0.frameIndex < seedFrame - 20 })
        #expect(track.points.contains { $0.frameIndex > seedFrame + 20 })
    }

    @Test("Con la velocidad de la curva propuesta, la semilla también vale cerca del final")
    func tracksFromLateSeedWithVelocity() throws {
        let tracker = try #require(BlobTracker(frames: Flight.frames(), impactFrame: Flight.impactFrame,
                                               frameRate: Flight.frameRate, teePosition: Flight.tee))
        let seedFrame = 70
        let velocity = (Flight.ballCenter(frame: seedFrame + 1) - Flight.ballCenter(frame: seedFrame - 1)) * (Flight.frameRate / 2)
        let track = tracker.track(fromSeed: Flight.ballCenter(frame: seedFrame), atFrame: seedFrame, velocity: velocity)
        expectFollowsBall(track, frames: (Flight.impactFrame + 2)...(Flight.frameCount - 1))
    }

    @Test("Si la bola deja de verse, para a los 12 fotogramas y dice dónde la perdió")
    func reportsLoss() throws {
        let tracker = try #require(BlobTracker(frames: Flight.frames(hideBallFrom: 45), impactFrame: Flight.impactFrame,
                                               frameRate: Flight.frameRate, teePosition: Flight.tee))
        let track = tracker.trackFromBall(at: Flight.tee)
        #expect(track.end == .lost)
        #expect(track.lastSeenFrame == 44)
        #expect(track.points.allSatisfy { $0.frameIndex <= 44 })
        let lostAt = Double(try #require(track.lastSeenFrame) - Flight.impactFrame) / Flight.frameRate
        #expect(abs(lostAt - 0.2) < 1e-9)
    }

    @Test("El fondo borra lo que se mueve y el palo alargado no cuenta como bola")
    func backgroundAndShapeFilter() throws {
        let frames = Flight.frames()
        let tracker = try #require(BlobTracker(frames: frames, impactFrame: Flight.impactFrame, frameRate: Flight.frameRate))
        // El palo (valor 30) pasó por x = 60 en el fotograma 18, pero en el fondo (mediana) queda el suelo (95).
        let clubPixel = Int(tracker.background[60, 195])
        #expect(abs(clubPixel - 95) < 8)
        #expect(frames[18][60, 195] < 40)
        // La bola en el tee sí es parte del fondo.
        #expect(tracker.background[70, 205] > 220)
        // En el fotograma 18 el palo está ahí: es una mancha alargada y se descarta.
        #expect(tracker.blobs(inFrame: 18, around: Point2D(60.5, 195), radius: 14).isEmpty)
        // El pájaro (2 x 2) sí es una mancha pequeña, pero está lejos del vuelo.
        #expect(!tracker.blobs(inFrame: 40, around: Point2D(40.5, 40.5), radius: 6).isEmpty)
    }

    @Test("Sin fotogramas antes del impacto no hay fondo ni seguimiento")
    func needsFramesBeforeImpact() {
        #expect(BlobTracker(frames: Flight.frames(), impactFrame: 0, frameRate: 120) == nil)
        #expect(BlobTracker(frames: [], impactFrame: 3, frameRate: 120) == nil)
    }

    @Test("Los puntos pasan a muestras con el tiempo desde el impacto y el toque como punto fijo")
    func samplesForFit() {
        let track = BlobTrack(points: [
            TrackedBallPoint(frameIndex: 32, point: Point2D(10, 20), isSeed: false),
            TrackedBallPoint(frameIndex: 50, point: Point2D(30, 40), isSeed: true),
        ], lastSeenFrame: 50, end: .endOfClip)
        let samples = track.samples(frameRate: 120, impactFrame: 20, scale: 2)
        #expect(samples[0].time == 0.1)
        #expect(samples[0].point == Point2D(20, 40))
        #expect(samples[1].isFixed)
    }
}
