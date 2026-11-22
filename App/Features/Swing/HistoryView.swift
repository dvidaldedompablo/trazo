import Charts
import GolfCore
import SwiftData
import SwiftUI

/// Un análisis en el historial: fecha, nota y ritmo.
struct HistoryEntry: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let score: Int
    let tempo: Double?
}

/// Tu progreso (docs/00, etapa 9): la nota y el ritmo de cada análisis en el tiempo (Swift Charts) y la
/// lista. Solo cuentan los análisis revisados (los que tienen nota).
struct HistoryView: View {
    @Query(sort: \SwingResult.createdAt) private var results: [SwingResult]
    /// Para las capturas del CI.
    var demo: [HistoryEntry]? = nil

    private var entries: [HistoryEntry] {
        if let demo { return demo }
        return results.compactMap { result in
            guard let score = result.scoreTotal else { return nil }
            return HistoryEntry(id: result.id, date: result.createdAt, score: score, tempo: result.analysis?.phases.tempo)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Tu progreso")
                        .typeStyle(.tituloPantalla)
                        .foregroundStyle(Color.pino)
                        .accessibilityAddTraits(.isHeader)
                    Text(entries.isEmpty ? "Aún no hay análisis. Graba un swing y genera su análisis para empezar."
                                         : "La nota y el ritmo de tus análisis, del más antiguo al último.")
                        .typeStyle(.sub)
                        .foregroundStyle(Color.texto2)
                }
                if entries.count >= 1 {
                    chartCard(title: "Nota", unit: "sobre 100") {
                        Chart(entries) { entry in
                            LineMark(x: .value("Fecha", entry.date), y: .value("Nota", entry.score))
                                .foregroundStyle(Color.pino)
                            PointMark(x: .value("Fecha", entry.date), y: .value("Nota", entry.score))
                                .foregroundStyle(Color.pino)
                        }
                        .chartYScale(domain: 0...100)
                    }
                    let tempos = entries.filter { $0.tempo != nil }
                    if !tempos.isEmpty {
                        chartCard(title: "Ritmo", unit: "subida : bajada (los profesionales, 3 : 1)") {
                            Chart {
                                RuleMark(y: .value("Profesionales", 3.0))
                                    .foregroundStyle(Color.amarillo)
                                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                ForEach(tempos) { entry in
                                    LineMark(x: .value("Fecha", entry.date), y: .value("Ritmo", entry.tempo ?? 0))
                                        .foregroundStyle(Color.pino)
                                    PointMark(x: .value("Fecha", entry.date), y: .value("Ritmo", entry.tempo ?? 0))
                                        .foregroundStyle(Color.pino)
                                }
                            }
                            .chartYScale(domain: 0...5)
                        }
                    }
                    VStack(spacing: Spacing.s) {
                        ForEach(entries.reversed()) { entry in
                            HStack {
                                Text(entry.date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "es_ES"))))
                                    .typeStyle(.filaTitulo)
                                    .foregroundStyle(Color.pino)
                                Spacer()
                                if let tempo = entry.tempo {
                                    Text("\(SpanishFormat.number(tempo, decimals: 1)) : 1")
                                        .typeStyle(.filaSub)
                                        .foregroundStyle(Color.texto2)
                                }
                                Text("\(entry.score)")
                                    .typeStyle(.valor)
                                    .foregroundStyle(Color.pino)
                                    .frame(minWidth: 40, alignment: .trailing)
                            }
                            .padding(Spacing.m)
                            .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.cardMargin)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.bola)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chartCard(title: String, unit: String, @ViewBuilder chart: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title).typeStyle(.etiqueta).foregroundStyle(Color.pino)
            Text(unit).typeStyle(.nota).foregroundStyle(Color.texto3)
            chart()
                // Fechas en español ("25 oct") aunque el iPhone esté en otro idioma, y margen a los
                // lados para que la última etiqueta no se corte.
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_ES")))
                    }
                }
                .chartXScale(range: .plotDimension(startPadding: 14, endPadding: 34))
                .environment(\.locale, Locale(identifier: "es_ES"))
                .frame(height: 180)
        }
        .padding(Spacing.l)
        .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }
}
