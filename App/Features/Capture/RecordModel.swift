import Foundation
import GolfCore
import Observation
import os
import SwiftData

/// Estado de la pantalla Grabar. La vista lo dibuja; aquí está lo que pasa al tocar los botones.
///
/// `@Observable` hace que SwiftUI vuelva a dibujar la vista cuando cambia cualquier propiedad que lea.
/// `@MainActor`: todo esto vive en el hilo principal, el de la interfaz; el trabajo pesado
/// (la cámara, el análisis del audio) se espera con `await` y se hace en otros hilos.
@MainActor
@Observable
final class RecordModel {
    enum CameraState: Equatable {
        case starting
        case running
        /// Capturas del CI: sin cámara, con el campo de la maqueta de fondo.
        case demo
        case denied
        case unavailable(String)
    }

    enum Phase: Equatable {
        case idle
        case countdown(Int)
        case recording
        /// Buscando los golpes en el audio.
        case analyzing
        case saving
    }

    let mode: CaptureMode
    private(set) var camera: CameraState
    private(set) var phase: Phase = .idle
    private(set) var configuration: CameraConfiguration?
    /// Exposición aplicada al grabar (modo diagnóstico).
    private(set) var exposure: String?
    private(set) var hasMicrophone = true
    private(set) var recordingStart: Date?
    /// Grabación analizada a la espera de que el usuario elija los golpes (abre la hoja).
    var pending: PendingRecording?
    /// Mensaje corto tras guardar o si algo falla.
    var message: String?
    /// Clips recién guardados (cada vez uno nuevo): la pantalla los manda a la cola del tracer.
    private(set) var savedBatch: SavedBatch?

    @ObservationIgnored let controller: CameraController?
    @ObservationIgnored var context: ModelContext?
    @ObservationIgnored private var work: Task<Void, Never>?

    init(mode: CaptureMode, demo: Bool) {
        self.mode = mode
        controller = demo ? nil : CameraController()
        camera = demo ? .demo : .starting
        if demo {
            configuration = CameraConfiguration(frameRate: 240, width: 1080, height: 1920, hasAudio: true, pixelFormat: "420f")
        }
    }

    var isBusy: Bool { phase != .idle }

    // MARK: Cámara

    /// Pide los permisos y arranca la cámara con los fps elegidos.
    func start(frameRate: Int) async {
        guard let controller else { return }
        guard await Permissions.requestCamera() else {
            camera = .denied
            return
        }
        // Sin micrófono se puede grabar, pero no habrá corte automático (no se oye el impacto).
        hasMicrophone = await Permissions.requestMicrophone()
        do {
            configuration = try await controller.start(preferredFrameRate: frameRate, withAudio: hasMicrophone)
            camera = .running
        } catch {
            camera = .unavailable(error.localizedDescription)
        }
    }

    func stop() {
        work?.cancel()
        if phase == .recording { controller?.stopRecording() }
        controller?.stop()
    }

    /// Cambia los fps (solo con la cámara parada de grabar).
    func changeFrameRate(_ frameRate: Int) async {
        guard let controller, phase == .idle, camera == .running else { return }
        do {
            configuration = try await controller.start(preferredFrameRate: frameRate, withAudio: hasMicrophone)
        } catch {
            camera = .unavailable(error.localizedDescription)
        }
    }

    // MARK: Grabar

    /// El botón grande: empieza (con cuenta atrás si la hay), cancela la cuenta atrás o para.
    func recordButtonTapped(countdown: Int, autoCut: Bool, fastShutter: Bool) {
        switch phase {
        case .idle:
            guard camera == .running else { return }
            if let free = MediaStore.availableCapacity, free < Self.minimumFreeSpace {
                message = "No queda espacio en el iPhone. Libera al menos 1 GB y vuelve a intentarlo."
                return
            }
            work = Task { await runCountdownAndRecord(countdown: countdown, autoCut: autoCut, fastShutter: fastShutter) }
        case .countdown:
            work?.cancel()
            phase = .idle
        case .recording:
            controller?.stopRecording()
        case .analyzing, .saving:
            break
        }
    }

    private func runCountdownAndRecord(countdown: Int, autoCut: Bool, fastShutter: Bool) async {
        guard let controller else { return }
        for remaining in stride(from: countdown, to: 0, by: -1) {
            phase = .countdown(remaining)
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
        // La obturación rápida se calcula ahora, con la luz que hay justo antes de grabar.
        exposure = mode == .tracer ? await controller.setFastShutter(fastShutter) : nil
        phase = .recording
        recordingStart = .now
        let file: URL
        do {
            file = try await controller.record(to: MediaStore.temporaryURL(extension: "mov"))
        } catch {
            phase = .idle
            recordingStart = nil
            message = "La grabación se ha cortado: \(error.localizedDescription)"
            return
        }
        _ = await controller.setFastShutter(false)
        recordingStart = nil
        await process(file, autoCut: autoCut && hasMicrophone)
    }

    /// Tras parar: con corte automático se buscan los golpes y se abre la hoja para elegirlos;
    /// sin él, el vídeo entero se guarda directamente.
    private func process(_ file: URL, autoCut: Bool) async {
        phase = .analyzing
        do {
            let analyzed = try await RecordingAnalyzer.analyze(file, mode: mode, origin: .recorded)
            if autoCut {
                pending = analyzed
                phase = .idle
            } else {
                phase = .saving
                guard let context else { return }
                let clip = try await ClipSaver.saveWhole(analyzed, in: context)
                phase = .idle
                message = "Guardado en Tus vídeos"
                savedBatch = SavedBatch(clipIDs: [clip.id])
            }
        } catch {
            phase = .idle
            message = "No se ha podido preparar el vídeo: \(error.localizedDescription)"
            Self.logger.error("Análisis: \(error.localizedDescription)")
        }
    }

    // MARK: Elegir golpes

    /// El usuario ha elegido qué guardar en la hoja. `selection` vacío y sin vídeo entero = descartar todo.
    func finishChoosing(selection: [Bool], keepFullRecording: Bool) {
        guard let pending else { return }
        self.pending = nil
        guard selection.contains(true) || keepFullRecording else {
            MediaStore.removeIfPresent(pending.sourceURL)
            message = "Grabación descartada"
            return
        }
        guard let context else { return }
        phase = .saving
        work = Task {
            do {
                let clips = try await ClipSaver.save(pending, selection: selection, keepFullRecording: keepFullRecording, in: context)
                message = clips.count == 1 ? "1 vídeo guardado en Tus vídeos" : "\(clips.count) vídeos guardados en Tus vídeos"
                savedBatch = SavedBatch(clipIDs: clips.map(\.id))
            } catch {
                message = "No se han podido guardar los clips: \(error.localizedDescription)"
            }
            phase = .idle
        }
    }

    /// Sin espacio para unos minutos a 240 fps no se empieza a grabar (docs/02: "Libera al menos 1 GB").
    private static let minimumFreeSpace: Int64 = 1_000_000_000
    private static let logger = Logger(subsystem: "io.github.dvidaldedompablo.trazo", category: "Record")
}

/// Clips guardados de una vez. Cada lote es distinto aunque tenga los mismos clips (para `onChange`).
struct SavedBatch: Equatable {
    let id = UUID()
    let clipIDs: [UUID]
}
