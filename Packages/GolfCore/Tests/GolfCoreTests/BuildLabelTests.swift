import Foundation
import Testing
@testable import GolfCore

// Tests con Swift Testing: cada función marcada con @Test es una prueba
// y #expect comprueba una condición (si falla, el CI se pone en rojo).
struct BuildLabelTests {
    @Test("La versión lleva el número de compilación entre paréntesis")
    func versionIncludesBuildNumber() {
        #expect(BuildLabel.version("0.1", build: "12") == "Versión 0.1 (12)")
    }

    @Test("La fecha sale en español y con la hora de Madrid")
    func dateInSpanishWithMadridTime() throws {
        // 9:30 UTC del 26 de octubre de 2026 son las 10:30 en Madrid (ya en horario de invierno).
        let date = try #require(BuildLabel.parseISO8601("2026-10-26T09:30:00Z"))
        let madrid = try #require(TimeZone(identifier: "Europe/Madrid"))
        #expect(BuildLabel.date(date, timeZone: madrid) == "26 de octubre de 2026, 10:30")
    }

    @Test("Los minutos llevan siempre dos cifras")
    func minutesArePadded() throws {
        let date = try #require(BuildLabel.parseISO8601("2026-03-01T09:05:00Z"))
        let utc = try #require(TimeZone(identifier: "UTC"))
        #expect(BuildLabel.date(date, timeZone: utc) == "1 de marzo de 2026, 9:05")
    }

    @Test("Sin fecha válida no se inventa ninguna")
    func invalidDateIsNil() {
        #expect(BuildLabel.parseISO8601("") == nil)
        // Lo que quedaría en el Info.plist si el ajuste no se rellenara.
        #expect(BuildLabel.parseISO8601("$(TRAZO_BUILD_DATE)") == nil)
    }
}
