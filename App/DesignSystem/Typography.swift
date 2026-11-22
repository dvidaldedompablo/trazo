import SwiftUI
import UIKit
import os

// Tipografía de docs/02_DISENO.md: Lato en toda la app (decisión del usuario, 22-11-2026; antes,
// Archivo para títulos y cifras y SF Pro para el resto). Lato tiene pesos sueltos, no ejes variables:
// Regular, Bold y Black.

/// Un estilo de texto de la tabla de docs/02: fuente, tamaño, cómo crece con el tamaño de texto
/// de iOS y alto de línea.
struct TypeStyle {
    enum Family {
        /// Títulos y cifras: Lato con un peso de 100 a 900 (800 o más, Black; 650 o más, Bold).
        case lato(weight: CGFloat)
        /// El resto del texto: Lato con el peso de UIKit más parecido.
        case system(UIFont.Weight)
    }

    let family: Family
    /// Tamaño en puntos con el tamaño de texto normal de iOS.
    let size: CGFloat
    /// Estilo de iOS al que sigue cuando cambias el tamaño del texto en Ajustes (Dynamic Type).
    var relativeTo: UIFont.TextStyle = .body
    /// Alto de línea como múltiplo del tamaño, igual que `line-height` en la maqueta.
    /// `nil` deja el natural de la fuente.
    var lineHeight: CGFloat?
}

// Estilos de la tabla de docs/02. Van en una extensión @MainActor porque las fuentes de UIKit
// se crean en el hilo principal, el mismo de las vistas.
@MainActor
extension TypeStyle {
    /// Nota en la tarjeta del vídeo (96 a 132 pt).
    static let displayXL = TypeStyle(family: .lato(weight: 820), size: 120, relativeTo: .largeTitle, lineHeight: 0.92)
    /// Nota en "Tu análisis".
    static let displayL = TypeStyle(family: .lato(weight: 820), size: 64, relativeTo: .largeTitle, lineHeight: 0.92)
    /// Ritmo "2,8 : 1" y distancia grande (36 a 40 pt).
    static let displayM = TypeStyle(family: .lato(weight: 800), size: 38, relativeTo: .title1, lineHeight: 1)
    /// "Trazo" en Inicio.
    static let marca = TypeStyle(family: .lato(weight: 850), size: 38, relativeTo: .largeTitle, lineHeight: 1)
    /// Títulos grandes de pantalla.
    static let tituloPantalla = TypeStyle(family: .lato(weight: 820), size: 34, relativeTo: .largeTitle, lineHeight: 1.05)
    /// "Tracer", "Análisis de swing".
    static let tituloTarjeta = TypeStyle(family: .lato(weight: 800), size: 27, relativeTo: .title1, lineHeight: 1.05)
    /// Valores de los deslizadores.
    static let valor = TypeStyle(family: .lato(weight: 750), size: 17)
    /// Botones.
    static let boton = TypeStyle(family: .system(.semibold), size: 16)
    /// Texto general.
    static let cuerpo = TypeStyle(family: .system(.regular), size: 17)
    /// Descripciones (14,5 a 15 pt).
    static let sub = TypeStyle(family: .system(.regular), size: 14.5, relativeTo: .subheadline, lineHeight: 1.35)
    /// Descripción sobre la tarjeta oscura de Análisis: un pelo más pequeña para que quepa junto a la figura.
    static let subCompacto = TypeStyle(family: .system(.regular), size: 14, relativeTo: .subheadline, lineHeight: 1.38)
    /// Notas al pie.
    static let nota = TypeStyle(family: .system(.regular), size: 13, relativeTo: .footnote)
    /// Chips y etiquetas (11 a 13,5 pt).
    static let chip = TypeStyle(family: .system(.semibold), size: 13, relativeTo: .footnote)
    /// Etiqueta junto a un control, como "Distancia".
    static let etiqueta = TypeStyle(family: .system(.semibold), size: 14.5, relativeTo: .subheadline)
    /// Título de una fila, como "Ayuda".
    static let filaTitulo = TypeStyle(family: .system(.semibold), size: 16)
    /// Subtítulo de una fila.
    static let filaSub = TypeStyle(family: .system(.regular), size: 13.5, relativeTo: .footnote)
    /// Consejo en cristal sobre la cámara (s02): SF de peso medio, 15 pt, alto de línea 1,4.
    static let consejo = TypeStyle(family: .system(.medium), size: 15, relativeTo: .subheadline, lineHeight: 1.4)
    /// Frase bajo un título de pantalla ("Mantén la app abierta…", s03): 15 pt, alto de línea 1,4.
    static let leadText = TypeStyle(family: .system(.regular), size: 15, relativeTo: .subheadline, lineHeight: 1.4)
    /// Nota en un recuadro (pie de s03): 14 pt, alto de línea 1,45.
    static let footNote = TypeStyle(family: .system(.regular), size: 14, relativeTo: .footnote, lineHeight: 1.45)
    /// Título de un panel o de un paso ("Sonido del golpe", "Impacto encontrado"): 15,5 pt seminegrita.
    static let panelTitle = TypeStyle(family: .system(.semibold), size: 15.5, relativeTo: .subheadline)
    /// Paso que aún no ha empezado: mismo tamaño, más fino.
    static let stepPending = TypeStyle(family: .system(.medium), size: 15.5, relativeTo: .subheadline)
}

@MainActor
enum Typography {
    /// `true` si iOS ha registrado Lato. Se registra sola al arrancar porque el Info.plist la lista
    /// en `UIAppFonts`.
    static var isLatoAvailable: Bool {
        UIFont(name: "Lato-Regular", size: 12) != nil
    }

    /// Lato al peso más cercano de los que hay (Regular, Bold, Black), sin escalar.
    /// `weight` va de 100 a 900, como en CSS.
    nonisolated static func latoUIFont(_ size: CGFloat, weight: CGFloat) -> UIFont {
        let name = weight >= 800 ? "Lato-Black" : (weight >= 650 ? "Lato-Bold" : "Lato-Regular")
        guard let font = UIFont(name: name, size: size) else {
            // No se inventa nada: se usa la del sistema y la pantalla avisa (ver HomeView).
            logger.error("No se ha cargado la fuente Lato; uso la del sistema")
            return .systemFont(ofSize: size, weight: weight >= 800 ? .heavy : (weight >= 650 ? .bold : .regular))
        }
        return font
    }

    /// Los pesos de UIKit pasados a la escala de 100 a 900 (para elegir el archivo de Lato).
    nonisolated static func cssWeight(_ weight: UIFont.Weight) -> CGFloat {
        switch weight {
        case .black, .heavy: 900
        case .bold, .semibold: 700
        default: 400
        }
    }

    /// La fuente de un estilo al tamaño de texto que tengas en Ajustes de iOS.
    /// `UIFontMetrics` sabe cuánto crece cada estilo de iOS; aquí se le pasa el tamaño de texto
    /// que llega del entorno de SwiftUI, así la fuente cambia en cuanto lo cambias.
    static func uiFont(for style: TypeStyle, dynamicTypeSize: DynamicTypeSize = .large) -> UIFont {
        let base = unscaledFont(for: style, size: style.size)
        let traits = UITraitCollection(preferredContentSizeCategory: contentSizeCategory(for: dynamicTypeSize))
        return UIFontMetrics(forTextStyle: style.relativeTo).scaledFont(for: base, compatibleWith: traits)
    }

    /// Fuente fija para dibujos que no deben crecer con el tamaño de texto (la ventana del Tracer,
    /// la figura del telestrador): son una imagen del vídeo, no texto de la interfaz.
    static func fixedFont(for style: TypeStyle, size: CGFloat? = nil) -> Font {
        Font(unscaledFont(for: style, size: size ?? style.size) as CTFont)
    }

    private static func unscaledFont(for style: TypeStyle, size: CGFloat) -> UIFont {
        switch style.family {
        case let .lato(weight):
            latoUIFont(size, weight: weight)
        case let .system(weight):
            latoUIFont(size, weight: cssWeight(weight))
        }
    }

    /// SwiftUI y UIKit llaman distinto al tamaño de texto: aquí se traduce de uno a otro.
    private static func contentSizeCategory(for size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }

    nonisolated private static let logger = Logger(subsystem: "io.github.dvidaldedompablo.trazo", category: "Typography")
}

/// Aplica un estilo de texto. Lee el tamaño de texto del entorno para que la fuente crezca
/// con Dynamic Type, y reparte el alto de línea como lo hace CSS en la maqueta: la mitad del
/// espacio extra arriba y la otra mitad abajo, y entre líneas el espacio entero.
private struct TypeStyleModifier: ViewModifier {
    let style: TypeStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let font = Typography.uiFont(for: style, dynamicTypeSize: dynamicTypeSize)
        // Diferencia entre el alto de línea pedido y el natural de la fuente (puede ser negativa).
        let extra = style.lineHeight.map { $0 * font.pointSize - font.lineHeight } ?? 0
        content
            .font(Font(font as CTFont))
            .lineSpacing(max(extra, 0))
            .padding(.vertical, extra / 2)
    }
}

extension Font {
    /// Lato a un tamaño fijo, para textos sueltos que no siguen un estilo (contadores, carteles).
    static func lato(_ size: CGFloat, weight: UIFont.Weight = .regular) -> Font {
        Font(Typography.latoUIFont(size, weight: Typography.cssWeight(weight)) as CTFont)
    }
}

extension View {
    /// Aplica un estilo de la tabla de docs/02, por ejemplo `.typeStyle(.sub)`.
    func typeStyle(_ style: TypeStyle) -> some View {
        modifier(TypeStyleModifier(style: style))
    }
}
