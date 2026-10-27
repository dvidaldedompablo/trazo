import SwiftUI

/// La marca de Inicio: "Trazo" con el arco rojo que sale de la T (la T es el tee) y cae tras la "o".
/// Es un logotipo, así que no crece con el tamaño de texto; VoiceOver la lee como título "Trazo".
struct Wordmark: View {
    var body: some View {
        Text("Trazo")
            .typeStyle(.marca)
            .foregroundStyle(Color.pino)
            // Caja de 48 pt con el texto abajo, como en la maqueta.
            .frame(minHeight: WordmarkArc.boxHeight, alignment: .bottom)
            .overlay(alignment: .topLeading) {
                WordmarkArc()
                    .frame(width: WordmarkArc.size.width, height: WordmarkArc.size.height)
                    .offset(WordmarkArc.offset)
            }
            .dynamicTypeSize(.large)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Trazo")
            .accessibilityAddTraits(.isHeader)
    }
}

/// El arco de la marca: una curva roja con la bola al final, en las coordenadas del SVG de la maqueta.
private struct WordmarkArc: View {
    static let boxHeight: CGFloat = 48
    static let size = CGSize(width: 130, height: 44)
    /// El dibujo empieza un poco a la izquierda y por encima de la caja del texto.
    static let offset = CGSize(width: -2, height: -14)
    static let lineWidth: CGFloat = 2.4
    static let ball = CGPoint(x: 116, y: 30)
    static let ballRadius: CGFloat = 3.2

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: 22, y: 26))
                path.addCurve(to: Self.ball, control1: CGPoint(x: 38, y: 2), control2: CGPoint(x: 90, y: -4))
            }
            .stroke(Color.rojoTrazo, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
            Circle()
                .fill(Color.rojoTrazo)
                .frame(width: Self.ballRadius * 2, height: Self.ballRadius * 2)
                .position(Self.ball)
        }
    }
}
