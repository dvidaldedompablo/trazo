import SwiftUI

/// Tarjeta de instrumento (las de Tracer y Análisis en Inicio): radio de 32 pt, como las esquinas del iPhone.
/// - `.light`: Papel con la sombra larga de docs/02 (solo la lleva la tarjeta del Tracer).
/// - `.dark`: Pino, plana.
struct InstrumentCard<Content: View>: View {
    enum Style {
        case light, dark
    }

    let style: Style
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        switch style {
        case .light:
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.papel)
                .clipShape(shape)
                .tracerCardShadow()
        case .dark:
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.pino)
                .clipShape(shape)
        }
    }
}

/// Fila de ayuda (FilaAyuda en docs/02): icono en un cuadrado Niebla, título, subtítulo y flecha.
/// Se mete dentro de un botón o un enlace con `.buttonStyle(RowButtonStyle())`.
struct HelpRow: View {
    let systemImage: String
    let title: String
    let subtitle: String

    // `nonisolated`: la guía de alineación la lee desde un cierre que puede correr fuera del hilo
    // principal. Es una constante, así que no hay nada que proteger (Swift 6 avisaba de ello).
    private nonisolated static let textDrop: CGFloat = 2

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: Size.icon, weight: .medium))
                .foregroundStyle(Color.pino)
                .frame(width: Size.iconTile, height: Size.iconTile)
                .background(Color.niebla, in: RoundedRectangle(cornerRadius: Radius.iconTile, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .typeStyle(.filaTitulo)
                    .foregroundStyle(Color.pino)
                Text(subtitle)
                    .typeStyle(.filaSub)
                    .foregroundStyle(Color.texto2)
            }
            // La maqueta centra el texto con las medidas de Inter; con SF Pro queda 2 pt más alto.
            // La guía de alineación baja el bloque esos 2 pt respecto al icono.
            .alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.center] - Self.textDrop }
            Spacer(minLength: Spacing.s)
            Image(systemName: "chevron.right")
                .font(.system(size: Size.chevron, weight: .semibold))
                .foregroundStyle(Color.texto3)
                // La flecha va centrada en una caja de 18 pt, como en la maqueta.
                .frame(width: Size.chevronBox)
                .accessibilityHidden(true)
        }
        .padding(.leading, Spacing.s)
        .padding(.trailing, Size.helpRowTrailing)
        .frame(minHeight: Size.helpRowHeight)
        // VoiceOver lee la fila entera de una vez: "Ayuda, Guía de uso, paso a paso".
        .accessibilityElement(children: .combine)
    }
}

/// Chip en cápsula (docs/02): una etiqueta corta con punto o icono opcional.
/// - `.light`: Niebla con texto Pino, para pantallas claras.
/// - `.video`: sobre vídeo, Pino al 42 % con cristal y texto blanco.
struct Chip: View {
    enum Surface {
        case light, video
    }

    let title: String
    var dotColor: Color?
    var systemImage: String?
    var surface: Surface = .light

    var body: some View {
        HStack(spacing: Size.chipGap) {
            if let dotColor {
                Circle().fill(dotColor)
                    .frame(width: Size.chipDot, height: Size.chipDot)
                    .accessibilityHidden(true)
            }
            if let systemImage {
                Image(systemName: systemImage).accessibilityHidden(true)
            }
            Text(title)
                // Las cifras de los chips cambian (fps, contadores): con ancho fijo no bailan.
                .monospacedDigit()
        }
        .typeStyle(.chip)
        .lineLimit(1)
        .foregroundStyle(surface == .video ? Color.white : Color.pino)
        .padding(.horizontal, Size.chipPadding)
        .frame(minHeight: Size.chipHeight)
        .background { background }
    }

    @ViewBuilder
    private var background: some View {
        switch surface {
        case .light:
            Capsule().fill(Color.niebla)
        case .video:
            Capsule().fill(.clear)
                .glassEffect(.regular.tint(Color.pino.opacity(0.42)), in: Capsule())
        }
    }
}
