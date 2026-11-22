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
        do {
            let started = Date.now
            let output = try await AnalysisVideoExporter.export(clipURL: clip, analysis: DemoData.swingAnalysis(reviewed: true),
                                                                short: false, subtitles: true) { progress in
                Task { @MainActor in status = "\(progress.stepName) \(Int(progress.fraction * 100)) %" }
            }
            let documents = URL.documentsDirectory
            let main = documents.appending(path: "demo-analisis.mp4")
            try? FileManager.default.removeItem(at: main)
            try FileManager.default.copyItem(at: output.main, to: main)
            var light = "no"
            if let url = output.light {
                let target = documents.appending(path: "demo-analisis-720p.mp4")
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: url, to: target)
                light = "sí"
            }
            let seconds = Int(Date.now.timeIntervalSince(started))
            finish("ok\nvoz Kokoro: \(kokoro ? "sí" : "no (voz de reserva)")\nversión 720p: \(light)\n"
                   + "recompresión: \(output.compressionProblem ?? "bien")\n"
                   + "clips que faltan: \(output.missingClips.isEmpty ? "ninguno" : output.missingClips.joined(separator: ", "))\n"
                   + "segundos en generarlo: \(seconds)")
        } catch {
            finish("error: \((error as? LocalizedError)?.errorDescription ?? describeError(error))\n"
                   + "detalle: \(describeError(error))\núltimo paso: \(status)\nvoz Kokoro: \(kokoro ? "sí" : "no")")
        }
    }
}
