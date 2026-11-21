@preconcurrency import AVFoundation
import Foundation
import GolfCore
import UIKit

/// El verificador de golpes en el iPhone (docs/10, Fase 4): dibuja una hoja de fotogramas por cada
/// sonido fuerte, las manda a Gemini con la clave del usuario y decide con `ShotCheck` (GolfCore).
///
/// Es la única llamada de red de la app (la excepción escrita en CLAUDE.md). Solo se hace después de
/// que el usuario acepte el aviso, con la clave que escribió en Ajustes (llavero), y el plan B es el
/// de siempre: si no hay red o algo falla, la lista de golpes se queda como la dejó el corte automático.
/// Se envían hojas de fotogramas, nunca el vídeo ni el sonido.
enum ShotChecker {
    struct Result: Sendable {
        let checked: ShotCheck.CheckedProposal
        /// Una miniatura por clip de `checked.windows` (JPEG).
        let thumbnails: [Data?]
        /// Cuántos sonidos se comprobaron.
        let sounds: Int
        /// Lo que no validó de la respuesta (para el registro; el usuario ve el resultado).
        let warnings: [String]
    }

    enum Failure: Error, LocalizedError {
        case offline, timeout, badKey, quota, busy, unreadable, server(Int)

        /// Mensajes en la hoja de elegir golpes: qué pasó y que la lista sigue como siempre.
        var errorDescription: String? {
            switch self {
            case .offline: "No hay conexión a internet."
            case .timeout: "Gemini ha tardado demasiado en contestar."
            case .badKey: "Google no acepta tu clave. Revísala en Ajustes."
            case .quota: "Se ha acabado la cuota gratuita de hoy. Mañana vuelve a funcionar."
            case .busy: "Gemini está saturado ahora mismo. Prueba en un rato."
            case .unreadable: "Gemini ha contestado algo que no se entiende."
            case .server(let code): "Google ha respondido con un error (\(code))."
            }
        }
    }

    /// Cuántos sonidos se mandarían (para el aviso antes de enviar).
    static func soundCount(_ pending: PendingRecording) -> Int {
        ShotCheck.candidates(pending.impacts).count
    }

    /// Comprueba la grabación con Gemini. `@concurrent`: leer fotogramas y esperar a la red va fuera
    /// del hilo principal. Si algo falla, lanza un `Failure` y la hoja sigue con la lista de siempre.
    @concurrent
    static func check(_ pending: PendingRecording, key: String) async throws -> Result {
        let requests = ShotCheck.plan(for: pending.impacts, duration: pending.info.duration)
        let layout = ShotCheck.layout(frameWidth: pending.info.width, frameHeight: pending.info.height)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: pending.sourceURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: layout.cellWidth, height: layout.cellHeight)
        // Medio fotograma a 30 fps: el fotograma más cercano sin decodificar de más.
        let tolerance = CMTime(value: 1, timescale: 60)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        var verdicts: [ShotCheck.Verdict] = []
        var warnings: [String] = []
        for request in requests {
            var jpegs: [Data] = []
            for sheet in request.sheets {
                jpegs.append(try await drawSheet(sheet, generator: generator, layout: layout))
            }
            let body = try ShotCheck.requestBody(request, sheetJPEGs: jpegs)
            let data = try await post(body, key: key)
            guard let text = ShotCheck.outputText(fromResponse: data) else { throw Failure.unreadable }
            let parsed = ShotCheck.parse(text, for: request)
            verdicts += parsed.verdicts
            warnings += parsed.warnings
        }
        // Nada válido en ninguna respuesta: mejor decirlo que fingir que se comprobó.
        if verdicts.isEmpty, !requests.isEmpty { throw Failure.unreadable }

        let checked = ShotCheck.proposal(impacts: pending.impacts, verdicts: verdicts,
                                         recordingDuration: pending.info.duration, mode: pending.mode)
        // Miniaturas: la que ya había para ese golpe o una nueva si el corte automático no lo propuso.
        var thumbnails: [Data?] = []
        for window in checked.windows {
            if let index = pending.windows.firstIndex(where: { $0.impactTime == window.impactTime }),
               index < pending.thumbnails.count {
                thumbnails.append(pending.thumbnails[index])
            } else {
                thumbnails.append(try? await Thumbnailer.jpeg(from: pending.sourceURL, at: window.impactTime))
            }
        }
        return Result(checked: checked, thumbnails: thumbnails, sounds: verdicts.count, warnings: warnings)
    }

    // MARK: Hojas

    /// Una hoja como las del laboratorio: título arriba, y en cada fotograma su número arriba a la
    /// izquierda y su instante abajo, en recuadros negros. Los colores son los de la imagen que mira
    /// el modelo, no de la interfaz: por eso no salen del sistema de diseño.
    private static func drawSheet(_ sheet: ShotCheck.Sheet, generator: AVAssetImageGenerator,
                                  layout: ShotCheck.SheetLayout) async throws -> Data {
        var frames: [(image: CGImage?, time: Double)] = []
        for t in sheet.frameTimes {
            let time = CMTime(seconds: max(t, 0), preferredTimescale: 600)
            if let result = try? await generator.image(at: time) {
                frames.append((result.image, result.actualTime.seconds))
            } else {
                frames.append((nil, t))
            }
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: layout.width, height: layout.height), format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: layout.width, height: layout.height))
            UIColor(white: 0.16, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: layout.width, height: layout.header))
            draw(sheet.caption, at: CGPoint(x: 10, y: 8), size: 20, weight: .bold, background: nil)
            for (k, frame) in frames.enumerated() {
                let row = k / layout.columns, column = k % layout.columns
                let cell = CGRect(x: layout.gap + column * (layout.cellWidth + layout.gap),
                                  y: layout.header + layout.gap + row * (layout.cellHeight + layout.gap),
                                  width: layout.cellWidth, height: layout.cellHeight)
                if let cgImage = frame.image {
                    UIImage(cgImage: cgImage).draw(in: cell)
                } else {
                    UIColor.darkGray.setFill()
                    context.fill(cell)
                }
                if k < sheet.numbers.count {
                    draw("\(sheet.numbers[k])", at: CGPoint(x: cell.minX, y: cell.minY), size: 22, weight: .bold, background: .black)
                }
                let label = String(format: "%.3f s", frame.time)
                draw(label, at: CGPoint(x: cell.minX, y: cell.maxY - 22), size: 14, weight: .regular, background: .black)
            }
        }
        guard let data = image.jpegData(compressionQuality: 0.85) else { throw Failure.unreadable }
        return data
    }

    private static func draw(_ text: String, at origin: CGPoint, size: CGFloat, weight: UIFont.Weight, background: UIColor?) {
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size, weight: weight),
                                                         .foregroundColor: UIColor.white]
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()
        if let background {
            background.setFill()
            UIRectFill(CGRect(x: origin.x, y: origin.y, width: textSize.width + 10, height: textSize.height + 4))
        }
        string.draw(at: CGPoint(x: origin.x + 5, y: origin.y + 2))
    }

    // MARK: Red

    /// POST a la API Interactions de Gemini. La clave va en una cabecera, nunca en la URL ni en un registro.
    private static func post(_ body: Data, key: String) async throws -> Data {
        guard let url = URL(string: ShotCheck.endpoint) else { throw Failure.server(0) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ShotCheck.apiRevision, forHTTPHeaderField: "Api-Revision")
        request.timeoutInterval = 120
        request.httpBody = body
        // Un reintento si Google está saturado (503): suele durar poco.
        for attempt in 0..<2 {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch let error as URLError {
                throw error.code == .timedOut ? Failure.timeout : Failure.offline
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200: return data
            case 401, 403: throw Failure.badKey
            case 400 where String(decoding: data, as: UTF8.self).localizedCaseInsensitiveContains("api key"): throw Failure.badKey
            case 429: throw Failure.quota
            case 500, 503, 504:
                if attempt == 0 {
                    try await Task.sleep(for: .seconds(5))
                    continue
                }
                throw Failure.busy
            default: throw Failure.server(status)
            }
        }
        throw Failure.busy
    }
}
