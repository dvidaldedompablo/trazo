import GolfCore
import SwiftUI

/// Solo para el CI (`-UITestScreen export-demo`): genera el vídeo de análisis completo con el clip y
/// el análisis de demostración, en el simulador. Así se comprueba sin iPhone lo que no se ve en una
/// captura: la voz Kokoro, la sección "A mejorar", los subtítulos y el tamaño final.
/// Deja los vídeos en Documents y una marca `tmp/export-done` con el resultado (scripts/video-demo.sh).
struct ExportDemoView: View {
    @State private var status = "Generando el vídeo de demostración…"

    var body: some View {
        Text(status)
            .typeStyle(.sub)
            .foregroundStyle(Color.pino)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bola)
            .task { await run() }
    }

    private func run() async {
        let marker = URL.temporaryDirectory.appending(path: "export-done")
        try? FileManager.default.removeItem(at: marker)
        func finish(_ text: String) {
            status = text
            try? Data(text.utf8).write(to: marker)
        }
        guard let clip = Bundle.main.url(forResource: "demo_swing", withExtension: "mp4") else {
            finish("error: falta demo_swing.mp4 en la app")
            return
        }
        // ¿Suena Kokoro o la voz de reserva? Se prueba una frase antes de montar.
        let kokoro = await KokoroEngine.shared.render("Prueba de voz.") != nil
        var report = ["voz Kokoro: \(kokoro ? "sí" : "no (voz de reserva)")"]
        var anyOK = false
        // Primero el vídeo de verdad. Si falla, variantes cortas sin una pieza cada una, para saber
        // qué pieza rompe el montaje (el error -12780 no dice cuál).
        let variants: [(String, Bool, AnalysisVideoExporter.Leave)] = [
            ("completo", false, []),
            ("sin ejercicios", true, [.exercises, .compression]),
            ("sin capas", true, [.overlay, .compression]),
            ("sin voz", true, [.voice, .compression]),
            ("sin capas, ejercicios ni voz", true, [.overlay, .exercises, .voice, .compression]),
        ]
        for (index, variant) in variants.enumerated() {
            if index > 0 && anyOK { break }
            let started = Date.now
            do {
                let output = try await AnalysisVideoExporter.export(clipURL: clip, analysis: DemoData.swingAnalysis(reviewed: true),
                                                                    short: variant.1, subtitles: true, leaveOut: variant.2) { progress in
                    Task { @MainActor in status = "\(variant.0): \(progress.stepName) \(Int(progress.fraction * 100)) %" }
                }
                let documents = URL.documentsDirectory
                let name = index == 0 ? "demo-analisis.mp4" : "demo-variante-\(index).mp4"
                let main = documents.appending(path: name)
                try? FileManager.default.removeItem(at: main)
                try FileManager.default.copyItem(at: output.main, to: main)
                var light = "no"
                if let url = output.light {
                    let target = documents.appending(path: "demo-analisis-720p.mp4")
                    try? FileManager.default.removeItem(at: target)
                    try FileManager.default.copyItem(at: url, to: target)
                    light = "sí"
                }
                if index == 0 { anyOK = true }
                report.append("[\(variant.0)] ok en \(Int(Date.now.timeIntervalSince(started))) s · 720p: \(light) · "
                              + "recompresión: \(output.compressionProblem ?? "bien") · clips que faltan: "
                              + (output.missingClips.isEmpty ? "ninguno" : output.missingClips.joined(separator: ", ")))
            } catch {
                report.append("[\(variant.0)] error: \(describeError(error)) · último paso: \(status)")
            }
        }
        finish((anyOK ? "ok" : "error: el vídeo completo no se ha podido generar") + "\n" + report.joined(separator: "\n"))
    }
}
