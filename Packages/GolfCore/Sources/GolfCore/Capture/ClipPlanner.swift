import Foundation

/// Para qué se graba: cada modo corta los clips con márgenes distintos alrededor del impacto.
public enum CaptureMode: String, Sendable, Codable, CaseIterable {
    case tracer
    case swing

    /// Nombre en pantalla.
    public var title: String {
        switch self {
        case .tracer: "Tracer"
        case .swing: "Swing"
        }
    }

    /// Segundos que se guardan antes del impacto. En el tracer basta con ver el golpe;
    /// en el swing hace falta la preparación y la subida entera.
    public var secondsBeforeImpact: Double {
        switch self {
        case .tracer: 1
        case .swing: 2.5
        }
    }

    /// Segundos que se guardan después: en el tracer, todo el vuelo que se pueda ver;
    /// en el swing, el final y que se quede quieto.
    public var secondsAfterImpact: Double {
        switch self {
        case .tracer: 8
        case .swing: 2
        }
    }

    /// Duración prevista de un clip: 9 s en Tracer y 4,5 s en Swing.
    public var clipDuration: Double { secondsBeforeImpact + secondsAfterImpact }
}

/// Un clip propuesto por el corte automático.
public struct ClipWindow: Sendable, Equatable {
    /// Inicio y final dentro de la grabación (s).
    public var start: Double
    public var end: Double
    /// Instante del impacto dentro de la grabación (s).
    public var impactTime: Double
    /// Fuerza del impacto (la de `Impact.strength`), para ordenar y proponer.
    public var strength: Double
    /// La propuesta lo marca para guardar: suena como un golpe propio, no como uno lejano.
    public var isSuggested: Bool
    /// Clip demasiado corto para analizarlo: queda menos de 1 s antes o después del impacto,
    /// o el clip no llega al 60 % de su duración prevista (en Tracer, sin casi todo el vuelo).
    public var isTooShort: Bool

    public var duration: Double { end - start }
    /// Instante del impacto contado desde el inicio del clip.
    public var impactOffset: Double { impactTime - start }
}

/// Lo que propone el corte automático para una grabación.
public struct ClipProposal: Sendable, Equatable {
    /// Un clip por golpe. Vacío si los impactos no parecen una tanda de golpes.
    public var windows: [ClipWindow]
    /// Los impactos parecen golpes de golf (`ClipPlanner.isShotSeries`).
    public var isShotSeries: Bool
}

/// Corte automático (etapa 3): de los impactos encontrados en el audio a un clip por golpe.
///
/// Cada clip va de `secondsBeforeImpact` antes del impacto a `secondsAfterImpact` después,
/// recortado a lo que dure la grabación. Si dos golpes están más cerca que eso, sus clips se solapan:
/// es mejor que los dos estén completos que cortar uno.
public enum ClipPlanner {
    /// Mínimo que tiene que quedar antes y después del golpe (docs/02: "al menos 1 s antes y 1 s después").
    public static let minimumMargin = 1.0
    /// Un clip recortado por el principio o el final de la grabación tiene que durar al menos esta
    /// fracción de lo previsto: 5,4 s de 9 en Tracer y 2,7 s de 4,5 en Swing.
    public static let minimumDurationFraction = 0.6
    /// Control de sensatez: dos golpes de golf seguidos no están a menos de 2 s.
    public static let minimumShotSpacing = 2.0
    /// Se proponen los golpes que suenan al menos esta fracción del más fuerte.
    /// Los más flojos suelen ser de otros jugadores del campo de prácticas.
    public static let suggestionFraction = 0.25

    /// La propuesta completa: el control de sensatez y, si lo pasa, un clip por golpe.
    /// Si no parece una tanda de golpes (una voz, aplausos), no se propone ninguna lista.
    public static func propose(for impacts: [Impact], recordingDuration: Double, mode: CaptureMode) -> ClipProposal {
        guard isShotSeries(impacts) else { return ClipProposal(windows: [], isShotSeries: false) }
        return ClipProposal(windows: windows(for: impacts, recordingDuration: recordingDuration, mode: mode),
                            isShotSeries: true)
    }

    public static func windows(for impacts: [Impact], recordingDuration: Double, mode: CaptureMode) -> [ClipWindow] {
        let strongest = impacts.map(\.strength).max() ?? 0
        return impacts.sorted { $0.time < $1.time }.map { impact in
            let start = max(0, impact.time - mode.secondsBeforeImpact)
            let end = min(recordingDuration, impact.time + mode.secondsAfterImpact)
            let tooShort = impact.time - start < minimumMargin - 1e-9 || end - impact.time < minimumMargin - 1e-9
                || end - start < minimumDurationFraction * mode.clipDuration - 1e-9
            return ClipWindow(start: start, end: end, impactTime: impact.time, strength: impact.strength,
                              isSuggested: impact.strength >= suggestionFraction * strongest && !tooShort,
                              isTooShort: tooShort)
        }
    }

    /// ¿Parece una tanda de golpes de golf? Entre golpe y golpe pasan varios segundos: hay que
    /// colocar la bola, prepararse y hacer el swing. Si más de la mitad de los impactos están a menos
    /// de 2 s del anterior, son otra cosa (las consonantes de una voz, aplausos, un martillo) y el corte
    /// automático no debe proponer clips. Con menos de dos impactos no hay nada que comparar.
    public static func isShotSeries(_ impacts: [Impact]) -> Bool {
        guard impacts.count >= 2 else { return true }
        let times = impacts.map(\.time).sorted()
        let close = zip(times, times.dropFirst()).filter { $1 - $0 < minimumShotSpacing }.count
        return 2 * close <= impacts.count
    }
}
