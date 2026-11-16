import GolfCore
import QuartzCore
import UIKit

/// Tarjetas de datos y portadas del vídeo del análisis (docs/02 y docs/08): el gancho, la cámara
/// lenta, el ritmo, la nota, el informe y el cierre. Todas a pantalla completa (1080 x 1920).
enum AnalysisCards {
    static let pino = UIColor(red: 16 / 255, green: 36 / 255, blue: 29 / 255, alpha: 1)
    static let bola = UIColor(red: 246 / 255, green: 247 / 255, blue: 244 / 255, alpha: 1)
    static let amarillo = UIColor(red: 1, green: 208 / 255, blue: 46 / 255, alpha: 1)
    static let texto2 = UIColor(red: 75 / 255, green: 93 / 255, blue: 85 / 255, alpha: 1)

    private static func fullFrame() -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: VideoLayers.width, height: VideoLayers.height)
        return layer
    }

    // MARK: Gancho

    /// Título "¿Qué nota le pones a este swing?", insignia "?/100" y barra inferior con la frase
    /// del gancho y su progreso (docs/08).
    static func hookOverlay(phrase: String, blockStart: Double, blockEnd: Double, total: Double) -> CALayer {
        let root = fullFrame()
        let title = VideoLayers.text("¿Qué nota le pones\na este swing?", font: VideoLayers.archivo(84, width: 74, weight: 820),
                                     color: .white, alignment: .center, outline: true)
        title.alignmentMode = .center
        title.frame = CGRect(x: 0, y: 170, width: VideoLayers.width, height: 220)
        root.addSublayer(title)

        let badgeText = VideoLayers.text("?/100", font: VideoLayers.archivo(56), color: pino)
        let badge = VideoLayers.capsule(badgeText, background: amarillo, paddingX: 28, paddingY: 12)
        badge.frame.origin = CGPoint(x: (VideoLayers.width - badge.bounds.width) / 2, y: 410)
        root.addSublayer(badge)

        // Barra inferior: la frase del gancho y una barra de progreso que cruza el bloque.
        let bar = CALayer()
        bar.frame = CGRect(x: VideoLayers.sideMargin, y: 1550, width: VideoLayers.width - 2 * VideoLayers.sideMargin, height: 150)
        bar.backgroundColor = pino.withAlphaComponent(0.84).cgColor
        bar.cornerRadius = 32
        let phraseLayer = VideoLayers.text(phrase, font: UIFont.systemFont(ofSize: 34, weight: .semibold), color: .white)
        phraseLayer.frame = CGRect(x: 32, y: 24, width: bar.bounds.width - 64, height: 60)
        phraseLayer.isWrapped = true
        phraseLayer.truncationMode = .end
        bar.addSublayer(phraseLayer)
        let trackLine = CALayer()
        trackLine.frame = CGRect(x: 32, y: 108, width: bar.bounds.width - 64, height: 10)
        trackLine.backgroundColor = UIColor.white.withAlphaComponent(0.25).cgColor
        trackLine.cornerRadius = 5
        bar.addSublayer(trackLine)
        let progress = CALayer()
        progress.frame = trackLine.frame
        progress.backgroundColor = amarillo.cgColor
        progress.cornerRadius = 5
        progress.anchorPoint = CGPoint(x: 0, y: 0.5)
        progress.position = CGPoint(x: trackLine.frame.minX, y: trackLine.frame.midY)
        let grow = CABasicAnimation(keyPath: "transform.scale.x")
        grow.fromValue = 0.001
        grow.toValue = 1
        grow.beginTime = AVCoreAnimationBeginTimeAtZero + blockStart
        grow.duration = max(blockEnd - blockStart, 0.1)
        grow.isRemovedOnCompletion = false
        grow.fillMode = .forwards
        progress.add(grow, forKey: "progress")
        bar.addSublayer(progress)
        root.addSublayer(bar)
        VideoLayers.show(root, from: blockStart, to: blockEnd, total: total)
        return root
    }

    // MARK: Cámara lenta

    /// Zona de plano, círculo de cabeza, línea de cadera y la trayectoria de las manos dibujándose
    /// (subida en blanco, bajada en amarillo). El chip del nombre de la fase va cambiando.
    static func slowMotionOverlay(analysis: SwingAnalysis, block: TimelineBlock, swingStart: Double,
                                  factor: Double, total: Double) -> CALayer {
        let root = fullFrame()
        func mapped(_ clipTime: Double) -> Double { block.start + (clipTime - swingStart) * factor }

        // Zona de plano: triángulo entre la línea del palo de la preparación y la línea bola-cuello.
        let addressPose = analysis.poses[analysis.phases[.address].frameIndex]
        if let clubHead = analysis.clubHeadAtAddress, let hands = addressPose.hands, let neck = addressPose.joints[.neck] {
            let direction = hands - clubHead
            let extended = clubHead + direction * 2.2
            let path = UIBezierPath()
            path.move(to: CGPoint(x: clubHead.x, y: clubHead.y))
            path.addLine(to: CGPoint(x: extended.x, y: extended.y))
            path.addLine(to: CGPoint(x: neck.x, y: neck.y))
            path.close()
            root.addSublayer(VideoLayers.shape(path, stroke: nil, width: 0,
                                               fill: UIColor.white.withAlphaComponent(0.13)))
        }
        // Las referencias fijas de la preparación (cadera, cabeza) las pinta el telestrador simple.
        root.addSublayer(VideoLayers.telestrator(analysis: analysis, position: .address))

        // Trayectoria de las manos: subida en blanco y bajada en amarillo, dibujándose a su ritmo.
        let positions = analysis.phases
        func handsPath(from: Double, to: Double) -> UIBezierPath {
            let path = UIBezierPath()
            var started = false
            for pose in analysis.poses where pose.time >= from && pose.time <= to {
                guard let hands = pose.hands else { continue }
                let point = CGPoint(x: hands.x, y: hands.y)
                if started { path.addLine(to: point) } else { path.move(to: point); started = true }
            }
            return path
        }
        let backswingStart = analysis.phases.backswingStartTime
        let up = VideoLayers.shape(handsPath(from: backswingStart, to: positions[.top].time),
                                   stroke: UIColor.white.withAlphaComponent(0.9), width: 7)
        let down = VideoLayers.shape(handsPath(from: positions[.top].time, to: positions[.finish].time),
                                     stroke: amarillo, width: 7)
        for (layer, from, to) in [(up, backswingStart, positions[.top].time),
                                  (down, positions[.top].time, positions[.finish].time)] {
            layer.strokeEnd = 0
            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0
            draw.toValue = 1
            draw.beginTime = AVCoreAnimationBeginTimeAtZero + mapped(from)
            draw.duration = max((to - from) * factor, 0.05)
            draw.isRemovedOnCompletion = false
            draw.fillMode = .forwards
            layer.add(draw, forKey: "draw")
            root.addSublayer(layer)
        }

        // El nombre de cada fase aparece cuando la cámara lenta pasa por ella.
        for position in SwingPosition.allCases {
            let time = analysis.poses[positions[position].frameIndex].time
            let from = mapped(time)
            let to = position == .finish ? block.end : mapped(analysis.poses[positions[SwingPosition(rawValue: position.rawValue + 1)!].frameIndex].time)
            let chip = VideoLayers.phaseChip(position.rawValue, title: position.title)
            VideoLayers.show(chip, from: from, to: max(to, from + 0.5), total: total)
            root.addSublayer(chip)
        }
        VideoLayers.show(root, from: block.start, to: block.end, total: total)
        return root
    }

    // MARK: Ritmo

    static func tempoCard(analysis: SwingAnalysis, block: TimelineBlock, total: Double) -> CALayer {
        let root = fullFrame()
        root.backgroundColor = bola.cgColor
        let phases = analysis.phases
        let tempo = phases.tempo ?? 0

        let title = VideoLayers.text("Tu ritmo", font: UIFont.systemFont(ofSize: 44, weight: .semibold), color: texto2)
        title.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: 300)
        root.addSublayer(title)
        let big = VideoLayers.text("\(SpanishFormat.number(tempo, decimals: 1)) : 1",
                                   font: VideoLayers.archivo(200, width: 68, weight: 820), color: pino)
        big.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: 360)
        root.addSublayer(big)

        // Barras de subida y bajada que crecen en 0,8 s, a escala del tiempo real.
        let barAreaY: CGFloat = 760
        let maxBarHeight: CGFloat = 420
        let up = CGFloat(phases.backswingDuration / max(phases.backswingDuration, 0.01)) * maxBarHeight
        let down = CGFloat(phases.downswingDuration / max(phases.backswingDuration, 0.01)) * maxBarHeight
        for (index, (height, color, label, seconds)) in [
            (up, pino, "Subida", phases.backswingDuration),
            (down, amarillo, "Bajada", phases.downswingDuration),
        ].enumerated() {
            let x = VideoLayers.sideMargin + CGFloat(index) * 260
            let bar = CALayer()
            bar.frame = CGRect(x: x, y: barAreaY + (maxBarHeight - height), width: 170, height: height)
            bar.backgroundColor = color.cgColor
            bar.cornerRadius = 24
            bar.anchorPoint = CGPoint(x: 0.5, y: 1)
            bar.position = CGPoint(x: x + 85, y: barAreaY + maxBarHeight)
            let grow = CABasicAnimation(keyPath: "transform.scale.y")
            grow.fromValue = 0.001
            grow.toValue = 1
            grow.beginTime = AVCoreAnimationBeginTimeAtZero + block.start + 0.3
            grow.duration = 0.8
            grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
            grow.isRemovedOnCompletion = false
            grow.fillMode = .backwards
            bar.add(grow, forKey: "grow")
            root.addSublayer(bar)
            let caption = VideoLayers.text("\(label) \(SpanishFormat.seconds(seconds, decimals: 2))",
                                           font: UIFont.monospacedDigitSystemFont(ofSize: 36, weight: .semibold), color: pino)
            caption.frame.origin = CGPoint(x: x, y: barAreaY + maxBarHeight + 24)
            root.addSublayer(caption)
        }

        let reference = VideoLayers.text("Profesionales ≈ 3 : 1", font: UIFont.systemFont(ofSize: 40, weight: .semibold), color: texto2)
        reference.frame.origin = CGPoint(x: VideoLayers.sideMargin + 560, y: barAreaY + 160)
        root.addSublayer(reference)

        let upFrames = Int((phases.backswingDuration * analysis.frameRate).rounded())
        let downFrames = Int((phases.downswingDuration * analysis.frameRate).rounded())
        let foot = VideoLayers.text("Medido a \(SpanishFormat.number(analysis.frameRate)) fps: subida \(upFrames) fotogramas, bajada \(downFrames)",
                                    font: UIFont.systemFont(ofSize: 30), color: texto2)
        foot.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: 1460)
        root.addSublayer(foot)

        VideoLayers.show(root, from: block.start, to: block.end, total: total)
        return root
    }

    // MARK: Nota

    static func scoreCard(score: SwingScore, block: TimelineBlock, total: Double) -> CALayer {
        let root = fullFrame()
        root.backgroundColor = bola.cgColor
        let title = VideoLayers.text("Tu nota", font: UIFont.systemFont(ofSize: 44, weight: .semibold), color: texto2)
        title.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: 160)
        root.addSublayer(title)

        if let totalScore = score.total {
            // La cuenta de 0 a la nota en 1,2 s: una docena de capas que se van turnando.
            let steps = 12
            for step in 0...steps {
                let value = step == steps ? totalScore : totalScore * step / steps
                let number = VideoLayers.text("\(value)", font: VideoLayers.archivo(340, width: 68, weight: 820), color: pino)
                number.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: 190)
                let from = block.start + 1.2 * Double(step) / Double(steps)
                let to = step == steps ? block.end : block.start + 1.2 * Double(step + 1) / Double(steps)
                VideoLayers.show(number, from: from, to: to, total: total, fade: 0.02)
                root.addSublayer(number)
            }
            let outOf = VideoLayers.text("/100", font: VideoLayers.archivo(90), color: texto2)
            outOf.frame.origin = CGPoint(x: VideoLayers.sideMargin + 480, y: 420)
            root.addSublayer(outOf)
            let label = VideoLayers.capsule(VideoLayers.text(score.label, font: UIFont.systemFont(ofSize: 38, weight: .semibold), color: .white),
                                            background: pino, paddingX: 30, paddingY: 14)
            label.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: 590)
            root.addSublayer(label)
        }

        // Filas por fase con su marca: círculo (punto fuerte, ≥ 8) o cuadrado (a mejorar, < 6).
        var y: CGFloat = 760
        for phase in score.phases {
            let name = VideoLayers.text(phase.phase.title, font: UIFont.systemFont(ofSize: 40, weight: .medium), color: pino)
            name.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: y)
            root.addSublayer(name)
            let valueText = phase.score.map { SpanishFormat.number($0, decimals: $0 == $0.rounded() ? 0 : 1) } ?? "—"
            let value = VideoLayers.text(valueText, font: VideoLayers.archivo(52), color: pino)
            value.frame.origin = CGPoint(x: VideoLayers.width - VideoLayers.sideMargin - 110, y: y - 6)
            root.addSublayer(value)
            if let scoreValue = phase.score {
                let mark = CAShapeLayer()
                let rect = CGRect(x: VideoLayers.width - VideoLayers.sideMargin - 180, y: y + 2, width: 44, height: 44)
                if scoreValue >= 8 {
                    mark.path = UIBezierPath(ovalIn: rect).cgPath
                } else if scoreValue < 6 {
                    mark.path = UIBezierPath(rect: rect).cgPath
                }
                mark.strokeColor = pino.cgColor
                mark.fillColor = UIColor.clear.cgColor
                mark.lineWidth = 3
                root.addSublayer(mark)
            }
            y += 78
        }
        let legend = VideoLayers.text("○ Punto fuerte   □ A mejorar", font: UIFont.systemFont(ofSize: 32), color: texto2)
        legend.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: y + 20)
        root.addSublayer(legend)
        let foot = VideoLayers.text("Transición e impacto cuentan doble; el ritmo, 1,5 veces.",
                                    font: UIFont.systemFont(ofSize: 30), color: texto2)
        foot.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: y + 80)
        root.addSublayer(foot)

        VideoLayers.show(root, from: block.start, to: block.end, total: total)
        return root
    }

    // MARK: Informe

    static func reportCard(analysis: SwingAnalysis, score: SwingScore, block: TimelineBlock,
                           total: Double, date: Date) -> CALayer {
        let root = fullFrame()
        root.backgroundColor = bola.cgColor
        var y: CGFloat = 170
        func heading(_ text: String) {
            let layer = VideoLayers.text(text, font: UIFont.systemFont(ofSize: 40, weight: .semibold), color: texto2)
            layer.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: y)
            root.addSublayer(layer)
            y += 70
        }
        func row(_ text: String, size: CGFloat = 36, color: UIColor = pino) {
            let layer = VideoLayers.text(text, font: UIFont.systemFont(ofSize: size, weight: .medium), color: color)
            layer.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: y)
            layer.frame.size.width = min(layer.frame.width, VideoLayers.width - 2 * VideoLayers.sideMargin)
            layer.truncationMode = .end
            root.addSublayer(layer)
            y += size + 22
        }

        if !score.strengths.isEmpty {
            heading("Puntos fuertes")
            for phase in score.strengths { row("○  \(phase.title)") }
            y += 30
        }
        if !score.improvements.isEmpty {
            heading("A mejorar")
            for (index, item) in score.improvements.enumerated() {
                row("\(index + 1).  \(FaultLibrary.fault(item.fault).reportLabel)")
                row("Ejercicio: \(FaultLibrary.fault(item.fault).exercise)", size: 28, color: texto2)
            }
            y += 30
        }
        if let priority = score.priority {
            heading("Prioridad nº 1")
            row(FaultLibrary.fault(priority).reportLabel)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d 'de' MMMM 'de' yyyy"
        let foot = VideoLayers.text("Medidas aproximadas, vídeo 2D a \(SpanishFormat.number(analysis.frameRate)) fps · \(formatter.string(from: date))",
                                    font: UIFont.systemFont(ofSize: 28), color: texto2)
        foot.frame.origin = CGPoint(x: VideoLayers.sideMargin, y: 1700)
        root.addSublayer(foot)
        VideoLayers.show(root, from: block.start, to: block.end, total: total)
        return root
    }

    /// Cierre: la marca pequeña con la fecha (docs/04, punto 10).
    static func closingCard(block: TimelineBlock, total: Double, date: Date) -> CALayer {
        let root = fullFrame()
        root.backgroundColor = pino.cgColor
        let brand = VideoLayers.text("Trazo", font: VideoLayers.archivo(110, width: 70, weight: 850), color: .white)
        brand.frame.origin = CGPoint(x: (VideoLayers.width - brand.bounds.width) / 2, y: 880)
        root.addSublayer(brand)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d 'de' MMMM 'de' yyyy"
        let caption = VideoLayers.text(formatter.string(from: date), font: UIFont.systemFont(ofSize: 34), color: UIColor.white.withAlphaComponent(0.7))
        caption.frame.origin = CGPoint(x: (VideoLayers.width - caption.bounds.width) / 2, y: 1020)
        root.addSublayer(caption)
        VideoLayers.show(root, from: block.start, to: block.end, total: total)
        return root
    }
}
