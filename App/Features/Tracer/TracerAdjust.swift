@preconcurrency import AVFoundation
import GolfCore
import SwiftData
import SwiftUI
import UIKit

// Etapa 5 del tracer (docs/03 y docs/02): ajustar el vuelo a mano, el estilo del trazo y el vídeo final.

/// Lo que el usuario ha ajustado en "Ajusta el vuelo". Se guarda con el tracer para poder volver a
/// editarlo ("Editar" no pierde nada).
struct TracerEdit: Codable, Sendable, Equatable {
    var curve: TracerCurve
    var colorRaw: String
    var customColorHex: Int
    var showsDistance: Bool
    /// Distancia escrita a mano (m). Si es nil, la del palo elegido en "Mis palos".
    var manualDistanceMeters: Double?
    var clubName: String?
    var clubDistanceMeters: Double?

    var color: TracerColorChoice { TracerColorChoice(rawValue: colorRaw) ?? .rojoTV }
    var uiColor: UIColor { UIColor(color.color(custom: Color(hex: UInt32(customColorHex)))) }
    /// La distancia que se enseña (nunca medida): la escrita o la del palo.
    var distanceMeters: Double? { manualDistanceMeters ?? clubDistanceMeters }

    /// Solo para los `Binding` mientras aún no hay ajuste (no se llega a ver).
    static let placeholder = TracerEdit(curve: TracerCurve(launch: Point2D(0, 0), apex: Point2D(0, 0), landing: Point2D(0, 0), flightTime: 4),
                                        colorRaw: TracerColorChoice.rojoTV.rawValue, customColorHex: Int(TracerPalette.customDefaultHex),
                                        showsDistance: false, manualDistanceMeters: nil, clubName: nil, clubDistanceMeters: nil)

    /// La curva de las capturas del CI, como en la maqueta (s04): sale de la bola de la escena de
    /// demostración, sube hasta arriba en el centro y cae en el horizonte, a la izquierda (draw).
    static func demo(videoSize: CGSize) -> TracerEdit {
        let w = videoSize.width, h = videoSize.height
        return TracerEdit(curve: TracerCurve(launch: Point2D(0.836 * w, 0.906 * h), apex: Point2D(0.64 * w, 0.125 * h),
                                             landing: Point2D(0.50 * w, 0.315 * h), shape: drawShape, flightTime: 5.8),
                          colorRaw: TracerColorChoice.rojoTV.rawValue, customColorHex: Int(TracerPalette.customDefaultHex),
                          showsDistance: true, manualDistanceMeters: nil, clubName: "Hierro 7", clubDistanceMeters: 150)
    }

    /// Forma de la curva: draw, recta o fade (docs/03: s de −1 a +1).
    static let drawShape = -0.6
    static let fadeShape = 0.6

    /// "150 m" o "164 yd" (docs/03, Distancia). La distancia se guarda en metros.
    static func distanceText(_ meters: Double, units: String) -> String {
        units == "yd" ? "\(Int((meters / 0.9144).rounded())) yd" : "\(Int(meters.rounded())) m"
    }
}

extension TracerResult {
    var edit: TracerEdit? {
        get { editData.flatMap { try? JSONDecoder().decode(TracerEdit.self, from: $0) } }
        set { editData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}

// MARK: - El trazo en pantalla (vista previa del ajuste)

/// El trazo con su estilo (docs/02, s09): halo difuminado, color y núcleo blanco, más fino al caer,
/// la marca de caída y la etiqueta. En "Ajusta el vuelo" se ve entero.
struct TracerStyledPath: View {
    let curve: TracerCurve
    let videoSize: CGSize
    let color: Color
    let label: (club: String?, distance: String)?

    var body: some View {
        let flight = curve.makeFlight()
        Canvas { context, size in
            let sx = size.width / videoSize.width, sy = size.height / videoSize.height
            let k = size.height / 1920 // medidas de docs/02 para un vídeo de 1080 x 1920
            func view(_ p: Point2D) -> CGPoint { CGPoint(x: p.x * sx, y: p.y * sy) }
            let points = flight.points.map(view)
            guard points.count > 1 else { return }
            let pieces = 8
            for piece in 0..<pieces {
                let from = piece * (points.count - 1) / pieces
                let to = (piece + 1) * (points.count - 1) / pieces
                guard to > from else { continue }
                var path = Path()
                path.addLines(Array(points[from...to]))
                // El grosor baja del 125 % en la salida al 50 % en la caída (perspectiva).
                let f = 1.25 - 0.75 * Double(piece) / Double(pieces - 1)
                var halo = context
                halo.addFilter(.blur(radius: 9 * k * 2))
                let cap: CGLineCap = piece == 0 ? .round : .butt
                halo.stroke(path, with: .color(color.opacity(0.42)), style: StrokeStyle(lineWidth: 41 * k * f, lineCap: cap, lineJoin: .round))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 12 * k * f, lineCap: cap, lineJoin: .round))
                context.stroke(path, with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: max(4 * k * f, 1), lineCap: cap))
            }
            let landing = view(curve.landing)
            context.stroke(Path(ellipseIn: CGRect(x: landing.x - 12 * k, y: landing.y - 12 * k, width: 24 * k, height: 24 * k)),
                           with: .color(.white), lineWidth: max(3 * k, 1))
            context.fill(Path(ellipseIn: CGRect(x: landing.x - 6 * k, y: landing.y - 6 * k, width: 12 * k, height: 12 * k)), with: .color(.white))
            if let label {
                let box = CGRect(x: landing.x - 300 * k, y: landing.y - 230 * k, width: 270 * k, height: 135 * k)
                var line = Path()
                line.move(to: CGPoint(x: box.maxX, y: box.maxY))
                line.addLine(to: landing)
                context.stroke(line, with: .color(.white.opacity(0.8)), lineWidth: max(2 * k, 1))
                context.fill(Path(roundedRect: box, cornerRadius: 28 * k), with: .color(Color.pino.opacity(0.88)))
                if let club = label.club {
                    context.draw(Text(club).font(.lato(30 * k, weight: .bold)).foregroundStyle(.white.opacity(0.72)),
                                 at: CGPoint(x: box.minX + 26 * k, y: box.minY + 34 * k), anchor: .leading)
                }
                context.draw(Text(label.distance).font(.lato(66 * k, weight: .black)).foregroundStyle(.white),
                             at: CGPoint(x: box.minX + 26 * k, y: box.maxY - 46 * k), anchor: .leading)
            }
        }
    }
}

/// Las tres asas (Salida, Altura, Caída): círculos blancos con anillo Pino que se arrastran.
struct TracerHandles: View {
    @Binding var curve: TracerCurve
    let videoSize: CGSize

    var body: some View {
        GeometryReader { proxy in
            let sx = proxy.size.width / videoSize.width, sy = proxy.size.height / videoSize.height
            ForEach(Handle.allCases, id: \.self) { handle in
                let p = handle.point(of: curve)
                // El nombre del asa en una píldora de cristal a su lado (s04): Altura a la derecha,
                // Salida y Caída a la izquierda.
                Text(handle.title)
                    .typeStyle(.chip)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.m)
                    .frame(height: Size.chipHeight)
                    .background(Color.pino.opacity(0.55), in: Capsule())
                    .fixedSize()
                    .frame(width: 120, alignment: handle == .apex ? .leading : .trailing)
                    .position(x: p.x * sx + (handle == .apex ? 82 : -82), y: p.y * sy)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(Color.pino, lineWidth: 4))
                    .frame(width: 30, height: 30)
                    .frame(width: Size.minTouch, height: Size.minTouch)
                    .contentShape(Circle())
                    .position(x: p.x * sx, y: p.y * sy)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space)).onChanged { value in
                        let x = min(max(value.location.x / sx, 0), videoSize.width)
                        let y = min(max(value.location.y / sy, 0), videoSize.height)
                        handle.set(Point2D(x, y), in: &curve)
                    })
                    .accessibilityLabel(handle.title)
                    .accessibilityHint("Arrastra para mover el punto \(handle.title.lowercased()) del vuelo")
            }
        }
        // El arrastre se mide en el espacio del vídeo encajado, no en el del círculo.
        .coordinateSpace(.named(Self.space))
    }

    private static let space = "tracer-video"

    enum Handle: CaseIterable {
        case launch, apex, landing

        var title: String {
            switch self {
            case .launch: "Salida"
            case .apex: "Altura"
            case .landing: "Caída"
            }
        }

        func point(of curve: TracerCurve) -> Point2D {
            switch self {
            case .launch: curve.launch
            case .apex: curve.apex
            case .landing: curve.landing
            }
        }

        func set(_ point: Point2D, in curve: inout TracerCurve) {
            switch self {
            case .launch: curve.launch = point
            case .apex: curve.apex = point
            case .landing: curve.landing = point
            }
        }
    }
}

/// La hoja de abajo de "Ajusta el vuelo" (s04): forma, altura, tiempo de vuelo, colores, distancia y
/// "Crear vídeo".
/// La línea de tiempo de "Ajusta el vuelo" (s04): blanca, con el impacto en rojo y un círculo que se
/// arrastra para ir a cualquier fotograma.
struct TracerTimeline: View {
    let duration: Double
    let impact: Double
    let current: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = { (t: Double) in width * min(max(t / max(duration, 0.01), 0), 1) }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.3)).frame(height: 4)
                Capsule().fill(Color.white).frame(width: x(current), height: 4)
                Capsule().fill(Color.rojoTrazo).frame(width: 3, height: 16).offset(x: x(impact) - 1.5)
                Circle().fill(Color.white).frame(width: 22, height: 22).offset(x: x(current) - 11)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                onSeek(min(max(value.location.x / max(width, 1), 0), 1) * duration)
            })
        }
        .frame(height: Size.minTouch)
        .accessibilityElement()
        .accessibilityLabel("Línea de tiempo")
        .accessibilityValue("\(SpanishFormat.number(current, decimals: 1)) de \(SpanishFormat.number(duration, decimals: 1)) segundos; impacto a los \(SpanishFormat.number(impact, decimals: 1))")
        .accessibilityAdjustableAction { direction in
            let step = 1.0 / 30
            onSeek(min(max(current + (direction == .increment ? step : -step), 0), duration))
        }
    }
}

struct TracerAdjustPanel: View {
    @Binding var edit: TracerEdit
    let clubs: [Club]
    let units: String
    let isExporting: Bool
    let onReset: () -> Void
    let onCreate: () -> Void
    @State private var asksForDistance = false
    @State private var manualText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Capsule()
                .fill(Color.borde)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            HStack {
                Text("Forma del golpe").typeStyle(.valor).foregroundStyle(Color.pino)
                Spacer()
                Button("Restablecer", action: onReset)
                    .typeStyle(.etiqueta)
                    .foregroundStyle(Color.texto2)
            }
            Picker("Forma", selection: shapeBinding) {
                Text("Draw").tag(TracerEdit.drawShape)
                Text("Recta").tag(0.0)
                Text("Fade").tag(TracerEdit.fadeShape)
            }
            .pickerStyle(.segmented)
            row("Altura", value: heightName) {
                Slider(value: heightBinding, in: 0.1...0.95).tint(Color.pino)
            }
            row("Tiempo de vuelo", value: "\(SpanishFormat.number(edit.curve.flightTime, decimals: 1)) s") {
                Slider(value: $edit.curve.flightTime, in: 2...9, step: 0.1).tint(Color.pino)
            }
            HStack(spacing: Spacing.s) {
                ColorSwatchRow(selection: colorBinding, customColor: customColorBinding)
                Spacer(minLength: 0)
                Toggle(isOn: $edit.showsDistance) { distanceMenu }
                    .toggleStyle(TrazoSwitchStyle())
            }
            Button(action: onCreate) {
                if isExporting {
                    ProgressView().tint(.white)
                } else {
                    Text("Crear vídeo")
                }
            }
            .buttonStyle(.principal)
            .disabled(isExporting)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.xl)
        .background(Color.bola, in: UnevenRoundedRectangle(topLeadingRadius: Radius.sheet, topTrailingRadius: Radius.sheet, style: .continuous))
        .environment(\.colorScheme, .light)
        .alert("Distancia", isPresented: $asksForDistance) {
            TextField(units == "yd" ? "164" : "150", text: $manualText)
                .keyboardType(.numberPad)
            Button("Aceptar") {
                let number = Double(manualText.filter(\.isNumber))
                edit.manualDistanceMeters = number.map { units == "yd" ? $0 * 0.9144 : $0 }
                if number != nil { edit.showsDistance = true }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("La app no mide la distancia: escribe la que sepas, en \(units == "yd" ? "yardas" : "metros").")
        }
    }

    /// "150 m" (la escrita o la del palo); al tocarlo, elegir palo o escribirla.
    private var distanceMenu: some View {
        Menu {
            ForEach(clubs) { club in
                Button(club.name + (club.distanceMeters.map { " · " + TracerEdit.distanceText($0, units: units) } ?? "")) {
                    edit.clubName = club.name
                    edit.clubDistanceMeters = club.distanceMeters
                    edit.manualDistanceMeters = nil
                }
            }
            Button("Escribir la distancia…") {
                manualText = edit.manualDistanceMeters.map { String(Int((units == "yd" ? $0 / 0.9144 : $0).rounded())) } ?? ""
                asksForDistance = true
            }
            Button("Sin palo") {
                edit.clubName = nil
                edit.clubDistanceMeters = nil
            }
        } label: {
            Text(edit.distanceMeters.map { TracerEdit.distanceText($0, units: units) } ?? "Distancia")
                .typeStyle(.cuerpo)
                .foregroundStyle(Color.pino)
                .monospacedDigit()
        }
        .accessibilityLabel("Distancia y palo")
    }

    private func row(_ title: String, value: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: Spacing.m) {
            Text(title).typeStyle(.cuerpo).foregroundStyle(Color.pino).frame(width: 128, alignment: .leading)
            content()
            Text(value).typeStyle(.valor).foregroundStyle(Color.pino).monospacedDigit().frame(width: 56, alignment: .trailing)
        }
    }

    private var heightName: String {
        let value = heightBinding.wrappedValue
        return value > 0.66 ? "Alta" : (value > 0.4 ? "Media" : "Baja")
    }

    private var shapeBinding: Binding<Double> {
        Binding(get: { edit.curve.shape < -0.2 ? TracerEdit.drawShape : (edit.curve.shape > 0.2 ? TracerEdit.fadeShape : 0) },
                set: { edit.curve.shape = $0 })
    }

    /// La altura del vértice como fracción entre la salida y lo alto de la imagen.
    private var heightBinding: Binding<Double> {
        Binding(get: {
            let launchY = edit.curve.launch.y
            return launchY > 0 ? min(max((launchY - edit.curve.apex.y) / launchY, 0.1), 0.95) : 0.5
        }, set: { value in
            edit.curve.apex.y = edit.curve.launch.y * (1 - value)
        })
    }

    private var colorBinding: Binding<TracerColorChoice> {
        Binding(get: { edit.color }, set: { edit.colorRaw = $0.rawValue })
    }

    private var customColorBinding: Binding<Color> {
        Binding(get: { Color(hex: UInt32(edit.customColorHex)) }, set: { edit.customColorHex = Int($0.hexValue) })
    }
}

// MARK: - El vídeo final

/// Monta el vídeo del tracer (docs/03, Exportación; docs/02, s09): el clip original con su audio y el
/// trazo encima, que arranca en el instante exacto del impacto y crece con la bola durante el tiempo de
/// vuelo; al caer, la marca y la etiqueta (si la distancia está activada) y 1,5 s más de trazo entero.
/// H.264 a la resolución del original hasta 1080p, con `shouldOptimizeForNetworkUse`.
enum TracerVideoExporter {
    static let holdAfterLanding = 1.5

    @concurrent
    static func export(clipURL: URL, impactTime: Double, edit: TracerEdit, units: String, watermark: Bool) async throws -> (url: URL, duration: Double) {
        let asset = AVURLAsset(url: clipURL)
        guard let source = try await asset.loadTracks(withMediaType: .video).first else { throw MediaError.noVideoTrack }
        let audio = try await asset.loadTracks(withMediaType: .audio).first
        let duration = try await asset.load(.duration).seconds
        let natural = try await source.load(.naturalSize)
        let transform = try await source.load(.preferredTransform)
        let oriented = natural.applying(transform)
        let width = abs(oriented.width), height = abs(oriented.height)
        // Hasta 1080p: el lado corto como mucho 1080.
        let scale = min(1, 1080 / max(min(width, height), 1))
        let render = CGSize(width: (width * scale / 2).rounded() * 2, height: (height * scale / 2).rounded() * 2)

        let composition = AVMutableComposition()
        let timescale: CMTimeScale = 48_000
        func time(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: timescale) }
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw MediaError.exportFailed("montaje") }
        let sourceRange = try await source.load(.timeRange)
        try videoTrack.insertTimeRange(sourceRange, of: source, at: .zero)
        if let audio, let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let audioRange = try await audio.load(.timeRange)
            try? audioTrack.insertTimeRange(audioRange, of: audio, at: .zero)
        }
        // Si el clip acaba antes de que caiga la bola (+1,5 s), se congela el último fotograma.
        let landingTime = impactTime + edit.curve.flightTime
        let total = max(duration, landingTime + holdAfterLanding)
        if total - sourceRange.duration.seconds > 0.05 {
            let last = CMTimeRange(start: sourceRange.end - time(1.0 / 30), duration: time(1.0 / 30))
            let at = sourceRange.duration
            try videoTrack.insertTimeRange(last, of: source, at: at)
            videoTrack.scaleTimeRange(CMTimeRange(start: at, duration: last.duration), toDuration: time(total - at.seconds))
        }

        let overlay = overlayLayer(edit: edit, impactTime: impactTime, total: total, scale: scale, render: render,
                                   units: units, watermark: watermark)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = render
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: time(total))
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(transform.concatenating(CGAffineTransform(scaleX: scale, y: scale)), at: .zero)
        // El trazo va como pista aparte encima del vídeo (ver VideoLayers.attachOverlay).
        let overlayInstruction = VideoLayers.attachOverlay(overlay, to: videoComposition, composition: composition)
        instruction.layerInstructions = [overlayInstruction, layerInstruction]
        videoComposition.instructions = [instruction]

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw MediaError.exportFailed("sesión de exportación") }
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true
        let output = MediaStore.temporaryURL(extension: "mp4")
        MediaStore.removeIfPresent(output)
        do {
            try await session.export(to: output, as: .mp4)
        } catch {
            throw MediaError.exportFailed("tracer: " + describeError(error))
        }
        // La pista solo guarda una referencia débil a su asset: tiene que seguir vivo hasta aquí.
        withExtendedLifetime(asset) {}
        return (output, total)
    }

    /// Las capas del trazo, animadas en el tiempo del vídeo (Core Animation con
    /// `AVCoreAnimationBeginTimeAtZero`).
    private static func overlayLayer(edit: TracerEdit, impactTime: Double, total: Double, scale: CGFloat,
                                     render: CGSize, units: String, watermark: Bool) -> CALayer {
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: render)
        let flight = edit.curve.makeFlight()
        let k = render.height / 1920
        let color = edit.uiColor
        let points = flight.points.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
        guard points.count > 1, total > 0 else { return root }
        let T = edit.curve.flightTime

        func keyframes(_ values: [Any], times: [Double], key: String) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: key)
            animation.values = values
            animation.keyTimes = times.map { NSNumber(value: min(max($0 / total, 0), 1)) }
            animation.duration = total
            animation.beginTime = AVCoreAnimationBeginTimeAtZero
            animation.isRemovedOnCompletion = false
            animation.fillMode = .forwards
            animation.calculationMode = .linear
            return animation
        }
        // Instantes del vuelo y cuánto recorrido lleva la bola en cada uno (rápida al salir, lenta al final).
        let steps = max(Int(T * 30), 2)
        let flightTimes = (0...steps).map { Double($0) / Double(steps) * T }
        let progress = flightTimes.map { flight.progress(at: $0) }

        // El trazo en trozos, cada uno más fino que el anterior; cada trozo se dibuja cuando la bola pasa.
        let pieces = 8
        for piece in 0..<pieces {
            let from = piece * (points.count - 1) / pieces
            let to = (piece + 1) * (points.count - 1) / pieces
            guard to > from else { continue }
            let a = Double(from) / Double(points.count - 1), b = Double(to) / Double(points.count - 1)
            let path = UIBezierPath()
            path.move(to: points[from])
            for p in points[(from + 1)...to] { path.addLine(to: p) }
            let f = 1.25 - 0.75 * Double(piece) / Double(pieces - 1)
            let ends: [Double] = progress.map { min(max(($0 - a) / max(b - a, 1e-6), 0), 1) }
            let times = [0, impactTime] + flightTimes.map { impactTime + $0 } + [total]
            let values = [0.0, 0.0] + ends + [1.0]
            for (width, stroke, shadow) in [(41 * k * f, color.withAlphaComponent(0.42), true),
                                            (12 * k * f, color, false),
                                            (max(4 * k * f, 1), UIColor.white.withAlphaComponent(0.95), false)] {
                let layer = CAShapeLayer()
                layer.path = path.cgPath
                layer.fillColor = nil
                layer.strokeColor = stroke.cgColor
                layer.lineWidth = width
                // Solo el principio del trazo es redondo: en las uniones entre trozos, un extremo redondo
                // pinta dos veces el halo translúcido y se ve una bolita.
                layer.lineCap = piece == 0 ? .round : .butt
                layer.lineJoin = .round
                if shadow {
                    layer.shadowColor = color.cgColor
                    layer.shadowRadius = 18 * k
                    layer.shadowOpacity = 0.9
                    layer.shadowOffset = .zero
                }
                layer.strokeEnd = 0
                layer.add(keyframes(values, times: times, key: "strokeEnd"), forKey: "trazo")
                root.addSublayer(layer)
            }
        }

        // La cabeza brillante de la bola mientras vuela.
        let head = CALayer()
        head.frame = CGRect(x: 0, y: 0, width: 25 * k * 2, height: 25 * k * 2)
        head.cornerRadius = 25 * k
        head.backgroundColor = color.withAlphaComponent(0.6).cgColor
        let core = CALayer()
        core.frame = CGRect(x: 25 * k - 4.5 * k, y: 25 * k - 4.5 * k, width: 9 * k, height: 9 * k)
        core.cornerRadius = 4.5 * k
        core.backgroundColor = UIColor.white.cgColor
        head.addSublayer(core)
        let positions = flightTimes.map { t -> NSValue in
            let p = flight.ballPosition(at: t)
            return NSValue(cgPoint: CGPoint(x: p.x * scale, y: p.y * scale))
        }
        head.position = positions.first?.cgPointValue ?? .zero
        head.add(keyframes(positions, times: flightTimes.map { impactTime + $0 }, key: "position"), forKey: "bola")
        head.add(keyframes([0, 0, 1, 1, 0, 0], times: [0, impactTime, impactTime + 0.01, impactTime + T, impactTime + T + 0.2, total],
                           key: "opacity"), forKey: "visible")
        head.opacity = 0
        root.addSublayer(head)

        // Al caer: punto y anillo, y la etiqueta con el palo y la distancia (fundido de 0,3 s).
        let landing = CGPoint(x: edit.curve.landing.x * scale, y: edit.curve.landing.y * scale)
        let ending = CALayer()
        ending.frame = root.bounds
        let ring = CAShapeLayer()
        ring.path = UIBezierPath(ovalIn: CGRect(x: landing.x - 12 * k, y: landing.y - 12 * k, width: 24 * k, height: 24 * k)).cgPath
        ring.fillColor = nil
        ring.strokeColor = UIColor.white.cgColor
        ring.lineWidth = max(3 * k, 1)
        ending.addSublayer(ring)
        let dot = CALayer()
        dot.frame = CGRect(x: landing.x - 6 * k, y: landing.y - 6 * k, width: 12 * k, height: 12 * k)
        dot.cornerRadius = 6 * k
        dot.backgroundColor = UIColor.white.cgColor
        ending.addSublayer(dot)
        if edit.showsDistance, let meters = edit.distanceMeters {
            let box = CGRect(x: max(landing.x - 300 * k, 20 * k), y: max(landing.y - 230 * k, 20 * k), width: 270 * k, height: 135 * k)
            let line = CAShapeLayer()
            let linePath = UIBezierPath()
            linePath.move(to: CGPoint(x: box.maxX, y: box.maxY))
            linePath.addLine(to: landing)
            line.path = linePath.cgPath
            line.strokeColor = UIColor.white.withAlphaComponent(0.8).cgColor
            line.lineWidth = max(2 * k, 1)
            ending.addSublayer(line)
            let panel = CALayer()
            panel.frame = box
            panel.cornerRadius = 28 * k
            panel.backgroundColor = AnalysisCards.pino.withAlphaComponent(0.88).cgColor
            if let club = edit.clubName {
                let clubText = VideoLayers.text(club, font: VideoLayers.lato(30 * k, weight: 700), color: UIColor.white.withAlphaComponent(0.72))
                clubText.frame.origin = CGPoint(x: 26 * k, y: 16 * k)
                panel.addSublayer(clubText)
            }
            let distance = VideoLayers.text(TracerEdit.distanceText(meters, units: units), font: VideoLayers.lato(66 * k, weight: 900), color: .white)
            distance.frame.origin = CGPoint(x: 26 * k, y: box.height - distance.bounds.height - 12 * k)
            panel.addSublayer(distance)
            ending.addSublayer(panel)
        }
        VideoLayers.show(ending, from: impactTime + T, to: total + 1, total: total, fade: 0.3)
        root.addSublayer(ending)

        if watermark {
            let mark = VideoLayers.text("Trazo", font: VideoLayers.lato(36 * k, weight: 900), color: UIColor.white.withAlphaComponent(0.55))
            mark.frame.origin = CGPoint(x: render.width - mark.bounds.width - 40 * k, y: render.height - mark.bounds.height - 60 * k)
            root.addSublayer(mark)
        }
        return root
    }
}

/// Vídeo listo (s05): el vídeo a pantalla completa en bucle, "Vídeo listo, 12 s" y Guardar en Fotos,
/// Compartir y Editar.
struct TracerVideoResultView: View {
    let url: URL?
    var duration: Double = 0
    /// Capturas del CI: la imagen de demostración con el trazo dibujado encima, en vez del vídeo.
    var demo: (image: UIImage, edit: TracerEdit, videoSize: CGSize)? = nil
    var units = "m"
    let onEdit: () -> Void
    var onClose: () -> Void = {}
    @State private var message: String?

    var body: some View {
        ZStack {
            Color.escenario
            if let demo {
                GeometryReader { proxy in
                    // La imagen llena la pantalla (como el vídeo) y el trazo va en el mismo marco.
                    let scale = max(proxy.size.width / demo.videoSize.width, proxy.size.height / demo.videoSize.height)
                    let size = CGSize(width: demo.videoSize.width * scale, height: demo.videoSize.height * scale)
                    ZStack {
                        Image(uiImage: demo.image).resizable()
                        TracerStyledPath(curve: demo.edit.curve, videoSize: demo.videoSize,
                                         color: demo.edit.color.color(custom: Color(hex: UInt32(demo.edit.customColorHex))),
                                         label: demo.edit.distanceMeters.map { (club: demo.edit.clubName, distance: TracerEdit.distanceText($0, units: units)) })
                    }
                    .frame(width: size.width, height: size.height)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            } else if let url {
                LoopingVideo(url: url)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            HStack {
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 17, weight: .regular)) }
                    .buttonStyle(.crystal)
                    .accessibilityLabel("Cerrar")
                Spacer(minLength: 0)
                Chip(title: "Vídeo listo, \(SpanishFormat.number(duration, decimals: 0)) s", dotColor: .nivelado, surface: .video)
                Spacer(minLength: 0)
                Color.clear.frame(width: Size.glassButton, height: Size.glassButton)
            }
            .padding(.horizontal, Spacing.cardMargin)
            .padding(.top, Spacing.s)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: Spacing.m) {
                Button {
                    guard let url else { return }
                    Task {
                        do {
                            try await PhotoLibrary.saveVideo(at: url)
                            message = "Guardado en Fotos"
                        } catch {
                            message = "No se ha podido guardar: \(error.localizedDescription)"
                        }
                    }
                } label: {
                    tile("Guardar en Fotos", icon: "arrow.down.to.line", primary: true)
                }
                .frame(maxWidth: .infinity)
                if let url {
                    ShareLink(item: url) { tile("Compartir", icon: "square.and.arrow.up") }
                        .frame(width: 96)
                } else {
                    tile("Compartir", icon: "square.and.arrow.up").frame(width: 96)
                }
                Button(action: onEdit) { tile("Editar", icon: "slider.horizontal.3") }
                    .frame(width: 96)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.cardMargin)
            .padding(.bottom, Spacing.l)
        }
        .overlay(alignment: .bottom) { Toast(message: $message).padding(.bottom, 110) }
        .preferredColorScheme(.dark)
    }

    /// Botón alto de s05: icono encima del texto. El principal es blanco; los otros, de cristal.
    private func tile(_ title: String, icon: String, primary: Bool = false) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon).font(.system(size: 19, weight: .medium))
            Text(title).typeStyle(.boton).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(primary ? Color.pino : .white)
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .background {
            if primary {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(Color.papel)
            } else {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(.clear)
                    .glassEffect(.clear.tint(Color.pino.opacity(0.3)), in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
    }
}
