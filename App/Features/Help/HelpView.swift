import SwiftUI

/// Un trozo de un capítulo de la Ayuda.
enum HelpBlock: Hashable {
    case heading(String)
    case paragraph(String)
    case bullets([String])
    case steps([String])
}

/// Un capítulo de la Ayuda (docs/05): título y subtítulo de la lista, icono y contenido.
struct HelpChapter: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let blocks: [HelpBlock]
}

/// Los textos de docs/05 (que manda), al día con la voz Kokoro, Gemini y los Ejercicios.
enum HelpContent {
    static let chapters: [HelpChapter] = [
        HelpChapter(id: "grabar", title: "Cómo grabar para que funcione", subtitle: "Dónde poner el móvil y cuántos fps usar",
                    systemImage: "camera", blocks: [
            .heading("Para el Tracer"),
            .bullets(["Pon el móvil quieto, en un trípode o apoyado en la bolsa, detrás de ti y en la línea del golpe.",
                      "Que quede a la altura de tus manos y en vertical.",
                      "Deja bastante cielo por encima de la bola: la app necesita ver la bola subir.",
                      "Graba a 240 fps. Con poca luz, usa 120.",
                      "Activa \"Obturación rápida\" si hace sol: la bola sale más nítida.",
                      "Que la bola no se salga del encuadre mientras sube: es lo que más ayuda a que la app la siga."]),
            .heading("Para el Análisis de swing"),
            .bullets(["Mismo sitio, detrás de ti, a la altura de las manos y a 3 o 4 metros.",
                      "Que se te vea entero, con el palo, también arriba del todo.",
                      "Evita que pase gente por detrás."]),
            .heading("Para los dos"),
            .bullets(["Activa \"Corte auto\": graba varios golpes seguidos y la app te propone un clip por golpe usando el sonido del impacto.",
                      "Con tu clave de Gemini en Ajustes, la app comprueba mirando los fotogramas qué sonidos son golpes y reparte el vídeo en un clip por golpe.",
                      "Si hay mucho viento, el micrófono lo nota. La app usará también el movimiento para encontrar el impacto."]),
        ]),
        HelpChapter(id: "tracer", title: "Tracer, paso a paso", subtitle: "Del golpe al vídeo en cuatro toques",
                    systemImage: "flag", blocks: [
            .steps(["En Inicio, elige el color del trazo y si quieres ver la distancia.",
                    "Toca \"Grabar golpe\" o \"Elegir vídeo\".",
                    "La app encuentra el impacto por el sonido y sigue la bola. Verás cómo aparecen los puntos.",
                    "Si no está segura o pierde la bola, se abre \"Ajusta el vuelo\" y te dice en qué momento la perdió. Puedes tocar la bola en un fotograma posterior para que la siga desde ahí, o mover las asas: Salida, Altura y Caída. Elige también la forma (draw, recta o fade) y el tiempo de vuelo.",
                    "Toca \"Crear vídeo\" y guárdalo en Fotos o compártelo."]),
            .paragraph("Si grabaste varios golpes seguidos, la app los prepara uno detrás de otro. En \"Tus vídeos\" ves cuáles están listos."),
            .paragraph("**Sobre la distancia**: la app no la mide. Pone el número que escribas o el de tu palo en \"Mis palos\". Para saberla, usa la medición de golpe de tu reloj GPS o los carteles del campo de prácticas."),
        ]),
        HelpChapter(id: "swing", title: "Análisis de swing, paso a paso", subtitle: "Grabar, revisar posiciones y generar",
                    systemImage: "figure.golf", blocks: [
            .steps(["Toca \"Grabar swing\" o \"Elegir vídeo\".",
                    "La app busca tu cuerpo, el impacto y siete posiciones: preparación, takeaway, mitad de subida, top, transición, impacto y final. Con tu clave de Gemini lo hace Gemini; sin red, el propio iPhone.",
                    "En \"Revisa las posiciones\", comprueba cada una. Si alguna no está en su sitio, muévela fotograma a fotograma.",
                    "Toca la cabeza del palo en la preparación. Si te lo pide, ajusta la línea del palo en las posiciones 3 y 5.",
                    "Toca \"Generar análisis\". En uno o dos minutos tendrás el vídeo con voz, líneas, medidas, ritmo, nota, informe y, al final, \"A mejorar\" con tres ejercicios."]),
            .paragraph("El vídeo se entiende solo: puedes reenviárselo a tu profesor. Pesa menos de 16 MB para que quepa en un mensaje."),
            .paragraph("Consejo: enséñale el informe a tu profesor. La app mide lo que ve en un vídeo; tu profesor sabe por qué lo haces."),
        ]),
        HelpChapter(id: "medidas", title: "Qué significa cada medida", subtitle: "Inclinación, plano, ritmo y nota",
                    systemImage: "ruler", blocks: [
            .bullets(["**Inclinación**: cuánto se inclina tu tronco hacia la bola. En la preparación suele estar entre 28 y 42 grados. Si en el impacto baja mucho, te estás levantando.",
                      "**Flexión de rodilla**: cuánto doblas la rodilla en la preparación. Lo normal, entre 15 y 30 grados.",
                      "**Brazos bajo los hombros**: en la preparación, las manos cuelgan más o menos debajo de los hombros.",
                      "**Plano del palo**: la línea del palo en la preparación. Sirve de referencia para ver si en la subida y en la bajada el palo va por encima o por debajo.",
                      "**Takeaway**: el primer tramo de la subida. Si la cabeza del palo se va detrás de las manos muy pronto, es un takeaway por dentro.",
                      "**Cabeza estable**: cuánto se mueve tu cabeza desde la preparación. Menos de unos 5 cm es buena señal.",
                      "**Cadera hacia la bola**: si tu cadera avanza hacia la bola en la bajada, sueles levantarte en el impacto.",
                      "**Ritmo**: tiempo de subida dividido por tiempo de bajada. Los profesionales rondan 3 a 1.",
                      "**Nota**: media de las notas de cada fase. La transición y el impacto cuentan doble y el ritmo, una vez y media.",
                      "**Círculo y cuadrado**: como en una tarjeta de golf. Círculo, punto fuerte. Cuadrado, a mejorar."]),
            .paragraph("Todas las medidas son aproximadas: salen de un vídeo en dos dimensiones."),
        ]),
        HelpChapter(id: "problemas", title: "Si algo sale mal", subtitle: "La bola se pierde, no oye el impacto…",
                    systemImage: "exclamationmark.triangle", blocks: [
            .bullets(["**No encuentra el impacto**: arrastra el marcador rojo de la línea de tiempo hasta el golpe.",
                      "**La bola se pierde**: es normal con cielo blanco o árboles detrás. Si la ves más adelante en el vídeo, usa \"Tocar la bola\". Si no, ajusta el final del vuelo con las asas. Para la próxima vez: móvil quieto y más cielo detrás de la bola.",
                      "**No me encuentra en el vídeo**: graba con el cuerpo entero y el palo dentro del encuadre, con buena luz. Con tu clave de Gemini en Ajustes, Gemini lo intenta antes que el iPhone.",
                      "**Gemini no contesta**: sin red, sin cuota del día (unas 20 comprobaciones) o con Google saturado, la app sigue sola con el iPhone y te dice el motivo.",
                      "**Las posiciones están mal**: muévelas en \"Revisa las posiciones\". Dos o tres toques suelen bastar.",
                      "**El ritmo sale raro**: si importaste un vídeo a cámara lenta sin dar acceso a Fotos, puede venir estirado. Da acceso a Fotos o graba desde la app.",
                      "**La voz no suena como siempre**: la voz del análisis es Dora (Kokoro) y va dentro de la app. Si no carga, se usa una voz del iPhone; puedes elegirla en Ajustes, en Voz del análisis.",
                      "**La app no abre**: probablemente ha caducado. Mira \"Renovar la app cada 7 días\"."]),
        ]),
        HelpChapter(id: "ajustes", title: "Ajustes y tus palos", subtitle: "Distancias por palo, voz, unidades",
                    systemImage: "slider.horizontal.3", blocks: [
            .bullets(["**Unidades**: metros o yardas.",
                      "**Tú**: mano dominante y estatura (sirve para pasar las medidas a centímetros).",
                      "**Mis palos**: escribe tu distancia de vuelo con cada palo. El Tracer la usa cuando eliges el palo.",
                      "**Tracer**: color y distancia por defecto, obturación rápida y marca de agua.",
                      "**Análisis**: voz, botón para probarla, vídeo completo o corto y subtítulos.",
                      "**Comprobar golpes con Gemini**: tu clave gratuita de Google AI Studio, guardada en el llavero, y si quieres que compruebe siempre sin preguntar.",
                      "**Avanzado**: modo diagnóstico (para ver lo que detecta la app) y borrar vídeos antiguos."]),
        ]),
        HelpChapter(id: "renovar", title: "Renovar la app cada 7 días", subtitle: "Por qué caduca y cómo renovarla",
                    systemImage: "calendar", blocks: [
            .paragraph("La app está instalada con un Apple ID gratuito. Apple la deja funcionar 7 días. Después no abre hasta que la renuevas. Tus vídeos y ajustes no se pierden si la renuevas con el mismo Apple ID y el mismo archivo."),
            .heading("Cómo renovarla"),
            .steps(["Conecta el iPhone al ordenador con el cable.",
                    "Abre Sideloadly.",
                    "Arrastra el archivo Trazo.ipa (está en la carpeta builds del proyecto).",
                    "Escribe tu Apple ID y toca Start.",
                    "Si te pide un código, mira el iPhone."]),
            .paragraph("La fecha de caducidad aparece arriba en la Ayuda. La app te avisa un día antes."),
        ]),
    ]

    static func chapter(_ id: String) -> HelpChapter? { chapters.first { $0.id == id } }
}

/// Ayuda (s08): aviso de caducidad y "Guía de uso" con los capítulos.
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("Ayuda")
                    .typeStyle(.tituloPantalla)
                    .foregroundStyle(Color.pino)
                    .accessibilityAddTraits(.isHeader)
                if let expiry = ProvisioningInfo.expirationDate {
                    ExpiryCard(date: expiry)
                }
                Text("Guía de uso")
                    .typeStyle(.etiqueta)
                    .foregroundStyle(Color.texto2)
                    .padding(.top, Spacing.xs)
                VStack(spacing: 0) {
                    ForEach(Array(HelpContent.chapters.enumerated()), id: \.element.id) { index, chapter in
                        NavigationLink(value: HomeDestination.helpChapter(chapter.id)) {
                            HelpRow(systemImage: chapter.systemImage, title: chapter.title, subtitle: chapter.subtitle)
                        }
                        .buttonStyle(RowButtonStyle())
                        if index < HelpContent.chapters.count - 1 {
                            Divider().padding(.leading, 86)
                        }
                    }
                }
                .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            }
            .padding(.horizontal, Spacing.cardMargin)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xxl)
        }
        .background(Color.bola)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// El aviso de caducidad (s08): icono amarillo, fecha y "Cómo renovar".
struct ExpiryCard: View {
    let date: Date

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: "calendar")
                .font(.system(size: Size.icon, weight: .semibold))
                .foregroundStyle(Color.pino)
                .frame(width: Size.iconTile, height: Size.iconTile)
                .background(Color.amarillo, in: RoundedRectangle(cornerRadius: Radius.iconTile, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Tu app caduca \(ProvisioningInfo.longDate(date))")
                    .typeStyle(.filaTitulo)
                    .foregroundStyle(Color.pino)
                Text("Renuévala con Sideloadly antes de esa fecha. Son dos minutos con el cable.")
                    .typeStyle(.sub)
                    .foregroundStyle(Color.texto2)
                NavigationLink(value: HomeDestination.helpChapter("renovar")) {
                    Text("Cómo renovar")
                }
                .buttonStyle(.secundario)
                .fixedSize()
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.papel, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }
}

/// Un capítulo de la Ayuda, con desplazamiento.
struct HelpChapterView: View {
    let chapter: HelpChapter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text(chapter.title)
                    .typeStyle(.tituloPantalla)
                    .foregroundStyle(Color.pino)
                    .accessibilityAddTraits(.isHeader)
                ForEach(chapter.blocks, id: \.self) { block in
                    switch block {
                    case .heading(let text):
                        Text(text)
                            .typeStyle(.filaTitulo)
                            .foregroundStyle(Color.pino)
                            .padding(.top, Spacing.s)
                    case .paragraph(let text):
                        Text(Self.markdown(text))
                            .typeStyle(.sub)
                            .foregroundStyle(Color.texto2)
                    case .bullets(let items):
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            ForEach(items, id: \.self) { item in
                                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                                    Text("•").typeStyle(.sub).foregroundStyle(Color.pino)
                                    Text(Self.markdown(item)).typeStyle(.sub).foregroundStyle(Color.texto2)
                                }
                            }
                        }
                    case .steps(let items):
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                                HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                                    Text("\(index + 1).").typeStyle(.filaTitulo).foregroundStyle(Color.pino)
                                    Text(Self.markdown(item)).typeStyle(.sub).foregroundStyle(Color.texto2)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.textMargin)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.bola)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Las negritas de docs/05 (**así**).
    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
