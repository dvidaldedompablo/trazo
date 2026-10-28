import Foundation
import Testing
@testable import GolfCore

struct TracerCurveTests {
    /// Las asas de la curva de la maqueta (escena de 358 x 180 de Inicio).
    static let mockup = TracerCurve(launch: Point2D(38, 176), apex: Point2D(175.5, 23.7), landing: Point2D(262, 104),
                                    flightTime: 5.5)

    @Test("La bola sale de S en t = 0, llega a L en t = T y se queda ahí")
    func startsAtLaunchEndsAtLanding() {
        let flight = Self.mockup.makeFlight()
        #expect(flight.ballPosition(at: 0) == Self.mockup.launch)
        #expect(flight.ballPosition(at: -1) == Self.mockup.launch)
        #expect(flight.ballPosition(at: 5.5).distance(to: Self.mockup.landing) < 1e-9)
        #expect(flight.ballPosition(at: 9).distance(to: Self.mockup.landing) < 1e-9)
    }

    @Test("La bola llega al vértice a mitad del tiempo de vuelo")
    func apexAtHalfTime() {
        let flight = Self.mockup.makeFlight()
        #expect(flight.ballPosition(at: 2.75).distance(to: Self.mockup.apex) < 1)
    }

    @Test("La curva pasa por las tres asas con cualquier forma, y con forma recta el vértice es lo más alto")
    func passesThroughHandles() {
        for shape in [-1.0, -0.5, 0, 0.5, 1] {
            var curve = Self.mockup
            curve.shape = shape
            let flight = curve.makeFlight()
            let nearest = flight.points.map { $0.distance(to: curve.apex) }.min() ?? 99
            #expect(nearest < 0.5)
            #expect(flight.points.first == curve.launch)
            #expect(flight.points.last == curve.landing)
        }
        #expect(abs(Self.mockup.makeFlight().highestPoint.y - Self.mockup.apex.y) < 0.5)
    }

    @Test("Perfil de velocidad creíble: rápida al salir, frenando, sin saltos en el vértice")
    func credibleSpeedProfile() {
        let flight = Self.mockup.makeFlight()
        let total = flight.totalLength
        let dt = 0.01
        let speeds = stride(from: 0.0, to: 5.5, by: dt).map { t in (flight.progress(at: t + dt) - flight.progress(at: t)) * total / dt }
        // El recorrido nunca va hacia atrás.
        #expect(speeds.allSatisfy { $0 >= 0 })
        // En la subida la velocidad baja siempre.
        let rise = speeds.prefix(270)
        #expect(zip(rise, rise.dropFirst()).allSatisfy { $1 <= $0 + 1e-6 })
        // Al final va mucho más lenta que al salir.
        #expect(speeds.last! < speeds.first! / 3)
        // En el vértice no hay saltos de velocidad (menos del 10 % entre antes y después).
        let before = speeds[273], after = speeds[276]
        #expect(abs(after - before) / before < 0.1)
    }

    @Test("El perfil de tiempo llega al vértice en τ = 0,5 y al final en τ = 1", arguments: [0.6, 0.63, 0.81, 0.9])
    func timeProfileHitsApex(apexFraction: Double) {
        let profile = TimeProfile(apexFraction: apexFraction)
        #expect(profile.fraction(at: 0) == 0)
        #expect(abs(profile.fraction(at: 0.5) - apexFraction) < 1e-9)
        #expect(abs(profile.fraction(at: 1) - 1) < 1e-9)
        let values = stride(from: 0.0, through: 1.0, by: 0.01).map(profile.fraction(at:))
        #expect(zip(values, values.dropFirst()).allSatisfy { $1 >= $0 - 1e-12 })
    }

    @Test("Con la subida en el 81 % del recorrido sale el exponente 2,4 de docs/03; fuera de margen se limita")
    func timeProfileExponent() {
        #expect(abs(TimeProfile(apexFraction: 1 - pow(0.5, 2.4)).exponent - 2.4) < 1e-9)
        #expect(TimeProfile(apexFraction: 0.3).exponent == TracerConstants.timeProfileMinimumExponent)
        #expect(TimeProfile(apexFraction: 0.99).exponent == TracerConstants.timeProfileMaximumExponent)
        // Aunque se limite, la bola sigue saliendo de S y llegando a L.
        let clamped = TimeProfile(apexFraction: 0.3)
        #expect(clamped.fraction(at: 0) == 0 && clamped.fraction(at: 1) == 1)
    }

    @Test("Vuelo alto y estrecho visto desde detrás: sin lazos, la curva no se sale de la salida ni de la caída")
    func narrowFlightHasNoLoops() {
        // Caso de la propuesta cuando se pierde la bola subiendo: 65 px de la salida al vértice y 42 px a la caída
        // en horizontal, con 1394 px de altura (vídeo de 1080 x 1920).
        let curve = TracerCurve(launch: Point2D(903, 1740), apex: Point2D(838, 346), landing: Point2D(796, 760),
                                flightTime: 5.5)
        let flight = curve.makeFlight()
        let rise = flight.points[...flight.apexPointIndex]
        let fall = flight.points[flight.apexPointIndex...]
        // La subida va de la salida al vértice sin pasarse por fuera (como mucho 3 px de redondeo).
        #expect(rise.allSatisfy { $0.x <= 903 + 3 && $0.x >= 838 - 3 })
        // La bajada, del vértice a la caída, se pasa como mucho un 2 % de la altura del vuelo.
        #expect(fall.allSatisfy { $0.x <= 838 + 3 && $0.x >= 796 - 0.02 * 1394 })
        // Y la cima sigue siendo el vértice.
        #expect(abs(flight.highestPoint.y - curve.apex.y) < 0.5)
    }

    @Test("Draw y fade doblan el vuelo hacia lados opuestos; en un zurdo, al revés")
    func shapeBendsSideways() {
        func midRiseX(shape: Double, handedness: Handedness = .right) -> Double {
            var curve = Self.mockup
            curve.shape = shape
            curve.handedness = handedness
            return curve.makeFlight().ballPosition(at: 1.0).x
        }
        let straight = midRiseX(shape: 0)
        #expect(midRiseX(shape: -1) > straight + 2)   // draw de diestro: sale a la derecha
        #expect(midRiseX(shape: 1) < straight - 2)    // fade de diestro: sale a la izquierda
        #expect(midRiseX(shape: -1, handedness: .left) < straight - 2)
    }

    @Test("El trazo dibujado crece con el tiempo y acaba en la bola")
    func pathGrows() {
        let flight = Self.mockup.makeFlight()
        let early = flight.path(upTo: 0.5)
        let late = flight.path(upTo: 3)
        #expect(late.count > early.count)
        #expect(early.last!.distance(to: flight.ballPosition(at: 0.5)) < 1e-9)
        #expect(flight.path(upTo: 0).count == 1)
    }

    @Test("La curva por defecto se parece a la de la maqueta (menos de 1,5 px)")
    func matchesMockupCurve() {
        // Puntos del vuelo de la maqueta (App/Features/Home/PreviewScene.swift), uno de cada cuatro.
        let mockupPoints = [
            Point2D(38.0, 176.0), Point2D(51.3, 143.9), Point2D(67.0, 113.3), Point2D(84.7, 85.5),
            Point2D(104.2, 61.6), Point2D(125.1, 42.6), Point2D(147.2, 29.7), Point2D(170.0, 24.0),
            Point2D(190.7, 25.0), Point2D(208.5, 30.8), Point2D(223.6, 40.6), Point2D(236.3, 53.6),
            Point2D(246.7, 69.1), Point2D(255.2, 86.1), Point2D(262.0, 104.0),
        ]
        let points = Self.mockup.makeFlight().points
        for target in mockupPoints {
            let nearest = points.map { $0.distance(to: target) }.min() ?? 99
            #expect(nearest < 1.5)
        }
    }

    @Test("Propuesta inicial: sale de la bola, cae en el horizonte y usa los valores del palo")
    func initialProposal() {
        let curve = TracerCurve.proposal(ball: Point2D(540, 1700), imageWidth: 1080, imageHeight: 1920, club: .longIrons)
        #expect(curve.launch == Point2D(540, 1700))
        #expect(abs(curve.landing.y - 0.44 * 1920) < 1e-9)
        #expect(abs(curve.apex.y - 0.18 * 1920) < 1e-9)
        #expect(curve.flightTime == 5.5)
        #expect(curve.shape == 0)
        #expect(ClubCategory.driver.typicalFlightTime == 6.5)
        #expect(ClubCategory.wedges.apexFromTop == 0.23)
    }
}
