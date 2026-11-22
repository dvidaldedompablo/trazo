import AVFoundation
import GolfCore
import SwiftUI
import UIKit

/// Ejercicios (Fase 3 de los cambios del análisis, 22-11-2026): la lista de fallos que el análisis
/// puede ver con la cámara de detrás y, al tocar uno, su ejercicio con el clip en bucle.
/// Los textos y las rutas salen de `ExerciseCatalog` (GolfCore); los archivos, de `assets/ejercicios`
/// (dentro de la app, en la carpeta "ejercicios"): cambiar un clip no exige tocar código.
struct ExercisesView: View {
    private let shown = ExerciseCatalog.shown(camera: .behind)
    private let notYet = ExerciseCatalog.all.filter { !$0.isMeasurable(with: .behind) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Ejercicios")
                        .typeStyle(.tituloPantalla)
                        .foregroundStyle(Color.pino)
                        .accessibilityAddTraits(.isHeader)
                    Text("Un ejercicio para cada fallo que el análisis puede ver en tu vídeo.")
                        .typeStyle(.sub)
                        .foregroundStyle(Color.texto2)
                }
                VStack(spacing: Spacing.s) {
                    ForEach(shown) { exercise in
                        NavigationLink(value: HomeDestination.exercise(exercise.id)) {
                            ExerciseRow(exercise: exercise)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !notYet.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Todavía no se pueden ver desde detrás")
                            .typeStyle(.etiqueta)
                            .foregroundStyle(Color.texto2)
                        Text(notYet.map(\.fault).joined(separator: " · "))
                            .typeStyle(.nota)
                            .foregroundStyle(Color.texto3)
                    }
                    .padding(.top, Spacing.s)
                }
                Text("Son consejos generales, sin revisar por un profesor. Si tienes dudas, enséñale el ejercicio.")
                    .typeStyle(.nota)
                    .foregroundStyle(Color.texto3)
            }
            .padding(.horizontal, Spacing.cardMargin)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.bola)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Una fila: imagen, número y nombre del fallo y el ejercicio en una línea.
private struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: Spacing.m) {
            ExerciseImage(exercise: exercise)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnailSmall, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(exercise.number). \(exercise.fault)")
                    .typeStyle(.filaTitulo)
                    .foregroundStyle(Color.pino)
                    .multilineTextAlignment(.leading)
                Text(exercise.exercise)
                    .typeStyle(.filaSub)
                    .foregroundStyle(Color.texto2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: Spacing.s)
            Image(systemName: "chevron.right")
                .foregroundStyle(Color.texto3)
        }
        .padding(Spacing.m)
        .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
    }
}

/// El detalle: clip en bucle, qué se ve, el ejercicio y lo que hay que sentir, en palabras llanas.
struct ExerciseDetailView: View {
    let exercise: Exercise

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("Ejercicio \(exercise.number)")
                        .typeStyle(.etiqueta)
                        .foregroundStyle(Color.texto2)
                    Text(exercise.fault)
                        .typeStyle(.tituloPantalla)
                        .foregroundStyle(Color.pino)
                        .accessibilityAddTraits(.isHeader)
                    Chip(title: "Se ve: \(exercise.camera.title.lowercased())", systemImage: "video")
                }
                ExerciseClip(exercise: exercise)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
                section("El ejercicio", exercise.exercise, strong: true)
                HStack(alignment: .top, spacing: Spacing.m) {
                    fact("Necesitas", exercise.equipment)
                    fact("Repeticiones", exercise.repetitions)
                }
                section("Qué se ve en tu vídeo", exercise.whatYouSee)
                section("Qué debes sentir", exercise.feeling)
                section("Error típico", exercise.typicalMistake)
                Text("Consejo general, sin revisar por un profesor.")
                    .typeStyle(.nota)
                    .foregroundStyle(Color.texto3)
            }
            .padding(.horizontal, Spacing.cardMargin)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.bola)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, _ text: String, strong: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .typeStyle(.etiqueta)
                .foregroundStyle(Color.texto2)
            Text(text)
                .typeStyle(strong ? .filaTitulo : .sub)
                .foregroundStyle(Color.pino)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fact(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .typeStyle(.etiqueta)
                .foregroundStyle(Color.texto2)
            Text(text)
                .typeStyle(.sub)
                .foregroundStyle(Color.pino)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
    }
}

// MARK: - Archivos de los ejercicios

enum ExerciseAssets {
    /// `assets/ejercicios/<archivo>` dentro de la app (carpeta "ejercicios").
    static func url(_ file: String) -> URL? {
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "ejercicios")
    }

    static func image(_ exercise: Exercise) -> UIImage? {
        url(exercise.imageFile).flatMap { UIImage(contentsOfFile: $0.path(percentEncoded: false)) }
    }
}

/// La imagen del ejercicio; si falta el archivo, un recuadro con el número (y se ve que falta).
struct ExerciseImage: View {
    let exercise: Exercise

    var body: some View {
        if let image = ExerciseAssets.image(exercise) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Color.pino
                Text("\(exercise.number)").typeStyle(.displayM).foregroundStyle(.white)
            }
        }
    }
}

/// El clip en bucle, sin sonido, encima de su imagen (que se ve mientras carga o si no hay clip).
struct ExerciseClip: View {
    let exercise: Exercise

    var body: some View {
        ZStack {
            ExerciseImage(exercise: exercise)
            if exercise.hasClip, !UITestHarness.isActive, let url = ExerciseAssets.url(exercise.clipFile) {
                LoopingVideo(url: url)
            }
        }
    }
}

/// Vídeo en bucle con `AVPlayerLooper` (repite el clip sin saltos) en una capa de AVFoundation.
struct LoopingVideo: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let player = AVQueuePlayer()
        player.isMuted = true
        view.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
        uiView.playerLayer.player?.pause()
        uiView.looper = nil
    }

    final class PlayerView: UIView {
        var looper: AVPlayerLooper?
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
