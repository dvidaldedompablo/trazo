import Foundation

/// Parámetros del tracer para afinar, todos en un sitio (tabla "Parámetros para afinar" de docs/03).
/// Si la prueba de 5 golpes pide cambiar algo, se cambia aquí y en ningún otro archivo.
public enum TracerConstants {
    // MARK: Detector de impacto (docs/03, paso 2)

    /// Banda del sonido del impacto (Hz). Fuera quedan el viento y las voces (graves) y el siseo (agudos).
    public static let impactBandLow = 1500.0
    public static let impactBandHigh = 7000.0
    /// Ventanas de 256 muestras con salto de 64: a 48 kHz, un análisis cada 1,3 ms.
    public static let impactWindowSize = 256
    public static let impactHopSize = 64
    /// Umbral adaptativo: mediana móvil de 500 ms más 6 veces la MAD.
    public static let impactMedianWindow = 0.5
    public static let impactMADFactor = 6.0
    /// Además, el pico tiene que superar 4 veces la mediana local. Con ruido constante la MAD
    /// es tan pequeña que "mediana + 6 MAD" salta con el propio ruido (probado con ruido blanco:
    /// sus picos no pasan de 3 veces la mediana; un golpe la supera decenas de veces).
    public static let impactMinimumMedianRatio = 4.0
    /// Dos impactos no pueden estar a menos de 400 ms: el eco y el rebote no cuentan como otro golpe.
    public static let impactRefractoryPeriod = 0.4
    /// Afinado del instante: máximo de la envolvente en ±5 ms alrededor del pico.
    public static let impactRefineRadius = 0.005
    /// Por debajo de esta amplitud (−50 dBFS) no hay impacto: es silencio digital o casi.
    public static let impactMinimumPeakAmplitude = 0.003

    // MARK: Vision (docs/03, paso 4 A). Se usan en la etapa 4.

    public static let analysisFrameRate = 120.0
    public static let trajectoryLength = 10
    public static let minimumNormalizedRadius = 0.0015
    public static let maximumNormalizedRadius = 0.02
    /// Mitad del ancho de la zona de interés, en fracción del ancho de la imagen (±35 %).
    public static let regionOfInterestHalfWidth = 0.35
    /// Ventana de análisis tras el impacto (s).
    public static let flightAnalysisWindow = 2.5

    // MARK: BlobTracker (docs/03, paso 4 B)

    /// Ancho aproximado de los fotogramas reducidos que recibe BlobTracker (px).
    public static let blobImageWidth = 480
    /// Fotogramas antes del impacto con los que se hace la mediana del fondo.
    public static let backgroundFrameCount = 15
    /// Fotogramas seguidos sin ver la bola para dar el seguimiento por terminado.
    public static let maximumMissedFrames = 12
    /// Tamaño de mancha aceptado como bola (px de la imagen reducida).
    public static let blobMinimumArea = 1
    public static let blobMaximumArea = 40

    // MARK: Ajuste de la trayectoria (docs/03, paso 5)

    /// Duración de cada tramo del ajuste por tramos (s). Los tramos se solapan a la mitad.
    public static let fitSegmentDuration = 0.25
    /// Un punto es atípico si se aleja de su tramo más de 3 veces el error mediano del tramo.
    public static let outlierFactor = 3.0
    /// Umbral mínimo de atípico (px): con datos casi perfectos el error mediano es casi cero
    /// y 3 veces casi cero descartaría puntos buenos por décimas de píxel.
    public static let minimumOutlierThreshold = 1.5
    /// Peso de un toque del usuario en el ajuste frente a 1 de un punto detectado.
    public static let fixedPointWeight = 100.0
    /// Últimos segundos de puntos buenos que se usan para extrapolar hasta la caída.
    public static let extrapolationWindow = 0.5
    /// Velocidad máxima de la bola (px por fotograma): se fija con la prueba de 5 golpes.
    public static let maximumBallSpeed: Double? = nil
    /// Vuelo seguido mínimo para no avisar de pérdida (s) y confianza mínima para no pedir ajuste.
    public static let minimumTrackedFlight = 0.5
    public static let minimumConfidence = 0.5
    /// Toques de refuerzo por golpe.
    public static let maximumReinforcementTaps = 5

    // MARK: Curva del vuelo (docs/03, "Modelo de la curva")

    /// Exponente del perfil de tiempo f(τ) = 1 − (1 − τ)^2,4: rápida al salir, lenta al final.
    /// Es el de docs/03 y el que se usa si la curva no tiene longitud. En cada curva el exponente
    /// se ajusta para llegar al vértice en `apexTimeFraction`, dentro de estos límites (ver `TimeProfile`).
    public static let timeProfileExponent = 2.4
    public static let timeProfileMinimumExponent = 1.2
    public static let timeProfileMaximumExponent = 4.0
    /// Fracción del tiempo de vuelo en la que la bola llega al vértice.
    public static let apexTimeFraction = 0.5
    /// Forma de los dos tramos Bézier (fracciones de cada tramo; ver `TracerCurve`). Con estos valores
    /// la curva se separa como mucho 1,4 px de la de la maqueta (escena de 358 px de ancho).
    public static let launchLean = 0.2
    public static let launchRise = 0.5
    public static let apexRoundness = 0.45
    public static let descentLean = 0.15
    public static let descentDrop = 0.65
    /// Cuánto se dobla el vuelo hacia un lado con draw o fade, en fracción de la altura del vuelo.
    public static let shapeBulge = 0.18
    /// Tras la caída, el trazo se queda entero 1,5 s y la etiqueta aparece con un fundido de 0,3 s.
    public static let landingHoldDuration = 1.5
    public static let labelFadeDuration = 0.3
    /// Horizonte por defecto si no se encuentra el cambio cielo-suelo (fracción de la altura).
    public static let defaultHorizonFraction = 0.44
}

/// Grupos de palos con los valores de partida de la propuesta inicial (docs/03, paso 6).
/// Son valores para que la propuesta se vea bien, no medidas.
public enum ClubCategory: String, CaseIterable, Sendable, Codable {
    case driver
    case woods
    /// Hierros 5 a 7.
    case longIrons
    /// Hierros 8 y 9 y PW.
    case shortIrons
    case wedges

    /// Tiempo de vuelo inicial (s).
    public var typicalFlightTime: Double {
        switch self {
        case .driver: 6.5
        case .woods: 6.0
        case .longIrons: 5.5
        case .shortIrons: 5.0
        case .wedges: 4.5
        }
    }

    /// Altura del vértice medida desde arriba del encuadre (fracción de la altura de la imagen).
    public var apexFromTop: Double {
        switch self {
        case .driver: 0.14
        case .woods: 0.15
        case .longIrons: 0.18
        case .shortIrons: 0.20
        case .wedges: 0.23
        }
    }
}
