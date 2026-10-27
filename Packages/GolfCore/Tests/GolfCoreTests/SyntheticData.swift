import Foundation
@testable import GolfCore

// Datos sintéticos para los tests: audio con clics, un swing de mentira y fotogramas de una bola que sube.
// Todo sale de un generador con semilla, así cada ejecución da exactamente lo mismo.

enum SyntheticAudio {
    static let sampleRate = 48_000.0

    /// Ruido blanco gaussiano de `seconds` segundos con desviación `level`.
    static func noise(seconds: Double, level: Double = 0.02, seed: UInt64) -> [Float] {
        var rng = SeededRandom(seed: seed)
        return (0..<Int(seconds * sampleRate)).map { _ in Float(rng.nextGaussian() * level) }
    }

    /// Suma un "clic" de impacto que empieza en `time`: dos tonos agudos (3,2 y 5,1 kHz)
    /// que se apagan en unos milisegundos, como el golpe seco del palo contra la bola.
    static func addClick(to samples: inout [Float], at time: Double, amplitude: Double = 0.8) {
        let start = Int((time * sampleRate).rounded())
        let length = Int(0.02 * sampleRate)
        for n in 0..<length where start + n < samples.count {
            let t = Double(n) / sampleRate
            let value = amplitude * exp(-t / 0.0015)
                * (sin(2 * .pi * 3200 * t) + 0.6 * sin(2 * .pi * 5100 * t + 0.5))
            samples[start + n] += Float(value)
        }
    }

    /// Seno de `frequency` Hz con amplitud `amplitude` (1 = 0 dBFS).
    static func sine(frequency: Double, seconds: Double, amplitude: Double = 1, phase: Double = 0,
                     sampleRate: Double = sampleRate) -> [Float] {
        (0..<Int(seconds * sampleRate)).map { Float(amplitude * sin(2 * .pi * frequency * Double($0) / sampleRate + phase)) }
    }
}

/// Swing de un diestro visto desde detrás, a 120 fps. El cuerpo está quieto y el brazo de delante
/// gira alrededor del hombro como un péndulo: así se sabe de antemano dónde caen las posiciones.
/// - Preparación quieta hasta 1,0 s; subida de 1,0 a 1,8 s (top); bajada hasta el impacto en 2,07 s;
///   final hasta 2,6 s y quieto hasta 3,6 s.
enum SyntheticSwing {
    static let frameRate = 120.0
    static let duration = 3.6
    static let backswingStart = 1.0
    static let topTime = 1.8
    static let impactTime = 2.07
    static let finishTime = 2.6
    static let leadShoulder = Point2D(615, 850)
    static let armLength = 330.0

    /// Ángulo del brazo de delante (grados): 0 colgando, 90 paralelo al suelo, 150 en el top.
    static func armAngle(at t: Double) -> Double {
        if t < backswingStart { return 0 }
        if t < topTime {
            let u = (t - backswingStart) / (topTime - backswingStart)
            return 150 * (3 * u * u - 2 * u * u * u)
        }
        if t < impactTime {
            let u = (t - topTime) / (impactTime - topTime)
            return 150 * (1 - u * u)
        }
        if t < finishTime {
            let u = (t - impactTime) / (finishTime - impactTime)
            return -160 * (1 - (1 - u) * (1 - u))
        }
        return -160
    }

    static func hands(at t: Double) -> Point2D {
        let phi = Geometry.radians(armAngle(at: t))
        return leadShoulder + Point2D(-sin(phi) * armLength, cos(phi) * armLength)
    }

    /// Articulaciones de la preparación (cuerpo quieto). Inclinación de unos 32°, rodilla flexionada unos 24°.
    static let body: [Joint: Point2D] = [
        .nose: Point2D(665, 795), .leftEar: Point2D(650, 790), .rightEar: Point2D(655, 788),
        .neck: Point2D(640, 842),
        .leftShoulder: leadShoulder, .rightShoulder: Point2D(630, 845),
        .root: Point2D(492, 1079), .leftHip: Point2D(495, 1078), .rightHip: Point2D(490, 1080),
        .leftKnee: Point2D(545, 1288), .rightKnee: Point2D(540, 1290),
        .leftAnkle: Point2D(510, 1495), .rightAnkle: Point2D(500, 1500),
    ]

    /// Fotogramas del swing. `modify` permite cambiar articulaciones en ciertos instantes.
    static func frames(jitter: Double = 0.4, seed: UInt64 = 7, dropLeadArm: Bool = false,
                       modify: ((Double, inout [Joint: Point2D]) -> Void)? = nil) -> [PoseFrame] {
        var rng = SeededRandom(seed: seed)
        let count = Int(duration * frameRate) + 1
        return (0..<count).map { i in
            let t = Double(i) / frameRate
            var joints = body
            let h = hands(at: t) + Point2D((rng.nextUnit() - 0.5) * 2 * jitter, (rng.nextUnit() - 0.5) * 2 * jitter)
            joints[.leftWrist] = h + Point2D(-2, 1)
            joints[.rightWrist] = h + Point2D(2, -1)
            if dropLeadArm {
                joints[.leftWrist] = nil
                joints[.leftShoulder] = nil
            }
            modify?(t, &joints)
            return PoseFrame(time: t, joints: joints)
        }
    }

    /// Refleja el swing en horizontal (ancho 1080) y cambia izquierda por derecha: un zurdo.
    static func mirrored(_ frames: [PoseFrame]) -> [PoseFrame] {
        let swap: [Joint: Joint] = [
            .leftEye: .rightEye, .rightEye: .leftEye, .leftEar: .rightEar, .rightEar: .leftEar,
            .leftShoulder: .rightShoulder, .rightShoulder: .leftShoulder, .leftElbow: .rightElbow,
            .rightElbow: .leftElbow, .leftWrist: .rightWrist, .rightWrist: .leftWrist, .leftHip: .rightHip,
            .rightHip: .leftHip, .leftKnee: .rightKnee, .rightKnee: .leftKnee, .leftAnkle: .rightAnkle,
            .rightAnkle: .leftAnkle,
        ]
        return frames.map { frame in
            var joints: [Joint: Point2D] = [:]
            for (joint, point) in frame.joints { joints[swap[joint] ?? joint] = Point2D(1080 - point.x, point.y) }
            return PoseFrame(time: frame.time, joints: joints)
        }
    }
}

/// Fotogramas en gris (160 x 240, 120 fps) de una bola que sale del tee y sube, como desde detrás del jugador.
/// Hay textura fija en el fondo, ruido en cada fotograma, un jugador oscuro quieto, un palo que barre
/// antes del impacto y un pájaro que cruza arriba (no debe confundirse con la bola).
enum SyntheticFlight {
    static let width = 160
    static let height = 240
    static let frameRate = 120.0
    static let impactFrame = 20
    static let frameCount = 80
    static let tee = Point2D(70, 205)
    static let ballRadius = 1.6

    /// Centro verdadero de la bola en el fotograma (coordenadas de píxel: el centro del píxel (i, j) es (i, j)).
    static func ballCenter(frame: Int) -> Point2D {
        guard frame > impactFrame else { return tee }
        let tau = Double(frame - impactFrame) / frameRate
        return Point2D(70 + 30 * tau, 205 - 260 * tau + 120 * tau * tau)
    }

    static func frames(hideBallFrom: Int? = nil, seed: UInt64 = 42) -> [GrayImage] {
        var rng = SeededRandom(seed: seed)
        // Fondo fijo: cielo claro con degradado y suelo más oscuro, con textura.
        var base = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let texture = (rng.nextUnit() - 0.5) * 6
                base[y * width + x] = (y < 150 ? 185 + Double(y) * 0.1 : 95) + texture
                // Jugador oscuro y quieto a la izquierda.
                if x >= 30 && x <= 55 && y >= 110 && y <= 235 { base[y * width + x] = 50 + texture }
            }
        }
        return (0..<frameCount).map { f in
            var pixels = base
            // Palo: barra fina que barre de izquierda a derecha antes del impacto.
            if f >= 8 && f < impactFrame {
                let clubX = 20 + Double(f - 8) * 4
                for y in 185...206 {
                    for x in Int(clubX)...Int(clubX) + 1 { pixels[y * width + x] = 30 }
                }
            }
            // Pájaro: mancha oscura de 2 x 2 que cruza arriba.
            if f >= 30 && f < 70 {
                let birdX = 10 + (f - 30) * 3
                for y in 40...41 {
                    for x in birdX...birdX + 1 { pixels[y * width + x] = 60 }
                }
            }
            // Bola brillante, dibujada con su cobertura de cada píxel (4 x 4 submuestras por píxel).
            if hideBallFrom.map({ f < $0 }) ?? true {
                let c = ballCenter(frame: f)
                let r = ballRadius
                for y in Int(c.y - r - 1)...Int(c.y + r + 1) {
                    for x in Int(c.x - r - 1)...Int(c.x + r + 1) {
                        var inside = 0
                        for sy in 0..<4 {
                            for sx in 0..<4 {
                                let px = Double(x) - 0.5 + (Double(sx) + 0.5) / 4
                                let py = Double(y) - 0.5 + (Double(sy) + 0.5) / 4
                                if (px - c.x) * (px - c.x) + (py - c.y) * (py - c.y) <= r * r { inside += 1 }
                            }
                        }
                        let coverage = Double(inside) / 16
                        let i = y * width + x
                        pixels[i] = pixels[i] * (1 - coverage) + 245 * coverage
                    }
                }
            }
            // Ruido de cada fotograma (±2).
            let bytes = pixels.map { value -> UInt8 in
                let noisy = value + Double(Int(rng.next() % 5) - 2)
                return UInt8(min(max(noisy.rounded(), 0), 255))
            }
            return GrayImage(width: width, height: height, pixels: bytes)
        }
    }
}
