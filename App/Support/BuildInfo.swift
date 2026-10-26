import Foundation
import GolfCore

/// Versión y fecha de compilación, leídas del Info.plist de la app.
enum BuildInfo {
    /// "0.1": MARKETING_VERSION en project.yml.
    static var version: String { string(for: "CFBundleShortVersionString") ?? "?" }
    /// Número de compilación: el CI pone aquí el número de run.
    static var build: String { string(for: "CFBundleVersion") ?? "?" }
    /// Fecha que escribe el CI. `nil` si la app se compiló fuera del CI.
    static var date: Date? { BuildLabel.parseISO8601(string(for: "TrazoBuildDate") ?? "") }

    private static func string(for key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
