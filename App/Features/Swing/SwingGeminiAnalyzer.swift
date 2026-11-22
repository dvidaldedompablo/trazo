@preconcurrency import AVFoundation
import Foundation
import GolfCore
import UIKit

/// El análisis de swing con Gemini (docs/10, Fase 4). El usuario lo pidió el 22-11-2026: "quiero que
/// lo haga todo Gemini", porque Vision no le veía en una story. Medido antes en el PC
/// (lab/analisis_gemini.py): posiciones como la lógica de siempre (0 a 2 fotogramas), palo 3 de 9
/// (la lógica de siempre, 0 de 6) y el cuerpo a un 2 o 3 % del alto de lo que ve MediaPipe.
///
/// Dos peticiones (la lógica está en `SwingCheck`, GolfCore):
/// 1. Hojas de fotogramas alrededor del impacto: en qué fotograma está cada posición.
/// 2. Los 7 fotogramas elegidos, sueltos: articulaciones, empuñadura y cabeza del palo.
/// Si algo falla, lanza el error y `SwingAnalyzer` sigue con Vision (el plan B sin red).
/// Solo se usa con la clave en el llavero y "Comprobar siempre, sin preguntar" activado.
enum SwingGeminiAnalyzer {
    struct Failure: Error {
        let reason: String
    }

    @concurrent
    static func analyze(url: URL, knownImpact: Double?, handedness: Handedness, heightCentimeters: Double,
                        key: String) async throws -> SwingAnalysis {
        let clock = ContinuousClock()
        let started = clock.now
        let info = try await VideoInspector.info(of: url, measureFrames: true)
        let request = SwingCheck.positionsPlan(duration: info.duration, impactHint: knownImpact)
        let layout = ShotCheck.layout(frameWidth: info.width, frameHeight: info.height)

        // 1. Posiciones.
        let sheetGenerator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        sheetGenerator.appliesPreferredTrackTransform = true
        sheetGenerator.maximumSize = CGSize(width: layout.cellWidth, height: layout.cellHeight)
        let tolerance = CMTime(value: 1, timescale: 60)
        sheetGenerator.requestedTimeToleranceBefore = tolerance
        sheetGenerator.requestedTimeToleranceAfter = tolerance
        var sheets: [Data] = []
        for (k, indices) in request.sheets.enumerated() {
            sheets.append(try await ShotChecker.drawSheet(caption: request.caption(k), frameTimes: indices.map { request.frameTimes[$0] },
                                                          numbers: indices.map { $0 + 1 }, generator: sheetGenerator, layout: layout))
        }
        let positionsData = try await ShotChecker.post(try SwingCheck.positionsBody(request, sheetJPEGs: sheets), key: key)
        guard let positionsText = ShotCheck.outputText(fromResponse: positionsData) else { throw Failure(reason: "respuesta vacía") }
        let chosen: SwingCheck.ChosenPositions
        switch SwingCheck.parsePositions(positionsText, for: request) {
        case let .success(value): chosen = value
        case let .failure(failure): throw Failure(reason: failure.description)
        }
        let positionsDone = clock.now

        // 2. Cuerpo y palo en los 7 fotogramas, sueltos y a buena resolución.
        let frameGenerator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        frameGenerator.appliesPreferredTrackTransform = true
        frameGenerator.maximumSize = CGSize(width: 1080, height: 1920)
        frameGenerator.requestedTimeToleranceBefore = tolerance
        frameGenerator.requestedTimeToleranceAfter = tolerance
        var frames: [Data] = []
        for moment in SwingCheck.bodyMoments {
            let time = CMTime(seconds: chosen.times[moment.key] ?? 0, preferredTimescale: 600)
            let image = try await frameGenerator.image(at: time).image
            guard let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else { throw Failure(reason: "fotograma") }
            frames.append(jpeg)
        }
        let bodyData = try await ShotChecker.post(try SwingCheck.bodyBody(frameJPEGs: frames), key: key)
        guard let bodyText = ShotCheck.outputText(fromResponse: bodyData) else { throw Failure(reason: "respuesta vacía") }
        let marks: [SwingPosition: SwingCheck.BodyMarks]
        switch SwingCheck.parseBody(bodyText, width: info.width, height: info.height) {
        case let .success(value): marks = value
        case let .failure(failure): throw Failure(reason: failure.description)
        }
        let result = SwingCheck.result(request, chosen: chosen, marks: marks)
        let finished = clock.now

        func seconds(_ d: Duration) -> Double { Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18 }
        var analysis = SwingAnalysis(
            videoWidth: info.width, videoHeight: info.height, frameRate: info.frameRate,
            analysisFrameRate: 1 / SwingCheck.sampleInterval, impactTime: result.impactTime, impactFromSound: false,
            poses: result.frames, phases: result.phases, handedness: handedness, heightCentimeters: heightCentimeters,
            clubHeadAtAddress: result.clubHeadAtAddress, clubHeadAtTakeaway: result.clubHeadAtTakeaway,
            clubLineAtMidBackswing: result.clubLineAtMidBackswing, clubLineAtTransition: result.clubLineAtTransition,
            notes: ["Las posiciones, el cuerpo y el palo los ha marcado Gemini: son aproximados. Revísalos y corrige lo que no cuadre."],
            timings: [StepTiming(name: "Gemini: posiciones", seconds: seconds(started.duration(to: positionsDone))),
                      StepTiming(name: "Gemini: cuerpo y palo", seconds: seconds(positionsDone.duration(to: finished)))])
        analysis.debugLog = (["Análisis con Gemini (\(ShotCheck.model))",
                              "Impacto de partida: \(knownImpact.map { String(format: "%.3f s", $0) } ?? "ninguno")",
                              "Hojas: \(request.sheets.count), \(request.frameTimes.count) fotogramas"]
                             + SwingCheck.moments.map { m in
                                 String(format: "%@: %.3f s (confianza %.2f)", m.key, chosen.times[m.key] ?? 0, chosen.confidence[m.key] ?? 0)
                             }
                             + SwingCheck.bodyMoments.map { m in
                                 "\(m.key): \(marks[m.position]?.joints.count ?? 0) articulaciones, palo "
                                     + (marks[m.position]?.clubHead == nil ? "no" : "sí")
                             }).joined(separator: "\n")
        return analysis
    }
}
