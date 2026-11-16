import AVFoundation
import GolfCore
import QuartzCore
import UIKit

/// Capas de Core Animation del vídeo del análisis (docs/02, "Gráficos de los vídeos").
/// Todo se mide en píxeles del vídeo (1080 x 1920) con el origen arriba a la izquierda:
/// la capa raíz del montaje lleva `isGeometryFlipped = true`.
///
/// Las animaciones usan `beginTime` sobre `AVCoreAnimationBeginTimeAtZero`: en un montaje de
/// AVFoundation el tiempo 0 "normal" significa "ahora", no el principio del vídeo.
enum VideoLayers {
    static let width: CGFloat = 1080
    static let height: CGFloat = 1920
    /// Márgenes de seguridad (docs/02): 90 px a los lados, 160 arriba, 220 abajo.
    static let sideMargin: CGFloat = 90

    // MARK: Piezas básicas

    /// Texto como capa, con la fuente ya resuelta (Archivo o SF) y tamaño en píxeles de vídeo.
    static func text(_ string: String, font: UIFont, color: UIColor,
                     alignment: NSTextAlignment = .left, outline: Bool = false) -> CATextLayer {
        let layer = CATextLayer()
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if outline {
            // Contorno oscuro para leerse sobre cualquier fondo (docs/02, subtítulos).
            attributes[.strokeColor] = UIColor.black.withAlphaComponent(0.55)
            attributes[.strokeWidth] = -9.0
        }
        let attributed = NSAttributedString(string: string, attributes: attributes)
        layer.string = attributed
        layer.contentsScale = 1
        layer.alignmentMode = alignment == .center ? .center : .left
        let size = attributed.size()
        layer.frame = CGRect(x: 0, y: 0, width: ceil(size.width) + 4, height: ceil(size.height) + 4)
        return layer
    }

    static func archivo(_ size: CGFloat, width: CGFloat = 70, weight: CGFloat = 800) -> UIFont {
        Typography.archivoUIFont(size, width: width, weight: weight)
    }

    /// Enseña la capa solo entre `from` y `to` (s del vídeo), con un fundido corto (docs/04: 0,2 s).
    static func show(_ layer: CALayer, from: Double, to: Double, total: Double, fade: Double = 0.2) {
        layer.opacity = 0
        guard total > 0 else { return }
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        let t = { (x: Double) in NSNumber(value: min(max(x / total, 0), 1)) }
        animation.keyTimes = [0, t(from), t(from + fade), t(to - fade), t(to), 1]
        animation.values = [0, 0, 1, 1, 0, 0]
        animation.duration = total
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        layer.add(animation, forKey: "visible")
    }

    /// Cápsula con fondo.
    static func capsule(_ content: CATextLayer, background: UIColor, paddingX: CGFloat = 22,
                        paddingY: CGFloat = 10) -> CALayer {
        let layer = CALayer()
        let size = CGSize(width: content.bounds.width + 2 * paddingX, height: content.bounds.height + 2 * paddingY)
        layer.frame = CGRect(origin: .zero, size: size)
        layer.backgroundColor = background.cgColor
        layer.cornerRadius = size.height / 2
        content.frame.origin = CGPoint(x: paddingX, y: paddingY)
        layer.addSublayer(content)
        return layer
    }

    static func shape(_ path: UIBezierPath, stroke: UIColor?, width: CGFloat, fill: UIColor? = nil,
                      dash: [NSNumber]? = nil) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path.cgPath
        layer.strokeColor = stroke?.cgColor
        layer.lineWidth = width
        layer.fillColor = fill?.cgColor
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.lineDashPattern = dash
        return layer
    }

    // MARK: Telestrador de una posición (las mismas medidas que `SwingOverlayView`, a tamaño de vídeo)

    static func telestrator(analysis: SwingAnalysis, position: SwingPosition) -> CALayer {
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let pose = analysis.poses[analysis.phases[position].frameIndex]
        let handedness = analysis.handedness
        func point(_ p: Point2D) -> CGPoint { CGPoint(x: p.x, y: p.y) }

        func stroke(_ points: [Point2D], color: UIColor, lineWidth: CGFloat, dash: [NSNumber]? = nil) {
            guard points.count >= 2 else { return }
            let path = UIBezierPath()
            path.move(to: point(points[0]))
            for p in points.dropFirst() { path.addLine(to: point(p)) }
            if dash == nil {
                root.addSublayer(shape(path, stroke: UIColor.black.withAlphaComponent(0.28), width: lineWidth + 8))
            }
            root.addSublayer(shape(path, stroke: color, width: lineWidth, dash: dash))
        }

        // Verticales de referencia de la preparación (cadera y cabeza).
        let addressPose = analysis.poses[analysis.phases[.address].frameIndex]
        if let hip = addressPose.first(handedness.trailHip, handedness.leadHip) ?? addressPose.joints[.root] {
            stroke([Point2D(hip.x, Double(height) * 0.25), Point2D(hip.x, Double(height) * 0.98)],
                   color: UIColor.white.withAlphaComponent(0.85), lineWidth: 5, dash: [5, 14])
        }
        if let head = addressPose.head {
            stroke([Point2D(head.x, max(head.y - 400, 0)), Point2D(head.x, Double(height) * 0.95)],
                   color: UIColor.white.withAlphaComponent(0.85), lineWidth: 5, dash: [5, 14])
        }

        // Esqueleto del lado de atrás con articulaciones.
        let yellow = UIColor(red: 1, green: 208 / 255, blue: 46 / 255, alpha: 1)
        if let neck = pose.joints[.neck], let rootJoint = pose.joints[.root] {
            var chain = [neck, rootJoint]
            if let knee = pose.first(handedness.trailKnee, handedness.leadKnee) {
                chain.append(knee)
                if let ankle = pose.first(handedness.trailAnkle, handedness.leadAnkle) { chain.append(ankle) }
            }
            if let head = pose.head { chain.insert(head, at: 0) }
            stroke(chain, color: yellow, lineWidth: 9)
            for p in chain.dropFirst() {
                let joint = CAShapeLayer()
                joint.path = UIBezierPath(ovalIn: CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24)).cgPath
                joint.fillColor = yellow.cgColor
                let center = CAShapeLayer()
                center.path = UIBezierPath(ovalIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)).cgPath
                center.fillColor = UIColor.white.cgColor
                root.addSublayer(joint)
                root.addSublayer(center)
            }
            // Arco y valor de la inclinación en la preparación y el impacto.
            if position == .address || position == .impact,
               let angle = Geometry.angleFromVertical(from: rootJoint, to: neck) {
                let center = point(rootJoint)
                let spineAngle = atan2(neck.y - rootJoint.y, neck.x - rootJoint.x)
                let arc = UIBezierPath(arcCenter: center, radius: 120, startAngle: -.pi / 2,
                                       endAngle: spineAngle, clockwise: spineAngle > -.pi / 2)
                root.addSublayer(shape(arc, stroke: yellow, width: 7))
                let label = text("\(SpanishFormat.number(angle))°", font: archivo(60), color: yellow, outline: true)
                label.frame.origin = CGPoint(x: center.x - 120 - label.bounds.width - 20, y: center.y - 160)
                root.addSublayer(label)
            }
        }

        // Círculo de la cabeza.
        if let head = pose.head {
            let circle = UIBezierPath(ovalIn: CGRect(x: head.x - 85, y: head.y - 85, width: 170, height: 170))
            root.addSublayer(shape(circle, stroke: yellow, width: 6, dash: [10, 10]))
        }

        // El palo según la posición.
        switch position {
        case .address:
            if let head = analysis.clubHeadAtAddress, let hands = pose.hands {
                stroke([hands, head], color: UIColor.white.withAlphaComponent(0.9), lineWidth: 6)
            }
        case .takeaway:
            if let head = analysis.clubHeadAtTakeaway {
                let ring = UIBezierPath(ovalIn: CGRect(x: head.x - 16, y: head.y - 16, width: 32, height: 32))
                root.addSublayer(shape(ring, stroke: .white, width: 4))
            }
        case .midBackswing, .transition:
            let line = position == .midBackswing ? analysis.clubLineAtMidBackswing : analysis.clubLineAtTransition
            if let line {
                stroke([line.grip, line.head], color: UIColor.white.withAlphaComponent(0.9), lineWidth: 6)
            }
        default:
            break
        }
        return root
    }

    // MARK: Etiquetas, chips y contador

    /// Columna de etiquetas de medidas a la derecha, en el cielo (docs/02). Aparecen escalonadas
    /// cada 0,15 s desde que empieza el bloque.
    static func measureLabels(_ items: [(name: String, value: String)], blockStart: Double,
                              blockEnd: Double, total: Double) -> CALayer {
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: width, height: height)
        var y: CGFloat = 170
        for (index, item) in items.prefix(3).enumerated() {
            let card = CALayer()
            let name = text(item.name, font: UIFont.systemFont(ofSize: 28, weight: .semibold), color: .white)
            let value = text(item.value, font: archivo(62),
                             color: UIColor(red: 1, green: 208 / 255, blue: 46 / 255, alpha: 1))
            let cardWidth = max(name.bounds.width, value.bounds.width) + 48
            card.frame = CGRect(x: width - sideMargin - cardWidth, y: y,
                                width: cardWidth, height: name.bounds.height + value.bounds.height + 36)
            card.backgroundColor = UIColor(red: 16 / 255, green: 36 / 255, blue: 29 / 255, alpha: 0.84).cgColor
            card.cornerRadius = 32
            name.frame.origin = CGPoint(x: 24, y: 14)
            value.frame.origin = CGPoint(x: 24, y: 14 + name.bounds.height + 4)
            card.addSublayer(name)
            card.addSublayer(value)
            show(card, from: blockStart + 0.15 * Double(index + 1), to: blockEnd, total: total)
            root.addSublayer(card)
            y += card.bounds.height + 18
        }
        return root
    }

    /// Chip de fase "n/7" + nombre, arriba a la izquierda.
    static func phaseChip(_ n: Int, title: String) -> CALayer {
        let root = CALayer()
        let number = text("\(n)/7", font: archivo(36), color: UIColor(red: 16 / 255, green: 36 / 255, blue: 29 / 255, alpha: 1))
        let badge = capsule(number, background: UIColor(red: 1, green: 208 / 255, blue: 46 / 255, alpha: 1), paddingX: 18, paddingY: 8)
        badge.frame.origin = CGPoint(x: sideMargin, y: 64)
        let name = text(title, font: archivo(68), color: .white, outline: true)
        name.frame.origin = CGPoint(x: badge.frame.maxX + 22, y: 52)
        root.addSublayer(badge)
        root.addSublayer(name)
        return root
    }

    /// Estado arriba a la derecha ("Pausa" o "× 0,25") con el contador de fotograma debajo.
    static func stateBadge(_ state: String, counter: String?) -> CALayer {
        let root = CALayer()
        let label = text(state, font: UIFont.systemFont(ofSize: 30, weight: .semibold),
                         color: UIColor(red: 16 / 255, green: 36 / 255, blue: 29 / 255, alpha: 1))
        let badge = capsule(label, background: .white, paddingX: 20, paddingY: 9)
        badge.frame.origin = CGPoint(x: width - sideMargin - badge.bounds.width, y: 64)
        root.addSublayer(badge)
        if let counter {
            let count = text(counter, font: UIFont.monospacedDigitSystemFont(ofSize: 26, weight: .medium),
                             color: UIColor.white.withAlphaComponent(0.7))
            count.frame.origin = CGPoint(x: width - sideMargin - count.bounds.width, y: badge.frame.maxY + 10)
            root.addSublayer(count)
        }
        return root
    }

    // MARK: Subtítulos palabra a palabra

    /// Subtítulos de toda la pista: cada palabra pasa del 42 % al 100 % cuando suena (docs/02).
    /// Las frases largas se parten en pantallas de dos líneas (~22 letras por línea).
    static func subtitles(track: VoiceTrack, total: Double) -> CALayer {
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: width, height: height)
        let font = Typography.archivoUIFont(68, width: 92, weight: 800)
        let maxLineWidth = width - 2 * sideMargin
        let lineHeight: CGFloat = 86

        for (lineIndex, line) in track.lines.enumerated() {
            let words = track.words.filter { $0.line == lineIndex }
            guard !words.isEmpty else { continue }
            // Pantallas de como mucho 2 líneas: se van llenando palabras hasta que no caben.
            var pages: [[(word: SubtitleWord, size: CGSize)]] = [[]]
            var lineWidths: [CGFloat] = [0]
            for word in words {
                let size = NSAttributedString(string: word.text + " ", attributes: [.font: font]).size()
                if lineWidths[lineWidths.count - 1] + size.width > maxLineWidth {
                    lineWidths.append(0)
                    if lineWidths.count % 2 == 1 {
                        pages.append([])
                    }
                }
                lineWidths[lineWidths.count - 1] += size.width
                pages[pages.count - 1].append((word, size))
            }
            let pageEnds: [Double] = pages.indices.map { i in
                i + 1 < pages.count ? pages[i + 1].first!.word.time : line.end + 0.35
            }
            for (pageIndex, page) in pages.enumerated() where !page.isEmpty {
                let pageStart = max(pageIndex == 0 ? line.start : page.first!.word.time - 0.1, 0)
                let pageEnd = pageEnds[pageIndex]
                // Reparto en 1 o 2 líneas centradas hacia el 75 % de la altura.
                var rows: [[(word: SubtitleWord, size: CGSize)]] = [[]]
                var rowWidth: CGFloat = 0
                for item in page {
                    if rowWidth + item.size.width > maxLineWidth, !rows[rows.count - 1].isEmpty {
                        rows.append([])
                        rowWidth = 0
                    }
                    rows[rows.count - 1].append(item)
                    rowWidth += item.size.width
                }
                let baseY = height * 0.75 - CGFloat(rows.count) * lineHeight / 2
                for (rowIndex, row) in rows.enumerated() {
                    let totalWidth = row.reduce(0) { $0 + $1.size.width }
                    var x = (width - totalWidth) / 2
                    let y = baseY + CGFloat(rowIndex) * lineHeight
                    for item in row {
                        let said = text(item.word.text, font: font, color: .white, outline: true)
                        said.frame.origin = CGPoint(x: x, y: y)
                        show(said, from: item.word.time, to: pageEnd, total: total, fade: 0.06)
                        let pending = text(item.word.text, font: font,
                                           color: UIColor.white.withAlphaComponent(0.42), outline: true)
                        pending.frame.origin = CGPoint(x: x, y: y)
                        show(pending, from: pageStart, to: item.word.time, total: total, fade: 0.06)
                        root.addSublayer(pending)
                        root.addSublayer(said)
                        x += item.size.width
                    }
                }
            }
        }
        return root
    }
}
