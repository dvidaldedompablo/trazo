import SwiftUI
import UIKit
import os

// Tipografía de docs/02_DISENO.md: Archivo para títulos y cifras, SF Pro del sistema para el resto.

/// Un estilo de texto de la tabla de docs/02: fuente, tamaño, cómo crece con el tamaño de texto
/// de iOS y alto de línea.
struct TypeStyle {
    enum Family {
        /// Archivo con un punto de cada eje: anchura (`wdth`, 62 a 125) y peso (`wght`, 100 a 900).
        case archivo(width: CGFloat, weight: CGFloat)
        /// SF Pro, la fuente del sistema.
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
    static let displayXL = TypeStyle(family: .archivo(width: 68, weight: 820), size: 120, relativeTo: .largeTitle, lineHeight: 0.92)
    /// Nota en "Tu análisis".
    static let displayL = TypeStyle(family: .archivo(width: 68, weight: 820), size: 64, relativeTo: .largeTitle, lineHeight: 0.92)
    /// Ritmo "2,8 : 1" y distancia grande (36 a 40 pt).
    static let displayM = TypeStyle(family: .archivo(width: 70, weight: 800), size: 38, relativeTo: .title1, lineHeight: 1)
    /// "Trazo" en Inicio.
    static let marca = TypeStyle(family: .archivo(width: 70, weight: 850), size: 38, relativeTo: .largeTitle, lineHeight: 1)
    /// Títulos grandes de pantalla.
    static let tituloPantalla = TypeStyle(family: .archivo(width: 74, weight: 820), size: 34, relativeTo: .largeTitle, lineHeight: 1.05)
    /// "Tracer", "Análisis de swing".
    static let tituloTarjeta = TypeStyle(family: .archivo(width: 76, weight: 800), size: 27, relativeTo: .title1, lineHeight: 1.05)
    /// Valores de los deslizadores.
    static let valor = TypeStyle(family: .archivo(width: 72, weight: 750), size: 17)
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
}

@MainActor
enum Typography {
    /// Nombre interno (PostScript) de la fuente variable. Es el de su instancia por defecto
    /// (peso 600, anchura 100); los demás pesos y anchuras se piden con variaciones.
    static let archivoPostScriptName = "Archivo-SemiBold"

    /// `true` si iOS ha registrado la fuente. Se registra sola al arrancar
    /// porque el Info.plist la lista en `UIAppFonts`.
    static var isArchivoAvailable: Bool {
        UIFont(name: archivoPostScriptName, size: 12) != nil
    }

    /// Archivo con una anchura y un peso concretos, sin escalar.
    /// Una fuente variable lleva dentro todos los pesos y anchuras: se elige un punto de cada eje.
    /// Los ejes se identifican con códigos de 4 letras ('wght' es el peso, 'wdth' la anchura)
    /// guardados como un número de 32 bits.
    static func archivoUIFont(_ size: CGFloat, width: CGFloat, weight: CGFloat) -> UIFont {
        guard let base = UIFont(name: archivoPostScriptName, size: size) else {
            // No se inventa nada: se usa la del sistema y la pantalla avisa (ver HomeView).
            logger.error("No se ha cargado la fuente Archivo; uso la del sistema")
            return .systemFont(ofSize: size, weight: .heavy)
        }
        let axes: [UInt32: CGFloat] = [weightAxis: weight, widthAxis: width]
        let descriptor = base.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes,
        ])
        return UIFont(descriptor: descriptor, size: size)
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
        case let .archivo(width, weight):
            archivoUIFont(size, width: width, weight: weight)
        case let .system(weight):
            UIFont.systemFont(ofSize: size, weight: weight)
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

    private static let weightAxis: UInt32 = 0x7767_6874 // 'wght'
    private static let widthAxis: UInt32 = 0x7764_7468 // 'wdth'
    private static let logger = Logger(subsystem: "io.github.dvidaldedompablo.trazo", category: "Typography")
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

extension View {
    /// Aplica un estilo de la tabla de docs/02, por ejemplo `.typeStyle(.sub)`.
    func typeStyle(_ style: TypeStyle) -> some View {
        modifier(TypeStyleModifier(style: style))
    }
}
