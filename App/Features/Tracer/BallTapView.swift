import AVFoundation
import GolfCore
import SwiftUI
import UIKit

/// Qué fotograma enseñar para tocar la bola.
struct BallTapRequest: Identifiable {
    let id = UUID()
    let url: URL
    /// Instante del clip por el que empezar (s).
    let time: Double
    let frameRate: Double
    /// Tamaño del vídeo girado (px), para pasar el toque a coordenadas del vídeo.
    let videoWidth: Int
    let videoHeight: Int
    let title: String
    let hint: String
}

/// Toca la bola (docs/03, pasos 3 y 4 bis): el fotograma lo más grande posible, pasos de fotograma
/// para elegir uno nítido y una lupa x3 bajo el dedo para tocar justo encima de la bola.
///
/// Como en s04, los controles van sobre el negro, por encima y por debajo del fotograma: así no tapan
/// la bola (que suele estar abajo) y el cristal no se parte entre el negro y el cielo.
struct BallTapView: View {
    let request: BallTapRequest
    /// Instante elegido (s del clip) y punto en píxeles del vídeo girado.
    let onPick: (_ time: Double, _ point: Point2D) -> Void
    /// Capturas del CI: imagen fija, con un toque y la lupa ya puestos.
    var demoImage: UIImage?

    @Environment(\.dismiss) private var dismiss
    @State private var time: Double
    @State private var image: UIImage?
    @State private var marker: Point2D?
    @State private var finger: CGPoint?
    @State private var isLoading = false

    init(request: BallTapRequest, demoImage: UIImage? = nil, onPick: @escaping (_ time: Double, _ point: Point2D) -> Void) {
        self.request = request
        self.demoImage = demoImage
        self.onPick = onPick
        _time = State(initialValue: request.time)
        _image = State(initialValue: demoImage)
        if demoImage != nil {
            // En la captura se ve el toque sobre la bola de la escena y la lupa encima.
            _marker = State(initialValue: Point2D(Double(request.videoWidth) * 0.836, Double(request.videoHeight) * 0.906))
        }
    }

    var body: some View {
        VStack(spacing: Spacing.m) {
            topBar
                .padding(.horizontal, Spacing.cardMargin)
            Text(request.hint)
                .typeStyle(.consejo)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.textMargin)
            frameArea
            bottomControls
                .padding(.horizontal, Spacing.cardMargin)
        }
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.l)
        .background(Color.escenario)
        .preferredColorScheme(.dark)
        .task(id: time) { await loadFrame() }
    }

    /// El fotograma encajado en el hueco que dejan los controles.
    private var frameArea: some View {
        GeometryReader { proxy in
            if let image {
                let fit = AVMakeRect(aspectRatio: image.size, insideRect: CGRect(origin: .zero, size: proxy.size))
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: fit.width, height: fit.height)
                        .position(x: fit.midX, y: fit.midY)
                    if let marker {
                        let p = viewPoint(marker, fit: fit)
                        Circle().stroke(Color.white, lineWidth: 2).frame(width: 22, height: 22).position(p)
                        Circle().fill(Color.rojoTrazo).frame(width: 5, height: 5).position(p)
                    }
                    if let loupeCenter = finger ?? (demoImage != nil ? marker.map { viewPoint($0, fit: fit) } : nil) {
                        Loupe(image: image, fit: fit, focus: loupeCenter)
                            .position(Self.loupePosition(for: loupeCenter, in: proxy.size))
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in finger = clamp(value.location, to: fit) }
                    .onEnded { value in
                        marker = videoPoint(clamp(value.location, to: fit), fit: fit)
                        finger = nil
                    })
            }
        }
        .overlay { if isLoading { ProgressView().tint(.white) } }
    }

    private var topBar: some View {
        HStack(spacing: Spacing.s) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 17, weight: .regular)) }
                .buttonStyle(.crystal)
                .accessibilityLabel("Cerrar")
            Spacer(minLength: 0)
            Chip(title: request.title, systemImage: "scope", surface: .video)
            Spacer(minLength: 0)
            Color.clear.frame(width: Size.glassButton, height: Size.glassButton)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.crystal)
                    .accessibilityLabel("Fotograma anterior")
                Chip(title: "Fotograma \(Int((time * request.frameRate).rounded()))", surface: .video)
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.crystal)
                    .accessibilityLabel("Fotograma siguiente")
            }
            Button {
                guard let marker else { return }
                onPick(time, marker)
                dismiss()
            } label: {
                Text(marker == nil ? "Toca la bola en la imagen" : "Usar este punto")
            }
            .buttonStyle(.principal)
            .disabled(marker == nil)
            .opacity(marker == nil ? 0.6 : 1)
        }
    }

    /// La lupa va 100 pt por encima del dedo (si no cabe, por debajo) y sin salirse por los lados.
    private static func loupePosition(for focus: CGPoint, in size: CGSize) -> CGPoint {
        let radius = Loupe.diameter / 2
        let y = focus.y - 100 >= radius ? focus.y - 100 : focus.y + 100
        let x = min(max(focus.x, radius), max(size.width - radius, radius))
        return CGPoint(x: x, y: y)
    }

    private func step(_ frames: Int) {
        time = max(time + Double(frames) / request.frameRate, 0)
        marker = nil
    }

    private func loadFrame() async {
        guard demoImage == nil else { return }
        isLoading = true
        defer { isLoading = false }
        if let data = try? await FrameGrabber.jpeg(from: request.url, at: time) {
            image = UIImage(data: data)
        }
    }

    /// De píxeles del vídeo a puntos de la pantalla (y al revés), con la imagen encajada en `fit`.
    private func viewPoint(_ point: Point2D, fit: CGRect) -> CGPoint {
        CGPoint(x: fit.minX + CGFloat(point.x) / CGFloat(request.videoWidth) * fit.width,
                y: fit.minY + CGFloat(point.y) / CGFloat(request.videoHeight) * fit.height)
    }

    private func videoPoint(_ point: CGPoint, fit: CGRect) -> Point2D {
        Point2D(Double((point.x - fit.minX) / fit.width) * Double(request.videoWidth),
                Double((point.y - fit.minY) / fit.height) * Double(request.videoHeight))
    }

    private func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, rect.minX), rect.maxX), y: min(max(point.y, rect.minY), rect.maxY))
    }
}

/// Lupa x3: un círculo con la imagen ampliada y el punto bajo el dedo en el centro.
private struct Loupe: View {
    let image: UIImage
    let fit: CGRect
    let focus: CGPoint
    static let diameter: CGFloat = 120
    static let zoom: CGFloat = 3

    var body: some View {
        let d = Self.diameter, z = Self.zoom
        Image(uiImage: image)
            .resizable()
            .frame(width: fit.width * z, height: fit.height * z)
            // El punto enfocado de la imagen ampliada queda en el centro del círculo.
            .position(x: d / 2 + (fit.midX - focus.x) * z, y: d / 2 + (fit.midY - focus.y) * z)
            .frame(width: d, height: d)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .overlay {
                // Cruz fina en el centro: ahí cae el toque.
                ZStack {
                    Rectangle().fill(Color.white).frame(width: 14, height: 1)
                    Rectangle().fill(Color.white).frame(width: 1, height: 14)
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
            .accessibilityHidden(true)
    }
}
