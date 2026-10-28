import Foundation

/// El impacto visto en la imagen (docs/03, paso 2): la bola desaparece del tee.
///
/// Se mide en cada fotograma el contraste de la bola (su centro frente a lo que la rodea, con
/// `BallLocator.coreContrast`). Mientras la bola está quieta el contraste es alto; en el impacto el palo
/// la tapa y enseguida se va, y el contraste cae a casi cero y ya no vuelve.
public enum BallMotion {
    /// Índice del primer fotograma en que la bola ya no está.
    ///
    /// - Parameters:
    ///   - contrasts: contraste de la bola en cada fotograma, en orden.
    ///   - referenceCount: cuántos de los primeros fotogramas son seguro de antes del impacto (con la bola).
    /// - Returns: el primer índice desde el que el contraste se queda por debajo de la mitad del de antes
    ///   durante 4 fotogramas seguidos, o `nil` si la bola no se ve bien antes o no llega a irse.
    public static func disappearanceIndex(contrasts: [Double], referenceCount: Int,
                                          minimumContrast: Double = TracerConstants.ballMinimumContrast / 2,
                                          dropFraction: Double = TracerConstants.ballDisappearFraction,
                                          hold: Int = TracerConstants.ballDisappearHold) -> Int? {
        let reference = Array(contrasts.prefix(max(referenceCount, 1)))
        let baseline = LinearAlgebra.median(reference)
        guard baseline >= minimumContrast, contrasts.count >= referenceCount + hold else { return nil }
        let limit = dropFraction * baseline
        for i in referenceCount...(contrasts.count - hold) where contrasts[i..<(i + hold)].allSatisfy({ $0 < limit }) {
            return i
        }
        return nil
    }
}

/// Elige el instante del impacto con el sonido y el movimiento (docs/03, paso 2).
public enum ImpactChooser {
    public enum Source: String, Sendable, Codable {
        case sound
        case motion
    }

    public struct Choice: Sendable, Equatable {
        public var time: Double
        public var source: Source
    }

    /// - Parameters:
    ///   - audio: impactos oídos (puede haber golpes de otros jugadores).
    ///   - motionTime: instante en que la bola desaparece del tee, si se ha visto.
    ///   - frameDuration: duración de un fotograma (1/240 s a 240 fps).
    /// - Returns: con movimiento, el golpe oído más cercano a él si está a 2 fotogramas o menos (el sonido
    ///   es más preciso); si no, manda el movimiento. Sin movimiento, el golpe oído más fuerte.
    public static func choose(audio: [Impact], motionTime: Double?, frameDuration: Double,
                              toleranceFrames: Double = TracerConstants.impactAgreementFrames) -> Choice? {
        guard let motionTime else {
            return audio.max { $0.strength < $1.strength }.map { Choice(time: $0.time, source: .sound) }
        }
        if let nearest = audio.min(by: { abs($0.time - motionTime) < abs($1.time - motionTime) }),
           abs(nearest.time - motionTime) <= toleranceFrames * frameDuration + 1e-9 {
            return Choice(time: nearest.time, source: .sound)
        }
        return Choice(time: motionTime, source: .motion)
    }
}

/// Busca el horizonte (docs/03, paso 6): la fila donde el cielo, más claro, da paso al suelo.
public enum HorizonFinder {
    /// - Returns: la y del horizonte (px), o `nil` si no hay un cambio claro (entonces se usa el 44 % de la altura).
    public static func find(in image: GrayImage, search: ClosedRange<Double> = TracerConstants.horizonSearch,
                            minimumContrast: Double = TracerConstants.horizonMinimumContrast) -> Double? {
        let h = image.height
        guard h > 10 else { return nil }
        // Brillo medio de cada fila.
        var rows = [Double](repeating: 0, count: h)
        for y in 0..<h {
            var sum = 0
            for x in 0..<image.width { sum += Int(image.pixels[y * image.width + x]) }
            rows[y] = Double(sum) / Double(image.width)
        }
        // Se comparan franjas del 3 % de la altura por encima y por debajo de cada fila.
        let band = max(Int(0.03 * Double(h)), 2)
        let from = max(Int(search.lowerBound * Double(h)), band)
        let to = min(Int(search.upperBound * Double(h)), h - band)
        guard from < to else { return nil }
        var best: (y: Int, difference: Double)?
        for y in from..<to {
            let above = rows[(y - band)..<y].reduce(0, +) / Double(band)
            let below = rows[y..<(y + band)].reduce(0, +) / Double(band)
            let difference = above - below
            if best == nil || difference > best!.difference { best = (y, difference) }
        }
        guard let best, best.difference >= minimumContrast else { return nil }
        return Double(best.y)
    }
}
