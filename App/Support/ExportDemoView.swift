import GolfCore
import SwiftUI

/// Solo para el CI (`-UITestScreen export-demo -DemoVariant N`): genera el vídeo de análisis con el
/// clip y el análisis de demostración, en el simulador. Así se comprueba sin iPhone lo que no se ve en
/// una captura: la voz Kokoro, la sección "A mejorar", los subtítulos y el tamaño final.
/// Cada variante es un arranque distinto de la app (scripts/video-demo.sh), para que si una se cierra
/// de golpe las demás sigan. Deja el vídeo en Documents, el avance en `tmp/export-progress` y el
/// resultado en `tmp/export-done`.
struct ExportDemoView: View {
    @State private var status = "Generando el vídeo de demostración…"

    /// 0 es el vídeo de verdad; las demás quitan una pieza para saber cuál rompe el montaje.
    static let variants: [(name: String, short: Bool, leaveOut: AnalysisVideoExporter.Leave)] = [
        ("completo", false, []),
        ("sin ejercicios", true, [.exercises, .compression]),
        ("sin capas", true, [.overlay, .compression]),
        ("sin voz", true, [.voice, .compression]),
        ("sin capas, ejercicios ni voz", true, [.overlay, .exercises, .voice, .compression]),
    ]

    /// `-DemoVariant 9`: el vídeo del tracer (etapa 5) con la curva de demostración.
    static let tracerVariant = 9

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
        let progressFile = URL.temporaryDirectory.appending(path: "export-progress")
        try? FileManager.default.removeItem(at: marker)
        let index = min(max(UserDefaults.standard.integer(forKey: "DemoVariant"), 0), Self.variants.count - 1)
        let variant = Self.variants[index]
        func note(_ text: String) {
            status = text
            try? Data(text.utf8).write(to: progressFile)
        }
        func finish(_ text: String) {
            status = text
            try? Data(text.utf8).write(to: marker)
        }
        guard let clip = Bundle.main.url(forResource: "demo_swing", withExtension: "mp4") else {
            finish("error: falta demo_swing.mp4 en la app")
            return
        }
        if UserDefaults.standard.integer(forKey: "DemoVariant") == Self.tracerVariant {
            await exportTracer(clip: clip, finish: finish)
            return
        }
        note("[\(variant.name)] probando la voz")
        // ¿Suena Kokoro o la voz de reserva? Se prueba una frase antes de montar.
        let kokoro = await KokoroEngine.shared.render("Prueba de voz.") != nil
        let voice = "voz Kokoro: \(kokoro ? "sí" : "no (voz de reserva)")"
        let started = Date.now
        do {
            let output = try await AnalysisVideoExporter.export(clipURL: clip, analysis: DemoData.swingAnalysis(reviewed: true),
                                                                short: variant.short, subtitles: true,
                                                                leaveOut: variant.leaveOut) { progress in
                Task { @MainActor in note("[\(variant.name)] \(progress.stepName) \(Int(progress.fraction * 100)) %") }
            }
            let documents = URL.documentsDirectory
            let main = documents.appending(path: index == 0 ? "demo-analisis.mp4" : "demo-variante-\(index).mp4")
            try? FileManager.default.removeItem(at: main)
            try FileManager.default.copyItem(at: output.main, to: main)
            var light = "no"
            if let url = output.light {
                let target = documents.appending(path: "demo-analisis-720p.mp4")
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: url, to: target)
                light = "sí"
            }
            finish("ok [\(variant.name)] en \(Int(Date.now.timeIntervalSince(started))) s · \(voice) · 720p: \(light) · "
                   + "recompresión: \(output.compressionProblem ?? "bien") · clips que faltan: "
                   + (output.missingClips.isEmpty ? "ninguno" : output.missingClips.joined(separator: ", ")))
        } catch {
            finish("error [\(variant.name)]: \(describeError(error)) · último paso: \(status) · \(voice)")
        }
    }

    /// El vídeo del tracer sobre el clip de demostración: la curva de la captura, pasada al tamaño del
    /// clip, con la distancia del hierro 7 y la marca de agua. El clip acaba antes de que caiga la bola,
    /// así que también prueba el último fotograma congelado.
    private func exportTracer(clip: URL, finish: (String) -> Void) async {
        let analysis = DemoData.reviewAnalysis()
        let sx = 1080 / Double(analysis.videoWidth), sy = 1920 / Double(analysis.videoHeight)
        var curve = analysis.outcome.curve
        for keyPath in [\TracerCurve.launch, \TracerCurve.apex, \TracerCurve.landing] {
            curve[keyPath: keyPath] = Point2D(curve[keyPath: keyPath].x * sx, curve[keyPath: keyPath].y * sy)
        }
        let edit = TracerEdit(curve: curve, colorRaw: TracerColorChoice.rojoTV.rawValue,
                              customColorHex: Int(TracerPalette.customDefaultHex), showsDistance: true,
                              manualDistanceMeters: nil, clubName: "Hierro 7", clubDistanceMeters: 150)
        let started = Date.now
        do {
            let video = try await TracerVideoExporter.export(clipURL: clip, impactTime: 1.2, edit: edit, units: "m", watermark: true)
            let target = URL.documentsDirectory.appending(path: "demo-tracer.mp4")
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: video.url, to: target)
            finish("ok [tracer] en \(Int(Date.now.timeIntervalSince(started))) s · \(SpanishFormat.number(video.duration, decimals: 1)) s de vídeo")
        } catch {
            finish("error [tracer]: \(describeError(error))")
        }
    }
}
