import Foundation
import Testing
@testable import GolfCore

struct UnitsTests {
    @Test("Coma decimal, redondeo de toda la vida y signo menos")
    func numbers() {
        #expect(SpanishFormat.number(2.8, decimals: 1) == "2,8")
        #expect(SpanishFormat.number(2.85, decimals: 1) == "2,9")
        #expect(SpanishFormat.number(0.731, decimals: 2) == "0,73")
        #expect(SpanishFormat.number(3, decimals: 2) == "3,00")
        #expect(SpanishFormat.number(-3.04, decimals: 1) == "−3,0")
        #expect(SpanishFormat.number(-0.04, decimals: 1) == "0,0")
        #expect(SpanishFormat.number(149.6) == "150")
        #expect(SpanishFormat.number(.nan) == "—")
    }

    @Test("Sin separador de miles hasta 4 cifras; con espacio fino desde 5")
    func thousands() {
        #expect(SpanishFormat.number(1234) == "1234")
        #expect(SpanishFormat.number(12345) == "12\u{2009}345")
        #expect(SpanishFormat.number(1234567.25, decimals: 1) == "1\u{2009}234\u{2009}567,3")
    }

    @Test("Ritmo en pantalla y en voz")
    func ratios() {
        #expect(SpanishFormat.ratio(2.83) == "2,8 : 1")
        #expect(SpanishFormat.ratio(3) == "3,0 : 1")
        #expect(SpanishFormat.spokenRatio(2.83) == "2,8 a 1")
    }

    @Test("Medidas: \"~2 cm\", grados y segundos")
    func measures() {
        #expect(SpanishFormat.approximateCentimeters(2.4) == "~2 cm")
        #expect(SpanishFormat.approximateCentimeters(2.5) == "~3 cm")
        #expect(SpanishFormat.degrees(30.4) == "30°")
        #expect(SpanishFormat.seconds(0.731) == "0,73 s")
        #expect(SpanishFormat.score(78) == "78/100")
    }

    @Test("Distancias en m y yd (nunca medidas: las pone el usuario)")
    func distances() {
        #expect(SpanishFormat.distance(meters: 150, unit: .meters) == "150 m")
        #expect(SpanishFormat.distance(meters: 150, unit: .yards) == "164 yd")
        #expect(abs(DistanceUnit.yards.meters(fromValue: 164.04) - 150) < 0.01)
        #expect(DistanceUnit.meters.value(fromMeters: 150) == 150)
    }

    @Test("Duraciones dichas en décimas")
    func spokenTenths() {
        #expect(SpanishFormat.spokenTenths(0.73) == "siete décimas")
        #expect(SpanishFormat.spokenTenths(0.1) == "una décima")
        #expect(SpanishFormat.spokenTenths(1.0) == "un segundo")
        #expect(SpanishFormat.spokenTenths(1.24) == "un segundo y dos décimas")
        #expect(SpanishFormat.spokenTenths(2.5) == "dos segundos y cinco décimas")
        #expect(SpanishFormat.spokenTenths(0.04) == "menos de una décima")
    }
}
