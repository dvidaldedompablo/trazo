import Foundation
import GolfCore
import Observation
import os
import SwiftData

/// Cola de tracers (docs/03, "Varios golpes a la vez"): procesa los golpes uno detrás de otro y deja su
/// estado en `TracerResult` (en proceso, listo o falló con el motivo). Un golpe que falla no para la cola.
///
/// Vive en el hilo principal y se comparte por el entorno (`.environment(queue)`): Tus vídeos y
/// "Creando tu tracer" leen de aquí el avance en directo. El análisis va en otro hilo (`TracerPipeline`).
@MainActor
@Observable
final class TracerQueue {
    /// Clip que se está procesando ahora y lo que se sabe de él.
    private(set) var activeClipID: UUID?
    private(set) var live = TracerLive()
    /// Mientras se graba no se procesa (la cámara a 240 fps necesita todo el iPhone).
    var isPaused = false {
        didSet { if !isPaused { startIfNeeded() } }
    }

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let isEnabled: Bool
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var currentJob: Task<TracerPipelineResult, Error>?
    @ObservationIgnored private var cancelled: Set<UUID> = []

    init(context: ModelContext, isEnabled: Bool = true) {
        self.context = context
        self.isEnabled = isEnabled
        guard isEnabled else { return }
        // Si la app se cerró a mitad de un golpe, vuelve a la cola.
        for result in (try? context.fetch(FetchDescriptor<TracerResult>())) ?? [] where result.status == .processing {
            result.status = .pending
        }
        try? context.save()
        startIfNeeded()
    }

    // MARK: Pedidos

    /// Pone en la cola los golpes que aún no tienen tracer (o lo vuelve a pedir si falló).
    func enqueue(_ clipIDs: [UUID]) {
        for clipID in clipIDs {
            if let existing = result(for: clipID) {
                if existing.status == .failed { existing.status = .pending }
            } else {
                context.insert(TracerResult(clipID: clipID))
            }
        }
        try? context.save()
        startIfNeeded()
    }

    /// Vuelve a crear el tracer con la bola tocada a mano.
    func retry(_ clipID: UUID, manualBall: ManualBall?) {
        let result = result(for: clipID) ?? {
            let new = TracerResult(clipID: clipID)
            context.insert(new)
            return new
        }()
        if let manualBall { result.manualBall = manualBall }
        result.status = .pending
        result.failureReason = nil
        result.needsBall = false
        try? context.save()
        startIfNeeded()
    }

    /// Quita un golpe de la cola (o cancela el que se está procesando). Su tracer desaparece.
    func cancel(_ clipID: UUID) {
        if activeClipID == clipID {
            cancelled.insert(clipID)
            currentJob?.cancel()
        }
        if let result = result(for: clipID) { context.delete(result) }
        try? context.save()
    }

    func result(for clipID: UUID) -> TracerResult? {
        try? context.fetch(FetchDescriptor<TracerResult>(predicate: #Predicate { $0.clipID == clipID })).first
    }

    /// Cuántos golpes esperan delante de este.
    func position(of clipID: UUID) -> Int? {
        let pending = ((try? context.fetch(FetchDescriptor<TracerResult>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [])
            .filter { $0.status == .pending }
        return pending.firstIndex { $0.clipID == clipID }
    }

    // MARK: Trabajo

    private func startIfNeeded() {
        guard isEnabled, !isPaused, worker == nil else { return }
        worker = Task { [weak self] in
            await self?.runLoop()
            self?.worker = nil
        }
    }

    private func runLoop() async {
        while !isPaused, let next = nextPending() {
            await process(next)
        }
    }

    private func nextPending() -> TracerResult? {
        let all = (try? context.fetch(FetchDescriptor<TracerResult>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return all.first { $0.status == .pending }
    }

    private func process(_ result: TracerResult) async {
        let clipID = result.clipID
        guard let clip = try? context.fetch(FetchDescriptor<Clip>(predicate: #Predicate { $0.id == clipID })).first else {
            context.delete(result)
            try? context.save()
            return
        }
        result.status = .processing
        try? context.save()
        activeClipID = clipID
        live = TracerLive()
        let job = TracerJob(clipID: clipID, url: clip.fileURL, origin: clip.origin, knownImpact: clip.impactTime,
                            manualBall: result.manualBall)

        // El análisis avisa de cada avance por este canal; aquí se copia al estado que ven las pantallas.
        let (stream, continuation) = AsyncStream.makeStream(of: TracerLive.self, bufferingPolicy: .bufferingNewest(1))
        let listener = Task { [weak self] in
            for await update in stream { self?.live = update }
        }
        // En su propia tarea para poder cancelarlo (la lectura de fotogramas lo comprueba).
        let jobTask = Task { try await TracerPipeline.run(job, progress: continuation) }
        currentJob = jobTask
        let outcome = await jobTask.result
        currentJob = nil
        continuation.finish()
        await listener.value

        defer {
            activeClipID = nil
            try? context.save()
        }
        // Cancelado mientras se procesaba: su ficha ya no existe.
        if cancelled.remove(clipID) != nil { return }
        switch outcome {
        case let .success(.finished(analysis)):
            result.analysis = analysis
            result.status = .ready
            result.failureReason = nil
            result.needsBall = false
        case let .success(.needsBall(_, reason)):
            result.status = .failed
            result.failureReason = reason
            result.needsBall = true
        case let .failure(error):
            result.status = .failed
            result.failureReason = error.localizedDescription
            Self.logger.error("Tracer de \(clipID): \(error.localizedDescription)")
        }
    }

    private static let logger = Logger(subsystem: "io.github.dvidaldedompablo.trazo", category: "Tracer")
}
