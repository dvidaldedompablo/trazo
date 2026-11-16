import Foundation

/// Un swing sintético y verosímil sobre la escena de demostración de la app (1080 x 1920):
/// lo usan las capturas del CI (no hay vídeo en el simulador) y los tests, que comprueban
/// que `PhaseDetector` lo reconoce. Así una captura nunca se encuentra un análisis vacío.
///
/// El jugador es diestro, visto desde detrás. La subida dura 0,73 s y la bajada 0,26 s
/// (ritmo 2,8 : 1, como el vídeo de referencia). El takeaway se va por dentro a propósito:
/// la demo enseña un análisis con un fallo claro y su prioridad.
public enum DemoSwing {
    /// 120 muestras por segundo, 3,3 s.
    public static let sampleRate = 120.0
    public static let impactTime = 1.99
    /// La cabeza del palo en la preparación (sobre la bola de la escena).
    public static let clubHeadAtAddress = Point2D(895, 1735)
    /// En el takeaway, detrás de las manos (por dentro): el fallo de la demo.
    public static let clubHeadAtTakeaway = Point2D(555, 1500)
    /// Línea del palo a mitad de subida, más plana que el plano de la preparación.
    public static let clubLineAtMidBackswing = ClubLine(grip: Point2D(520, 1180), head: Point2D(980, 1340))
    /// En la transición vuelve cerca del plano.
    public static let clubLineAtTransition = ClubLine(grip: Point2D(560, 1210), head: Point2D(1000, 1560))

    /// La pose de cada fotograma.
    public static func frames() -> [PoseFrame] {
        var rng = SeededRandom(seed: 21)
        // Articulaciones quietas de la preparación (aproximadas sobre la silueta de la escena).
        let base: [Joint: Point2D] = [
            .nose: Point2D(668, 1056), .leftEar: Point2D(650, 1062), .rightEar: Point2D(676, 1058),
            .neck: Point2D(655, 1135),
            .leftShoulder: Point2D(618, 1165), .rightShoulder: Point2D(682, 1152),
            .leftElbow: Point2D(652, 1300), .rightElbow: Point2D(702, 1288),
            .leftWrist: Point2D(676, 1424), .rightWrist: Point2D(694, 1420),
            .root: Point2D(520, 1318), .leftHip: Point2D(497, 1330), .rightHip: Point2D(545, 1305),
            .leftKnee: Point2D(572, 1552), .rightKnee: Point2D(600, 1545),
            .leftAnkle: Point2D(540, 1778), .rightAnkle: Point2D(575, 1770),
        ]
        let handsRest = Point2D(685, 1422)
        let top = Point2D(420, 1010)
        let finish = Point2D(590, 1000)
        // El inicio de la subida que mide PhaseDetector cae algo después de que las manos
        // empiecen a moverse (hasta que recorren el 2 % de la estatura): estos tiempos están
        // elegidos para que lo MEDIDO salga con subida ~0,75 s y ritmo ~2,8.
        let backswingStart = 0.893
        let topTime = backswingStart + 0.837
        let finishTime = impactTime + 0.31

        func hands(at t: Double) -> Point2D {
            func ease(_ u: Double) -> Double { 0.5 - 0.5 * cos(min(max(u, 0), 1) * .pi) }
            if t < backswingStart { return handsRest }
            if t < topTime {
                return Point2D.lerp(handsRest, top, ease((t - backswingStart) / (topTime - backswingStart)))
            }
            if t < impactTime {
                return Point2D.lerp(top, Point2D(690, 1435), ease((t - topTime) / (impactTime - topTime)))
            }
            if t < finishTime {
                return Point2D.lerp(Point2D(690, 1435), finish, ease((t - impactTime) / (finishTime - impactTime)))
            }
            return finish
        }

        return (0..<Int(3.3 * sampleRate)).map { i in
            let t = Double(i) / sampleRate
            var joints = base
            let h = hands(at: t)
            let jitter = { Point2D(rng.nextUnit() * 1.6 - 0.8, rng.nextUnit() * 1.6 - 0.8) }
            joints[.leftWrist] = h + Point2D(-9, 3) + jitter()
            joints[.rightWrist] = h + Point2D(9, -3) + jitter()
            // Los codos siguen a medio camino entre el hombro y la muñeca.
            joints[.leftElbow] = Point2D.lerp(base[.leftShoulder]!, joints[.leftWrist]!, 0.55) + jitter()
            joints[.rightElbow] = Point2D.lerp(base[.rightShoulder]!, joints[.rightWrist]!, 0.55) + jitter()
            for key in [Joint.nose, .neck, .root] { joints[key] = base[key]! + jitter() }
            return PoseFrame(time: t, joints: joints)
        }
    }
}
