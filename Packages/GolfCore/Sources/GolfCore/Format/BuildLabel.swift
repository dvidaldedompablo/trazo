import Foundation

/// Textos de versión y fecha de compilación que enseña la app.
/// Viven en GolfCore (y no en la app) para poder probarlos en el CI sin iPhone.
public enum BuildLabel {
    /// "Versión 0.1 (12)". El número entre paréntesis es el de la compilación del CI,
    /// así sabes qué compilación tienes instalada.
    public static func version(_ marketing: String, build: String) -> String {
        "Versión \(marketing) (\(build))"
    }

    /// Fecha en español de España: "26 de octubre de 2026, 10:30".
    /// Se compone a mano en vez de con `DateFormatter` para que el texto no dependa
    /// de los datos de idioma de cada sistema: así el test da lo mismo en todas partes.
    public static func date(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = parts.day ?? 0
        let month = monthNames[(parts.month ?? 1) - 1]
        let year = parts.year ?? 0
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        // Los minutos siempre con dos cifras ("9:05"); la hora sin cero delante, como se escribe en España.
        let minuteText = minute < 10 ? "0\(minute)" : "\(minute)"
        return "\(day) de \(month) de \(year), \(hour):\(minuteText)"
    }

    /// Lee la fecha en formato ISO 8601 ("2026-10-26T09:30:00Z") que escribe el CI en el Info.plist.
    /// Devuelve `nil` si está vacía o mal escrita (por ejemplo, si se compila fuera del CI):
    /// la app dice entonces que no hay fecha en vez de inventarse una.
    public static func parseISO8601(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601)
    }

    private static let monthNames = [
        "enero", "febrero", "marzo", "abril", "mayo", "junio",
        "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
    ]
}
