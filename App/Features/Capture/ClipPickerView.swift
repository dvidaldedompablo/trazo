import GolfCore
import SwiftUI
import UIKit

/// Elige los golpes (tras grabar con "Corte auto" o importar un vídeo con varios golpes):
/// la onda con los impactos y un clip por golpe para marcar los que se guardan.
struct ClipPickerView: View {
    let pending: PendingRecording
    /// Lo elegido. Ningún golpe y sin el vídeo entero = descartar.
    let onFinish: (_ selection: [Bool], _ keepFullRecording: Bool) -> Void

    @State private var selection: [Bool]
    @State private var keepFull = false

    init(pending: PendingRecording, onFinish: @escaping (_ selection: [Bool], _ keepFullRecording: Bool) -> Void) {
        self.pending = pending
        self.onFinish = onFinish
        _selection = State(initialValue: pending.windows.map(\.isSuggested))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Elige los golpes")
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
                ForEach(pending.windows.indices, id: \.self) { index in
                    ClipRow(number: index + 1, window: pending.windows[index], thumbnail: pending.thumbnails[index],
                            mode: pending.mode, isSelected: selection[index]) {
                        selection[index].toggle()
                    }
                }
                Toggle(isOn: $keepFull) { Text("Guardar también el vídeo entero") }
                    .toggleStyle(TrazoSwitchStyle())
                    .padding(.top, Spacing.xs)
                buttons
            }
            .padding(.horizontal, Spacing.cardMargin)
            .padding(.top, Spacing.xxl)
            .padding(.bottom, Spacing.l)
        }
        .background(Color.bola)
    }

    private var selectedCount: Int { selection.filter { $0 }.count }

    private var summary: String {
        let duration = SpanishFormat.number(pending.info.duration, decimals: 0)
        if !pending.info.hasAudio {
            return "Este vídeo no tiene sonido: no puedo buscar los golpes. Puedes guardarlo entero (\(duration) s)."
        }
        switch pending.windows.count {
        case 0: return "No se ha oído ningún golpe en \(duration) s. Puedes guardar el vídeo entero o descartarlo."
        case 1: return "He oído 1 golpe. Márcalo para guardarlo."
        default: return "He oído \(pending.windows.count) golpes. Marca los que quieres guardar."
        }
    }

    private var waveformPanel: some View {
        let markers = pending.windows.enumerated().map { offset, window in
            (index: Waveform.barIndex(for: window.impactTime, duration: pending.info.duration, count: pending.bars.count),
             label: "\(offset + 1)")
        }
        return VStack(alignment: .leading, spacing: Spacing.s) {
            WaveformView(bars: pending.bars, markers: markers)
                .frame(height: 76)
            HStack {
                Text("0:00")
                Spacer()
                Text(RecordScreen.clock(pending.info.duration))
            }
            .typeStyle(.nota)
            .monospacedDigit()
            .foregroundStyle(Color.texto3)
        }
        .padding(Spacing.l)
        .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }

    @ViewBuilder
    private var buttons: some View {
        let total = selectedCount + (keepFull ? 1 : 0)
        VStack(spacing: Spacing.m) {
            Button {
                onFinish(selection, keepFull)
            } label: {
                Text(saveTitle)
            }
            .buttonStyle(.principal)
            .disabled(total == 0)
            .opacity(total == 0 ? 0.5 : 1)
            Button {
                onFinish(selection.map { _ in false }, false)
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

/// Un golpe propuesto: miniatura en el instante del impacto, cuándo fue y si se guarda.
private struct ClipRow: View {
    let number: Int
    let window: ClipWindow
    let thumbnail: Data?
    let mode: CaptureMode
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
        .accessibilityLabel("Golpe \(number), \(detail)")
        .accessibilityValue(isSelected ? "Se guarda" : "No se guarda")
        .accessibilityAddTraits(.isToggle)
    }

    private var detail: String {
        var text = "A los \(RecordScreen.clock(window.impactTime)) · clip de \(SpanishFormat.number(window.duration)) s"
        if window.isTooShort { text += " · corto: falta margen antes o después" }
        return text
    }
}
