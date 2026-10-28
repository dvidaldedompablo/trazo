import Foundation
import os
import SwiftData

/// Dónde guarda SwiftData la biblioteca (clips y palos).
@MainActor
enum DataStore {
    /// El contenedor de la app. En las capturas del CI va en memoria (no toca nada guardado)
    /// y con datos de demostración.
    static func makeContainer(inMemory: Bool) -> ModelContainer {
        let schema = Schema([Clip.self, Club.self, TracerResult.self])
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Si la base de datos no abre (algo raro en el disco), la app funciona en memoria
            // en vez de cerrarse. Lo que se grabe en esta sesión se perdería: se apunta en el registro.
            logger.error("No se ha podido abrir la biblioteca: \(error.localizedDescription). Uso una en memoria.")
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // Un contenedor en memoria con este esquema no puede fallar; si fallara, no hay app posible.
            return try! ModelContainer(for: schema, configurations: [configuration])
        }
    }

    /// La primera vez, crea la lista de palos de docs/01.
    static func seedClubsIfNeeded(in context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Club>())) ?? 0
        guard count == 0 else { return }
        for (index, club) in ClubDefaults.list.enumerated() {
            context.insert(Club(name: club.name, distanceMeters: club.distanceMeters, order: index))
        }
        try? context.save()
    }

    private static let logger = Logger(subsystem: "io.github.dvidaldedompablo.trazo", category: "DataStore")
}
