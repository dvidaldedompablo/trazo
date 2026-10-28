import SwiftUI

/// Inicio (s01 en `design/capturas/`): la marca, la tarjeta del Tracer con la vista previa en vivo,
/// la tarjeta de Análisis de swing y la fila de Ayuda.
struct HomeView: View {
    // Ajustes del trazo. @AppStorage los guarda en el iPhone y los recupera al abrir la app.
    @AppStorage(SettingsKey.tracerColor) private var colorChoice: TracerColorChoice = .rojoTV
    @AppStorage(SettingsKey.tracerCustomColor) private var customColorHex = Int(TracerPalette.customDefaultHex)
    @AppStorage(SettingsKey.tracerShowsDistance) private var showsDistance = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Animación de arranque: el arco se dibuja, la bola cae y la distancia cuenta.
    // @State guarda valores que la vista cambia; al cambiarlos, SwiftUI vuelve a dibujarla.
    @State private var arcProgress: CGFloat = 0
    @State private var hasLanded = false
    @State private var shownDistance: Double = 0
    @State private var hasPlayedLaunch = false
    /// Cada vez que sube, suena la vibración de la caída.
    @State private var landingFeedback = 0

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    tracerCard
                        .padding(.top, HomeLayout.headerToTracer)
                    swingCard
                        .padding(.top, HomeLayout.tracerToSwing)
                    helpLink
                        .padding(.top, HomeLayout.swingToHelp)
                    if !Typography.isArchivoAvailable {
                        // Si la fuente no se cargó, se dice claro en vez de enseñar otra sin avisar.
                        Text("No se ha cargado la fuente Archivo")
                            .typeStyle(.nota)
                            .foregroundStyle(Color.texto2)
                            .padding(.top, Spacing.l)
                    }
                }
                .padding(.horizontal, Spacing.cardMargin)
                // La cabecera empieza a 56 pt del borde de arriba de la pantalla, como en la maqueta,
                // salvo que la barra de estado sea más alta (iPhone con isla dinámica).
                .padding(.top, max(HomeLayout.headerTop - proxy.safeAreaInsets.top, 0))
                .padding(.bottom, Spacing.l)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.bola)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: HomeDestination.self) { destination in
            destination.screen
        }
        // Vibración ligera cuando la bola cae.
        .sensoryFeedback(.impact(weight: .light), trigger: landingFeedback)
        .task { await playLaunchAnimation() }
    }

    // MARK: - Cabecera

    private var header: some View {
        HStack(alignment: .center) {
            Wordmark()
            Spacer()
            HStack(spacing: HomeLayout.headerButtonGap) {
                NavigationLink(value: HomeDestination.library) {
                    Image(systemName: "film.stack")
                }
                .buttonStyle(.circleIcon)
                .accessibilityLabel("Tus vídeos")
                NavigationLink(value: HomeDestination.settings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.circleIcon)
                .accessibilityLabel("Ajustes")
            }
        }
        // La cabecera va con el margen del texto suelto (20 pt), no con el de las tarjetas (16 pt).
        .padding(.horizontal, Spacing.textMargin - Spacing.cardMargin)
    }

    // MARK: - Tracer

    private var tracerCard: some View {
        InstrumentCard(style: .light) {
            VStack(alignment: .leading, spacing: 0) {
                TracerPreview(
                    color: tracerColor,
                    colorName: colorChoice.name,
                    showsDistance: showsDistance,
                    club: HomeLayout.previewClub,
                    progress: arcProgress,
                    hasLanded: hasLanded,
                    distance: shownDistance
                )
                VStack(alignment: .leading, spacing: 0) {
                    Text("Tracer")
                        .typeStyle(.tituloTarjeta)
                        .foregroundStyle(Color.pino)
                        .accessibilityAddTraits(.isHeader)
                    Text("Tu golpe con el vuelo de la bola dibujado, como en la tele.")
                        .typeStyle(.sub)
                        .foregroundStyle(Color.texto2)
                        .padding(.top, HomeLayout.titleToDescription)
                    tracerOptions
                        .padding(.top, HomeLayout.descriptionToOptions)
                    tracerButtons
                        .padding(.top, HomeLayout.optionsToButtons)
                }
                .padding(.top, HomeLayout.cardBodyTop)
                .padding([.horizontal, .bottom], HomeLayout.cardPadding)
            }
        }
    }

    /// Fila de colores e interruptor de distancia. Con el texto muy grande, uno debajo de otro.
    private var tracerOptions: some View {
        // Sin separación propia: el Spacer reparte lo que sobra, como `space-between` en la maqueta.
        // Con separación, el HStack la pondría a los dos lados del Spacer y la fila no cabría.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.m))
            : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            ColorSwatchRow(selection: $colorChoice, customColor: customColor)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Spacing.xs) }
            DistanceToggle(isOn: $showsDistance)
        }
    }

    private var tracerButtons: some View {
        buttonRow {
            NavigationLink(value: HomeDestination.recordShot) {
                Label { Text("Grabar golpe") } icon: { RecordDot() }
            }
            .buttonStyle(.principal)
            NavigationLink(value: HomeDestination.pickShotVideo) {
                Label("Elegir vídeo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.secundario)
        }
    }

    // MARK: - Análisis de swing

    private var swingCard: some View {
        InstrumentCard(style: .dark) {
            ZStack(alignment: .topTrailing) {
                TelestratorFigure()
                    .frame(width: HomeLayout.figureSize.width, height: HomeLayout.figureSize.height)
                    .padding(.top, HomeLayout.figureTop)
                    .padding(.trailing, HomeLayout.figureTrailing)
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Análisis de swing")
                            .typeStyle(.tituloTarjeta)
                            .foregroundStyle(Color.white)
                            .accessibilityAddTraits(.isHeader)
                        Text("Graba tu swing y recibe un vídeo explicado con voz, líneas y una nota.")
                            .typeStyle(.subCompacto)
                            .foregroundStyle(Color.white.opacity(0.72))
                            .frame(maxWidth: HomeLayout.swingDescriptionMaxWidth, alignment: .leading)
                            .padding(.top, HomeLayout.swingTitleToDescription)
                    }
                    // El texto ocupa al menos lo que deja libre la tarjeta de 206 pt: así los botones
                    // quedan abajo del todo, y si el texto crece, la tarjeta crece con él.
                    .frame(minHeight: HomeLayout.swingTextMinHeight, alignment: .topLeading)
                    swingButtons
                }
                .padding(HomeLayout.cardPadding)
                .padding(.trailing, HomeLayout.swingTextTrailing - HomeLayout.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var swingButtons: some View {
        buttonRow {
            NavigationLink(value: HomeDestination.recordSwing) {
                Label { Text("Grabar swing") } icon: { RecordDot(color: .pino, ringOpacity: 0.18) }
            }
            .buttonStyle(.amarillo)
            NavigationLink(value: HomeDestination.pickSwingVideo) {
                Image(systemName: "photo.on.rectangle")
            }
            .buttonStyle(CrystalButtonStyle(surface: .darkCard, outline: .circle(diameter: Size.buttonHeight)))
            .accessibilityLabel("Elegir vídeo de swing")
        }
    }

    // MARK: - Ayuda

    private var helpLink: some View {
        NavigationLink(value: HomeDestination.help) {
            HelpRow(systemImage: "book.pages", title: "Ayuda", subtitle: "Guía de uso, paso a paso")
        }
        .buttonStyle(RowButtonStyle())
    }

    // MARK: - Ayudantes

    /// Dos botones en fila; con el texto muy grande, uno debajo de otro.
    private func buttonRow(@ViewBuilder _ content: () -> some View) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: HomeLayout.buttonGap))
            : AnyLayout(HStackLayout(spacing: HomeLayout.buttonGap))
        return layout(content)
    }

    private var tracerColor: Color {
        colorChoice.color(custom: customColor.wrappedValue)
    }

    /// "Otro color" guardado como número: este Binding lo traduce a `Color` y de vuelta.
    private var customColor: Binding<Color> {
        Binding(
            get: { Color(hex: UInt32(customColorHex)) },
            set: { customColorHex = Int($0.hexValue) }
        )
    }

    /// El arranque: el arco se dibuja una vez en 1,3 s (sube rápido y frena en el vértice),
    /// la bola cae, vibra y la distancia cuenta hasta 150 m. Con "Reducir movimiento" o en las
    /// capturas del CI, todo aparece ya en su sitio.
    private func playLaunchAnimation() async {
        if hasPlayedLaunch {
            // Se vuelve a Inicio desde otra pantalla: si la animación se cortó, se deja terminada.
            if !hasLanded { showFinalState() }
            return
        }
        hasPlayedLaunch = true
        guard !reduceMotion, !UITestHarness.isActive else {
            showFinalState()
            return
        }
        withAnimation(.timingCurve(0.2, 0.7, 0.25, 1, duration: HomeLayout.arcDuration).delay(HomeLayout.arcDelay)) {
            arcProgress = 1
        }
        do {
            try await Task.sleep(for: .seconds(HomeLayout.arcDelay + HomeLayout.arcDuration))
        } catch {
            // La pantalla se cerró antes de acabar (por ejemplo, al abrir Ajustes enseguida).
            showFinalState()
            return
        }
        landingFeedback += 1
        withAnimation(.spring(duration: 0.25)) { hasLanded = true }
        withAnimation(.easeOut(duration: HomeLayout.countDuration)) { shownDistance = HomeLayout.previewDistance }
    }

    private func showFinalState() {
        arcProgress = 1
        hasLanded = true
        shownDistance = HomeLayout.previewDistance
    }
}

/// Medidas de Inicio sacadas de `design/maqueta.html` (en puntos, para una pantalla de 390 x 844).
private enum HomeLayout {
    /// Arriba de la cabecera, medido desde el borde de la pantalla.
    static let headerTop: CGFloat = 56
    static let headerButtonGap: CGFloat = 10
    /// Separaciones verticales entre bloques.
    static let headerToTracer: CGFloat = 18
    static let tracerToSwing: CGFloat = 10.5
    static let swingToHelp: CGFloat = 14
    /// Interior de las tarjetas.
    static let cardPadding: CGFloat = 18
    static let cardBodyTop: CGFloat = 14
    // La maqueta dice 5, 14 y 16, pero con Inter. SF Pro deja la descripción 1 pt más abajo
    // y la tarjeta salía 2,5 pt más alta: se quita aquí, medido contra s01.
    static let titleToDescription: CGFloat = 4
    static let descriptionToOptions: CGFloat = 13
    static let optionsToButtons: CGFloat = 15.5
    static let buttonGap: CGFloat = 10
    /// Tarjeta de Análisis: columna de texto a la izquierda y figura a la derecha.
    static let swingTitleToDescription: CGFloat = 6
    static let swingDescriptionMaxWidth: CGFloat = 209
    /// Hueco a la derecha de la columna de texto, donde va la figura (deja el botón amarillo en 163,5 pt).
    static let swingTextTrailing: CGFloat = 116.5
    static let swingTextMinHeight = Size.swingCardHeight - 2 * cardPadding - Size.buttonHeight
    static let figureSize = CGSize(width: 128, height: 180)
    static let figureTop: CGFloat = 14
    /// La figura se sale 6 pt por la derecha y la tarjeta la recorta.
    static let figureTrailing: CGFloat = -6
    /// Datos de la vista previa: el palo y la distancia por defecto de "Mis palos" (docs/01).
    static let previewClub = "Hierro 7"
    static let previewDistance: Double = 150
    /// Tiempos de la animación de arranque (docs/02).
    static let arcDelay: Double = 0.3
    static let arcDuration: Double = 1.3
    static let countDuration: Double = 0.6
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
