import Foundation
import os
import UserNotifications

/// Cuándo caduca la app (docs/01, "Caducidad de la app"). Con un Apple ID gratuito, Sideloadly mete un
/// perfil (`embedded.mobileprovision`) que vale 7 días. El archivo es un sobre firmado con un plist
/// dentro: se busca el trozo de `<?xml` a `</plist>` y se lee `ExpirationDate`.
/// En el simulador no hay perfil: no hay fecha (salvo en las capturas, que enseñan una de ejemplo).
enum ProvisioningInfo {
    static let expirationDate: Date? = {
        if UITestHarness.isActive {
            // Capturas: una fecha de ejemplo a 5 días (sin el aviso de Inicio, que sale con 2 o menos).
            return Calendar.current.date(byAdding: .day, value: 5, to: .now)
        }
        return readExpirationDate()
    }()

    static func readExpirationDate() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plist = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let object = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        else { return nil }
        return object["ExpirationDate"] as? Date
    }

    /// Días que quedan (0 si caduca hoy). `nil` si no se sabe.
    static func daysLeft(now: Date = .now) -> Int? {
        guard let expirationDate else { return nil }
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.startOfDay(for: expirationDate)
        return Calendar.current.dateComponents([.day], from: start, to: end).day
    }

    /// "el domingo 29 de noviembre"
    static func longDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "EEEE d 'de' MMMM"
        return "el " + formatter.string(from: date)
    }
}

/// Aviso local 24 h antes de caducar (docs/00, etapa 9). Las notificaciones locales funcionan con un
/// Apple ID gratuito; no salen del iPhone.
enum ExpiryReminder {
    static let identifier = "trazo.caducidad"
    private static let logger = Logger(subsystem: "io.github.dvidaldedompablo.trazo", category: "Caducidad")

    static func schedule() async {
        guard !UITestHarness.isActive, let expiry = ProvisioningInfo.expirationDate else { return }
        let fireDate = expiry.addingTimeInterval(-24 * 3600)
        guard fireDate > .now else { return }
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "Trazo caduca mañana"
        content.body = "Renuévala hoy con Sideloadly y el cable: son dos minutos. Tus vídeos no se pierden."
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let request = UNNotificationRequest(identifier: identifier, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        do {
            try await center.add(request)
        } catch {
            logger.error("No se ha podido programar el aviso de caducidad: \(error.localizedDescription, privacy: .public)")
        }
    }
}
