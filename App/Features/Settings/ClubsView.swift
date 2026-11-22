import SwiftData
import SwiftUI

/// Mis palos (docs/02 y docs/03): la distancia de vuelo de cada palo, que el Tracer usa cuando eliges
/// el palo. Nunca se mide: la escribe el usuario, en metros o yardas según Ajustes.
struct ClubsView: View {
    @Query(sort: \Club.order) private var clubs: [Club]
    @AppStorage(SettingsKey.units) private var units = "m"
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            Section {
                ForEach(clubs) { club in
                    ClubRow(club: club, units: units)
                }
            } footer: {
                Text("Escribe la distancia de vuelo que sueles hacer con cada palo. La app no la mide: el número es tuyo.")
            }
        }
        .navigationTitle("Mis palos")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? context.save() }
    }
}

private struct ClubRow: View {
    @Bindable var club: Club
    let units: String
    @State private var text = ""

    /// Una yarda son 0,9144 m: la distancia se guarda en metros y se enseña en lo que pida Ajustes.
    private var factor: Double { units == "yd" ? 1 / 0.9144 : 1 }

    var body: some View {
        HStack {
            Text(club.name).typeStyle(.filaTitulo).foregroundStyle(Color.pino)
            Spacer()
            TextField("—", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .typeStyle(.valor)
                .foregroundStyle(Color.pino)
                .frame(width: 80)
                .onChange(of: text) { _, value in
                    let number = Double(value.filter(\.isNumber))
                    club.distanceMeters = number.map { $0 / factor }
                }
            Text(units).typeStyle(.filaSub).foregroundStyle(Color.texto3)
        }
        .onAppear {
            text = club.distanceMeters.map { String(Int(($0 * factor).rounded())) } ?? ""
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(club.name), \(text.isEmpty ? "sin distancia" : "\(text) \(units == "yd" ? "yardas" : "metros")")")
    }
}
