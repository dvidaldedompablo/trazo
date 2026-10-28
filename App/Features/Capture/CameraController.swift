@preconcurrency import AVFoundation
import Foundation
import os

/// Lo que la cámara ha conseguido configurar (los chips y el modo diagnóstico lo enseñan).
struct CameraConfiguration: Sendable, Equatable {
    /// fps de verdad: 240 si el iPhone puede; si no, 120 o 60.
    var frameRate: Int
    var width: Int
    var height: Int
    var hasAudio: Bool
    /// Formato de píxel del sensor en cuatro letras ("420f"…), para el modo diagnóstico.
    var pixelFormat: String
}

enum CameraError: LocalizedError {
    case noCamera
    case cannotUseCamera(String)

    var errorDescription: String? {
        switch self {
        case .noCamera: "Este dispositivo no tiene cámara trasera."
        case let .cannotUseCamera(detail): "No se ha podido preparar la cámara (\(detail))."
        }
    }
}

/// La cámara: sesión de captura, formato de 240 fps, grabación a archivo y obturación rápida.
///
/// `AVCaptureSession` no se puede tocar desde varios hilos a la vez. Por eso todo lo que la cambia
/// pasa por una cola propia (`queue`), una cosa detrás de otra, y la interfaz espera con `await`.
/// La clase se declara `@unchecked Sendable`: le decimos a Swift que la protección la ponemos
/// nosotros (la cola y el candado), porque AVFoundation no está pensado para la comprobación de Swift 6.
final class CameraController: NSObject, @unchecked Sendable, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "io.github.dvidaldedompablo.trazo.camera")
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var frameRate = 0

    /// Candado para lo que tocan a la vez la cola de la cámara y los avisos de AVFoundation.
    private let lock = NSLock()
    private var finishContinuation: CheckedContinuation<URL, Error>?
    private var stopRequested = false

    // MARK: Preparar

    /// Configura la sesión con los fps pedidos (o los más altos posibles por debajo) y la arranca.
    func start(preferredFrameRate: Int, withAudio: Bool) async throws -> CameraConfiguration {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let configuration = try self.configure(preferredFrameRate: preferredFrameRate, withAudio: withAudio)
                    if !self.session.isRunning { self.session.startRunning() }
                    // Algunos formatos vuelven a sus fps por defecto al arrancar la sesión: se repiten.
                    self.applyFrameDuration()
                    continuation.resume(returning: configuration)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configure(preferredFrameRate: Int, withAudio: Bool) throws -> CameraConfiguration {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.noCamera
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // "inputPriority": manda el formato que elegimos en la cámara, no un preajuste de la sesión.
        session.sessionPreset = .inputPriority

        if videoInput == nil {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CameraError.cannotUseCamera("entrada de vídeo") }
            session.addInput(input)
            videoInput = input
        }
        if withAudio, audioInput == nil, let microphone = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: microphone), session.canAddInput(input) {
            session.addInput(input)
            audioInput = input
        }
        if !session.outputs.contains(movieOutput) {
            guard session.canAddOutput(movieOutput) else { throw CameraError.cannotUseCamera("salida de vídeo") }
            session.addOutput(movieOutput)
        }

        // 1080p a 240 fps; si el iPhone no llega, 120 y luego 60 (docs/01).
        let candidates = [preferredFrameRate, 240, 120, 60, 30].filter { $0 <= preferredFrameRate }
        guard let chosen = candidates.lazy.compactMap({ fps in Self.bestFormat(of: device, frameRate: fps).map { ($0, fps) } }).first
        else { throw CameraError.cannotUseCamera("sin formato de 1080p") }
        let (format, fps) = chosen

        try device.lockForConfiguration()
        device.activeFormat = format
        frameRate = fps
        let duration = CMTime(value: 1, timescale: CMTimeScale(fps))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.unlockForConfiguration()

        if let connection = movieOutput.connection(with: .video) {
            // Sin estabilización: va en trípode, y la estabilización recorta la imagen y la retrasa.
            if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
            // Vídeo vertical: el sensor graba en horizontal y se gira 90°.
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return CameraConfiguration(frameRate: fps, width: Int(dimensions.height), height: Int(dimensions.width),
                                   hasAudio: audioInput != nil,
                                   pixelFormat: VideoInspector.fourCharacterCode(CMFormatDescriptionGetMediaSubType(format.formatDescription)))
    }

    /// El mejor formato de 1920 x 1080 que llega a esos fps: de 8 bits y rango completo si lo hay.
    private static func bestFormat(of device: AVCaptureDevice, frameRate: Int) -> AVCaptureDevice.Format? {
        let matching = device.formats.filter { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dimensions.width == 1920 && dimensions.height == 1080
                && format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= Double(frameRate) - 0.01 }
        }
        let fullRange = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        return matching.first { CMFormatDescriptionGetMediaSubType($0.formatDescription) == fullRange } ?? matching.first
    }

    private func applyFrameDuration() {
        guard let device = videoInput?.device, frameRate > 0, (try? device.lockForConfiguration()) != nil else { return }
        let duration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        device.unlockForConfiguration()
    }

    // MARK: Exposición

    /// Obturación rápida (docs/01): exposición fija de 1/2000 s con el ISO que haga falta para que
    /// la imagen salga igual de clara que con la exposición automática. Si no hay luz suficiente
    /// (el ISO llega a su máximo), se alarga lo justo. Así la bola sale menos movida.
    /// Devuelve una descripción para el modo diagnóstico ("1/2000 s, ISO 320").
    func setFastShutter(_ enabled: Bool) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.applyExposure(fastShutter: enabled))
            }
        }
    }

    private func applyExposure(fastShutter: Bool) -> String? {
        guard let device = videoInput?.device, (try? device.lockForConfiguration()) != nil else { return nil }
        defer { device.unlockForConfiguration() }
        guard fastShutter, device.isExposureModeSupported(.custom) else {
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            return nil
        }
        let format = device.activeFormat
        let current = device.exposureDuration.seconds
        let target = 1.0 / 2000
        guard current.isFinite, current > 0 else { return nil }
        // Misma luz: ISO × tiempo constante.
        var iso = device.iso * Float(current / target)
        var seconds = target
        if iso > format.maxISO {
            seconds = target * Double(iso / format.maxISO)
            iso = format.maxISO
        }
        iso = min(max(iso, format.minISO), format.maxISO)
        let longest = min(format.maxExposureDuration.seconds, 1.0 / Double(max(frameRate, 1)))
        seconds = min(max(seconds, format.minExposureDuration.seconds), longest)
        device.setExposureModeCustom(duration: CMTime(seconds: seconds, preferredTimescale: 1_000_000), iso: iso,
                                     completionHandler: nil)
        return "1/\(Int((1 / seconds).rounded())) s, ISO \(Int(iso.rounded()))"
    }

    // MARK: Grabar

    /// Graba en `url` y vuelve cuando la grabación termina (al llamar a `stopRecording`, o sola si falla
    /// o se llena el disco). Devuelve el archivo grabado.
    func record(to url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                finishContinuation = continuation
                stopRequested = false
            }
            queue.async {
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
            }
        }
    }

    func stopRecording() {
        lock.withLock { stopRequested = true }
        queue.async {
            if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        // Si se pidió parar antes de que la grabación llegara a empezar, se para ahora.
        if lock.withLock({ stopRequested }) {
            queue.async { self.movieOutput.stopRecording() }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        // Ojo: AVFoundation puede dar un "error" aunque el archivo esté bien (por ejemplo, si se paró
        // por falta de espacio). Lo dice la clave AVErrorRecordingSuccessfullyFinishedKey.
        let finishedOK = error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true
        let continuation = lock.withLock { () -> CheckedContinuation<URL, Error>? in
            defer { finishContinuation = nil }
            return finishContinuation
        }
        if finishedOK {
            continuation?.resume(returning: outputFileURL)
        } else {
            Self.logger.error("La grabación ha fallado: \(error?.localizedDescription ?? "?")")
            continuation?.resume(throwing: error ?? CameraError.cannotUseCamera("grabación"))
        }
    }

    private static let logger = Logger(subsystem: "io.github.dvidaldedompablo.trazo", category: "Camera")
}
