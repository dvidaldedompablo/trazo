import GolfCore
import SwiftUI
import UIKit

/// Elige los golpes (tras grabar con "Corte auto" o importar un vídeo con varios golpes):
/// la onda con los impactos y un clip por golpe para marcar los que se guardan.
///
/// Con la clave de Gemini en Ajustes aparece "Comprobar con Gemini" (docs/10, Fase 4): tras un aviso,
/// el verificador de golpes mira los fotogramas de cada sonido fuerte y la lista se rehace con lo que
/// dice. Si falla, la lista se queda como la dejó el corte automático (el plan B).
struct ClipPickerView: View {
    let pending: PendingRecording
    /// Los clips elegidos. Ninguno y sin el vídeo entero = descartar.
    let onFinish: (_ chosen: [ClipWindow], _ keepFullRecording: Bool) -> Void

    @State private var windows: [ClipWindow]
    @State private var thumbnails: [Data?]
    @State private var selection: [Bool]
    /// Lo que dijo Gemini de cada clip; `nil` si no se ha comprobado.
    @State private var outcomes: [ShotCheck.Outcome]? = nil
    @State private var keepFull = false
    @State private var check: CheckState = .idle
    @State private var asksToSend = false
    /// "Comprobar siempre, sin preguntar" (Ajustes): el permiso para siempre que dio el usuario.
    @AppStorage(SettingsKey.geminiAlwaysCheck) private var alwaysCheck = true
    @State private var hasKey: Bool
    /// El usuario dijo "Cancelar" en el aviso: se enseña la lista por sonido (plan B).
    @State private var declined = false

    enum CheckState: Equatable {
        case idle
        case running
        case done(String)
        case failed(String)
    }

    /// - Parameter demoCheck: para las capturas del CI, la hoja ya comprobada sin red.
    init(pending: PendingRecording, demoCheck: ShotChecker.Result? = nil,
         onFinish: @escaping (_ chosen: [ClipWindow], _ keepFullRecording: Bool) -> Void) {
        self.pending = pending
        self.onFinish = onFinish
        // Se lee ya al abrir: con clave, la lista por sonido no llega a enseñarse (el usuario la quiere
        // siempre comprobada con Gemini, 22-11-2026).
        _hasKey = State(initialValue: demoCheck == nil && KeychainStore.geminiKey != nil)
        if let demoCheck {
            _windows = State(initialValue: demoCheck.checked.windows)
            _thumbnails = State(initialValue: demoCheck.thumbnails)
            _selection = State(initialValue: demoCheck.checked.selected)
            _outcomes = State(initialValue: demoCheck.checked.outcomes)
            _check = State(initialValue: .done(Self.checkSummary(demoCheck)))
        } else {
            _windows = State(initialValue: pending.windows)
            _thumbnails = State(initialValue: pending.thumbnails)
            // Si no parece una tanda de golpes no hay nada propuesto (ni se enseña la lista).
            _selection = State(initialValue: pending.windows.map { pending.isShotSeries && $0.isSuggested })
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text(showsClips ? "Elige los golpes" : "¿Guardar el vídeo?")
                        .typeStyle(.tituloPantalla)
                        .foregroundStyle(Color.pino)
                        .accessibilityAddTraits(.isHeader)
                    Text(summary)
                        .typeStyle(.sub)
                        .foregroundStyle(Color.texto2)
                }
                if pending.mayBeStretched {
                    Label("Sin acceso a Fotos, un vídeo a cámara lenta llega con la cámara lenta aplicada y las duraciones pueden salir mal.",
                          systemImage: "exclamationmark.triangle")
                        .typeStyle(.nota)
                        .foregroundStyle(Color.texto2)
                }
                waveformPanel
                if canCheck {
                    checkPanel
                }
                if waitingForGemini {
                    // Mientras se espera el permiso o la respuesta, solo se puede descartar.
                    Button {
                        onFinish([], false)
                    } label: {
                        Text("Descartar")
                    }
                    .buttonStyle(.secundario)
                    .padding(.top, Spacing.s)
                } else if showsClips {
                    ForEach(windows.indices, id: \.self) { index in
                        ClipRow(number: index + 1, window: windows[index], thumbnail: thumbnails[safe: index] ?? nil,
                                mode: pending.mode, outcome: outcomes?[safe: index], isSelected: selection[index]) {
                            selection[index].toggle()
                        }
                    }
                    Toggle(isOn: $keepFull) { Text("Guardar también el vídeo entero") }
                        .toggleStyle(TrazoSwitchStyle())
                        .padding(.top, Spacing.xs)
                    buttons
                } else {
                    wholeVideoButtons
                }
            }
            .padding(.horizontal, Spacing.cardMargin)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.l)
        }
        .background(Color.bola)
        .task {
            // Con clave, el aviso sale solo al abrir la hoja: un toque en "Enviar" y se comprueba.
            // Un instante después de abrir: presentar el aviso a la vez que la hoja puede fallar.
            guard waitingForGemini, check == .idle else { return }
            if alwaysCheck {
                startCheck()
            } else {
                try? await Task.sleep(for: .milliseconds(500))
                asksToSend = true
            }
        }
        // El aviso de CLAUDE.md: antes de enviar nada, el usuario lo acepta.
        .alert("¿Enviar a Google?", isPresented: $asksToSend) {
            Button("Enviar") { startCheck() }
            Button("Cancelar", role: .cancel) { declined = true }
        } message: {
            let n = ShotChecker.soundCount(pending)
            Text("Se envían \(n == 1 ? "1 hoja" : "\(n) hojas") con fotogramas de este vídeo a Gemini (Google), con tu clave, para ver qué sonidos son golpes. No se envía el vídeo entero ni el sonido.")
        }
    }

    private var selectedCount: Int { selection.filter { $0 }.count }

    /// Hay golpes que proponer: los del corte automático (si parece una tanda de golpes) o los que
    /// ha confirmado Gemini aunque el corte automático no los propusiera.
    private var showsClips: Bool { !windows.isEmpty && (pending.isShotSeries || outcomes != nil) && !waitingForGemini }

    /// Se puede comprobar con Gemini: hay sonido y algún sonido fuerte.
    private var canCheck: Bool { pending.info.hasAudio && !pending.impacts.isEmpty }

    /// Con clave, la lista no se enseña hasta que Gemini conteste (o el usuario cancele, o falle).
    private var waitingForGemini: Bool {
        check == .running || (hasKey && canCheck && outcomes == nil && check == .idle && !declined)
    }

    private var summary: String {
        let duration = SpanishFormat.number(pending.info.duration, decimals: 0)
        if !pending.info.hasAudio {
            return "Este vídeo no tiene sonido: no puedo buscar los golpes. Puedes guardarlo entero (\(duration) s)."
        }
        if check == .running {
            return "Gemini está mirando los fotogramas de cada sonido fuerte para decirte cuáles son golpes."
        }
        if waitingForGemini {
            return "Gemini va a mirar los fotogramas de cada sonido fuerte para decirte cuáles son golpes."
        }
        if outcomes != nil {
            switch windows.count {
            case 0: return "Ningún sonido es un golpe. Puedes guardar el vídeo entero o descartarlo."
            case 1: return "Marca el golpe para guardarlo."
            default: return "Marca los golpes que quieres guardar."
            }
        }
        if !pending.isShotSeries {
            // Control de sensatez: muchos sonidos secos seguidos (una voz, aplausos) no son golpes.
            return "No he reconocido una tanda de golpes en este vídeo. Puedes guardar el vídeo entero o descartarlo."
        }
        switch windows.count {
        case 0: return "No se ha oído ningún golpe en \(duration) s. Puedes guardar el vídeo entero o descartarlo."
        case 1: return "He oído 1 golpe. Márcalo para guardarlo."
        default: return "He oído \(windows.count) golpes. Marca los que quieres guardar."
        }
    }

    private var waveformPanel: some View {
        // Los golpes propuestos, en rojo en la onda. Si no es una tanda de golpes, ninguno; y tampoco
        // los que Gemini dice que no son golpes (o que son el mismo swing que otro).
        let shown = windows.indices.filter { index in
            guard let outcome = outcomes?[safe: index] else { return true }
            return outcome == .confirmed || outcome == .unknown
        }
        let highlighted = showsClips
            ? Set(shown.map { Waveform.barIndex(for: windows[$0].impactTime, duration: pending.info.duration, count: pending.bars.count) })
            : []
        return WaveformView(bars: pending.bars, highlighted: highlighted, duration: pending.info.duration)
            .frame(height: 86)
            .padding(Spacing.l)
        .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }

    // MARK: Comprobar con Gemini

    private var checkPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "sparkle.magnifyingglass").accessibilityHidden(true)
                Text("Comprobar con Gemini").typeStyle(.etiqueta)
            }
            .foregroundStyle(Color.pino)
            switch check {
            case .idle:
                if hasKey {
                    Text("¿No te fías del sonido? Gemini mira los fotogramas de cada sonido fuerte y dice cuáles son golpes.")
                        .typeStyle(.nota)
                        .foregroundStyle(Color.texto2)
                    Button { asksToSend = true } label: { Text("Comprobar los golpes") }
                        .buttonStyle(.secundario)
                } else {
                    Text("Si pones tu clave de Gemini en Ajustes, puedo comprobar qué sonidos son golpes mirando los fotogramas.")
                        .typeStyle(.nota)
                        .foregroundStyle(Color.texto2)
                }
            case .running:
                HStack(spacing: Spacing.s) {
                    ProgressView()
                    Text("Comprobando \(ShotChecker.soundCount(pending)) sonidos con Gemini…")
                        .typeStyle(.nota)
                        .foregroundStyle(Color.texto2)
                }
            case .done(let text):
                Text(text)
                    .typeStyle(.nota)
                    .foregroundStyle(Color.texto2)
            case .failed(let text):
                Text(text + " Te propongo los golpes como siempre, solo por el sonido.")
                    .typeStyle(.nota)
                    .foregroundStyle(Color.texto2)
                if hasKey {
                    Button {
                        if alwaysCheck { startCheck() } else { asksToSend = true }
                    } label: { Text("Volver a intentarlo") }
                        .buttonStyle(.secundario)
                }
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }

    private func startCheck() {
        guard let key = KeychainStore.geminiKey else {
            hasKey = false
            return
        }
        check = .running
        Task {
            do {
                let result = try await ShotChecker.check(pending, key: key)
                windows = result.checked.windows
                thumbnails = result.thumbnails
                selection = result.checked.selected
                outcomes = result.checked.outcomes
                check = .done(Self.checkSummary(result))
            } catch {
                // Plan B: la lista sigue como la dejó el corte automático.
                check = .failed((error as? LocalizedError)?.errorDescription ?? "No se ha podido comprobar.")
            }
        }
    }

    static func checkSummary(_ result: ShotChecker.Result) -> String {
        let confirmed = result.checked.confirmedCount
        let discarded = result.checked.discardedCount
        let sounds = result.sounds == 1 ? "1 sonido" : "\(result.sounds) sonidos"
        let rest = discarded == 0 ? "" : (discarded == 1 ? " 1 sonido no era un golpe." : " \(discarded) sonidos no eran golpes.")
        switch confirmed {
        case 0: return "Gemini ha mirado \(sounds) y no ve ningún golpe."
        case 1: return "Gemini ha mirado \(sounds) y ve 1 golpe: el clip lleva el vídeo que le toca." + rest
        default: return "Gemini ha mirado \(sounds) y ve \(confirmed) golpes: el vídeo se reparte en un clip por golpe." + rest
        }
    }

    // MARK: Botones

    @ViewBuilder
    private var buttons: some View {
        let total = selectedCount + (keepFull ? 1 : 0)
        VStack(spacing: Spacing.m) {
            Button {
                onFinish(chosen, keepFull)
            } label: {
                Text(saveTitle)
            }
            .buttonStyle(.principal)
            .disabled(total == 0 || check == .running)
            .opacity(total == 0 ? 0.5 : 1)
            Button {
                onFinish([], false)
            } label: {
                Text("Descartar")
            }
            .buttonStyle(.secundario)
        }
        .padding(.top, Spacing.s)
    }

    private var chosen: [ClipWindow] {
        zip(windows, selection).filter(\.1).map(\.0)
    }

    /// Sin golpes que proponer: guardar el vídeo entero o descartarlo.
    private var wholeVideoButtons: some View {
        VStack(spacing: Spacing.m) {
            Button {
                onFinish([], true)
            } label: {
                Text("Guardar el vídeo entero")
            }
            .buttonStyle(.principal)
            .disabled(check == .running)
            Button {
                onFinish([], false)
            } label: {
                Text("Descartar")
            }
            .buttonStyle(.secundario)
        }
        .padding(.top, Spacing.s)
    }

    private var saveTitle: String {
        switch (selectedCount, keepFull) {
        case (0, true): "Guardar el vídeo entero"
        case (0, false): "Guardar"
        case (1, false): "Guardar 1 golpe"
        case (let n, false): "Guardar \(n) golpes"
        case (1, true): "Guardar 1 golpe y el vídeo"
        case (let n, true): "Guardar \(n) golpes y el vídeo"
        }
    }
}

/// Un golpe propuesto: miniatura en el instante del impacto, cuándo fue, qué dijo Gemini y si se guarda.
private struct ClipRow: View {
    let number: Int
    let window: ClipWindow
    let thumbnail: Data?
    let mode: CaptureMode
    let outcome: ShotCheck.Outcome?
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Spacing.m) {
                Group {
                    if let thumbnail, let image = UIImage(data: thumbnail) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Color.niebla
                    }
                }
                .frame(width: 48, height: 85)
                .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnailSmall, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Golpe \(number)")
                        .typeStyle(.filaTitulo)
                        .foregroundStyle(Color.pino)
                    Text(detail)
                        .typeStyle(.filaSub)
                        .foregroundStyle(Color.texto2)
                    if let outcome {
                        HStack(spacing: Spacing.xs + 2) {
                            Circle().fill(Self.color(outcome))
                                .frame(width: Size.chipDot, height: Size.chipDot)
                                .accessibilityHidden(true)
                            Text(Self.text(outcome))
                                .typeStyle(.filaSub)
                                .foregroundStyle(Color.texto2)
                        }
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: Spacing.s)
                ZStack {
                    if isSelected {
                        Circle().fill(Color.pino)
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    } else {
                        Circle().strokeBorder(Color.linea, lineWidth: 2)
                    }
                }
                .frame(width: 26, height: 26)
            }
            .padding(Spacing.m)
            .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Golpe \(number), \(detail)" + (outcome.map { ", \(Self.text($0))" } ?? ""))
        .accessibilityValue(isSelected ? "Se guarda" : "No se guarda")
        .accessibilityAddTraits(.isToggle)
    }

    private var detail: String {
        var text = "A los \(RecordScreen.clock(window.impactTime)) · clip de \(SpanishFormat.number(window.duration)) s"
        if window.isTooShort {
            text += mode == .tracer ? " · corto: le falta parte del vuelo" : " · corto: le falta parte del swing"
        }
        return text
    }

    static func text(_ outcome: ShotCheck.Outcome) -> String {
        switch outcome {
        case .confirmed: "Gemini: es un golpe"
        case .rejected: "Gemini: no es un golpe"
        case .unknown: "Gemini: no lo tiene claro"
        case .sameSwing: "Gemini: es el mismo swing que otro"
        }
    }

    static func color(_ outcome: ShotCheck.Outcome) -> Color {
        switch outcome {
        case .confirmed: .bien
        case .rejected: .rojoTrazo
        case .unknown, .sameSwing: .texto3
        }
    }
}

extension Array {
    /// El elemento en `index`, o `nil` si se sale de la lista.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
