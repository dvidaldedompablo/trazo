import SwiftUI

/// Interruptor de distancia (docs/02): la etiqueta ("Distancia" o el valor, "150 m") y un interruptor Pino.
struct DistanceToggle: View {
    @Binding var isOn: Bool
    var title: String = "Distancia"

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
        }
        .toggleStyle(TrazoSwitchStyle())
    }
}

/// Interruptor con las medidas de la maqueta (48 x 29 pt). El de iOS 26 es más ancho y no cabe
/// junto a las seis muestras de color. Sigue siendo un `Toggle`: VoiceOver lo lee como interruptor.
struct TrazoSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Size.switchLabelGap) {
            configuration.label
                .typeStyle(.etiqueta)
                .foregroundStyle(Color.pino)
                .lineLimit(1)
                // Si la fila se queda corta, la etiqueta encoge un poco en vez de empujar la tarjeta.
                .minimumScaleFactor(0.7)
            Capsule()
                .fill(configuration.isOn ? Color.pino : Color.borde)
                .frame(width: Size.switchWidth, height: Size.switchHeight)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: Size.switchKnob, height: Size.switchKnob)
                        .shadow(color: Color.escenario.opacity(0.2), radius: 2.5, y: 2)
                        .padding((Size.switchHeight - Size.switchKnob) / 2)
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Muelle corto (0,25 s): el pomo se desliza y lo que dependa del interruptor
            // (la etiqueta de la vista previa) aparece o desaparece con la misma animación.
            withAnimation(.spring(duration: 0.25)) {
                configuration.isOn.toggle()
            }
        }
        // Para VoiceOver y Control por voz se describe como el interruptor normal de iOS.
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}
