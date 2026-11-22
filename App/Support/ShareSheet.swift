import UIKit

/// La hoja de compartir del iPhone (UIActivityViewController) con varios archivos a la vez.
/// Con varios vídeos, `ShareLink` de SwiftUI no siempre los pasaba todos; esta hoja sí, y ofrece
/// "Guardar N vídeos", AirDrop, WhatsApp, etc.
@MainActor
enum ShareSheet {
    static func present(_ urls: [URL]) {
        guard !urls.isEmpty, let top = topViewController() else { return }
        let sheet = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        // En iPad la hoja sale de un punto; en iPhone se ignora.
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 80, width: 1, height: 1)
        top.present(sheet, animated: true)
    }

    /// La pantalla que está delante (la hoja tiene que salir encima de ella).
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
