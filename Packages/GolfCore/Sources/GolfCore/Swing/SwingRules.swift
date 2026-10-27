import Foundation

/// Constantes del análisis de swing, todas en un sitio (docs/04) para afinarlas con el profesor.
/// Las que docs/04 no fija (casi todas las penalizaciones) son valores de partida razonables,
/// no verdades: se marcan con "(a afinar)".
public enum SwingRules {
    // MARK: Las 7 posiciones (docs/04, punto 3)

    /// Inicio de la subida: las manos se alejan más del 2 % de la estatura de su posición de preparación.
    public static let backswingStartDistance = 0.02
    /// …y siguen alejándose durante estos fotogramas.
    public static let backswingKeepsMovingFrames = 3
    /// Manos "quietas": en toda la ventana no se separan de su media más del 1 % de la estatura (a afinar).
    public static let stillTolerance = 0.01
    /// Preparación: manos quietas al menos 0,3 s. Alternativa: 0,2 s antes del inicio de la subida.
    public static let addressStillDuration = 0.3
    public static let addressFallbackOffset = 0.2
    /// Takeaway: las manos han recorrido el 22 % del camino entre el inicio de la subida y el top.
    public static let takeawayPathFraction = 0.22
    /// Mitad de subida y transición: brazo de delante paralelo al suelo con ±10° de margen.
    public static let armParallelTolerance = 10.0
    /// Alternativa de la mitad de subida: el 55 % del recorrido de las manos.
    public static let midBackswingFallbackFraction = 0.55
    /// Final: manos quietas 0,4 s (con algo más de margen que en la preparación, a afinar).
    /// Alternativa: impacto + 1,0 s.
    public static let finishStillDuration = 0.4
    public static let finishStillTolerance = 0.015
    public static let finishFallbackOffset = 1.0
    /// Sin sonido, el impacto se busca como mucho 0,6 s después del top.
    public static let impactSearchAfterTop = 0.6

    // MARK: Medidas (docs/04, punto 5)

    /// Parte de atrás de la cadera ≈ centro de cadera − 0,12 × estatura (hacia atrás).
    public static let backOfHipOffset = 0.12
    /// Radio del círculo de la cabeza, en fracción de la estatura (una cabeza mide ~1/8, a afinar).
    public static let headCircleRadius = 0.065
    /// Final equilibrado: articulaciones casi quietas 0,8 s tras el final (margen del 2,5 % de la estatura, a afinar).
    public static let finishBalanceDuration = 0.8
    public static let finishBalanceTolerance = 0.025

    // MARK: Nota (docs/04, punto 6)

    /// Ninguna fase baja de 2.
    public static let minimumPhaseScore = 2.0
    /// Puntos fuertes: fases con 8 o más (hasta 4).
    public static let strengthScore = 8.0
    public static let maximumStrengths = 4
    /// A mejorar: las 3 notas más bajas por debajo de 7.
    public static let improvementScore = 7.0
    public static let maximumImprovements = 3

    /// Reglas de cada medida: rango bueno, umbrales de fallo y penalización.
    /// La penalización es por unidad fuera del rango bueno (grados, cm, fracción del tronco o "veces").
    public static func rule(for kind: MetricKind) -> MetricRule {
        switch kind {
        case .spineTilt:
            // docs/04 da este ejemplo: 0,25 puntos por grado fuera.
            MetricRule(good: 28...42, lowFault: .uprightPosture, highFault: .lowPosture, penaltyPerUnit: 0.25)
        case .kneeFlex:
            MetricRule(good: 15...30, lowFault: .uprightPosture, highFault: .lowPosture, penaltyPerUnit: 0.2)
        case .armsHang:
            // 0,1 del tronco fuera = 1,5 puntos (a afinar).
            MetricRule(good: -0.05...0.20, lowFault: .handsTooClose, highFault: .handsFarFromBody, penaltyPerUnit: 15)
        case .clubPlane, .backswingDuration:
            MetricRule(good: nil, penaltyPerUnit: 0)
        case .takeawayClubHead:
            MetricRule(good: -0.05...0.10, lowFault: .takeawayInside, highFault: .takeawayOutside, penaltyPerUnit: 20)
        case .midBackswingClub:
            MetricRule(good: -10...10, lowFault: .flatMidBackswing, highFault: .steepMidBackswing, penaltyPerUnit: 0.2)
        case .handsHeight:
            // Bien por encima de 0,35; el fallo "Subida corta" se dice por debajo de 0,10.
            MetricRule(good: 0.35...Double.greatestFiniteMagnitude, faultBelow: 0.10,
                       lowFault: .shortBackswing, penaltyPerUnit: 8)
        case .headAtTop, .headAtImpact:
            MetricRule(good: 0...5, highFault: .headMovement, penaltyPerUnit: 0.5)
        case .transitionClub:
            MetricRule(good: -8...8, lowFault: .flatDownswing, highFault: .steepDownswing, penaltyPerUnit: 0.25)
        case .tiltLoss:
            MetricRule(good: -Double.greatestFiniteMagnitude...8, highFault: .earlyExtension, penaltyPerUnit: 0.3)
        case .hipToBall:
            MetricRule(good: -Double.greatestFiniteMagnitude...3, highFault: .earlyExtension, penaltyPerUnit: 0.6)
        case .finishBalanced:
            // Sí = 1, no = 0. Un final sin equilibrio resta 3 puntos (a afinar).
            MetricRule(good: 1...1, lowFault: .unbalancedFinish, penaltyPerUnit: 3)
        case .finishComplete:
            MetricRule(good: 1...1, lowFault: .shortFinish, penaltyPerUnit: 3)
        case .tempo:
            // Bien de 2,6 a 3,4; los fallos se dicen por debajo de 2,4 y por encima de 3,8.
            MetricRule(good: 2.6...3.4, faultBelow: 2.4, faultAbove: 3.8,
                       lowFault: .fastTempo, highFault: .slowTempo, penaltyPerUnit: 4)
        }
    }

    /// Peso de cada fase en la nota total: la transición y el impacto cuentan doble; el ritmo, 1,5 veces.
    public static func weight(of phase: SwingPhase) -> Double {
        switch phase {
        case .transition, .impact: 2
        case .tempo: 1.5
        default: 1
        }
    }

    /// Etiqueta de la nota total.
    public static func label(forTotal total: Int) -> String {
        switch total {
        case 90...: "Nivel muy alto"
        case 80..<90: "Muy sólido"
        case 70..<80: "Buena base"
        case 60..<70: "Con margen de mejora"
        default: "A construir"
        }
    }
}

/// Regla de una medida.
public struct MetricRule: Sendable {
    /// Rango bueno. `nil` = medida informativa (no puntúa).
    public var good: ClosedRange<Double>?
    /// Por debajo de este valor se dice el fallo de "poco". Por defecto, el límite bajo del rango bueno.
    public var faultBelow: Double?
    /// Por encima de este valor se dice el fallo de "mucho". Por defecto, el límite alto del rango bueno.
    public var faultAbove: Double?
    public var lowFault: FaultID?
    public var highFault: FaultID?
    /// Puntos que se restan por cada unidad fuera del rango bueno.
    public var penaltyPerUnit: Double

    public init(good: ClosedRange<Double>?, faultBelow: Double? = nil, faultAbove: Double? = nil,
                lowFault: FaultID? = nil, highFault: FaultID? = nil, penaltyPerUnit: Double) {
        self.good = good
        self.faultBelow = faultBelow ?? good?.lowerBound
        self.faultAbove = faultAbove ?? good?.upperBound
        self.lowFault = lowFault
        self.highFault = highFault
        self.penaltyPerUnit = penaltyPerUnit
    }
}
