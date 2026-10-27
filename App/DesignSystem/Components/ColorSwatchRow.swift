import SwiftUI
import UIKit

/// Fila de colores del trazo (FilaColores en docs/02): cinco muestras fijas y "Otro color".
/// La muestra elegida lleva un anillo blanco y otro Pino por fuera.
struct ColorSwatchRow: View {
    @Binding var selection: TracerColorChoice
    /// El color de "Otro color".
    @Binding var customColor: Color

    @State private var isPickingCustomColor = false

    var body: some View {
        HStack(spacing: Size.swatchGap) {
            ForEach(TracerColorChoice.presets) { choice in
                swatchButton(choice) {
                    Circle().fill(choice.color(custom: customColor))
                        .overlay {
                            // La muestra blanca lleva borde para que se vea sobre la tarjeta blanca.
                            if choice == .blanco {
                                Circle().strokeBorder(Color.borde, lineWidth: 1)
                            }
                        }
                }
            }
            swatchButton(.otro) {
                RainbowSwatch(fill: selection == .otro ? customColor : nil)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Color del trazo")
        .sheet(isPresented: $isPickingCustomColor) {
            SystemColorPicker(color: $customColor) { isPickingCustomColor = false }
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
    }

    private func swatchButton(_ choice: TracerColorChoice, @ViewBuilder swatch: () -> some View) -> some View {
        let isSelected = selection == choice
        return Button {
            // El fundido del color (0,2 s) lo hace la vista previa; aquí solo se cambia la elección.
            selection = choice
            if choice == .otro { isPickingCustomColor = true }
        } label: {
            swatch()
                .frame(width: Size.swatch, height: Size.swatch)
                .overlay {
                    if isSelected { SelectionRings() }
                }
                // Zona táctil más grande que la muestra (sin llegar a pisar la de al lado).
                .contentShape(Rectangle().inset(by: -Size.swatchGap / 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.name)
        // Con el rasgo "seleccionado", VoiceOver dice "Rojo TV, seleccionado".
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Los dos anillos de la muestra elegida. Se dibujan por fuera y no ocupan sitio en la fila.
private struct SelectionRings: View {
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white, lineWidth: Size.swatchInnerRing)
                .padding(-Size.swatchInnerRing)
            Circle()
                .strokeBorder(Color.pino, lineWidth: Size.swatchOuterRing)
                .padding(-(Size.swatchInnerRing + Size.swatchOuterRing))
        }
        .allowsHitTesting(false)
    }
}

/// Muestra de "Otro color": anillo arcoíris. Si es el color elegido, el centro lleva ese color.
private struct RainbowSwatch: View {
    var fill: Color?

    var body: some View {
        ZStack {
            if let fill {
                Circle().fill(fill).padding(Size.swatchRainbowRing + 1.5)
            }
            Circle().strokeBorder(
                // AngularGradient empieza a la derecha; con -90° empieza arriba, como en la maqueta.
                AngularGradient(colors: TracerPalette.rainbow, center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                lineWidth: Size.swatchRainbowRing
            )
        }
    }
}

/// El selector de colores de iOS (`UIColorPickerViewController`) metido en una vista de SwiftUI.
/// SwiftUI tiene `ColorPicker`, pero su botón tiene un aspecto fijo; así la muestra es la de la maqueta
/// y al tocarla se abre el mismo selector del sistema.
struct SystemColorPicker: UIViewControllerRepresentable {
    @Binding var color: Color
    var onDone: () -> Void

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.title = "Otro color"
        picker.supportsAlpha = false
        picker.selectedColor = UIColor(color)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIColorPickerViewController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// UIKit avisa de los cambios a un "delegado": este objeto los pasa al Binding de SwiftUI.
    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var parent: SystemColorPicker

        init(parent: SystemColorPicker) {
            self.parent = parent
        }

        func colorPickerViewController(_ picker: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
            parent.color = Color(uiColor: color)
        }

        func colorPickerViewControllerDidFinish(_ picker: UIColorPickerViewController) {
            parent.onDone()
        }
    }
}
