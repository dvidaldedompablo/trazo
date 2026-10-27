import SwiftUI
import UIKit

/// Catálogo de componentes del sistema de diseño (solo para las capturas del CI:
/// `-UITestScreen components`). Enseña los que Inicio no usa, como el cristal y los chips sobre vídeo.
struct ComponentCatalogView: View {
    @State private var color: TracerColorChoice = .azulTee
    @State private var customColor = TracerPalette.rosa
    @State private var distanceOn = true
    @State private var distanceOff = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("Componentes")
                    .typeStyle(.tituloPantalla)
                    .foregroundStyle(Color.pino)

                section("Botones") {
                    HStack(spacing: Spacing.m) {
                        Button {} label: { Label { Text("Grabar golpe") } icon: { RecordDot() } }
                            .buttonStyle(.principal)
                        Button {} label: { Label("Elegir vídeo", systemImage: "photo.on.rectangle") }
                            .buttonStyle(.secundario)
                    }
                    Button {} label: { Label { Text("Grabar swing") } icon: { RecordDot(color: .pino, ringOpacity: 0.18) } }
                        .buttonStyle(.amarillo)
                    HStack(spacing: Spacing.m) {
                        Button {} label: { Image(systemName: "film.stack") }
                            .buttonStyle(.circleIcon)
                            .accessibilityLabel("Tus vídeos")
                        Button {} label: { Image(systemName: "gearshape") }
                            .buttonStyle(.circleIcon)
                            .accessibilityLabel("Ajustes")
                        Chip(title: "240 fps")
                        Chip(title: "Tracer", dotColor: .rojoTrazo)
                    }
                }

                section("Colores y distancia") {
                    ColorSwatchRow(selection: $color, customColor: $customColor)
                    HStack(spacing: Spacing.xxl) {
                        DistanceToggle(isOn: $distanceOn)
                        DistanceToggle(isOn: $distanceOff, title: "150 m")
                    }
                }

                section("Sobre vídeo") {
                    videoSample
                }

                section("Fila de ayuda") {
                    Button {} label: {
                        HelpRow(systemImage: "book.pages", title: "Ayuda", subtitle: "Guía de uso, paso a paso")
                    }
                    .buttonStyle(RowButtonStyle())
                }
            }
            .padding(.horizontal, Spacing.textMargin)
            .padding(.vertical, Spacing.l)
        }
        .background(Color.bola)
    }

    /// Un fotograma de demostración con controles de cristal y chips encima.
    private var videoSample: some View {
        ZStack(alignment: .top) {
            demoFrame
            VStack(spacing: Spacing.m) {
                HStack {
                    Button {} label: { Image(systemName: "xmark") }
                        .buttonStyle(.crystal)
                        .accessibilityLabel("Cerrar")
                    Spacer()
                    Chip(title: "Tracer", dotColor: .rojoTrazo, surface: .video)
                    Chip(title: "240 fps", surface: .video)
                }
                Spacer()
                HStack {
                    Button {} label: { Label("Tocar la bola", systemImage: "scope") }
                        .buttonStyle(CrystalButtonStyle(outline: .capsule))
                    Spacer()
                    Chip(title: "Corte auto", systemImage: "waveform", surface: .video)
                }
            }
            .padding(Spacing.m)
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }

    @ViewBuilder
    private var demoFrame: some View {
        if let image = UIImage(named: "escena_tracer") {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .clipped()
        } else {
            Color.escenario
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(title)
                .typeStyle(.etiqueta)
                .foregroundStyle(Color.texto2)
            content()
        }
    }
}

#Preview {
    ComponentCatalogView()
}
