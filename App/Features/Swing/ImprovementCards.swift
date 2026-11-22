import GolfCore
import QuartzCore
import UIKit

/// Gráficos de la sección "A mejorar" del final del vídeo (Fase 4, 22-11-2026), con aspecto de
/// retransmisión: verde oscuro, blanco y el amarillo de acento, Lato, rótulos inferiores y fundidos
/// suaves. El vídeo se reenvía y tiene que entenderse solo, sin la app.
///
/// Disposición de un bloque de fallo (1080 x 1920):
///   0–260      banda superior: "A MEJORAR · 1 DE 3" y el nombre del fallo
///   260–1340   el clip del ejercicio a lo ancho (segunda pista de vídeo) o, si falta, su imagen
///   1340–1560  hueco oscuro: ahí caen los subtítulos (al 75 % de la altura)
///   1560–1920  rótulo inferior: "Ejercicio:", la instrucción y las repeticiones
enum ImprovementCards {
    static let clipTop: CGFloat = 260
    static let clipSide: CGFloat = 1080
    static let fade = 0.35

    private static let verde = UIColor(red: 15 / 255, green: 42 / 255, blue: 32 / 255, alpha: 1)
    private static let verdeClaro = UIColor(red: 22 / 255, green: 58 / 255, blue: 44 / 255, alpha: 1)
    private static var amarillo: UIColor { AnalysisCards.amarillo }

    /// Fondo opaco y fijo (sin fundido) de un bloque de "A mejorar": la pantalla entera en la entrada
    /// y el resumen; en un fallo, solo las bandas de arriba y de abajo, para que se vea el clip.
    /// Así, cuando los rótulos se funden al cambiar de bloque, no asoma el swing que hay debajo.
    static func backdrop(block: TimelineBlock, total: Double, aroundClip: Bool) -> CALayer {
        let root = full()
        let rects = aroundClip
            ? [CGRect(x: 0, y: 0, width: VideoLayers.width, height: clipTop),
               CGRect(x: 0, y: clipTop + clipSide, width: VideoLayers.width, height: VideoLayers.height - clipTop - clipSide)]
            : [root.bounds]
        for rect in rects {
            let band = CALayer()
            band.frame = rect
            band.backgroundColor = verde.cgColor
            root.addSublayer(band)
        }
        VideoLayers.show(root, from: block.start, to: block.end, total: total, fade: 0)
        return root
    }

    private static func full() -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: VideoLayers.width, height: VideoLayers.height)
        return layer
    }

    private static func wrapped(_ string: String, size: CGFloat, weight: CGFloat, color: UIColor,
                                width: CGFloat, lines: Int) -> CATextLayer {
        let layer = VideoLayers.text(string, font: VideoLayers.lato(size, weight: weight), color: color)
        layer.isWrapped = true
        layer.truncationMode = .end
        layer.frame.size = CGSize(width: width, height: ceil(size * 1.28) * CGFloat(lines) + 6)
        return layer
    }

    /// Entrada y resumen: tarjeta a pantalla completa con los fallos numerados.
    static func listCard(title: String, items: [ImprovementPlan.Item], block: TimelineBlock, total: Double) -> CALayer {
        let root = full()
        root.backgroundColor = verde.cgColor
        let kicker = VideoLayers.text("A MEJORAR", font: VideoLayers.lato(36, weight: 900), color: amarillo)
        kicker.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: 380)
        root.addSublayer(kicker)
        let heading = wrapped(title, size: 84, weight: 900, color: .white, width: VideoLayers.width - 2 * VideoLayers.sideMargin, lines: 2)
        heading.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: 440)
        root.addSublayer(heading)
        let rule = CALayer()
        rule.frame = CGRect(x: VideoLayers.sideMargin, y: 680, width: 160, height: 10)
        rule.backgroundColor = amarillo.cgColor
        root.addSublayer(rule)
        for (k, item) in items.enumerated() {
            let y = 760 + CGFloat(k) * 150
            let badge = CALayer()
            badge.frame = CGRect(x: VideoLayers.sideMargin, y: y, width: 96, height: 96)
            badge.cornerRadius = 48
            badge.backgroundColor = amarillo.cgColor
            let number = VideoLayers.text("\(item.number)", font: VideoLayers.lato(56, weight: 900), color: AnalysisCards.pino)
            number.frame.origin = CGPoint(x: (96 - number.bounds.width) / 2, y: (96 - number.bounds.height) / 2)
            badge.addSublayer(number)
            root.addSublayer(badge)
            let name = wrapped(item.exercise.fault, size: 50, weight: 700, color: .white,
                               width: VideoLayers.width - 2 * VideoLayers.sideMargin - 130, lines: 2)
            name.frame.origin = CGPoint(x: VideoLayers.sideMargin + 130, y: y + 14)
            root.addSublayer(name)
        }
        VideoLayers.show(root, from: block.start, to: block.end, total: total, fade: fade)
        return root
    }

    /// Un fallo: banda superior, el clip (o su imagen si falta) y el rótulo inferior del ejercicio.
    static func itemOverlay(item: ImprovementPlan.Item, count: Int, block: TimelineBlock, total: Double,
                            fallbackImage: UIImage?) -> CALayer {
        let root = full()
        // Banda superior.
        let top = CALayer()
        top.frame = CGRect(x: 0, y: 0, width: VideoLayers.width, height: clipTop)
        top.backgroundColor = verde.cgColor
        root.addSublayer(top)
        let kicker = VideoLayers.text("A MEJORAR · \(item.number) DE \(count)", font: VideoLayers.lato(34, weight: 900), color: amarillo)
        kicker.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: 72)
        root.addSublayer(kicker)
        let title = wrapped(item.exercise.fault, size: 64, weight: 900, color: .white,
                            width: VideoLayers.width - 2 * VideoLayers.sideMargin, lines: 2)
        title.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: 120)
        root.addSublayer(title)
        // Sin clip: la imagen fija en su sitio (y se dice en el registro del montaje).
        if let fallbackImage {
            let image = CALayer()
            image.frame = CGRect(x: 0, y: clipTop, width: clipSide, height: clipSide)
            image.contents = fallbackImage.cgImage
            image.contentsGravity = .resizeAspectFill
            image.masksToBounds = true
            root.addSublayer(image)
        }
        // Debajo del clip, oscuro (ahí van los subtítulos) y el rótulo inferior.
        let bottom = CALayer()
        bottom.frame = CGRect(x: 0, y: clipTop + clipSide, width: VideoLayers.width, height: VideoLayers.height - clipTop - clipSide)
        bottom.backgroundColor = verde.cgColor
        root.addSublayer(bottom)
        let lowerThird = CALayer()
        lowerThird.frame = CGRect(x: 0, y: 1540, width: VideoLayers.width, height: 380)
        lowerThird.backgroundColor = verdeClaro.cgColor
        root.addSublayer(lowerThird)
        let accent = CALayer()
        accent.frame = CGRect(x: 0, y: 1540, width: VideoLayers.width, height: 8)
        accent.backgroundColor = amarillo.cgColor
        root.addSublayer(accent)
        let label = VideoLayers.text("Ejercicio:", font: VideoLayers.lato(40, weight: 900), color: amarillo)
        label.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: 1572)
        root.addSublayer(label)
        let instruction = wrapped(item.instruction, size: 38, weight: 700, color: .white,
                                  width: VideoLayers.width - 2 * VideoLayers.sideMargin, lines: 4)
        instruction.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: 1626)
        root.addSublayer(instruction)
        let reps = VideoLayers.capsule(VideoLayers.text(item.repetitions, font: VideoLayers.lato(32, weight: 900), color: AnalysisCards.pino),
                                       background: amarillo, paddingX: 24, paddingY: 8)
        reps.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: 1838)
        root.addSublayer(reps)
        VideoLayers.show(root, from: block.start, to: block.end, total: total, fade: fade)
        return root
    }
}
