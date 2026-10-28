import GolfCore
import SwiftData
import SwiftUI
import UIKit

/// Grabar (s02): la cámara a pantalla completa con las guías del modo, el nivel, la cuenta atrás,
/// el botón de grabar, la miniatura del último clip y "Corte auto".
struct RecordScreen: View {
    let mode: CaptureMode
    /// Ir a otra pantalla (Tus vídeos, Elegir vídeo): la cámara se cierra y se abre en Inicio.
    var navigate: (HomeDestination) -> Void = { _ in }

    @State private var model: RecordModel
    @State private var level = LevelMonitor()
    @State private var tipHidden = false

    @AppStorage(SettingsKey.captureFrameRate) private var frameRate = 240
    @AppStorage(SettingsKey.captureCountdown) private var countdown = 0
    @AppStorage(SettingsKey.captureAutoCut) private var autoCut = true
    @AppStorage(SettingsKey.tracerFastShutter) private var fastShutter = true
    @AppStorage(SettingsKey.diagnostics) private var diagnostics = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Clip.createdAt, order: .reverse) private var clips: [Clip]

    init(mode: CaptureMode, navigate: @escaping (HomeDestination) -> Void = { _ in }) {
        self.mode = mode
        self.navigate = navigate
        _model = State(initialValue: RecordModel(mode: mode, demo: UITestHarness.isActive))
    }

    var body: some View {
        ZStack {
            Color.escenario
            cameraLayer
            CaptureShade()
            if model.camera == .running || model.camera == .demo {
                DesignSpace {
                    ZStack(alignment: .topLeading) {
                        if mode == .tracer { TracerGuides() } else { SwingGuides() }
                        LevelIndicator(roll: isDemo ? 0 : level.roll, isLevel: isDemo || level.isLevel)
                    }
                }
                .allowsHitTesting(false)
            }
            overlays
        }
        .ignoresSafeArea()
        // Pantalla de vídeo: negro puro y barra de estado clara (docs/02). Grabar se presenta
        // a pantalla completa, así que este esquema vale solo para ella.
        .preferredColorScheme(.dark)
        .sheet(item: $model.pending) { pending in
            ClipPickerView(pending: pending) { selection, keepFull in
                model.finishChoosing(selection: selection, keepFullRecording: keepFull)
            }
            .preferredColorScheme(.light)
            .interactiveDismissDisabled()
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.phase)
        .task {
            model.context = modelContext
            guard !isDemo else { return }
            // Que la pantalla no se apague con el móvil en el trípode.
            UIApplication.shared.isIdleTimerDisabled = true
            level.start()
            await model.start(frameRate: frameRate)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            level.stop()
            model.stop()
        }
        .onChange(of: frameRate) { _, newValue in
            Task { await model.changeFrameRate(newValue) }
        }
        .task(id: model.message) {
            // Los avisos cortos se van solos a los 3 s.
            guard model.message != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            model.message = nil
        }
    }

    private var isDemo: Bool { model.camera == .demo }

    private func pickVideo() {
        navigate(mode == .tracer ? .pickShotVideo : .pickSwingVideo)
    }

    // MARK: Imagen

    @ViewBuilder
    private var cameraLayer: some View {
        switch model.camera {
        case .demo:
            DesignSpace { DemoCameraBackground(showsBall: mode == .tracer) }
        case .running, .starting:
            if let controller = model.controller {
                CameraPreview(session: controller.session)
            }
        case .denied:
            CameraProblem(title: "Trazo no puede usar la cámara",
                          detail: "Para grabar tus golpes, permite la cámara en Ajustes > Trazo. También puedes elegir un vídeo de Fotos.",
                          showsSettings: true, pickVideo: pickVideo)
        case let .unavailable(detail):
            CameraProblem(title: "La cámara no está disponible", detail: detail, showsSettings: false, pickVideo: pickVideo)
        }
    }

    // MARK: Controles

    private var overlays: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                    .padding(.top, CaptureLayout.topBarTop)
                    .padding(.horizontal, CaptureLayout.topBarMargin)
                if model.camera == .running || isDemo {
                    VStack(spacing: Spacing.s) {
                        if !tipHidden { tip }
                        if !model.hasMicrophone {
                            Chip(title: "Sin micrófono: no habrá corte automático", systemImage: "mic.slash", surface: .video)
                        }
                        if diagnostics { diagnosticsPanel }
                    }
                    .padding(.top, CaptureLayout.tipTop - CaptureLayout.topBarTop - Size.glassButton)
                    .padding(.horizontal, CaptureLayout.tipMargin)
                }
                Spacer()
                if model.camera == .running || isDemo {
                    bottomBar
                        .padding(.horizontal, CaptureLayout.controlsMargin)
                        .padding(.bottom, CaptureLayout.controlsBottom)
                }
            }
            if case let .countdown(remaining) = model.phase {
                Text("\(remaining)")
                    .typeStyle(.displayXL)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 8)
                    .accessibilityLabel("Empieza en \(remaining)")
            }
            if model.phase == .analyzing || model.phase == .saving {
                busyOverlay
            }
            if let message = model.message {
                VStack {
                    Spacer()
                    Text(message)
                        .typeStyle(.chip)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.l)
                        .padding(.vertical, Spacing.s + 2)
                        .glassEffect(.regular.tint(Color.pino.opacity(0.6)), in: Capsule())
                        .padding(.bottom, CaptureLayout.controlsBottom + CaptureLayout.recordButton + Spacing.l)
                }
                .transition(.opacity)
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: Spacing.s) {
            Button { dismiss() } label: {
                // Más fina que el resto de iconos, como la de la maqueta.
                Image(systemName: "xmark").font(.system(size: 17, weight: .regular))
            }
            .buttonStyle(.crystal)
                .accessibilityLabel("Cerrar")
                .disabled(model.isBusy)
            Spacer(minLength: 0)
            Chip(title: mode.title, dotColor: mode == .tracer ? .rojoTrazo : .amarillo, surface: .video)
            frameRateMenu
            Spacer(minLength: 0)
            counter
        }
    }

    /// fps: 240, o 120 con poca luz (Ayuda). Si el iPhone no llega, el chip enseña los que consiguió.
    private var frameRateMenu: some View {
        Menu {
            Picker("Fotogramas por segundo", selection: $frameRate) {
                Text("240 fps").tag(240)
                Text("120 fps").tag(120)
                Text("60 fps").tag(60)
            }
        } label: {
            Chip(title: "\(model.configuration?.frameRate ?? frameRate) fps", surface: .video)
        }
        .disabled(model.isBusy)
        .accessibilityLabel("Fotogramas por segundo: \(model.configuration?.frameRate ?? frameRate)")
    }

    /// Contador de la grabación. Parado, al tocarlo se elige la cuenta atrás.
    @ViewBuilder
    private var counter: some View {
        if model.phase == .recording, let start = model.recordingStart {
            TimelineView(.periodic(from: start, by: 0.25)) { timeline in
                Chip(title: Self.clock(timeline.date.timeIntervalSince(start)), dotColor: .rojoTrazo, surface: .video)
            }
            .accessibilityLabel("Grabando")
        } else {
            Menu {
                Picker("Cuenta atrás", selection: $countdown) {
                    Text("Sin cuenta atrás").tag(0)
                    Text("3 s").tag(3)
                    Text("5 s").tag(5)
                    Text("10 s").tag(10)
                }
            } label: {
                if countdown > 0 {
                    Chip(title: "\(countdown) s", systemImage: "timer", surface: .video)
                } else {
                    Chip(title: "0:00", surface: .video)
                }
            }
            .disabled(model.isBusy)
            .accessibilityLabel(countdown > 0 ? "Cuenta atrás de \(countdown) segundos" : "Sin cuenta atrás")
        }
    }

    /// Consejo de dónde poner el móvil. Al tocarlo se esconde.
    private var tip: some View {
        Text(mode == .tracer
             ? "Apoya el móvil detrás de ti, en la línea del golpe y a la altura de las manos. Deja cielo por encima de la bola."
             : "Apoya el móvil detrás de ti, a 3 o 4 m y a la altura de las manos. Que se te vea entero, con el palo arriba.")
            .typeStyle(.consejo)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CaptureLayout.tipPaddingH)
            .padding(.vertical, CaptureLayout.tipPaddingV)
            .glassEffect(.regular.tint(Color.pino.opacity(0.45)),
                         in: RoundedRectangle(cornerRadius: CaptureLayout.tipRadius, style: .continuous))
            .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { tipHidden = true } }
            .accessibilityHint("Toca para esconder el consejo")
    }

    private var diagnosticsPanel: some View {
        let configuration = model.configuration
        let lines = [
            configuration.map { "\($0.width) x \($0.height) · \($0.frameRate) fps · \($0.pixelFormat)" } ?? "Sin formato",
            "Audio: \(configuration?.hasAudio == true ? "sí" : "no") · Nivel: \(SpanishFormat.number(level.roll, decimals: 1))°",
            "Exposición: \(model.exposure ?? (mode == .tracer && fastShutter ? "rápida al grabar" : "automática"))",
        ]
        return Text(lines.joined(separator: "\n"))
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.s)
            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: Radius.thumbnailSmall))
    }

    private var bottomBar: some View {
        HStack {
            lastClipThumbnail
            Spacer()
            RecordButton(isRecording: model.phase == .recording, color: mode == .tracer ? .rojoTrazo : .amarillo) {
                model.recordButtonTapped(countdown: countdown, autoCut: autoCut, fastShutter: fastShutter)
            }
            .disabled(model.phase == .analyzing || model.phase == .saving)
            Spacer()
            Button {
                autoCut.toggle()
            } label: {
                Chip(title: "Corte auto", systemImage: autoCut ? "waveform" : "waveform.slash", surface: .video,
                     height: CaptureLayout.autoCutHeight)
                    .opacity(autoCut && model.hasMicrophone ? 1 : 0.55)
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy || !model.hasMicrophone)
            .accessibilityLabel("Corte automático")
            .accessibilityValue(autoCut && model.hasMicrophone ? "Activado" : "Desactivado")
        }
    }

    /// Miniatura del último clip de este modo; al tocarla se abre "Tus vídeos".
    private var lastClipThumbnail: some View {
        Button { navigate(.library) } label: {
            Group {
                if let image = lastThumbnail {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.pino.opacity(0.42)
                }
            }
            .frame(width: CaptureLayout.thumbnail, height: CaptureLayout.thumbnail)
            .clipShape(RoundedRectangle(cornerRadius: CaptureLayout.thumbnailRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CaptureLayout.thumbnailRadius, style: .continuous)
                .inset(by: -1).stroke(Color.white, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .accessibilityLabel("Tus vídeos")
    }

    private var lastThumbnail: UIImage? {
        if isDemo { return UIImage(named: mode == .tracer ? "escena_tracer" : "escena_swing") }
        return Thumbnailer.load(named: clips.first { $0.mode == mode }?.thumbnailName)
    }

    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: Spacing.m) {
                ProgressView().tint(.white).controlSize(.large)
                Text(model.phase == .saving ? "Guardando los clips…" : "Buscando los golpes…")
                    .typeStyle(.cuerpo)
                    .foregroundStyle(.white)
            }
        }
    }

    /// "1:05" a partir de segundos.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let rest = total % 60
        return "\(total / 60):\(rest < 10 ? "0" : "")\(rest)"
    }
}

/// El botón de grabar de 78 pt: aro blanco y círculo de color; grabando, un cuadrado para parar.
private struct RecordButton: View {
    let isRecording: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(Color.white, lineWidth: CaptureLayout.recordRing)
                RoundedRectangle(cornerRadius: isRecording ? 8 : CaptureLayout.recordInner / 2, style: .continuous)
                    .fill(color)
                    .frame(width: isRecording ? 30 : CaptureLayout.recordInner, height: isRecording ? 30 : CaptureLayout.recordInner)
            }
            .frame(width: CaptureLayout.recordButton, height: CaptureLayout.recordButton)
            .contentShape(Circle())
            .animation(.spring(duration: 0.25), value: isRecording)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Parar" : "Grabar")
    }
}

/// Lo que se ve si no hay cámara: qué pasa y qué hacer.
private struct CameraProblem: View {
    let title: String
    let detail: String
    let showsSettings: Bool
    let pickVideo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Image(systemName: "camera")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .accessibilityHidden(true)
            Text(title)
                .typeStyle(.tituloTarjeta)
                .foregroundStyle(.white)
            Text(detail)
                .typeStyle(.sub)
                .foregroundStyle(.white.opacity(0.72))
            HStack(spacing: Spacing.m) {
                if showsSettings {
                    Button("Abrir Ajustes") { Permissions.openSettings() }
                        .buttonStyle(CrystalButtonStyle(outline: .capsule))
                }
                Button(action: pickVideo) {
                    Label("Elegir vídeo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(CrystalButtonStyle(outline: .capsule))
            }
            .padding(.top, Spacing.s)
        }
        .padding(.horizontal, Spacing.textMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Medidas de Grabar sacadas de `design/maqueta.html` (puntos, pantalla de 390 x 844).
enum CaptureLayout {
    /// Barra superior a 56 pt del borde de arriba, con 16 pt a los lados.
    static let topBarTop: CGFloat = 56
    static let topBarMargin: CGFloat = 16
    /// Consejo a 112 pt del borde de arriba, con 20 pt a los lados.
    static let tipTop: CGFloat = 112
    static let tipMargin: CGFloat = 20
    static let tipRadius: CGFloat = 18
    static let tipPaddingV: CGFloat = 12
    static let tipPaddingH: CGFloat = 14
    /// Controles de abajo: a 44 pt del borde, con 24 pt a los lados.
    static let controlsBottom: CGFloat = 44
    static let controlsMargin: CGFloat = 24
    /// Botón de grabar: 78 pt, aro de 4 pt y círculo de 62 pt.
    static let recordButton: CGFloat = 78
    static let recordRing: CGFloat = 4
    static let recordInner: CGFloat = 62
    /// Miniatura del último clip: 46 pt con radio 12 y aro blanco de 2 pt.
    static let thumbnail: CGFloat = 46
    static let thumbnailRadius: CGFloat = 12
    /// Chip "Corte auto", algo más alto que los demás.
    static let autoCutHeight: CGFloat = 36
}
