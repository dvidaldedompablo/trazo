import SwiftUI

// Botones de docs/02. Se usan como estilos de SwiftUI: `Button { } label: { }.buttonStyle(.principal)`.
// Un ButtonStyle solo cambia el aspecto: el botón sigue siendo un botón para VoiceOver y para el sistema.

/// Botón en cápsula de 50 pt: principal (Pino), secundario (Niebla) o amarillo.
/// Crece de alto si el texto es más grande (Dynamic Type).
struct PillButtonStyle: ButtonStyle {
    enum Kind {
        case principal, secundario, amarillo
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(PillLabelStyle())
            .typeStyle(.boton)
            .lineLimit(1)
            .foregroundStyle(foreground)
            // Margen mínimo a los lados; el contenido va centrado en lo que mida el botón.
            .padding(.horizontal, Spacing.m)
            .frame(maxWidth: .infinity, minHeight: Size.buttonHeight)
            .background(background, in: Capsule())
            .contentShape(Capsule())
            // Al pulsar, el botón se aclara un poco: respuesta inmediata sin moverse de sitio.
            .opacity(configuration.isPressed ? 0.72 : 1)
    }

    private var foreground: Color {
        kind == .principal ? .white : .pino
    }

    private var background: Color {
        switch kind {
        case .principal: .pino
        case .secundario: .niebla
        case .amarillo: .amarillo
        }
    }
}

/// Icono a la izquierda y texto, con la separación de la maqueta.
struct PillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Size.buttonIconGap) {
            configuration.icon
                .font(.system(size: Size.iconSmall, weight: .semibold))
            configuration.title
                // Si no cabe (letra muy grande), el texto encoge un poco antes que cortarse.
                .minimumScaleFactor(0.75)
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    /// Cápsula Pino con texto blanco ("Grabar golpe").
    static var principal: PillButtonStyle { PillButtonStyle(kind: .principal) }
    /// Cápsula Niebla con texto Pino ("Elegir vídeo").
    static var secundario: PillButtonStyle { PillButtonStyle(kind: .secundario) }
    /// Cápsula amarilla con texto Pino ("Grabar swing").
    static var amarillo: PillButtonStyle { PillButtonStyle(kind: .amarillo) }
}

/// Punto de grabar: círculo de 12 pt con un anillo suave del mismo color alrededor.
struct RecordDot: View {
    var color: Color = .rojoTrazo
    /// Opacidad del anillo: 0,28 sobre fondo oscuro (rojo sobre Pino) y 0,18 en el punto Pino.
    var ringOpacity: Double = 0.28

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: Size.recordDot, height: Size.recordDot)
            .background {
                // El anillo no ocupa sitio: se dibuja por fuera del punto, como el box-shadow de la maqueta.
                Circle()
                    .fill(color.opacity(ringOpacity))
                    .padding(-Size.recordDotRing)
            }
            .accessibilityHidden(true)
    }
}

/// Botón redondo con icono sobre fondo claro (cabecera de Inicio): círculo Niebla de 42 pt.
struct CircleIconButtonStyle: ButtonStyle {
    var diameter: CGFloat = Size.headerButton

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: Size.icon, weight: .medium))
            .foregroundStyle(Color.pino)
            .frame(width: diameter, height: diameter)
            .background(Color.niebla, in: Circle())
            // La zona táctil llega a 44 pt aunque el círculo mida 42.
            .contentShape(Circle().inset(by: (diameter - Size.minTouch) / 2))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

extension ButtonStyle where Self == CircleIconButtonStyle {
    static var circleIcon: CircleIconButtonStyle { CircleIconButtonStyle() }
}

/// Botón de cristal: círculo de 44 pt o cápsula.
/// - `.video`: Liquid Glass de iOS 26, solo para controles sobre vídeo (docs/02).
/// - `.darkCard`: el "cristal oscuro" de la tarjeta de Análisis. No hay vídeo detrás, así que
///   es un blanco translúcido plano con un borde fino, como en la maqueta.
struct CrystalButtonStyle: ButtonStyle {
    enum Surface {
        case video, darkCard
    }

    enum Outline {
        case circle(diameter: CGFloat)
        case capsule
    }

    var surface: Surface = .video
    var outline: Outline = .circle(diameter: Size.glassButton)

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .labelStyle(PillLabelStyle())
            .typeStyle(.boton)
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.72 : 1)

        switch outline {
        case let .circle(diameter):
            styled(label.frame(width: diameter, height: diameter), in: Circle())
        case .capsule:
            styled(label.padding(.horizontal, Spacing.l).frame(minHeight: Size.glassButton), in: Capsule())
        }
    }

    @ViewBuilder
    private func styled(_ content: some View, in shape: some InsettableShape) -> some View {
        switch surface {
        case .video:
            content
                .contentShape(shape)
                // .interactive(): el cristal reacciona al dedo (se ilumina y se estira un poco).
                .glassEffect(.regular.interactive(), in: shape)
        case .darkCard:
            content
                .background(Color.white.opacity(0.12), in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                .contentShape(shape)
        }
    }
}

extension ButtonStyle where Self == CrystalButtonStyle {
    /// Círculo de cristal de 44 pt sobre vídeo.
    static var crystal: CrystalButtonStyle { CrystalButtonStyle() }
}

/// Estilo para filas que se pueden tocar (como la de Ayuda): al pulsar se ve un fondo Niebla.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.niebla.opacity(configuration.isPressed ? 0.7 : 0),
                in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
    }
}
