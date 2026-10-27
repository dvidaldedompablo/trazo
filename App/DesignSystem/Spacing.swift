import CoreGraphics

// Rejilla de 4 pt de docs/02_DISENO.md.
enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32

    /// Margen lateral de las tarjetas.
    static let cardMargin: CGFloat = 16
    /// Margen lateral del texto suelto.
    static let textMargin: CGFloat = 20
}

/// Radios por jerarquía (docs/02). Los botones y chips no tienen radio: son cápsulas.
enum Radius {
    /// Tarjetas grandes: eco de las esquinas del iPhone.
    static let card: CGFloat = 32
    /// Hojas inferiores.
    static let sheet: CGFloat = 28
    /// Paneles.
    static let panel: CGFloat = 22
    /// Filas.
    static let row: CGFloat = 20
    /// Miniaturas pequeñas y grandes.
    static let thumbnailSmall: CGFloat = 10
    static let thumbnail: CGFloat = 16
    /// Cuadrado del icono en la fila de ayuda.
    static let iconTile: CGFloat = 13
}

/// Tamaños fijos de los componentes (docs/02 y la maqueta).
enum Size {
    /// Alto de los botones en cápsula.
    static let buttonHeight: CGFloat = 50
    /// Botones redondos de la cabecera de Inicio.
    static let headerButton: CGFloat = 42
    /// Botón de cristal sobre vídeo.
    static let glassButton: CGFloat = 44
    /// Cuadrado del icono en la fila de ayuda.
    static let iconTile: CGFloat = 42
    /// Muestras de color.
    static let swatch: CGFloat = 26
    /// Separación entre muestras.
    static let swatchGap: CGFloat = 8
    /// Punto de grabar dentro de los botones y el anillo suave que lo rodea.
    static let recordDot: CGFloat = 12
    static let recordDotRing: CGFloat = 3
    /// Separación entre el icono y el texto de un botón.
    static let buttonIconGap: CGFloat = 9
    /// Interruptor de distancia: pista y pomo (más estrecho que el de iOS 26 para que quepa en la fila).
    static let switchWidth: CGFloat = 48
    static let switchHeight: CGFloat = 29
    static let switchKnob: CGFloat = 25
    /// Separación entre la etiqueta y el interruptor.
    static let switchLabelGap: CGFloat = 9
    /// Anillos de la muestra elegida: blanco por dentro y Pino por fuera.
    static let swatchInnerRing: CGFloat = 2.5
    static let swatchOuterRing: CGFloat = 2
    /// Grosor del anillo arcoíris de "Otro color".
    static let swatchRainbowRing: CGFloat = 2.9
    /// Chips: alto y separación entre punto e icono y texto.
    static let chipHeight: CGFloat = 32
    static let chipDot: CGFloat = 8
    static let chipGap: CGFloat = 7
    static let chipPadding: CGFloat = 13
    /// Margen derecho de la fila de ayuda (hasta la flecha).
    static let helpRowTrailing: CGFloat = 14
    /// Zona táctil mínima.
    static let minTouch: CGFloat = 44
    /// Alto de la ventana de la vista previa del Tracer.
    static let tracerWindowHeight: CGFloat = 180
    /// Alto de la tarjeta de Análisis.
    static let swingCardHeight: CGFloat = 206
    /// Alto de la fila de ayuda.
    static let helpRowHeight: CGFloat = 60
    /// Iconos: en botones redondos y filas, y en los botones en cápsula.
    static let icon: CGFloat = 17
    static let iconSmall: CGFloat = 15
    /// Flecha de las filas ("ir") y la caja donde va centrada.
    static let chevron: CGFloat = 13
    static let chevronBox: CGFloat = 18
}
