import SwiftUI
import UIKit
import os

// Tipografía de docs/02_DISENO.md: Archivo para títulos y cifras, SF Pro del sistema para el resto.
// @MainActor: las fuentes se crean desde las vistas, que viven en el hilo principal.
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

    /// Archivo con una anchura y un peso concretos.
    /// Una fuente variable lleva dentro todos los pesos y anchuras: se elige un punto de cada eje.
    /// Los ejes se identifican con códigos de 4 letras ('wght' es el peso, 'wdth' la anchura)
    /// guardados como un número de 32 bits.
    static func archivo(
        _ size: CGFloat,
        width: CGFloat = 74,
        weight: CGFloat = 800,
        relativeTo style: UIFont.TextStyle = .body
    ) -> Font {
        guard let base = UIFont(name: archivoPostScriptName, size: size) else {
            // No se inventa nada: se usa la del sistema y la pantalla de prueba avisa.
            logger.error("No se ha cargado la fuente Archivo; uso la del sistema")
            return .system(size: size, weight: .heavy)
        }
        let axes: [UInt32: CGFloat] = [weightAxis: weight, widthAxis: width]
        let descriptor = base.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes,
        ])
        let varied = UIFont(descriptor: descriptor, size: size)
        // UIFontMetrics agranda o encoge la fuente según el tamaño de texto que elijas en Ajustes de iOS.
        let scaled = UIFontMetrics(forTextStyle: style).scaledFont(for: varied)
        return Font(scaled as CTFont)
    }

    // Estilos de la tabla de docs/02. En la etapa 1 se añaden los demás.

    /// "Trazo" en Inicio: Archivo, anchura 70, peso 850, 38 pt.
    static let marca = archivo(38, width: 70, weight: 850, relativeTo: .largeTitle)
    /// Descripciones: SF Pro Regular 15 pt.
    static let sub = Font.system(size: 15)

    private static let weightAxis: UInt32 = 0x7767_6874 // 'wght'
    private static let widthAxis: UInt32 = 0x7764_7468 // 'wdth'
    private static let logger = Logger(subsystem: "io.github.dvidaldedompablo.trazo", category: "Typography")
}
