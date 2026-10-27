import Foundation

/// Mano dominante del jugador. Las reglas del swing se escriben para un diestro visto desde detrás
/// (la bola a su derecha en la imagen, "hacia la bola" = +x); para un zurdo se reflejan en horizontal.
public enum Handedness: String, Sendable, Codable, CaseIterable, Hashable {
    case right
    case left

    /// +1 diestro, −1 zurdo. Multiplicando las diferencias en x por este signo,
    /// "hacia la bola" es siempre positivo.
    public var xSign: Double { self == .right ? 1 : -1 }

    // El lado de delante (el más cercano al objetivo) es el izquierdo en un diestro.
    public var leadShoulder: Joint { self == .right ? .leftShoulder : .rightShoulder }
    public var leadElbow: Joint { self == .right ? .leftElbow : .rightElbow }
    public var leadWrist: Joint { self == .right ? .leftWrist : .rightWrist }
    public var leadHip: Joint { self == .right ? .leftHip : .rightHip }
    public var leadKnee: Joint { self == .right ? .leftKnee : .rightKnee }
    public var leadAnkle: Joint { self == .right ? .leftAnkle : .rightAnkle }
    // El de atrás es el que mejor se ve desde detrás: se prefiere para rodilla y brazo (docs/04).
    public var trailShoulder: Joint { self == .right ? .rightShoulder : .leftShoulder }
    public var trailWrist: Joint { self == .right ? .rightWrist : .leftWrist }
    public var trailHip: Joint { self == .right ? .rightHip : .leftHip }
    public var trailKnee: Joint { self == .right ? .rightKnee : .leftKnee }
    public var trailAnkle: Joint { self == .right ? .rightAnkle : .leftAnkle }
}

/// Articulaciones que da la pose corporal de Vision (los mismos nombres que `HumanBodyPoseObservation`).
public enum Joint: String, Sendable, Codable, CaseIterable, Hashable {
    case nose, leftEye, rightEye, leftEar, rightEar
    case neck, leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
    /// Centro de la cadera.
    case root
    case leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle
}

/// La pose de un fotograma: el instante y las articulaciones que se ven (en píxeles).
/// Una articulación que falta (tapada o con confianza < 0,3) simplemente no está en el diccionario.
public struct PoseFrame: Sendable, Equatable {
    public var time: Double
    public var joints: [Joint: Point2D]

    public init(time: Double, joints: [Joint: Point2D]) {
        self.time = time
        self.joints = joints
    }

    public subscript(joint: Joint) -> Point2D? { joints[joint] }

    /// Manos: punto medio de las muñecas. Si solo se ve una, esa: en el grip van juntas.
    public var hands: Point2D? {
        switch (joints[.leftWrist], joints[.rightWrist]) {
        case let (l?, r?): Point2D.midpoint(l, r)
        case let (l?, nil): l
        case let (nil, r?): r
        case (nil, nil): nil
        }
    }

    /// Cabeza: la nariz; si no se ve, el punto medio de las orejas (o la que se vea).
    public var head: Point2D? {
        if let nose = joints[.nose] { return nose }
        switch (joints[.leftEar], joints[.rightEar]) {
        case let (l?, r?): return Point2D.midpoint(l, r)
        case let (l?, nil): return l
        case let (nil, r?): return r
        case (nil, nil): return nil
        }
    }

    /// La primera articulación que se vea de las dos (para preferir el lado de atrás).
    public func first(_ preferred: Joint, _ fallback: Joint) -> Point2D? {
        joints[preferred] ?? joints[fallback]
    }

    /// Estatura en píxeles con la cadena tobillo-rodilla-cadera-cuello-nariz (docs/04, punto 2),
    /// usando el lado de atrás si se ve y si no el de delante. `nil` si falta algún punto.
    public func staturePixels(handedness: Handedness) -> Double? {
        guard let ankle = first(handedness.trailAnkle, handedness.leadAnkle),
              let knee = first(handedness.trailKnee, handedness.leadKnee),
              let hip = first(handedness.trailHip, handedness.leadHip),
              let neck = joints[.neck], let nose = head
        else { return nil }
        return PixelScale.staturePixels(ankle: ankle, knee: knee, hip: hip, neck: neck, nose: nose)
    }
}
