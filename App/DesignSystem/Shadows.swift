import SwiftUI

// Sombras de docs/02: solo la tarjeta del Tracer lleva sombra; el resto es plano.

/// Sombra de la tarjeta del Tracer: `y 18, blur 34, Pino al 35 %, spread −24`, más una línea
/// de 1 pt debajo. SwiftUI no tiene "spread" (encoger la sombra antes de difuminarla), así que
/// se dibuja aparte una forma más pequeña que la tarjeta, se baja y se difumina.
private struct TracerCardShadow: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // Línea fina debajo de la tarjeta (0 1 px 0, Pino al 5 %).
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.pino.opacity(0.05))
                        .offset(y: 1)
                    // Sombra larga: la forma se encoge 24 pt por cada lado (el spread),
                    // se baja 18 pt y se difumina. El blur de CSS (34) es el doble del radio de SwiftUI.
                    RoundedRectangle(cornerRadius: max(cornerRadius - 24, 0), style: .continuous)
                        .fill(Color.pino.opacity(0.35))
                        .padding(24)
                        .offset(y: 18)
                        .blur(radius: 17)
                }
            }
    }
}

extension View {
    /// La sombra de la tarjeta del Tracer.
    func tracerCardShadow(cornerRadius: CGFloat = Radius.card) -> some View {
        modifier(TracerCardShadow(cornerRadius: cornerRadius))
    }
}
