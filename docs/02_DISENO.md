# Sistema de diseño

Referencia visual: `design/maqueta.html` y `design/capturas/` (s01 a s08 son pantallas; s09 a s11 son fotogramas de los vídeos que genera la app).

## Idea
Libreta de golf a pleno sol y realización de televisión.
- La app se usa en el campo de prácticas, al sol y entre golpe y golpe. Por eso la interfaz es **clara**, con texto grande y mucho contraste. Solo las pantallas donde vive el vídeo son de **negro puro**.
- Dos lenguajes de la tele, uno por función: el **trazo rojo** del tracer y el **amarillo del telestrador** (las líneas que dibujan los comentaristas sobre el swing) en el análisis.
- Un solo momento llamativo: el arco del tracer en Inicio, que es además la vista previa en vivo de los ajustes.
- Las formas tienen significado, como en una tarjeta de golf: **círculo = punto fuerte**, **cuadrado = a mejorar**.
- Palabras de golfista, no de técnico.

## Color
| Nombre | Hex | Uso |
|---|---|---|
| Bola | `#F6F7F4` | Fondo de las pantallas claras |
| Papel | `#FFFFFF` | Tarjetas, paneles, hojas |
| Niebla | `#E5EBE7` | Botones secundarios, fondos de icono, controles segmentados |
| Línea | `#D5DDD8` | Separadores, pistas de deslizadores |
| Pino | `#10241D` | Texto principal, botón principal, tarjeta de Análisis |
| Pino 2 | `#1C362C` | Variante para capas sobre Pino |
| Texto 2 | `#4B5D55` | Texto secundario |
| Texto 3 | `#7D8B84` | Texto terciario, flechas |
| Rojo trazo | `#FF3B2E` | Tracer: trazo, punto de grabar, impacto en la onda |
| Amarillo telestrador | `#FFD02E` | Análisis: líneas, botón de grabar swing, selección en la tira |
| Bien | `#1F9D63` | Confirmaciones (uso mínimo) |
| Escenario | `#000000` | Fondo de pantallas de vídeo |

Colores del trazo (fila de muestras): Rojo TV `#FF3B2E`, Amarillo `#FFD02E`, Blanco `#FFFFFF` (con borde `#C9D2CC`), Azul tee `#2F7CFF`, Verde `#2FD27A`, y un séptimo "Otro color" con `ColorPicker` (anillo arcoíris).

Reglas:
- El rojo y el amarillo no se usan para texto pequeño sobre blanco (no llegan al contraste). Para texto, Pino.
- La app fuerza el modo claro en las pantallas de navegación (`.preferredColorScheme(.light)`). Las pantallas de vídeo son negras siempre.

## Tipografía
- **Archivo** (variable, ejes `wght` 100 a 900 y `wdth` 62 a 125, licencia OFL): títulos, cifras, distancias, notas. Se usa estrecha y gruesa, como los carteles de distancia del campo de prácticas.
- **SF Pro** (fuente del sistema): todo lo demás. En la maqueta, Inter hace de SF Pro.

Cargar Archivo con variaciones (ejemplo):
```swift
// Los ejes se identifican con códigos de 4 letras: 'wght' y 'wdth'.
func archivo(_ size: CGFloat, width: CGFloat = 74, weight: CGFloat = 800, relativeTo style: UIFont.TextStyle = .body) -> Font {
    let axes: [UInt32: CGFloat] = [0x77676874: weight, 0x77647468: width]
    let descriptor = UIFontDescriptor(fontAttributes: [
        .name: "Archivo",
        UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes
    ])
    let base = UIFont(descriptor: descriptor, size: size)
    let scaled = UIFontMetrics(forTextStyle: style).scaledFont(for: base) // respeta Dynamic Type
    return Font(scaled)
}
```

| Estilo | Fuente | Tamaño (pt) | Uso |
|---|---|---|---|
| displayXL | Archivo, anchura 68, peso 820 | 96 a 132 | Nota en la tarjeta del vídeo |
| displayL | Archivo, 68, 820 | 64 | Nota en "Tu análisis" |
| displayM | Archivo, 70, 800 | 36 a 40 | Ritmo "2,8 : 1", distancia grande |
| marca | Archivo, 70, 850 | 38 | "Trazo" en Inicio |
| tituloPantalla | Archivo, 74, 820 | 34 | Títulos grandes |
| tituloTarjeta | Archivo, 76, 800 | 27 | "Tracer", "Análisis de swing" |
| valor | Archivo, 72, 750 | 17 | Valores de deslizadores |
| boton | SF Pro Semibold | 16 | Botones |
| cuerpo | SF Pro Regular | 17 | Texto general |
| sub | SF Pro Regular | 14,5 a 15 | Descripciones |
| nota | SF Pro Regular | 13 | Notas al pie |
| chip | SF Pro Semibold | 11 a 13,5 | Chips y etiquetas |

Cifras siempre con `monospacedDigit()` donde cambian (contadores, tiempos).

## Espacio, radios y sombras
- Rejilla de 4 pt. Espacios: 4, 8, 12, 16, 20, 24, 32.
- Márgenes: 16 pt para tarjetas, 20 pt para texto suelto.
- Radios por jerarquía: tarjetas grandes 32 (eco de las esquinas del iPhone), hojas 28, paneles 22, filas 20, miniaturas 10 a 16, chips y botones en cápsula.
- Sombra solo en la tarjeta del Tracer: `y 18, blur 34, Pino al 35 %, spread −24`. El resto, plano.
- Cristal (Liquid Glass de iOS 26: `.glassEffect()`, `.buttonStyle(.glass)`) **solo en controles sobre vídeo** (cámara, ajuste, resultado). Nunca como fondo de contenido.

## Iconos (SF Symbols)
Tus vídeos `film.stack` · Ajustes `gearshape` · Elegir vídeo `photo.on.rectangle` · Cerrar `xmark` · Atrás `chevron.left` · Ir `chevron.right` · Hecho `checkmark` · Ayuda `book.pages` · Compartir `square.and.arrow.up` · Guardar `arrow.down.to.line` · Editar `slider.horizontal.3` · Corte auto `waveform` · Reproducir `play.fill` · Caducidad `calendar` · Grabar guía `camera` · Medidas `ruler` · Problemas `exclamationmark.triangle` · Swing `figure.golf` · Tracer `flag`.

## Componentes
- **BotonPrincipal**: cápsula de 50 pt, Pino, texto blanco. Icono opcional a la izquierda (punto rojo de grabar en "Grabar golpe").
- **BotonSecundario**: cápsula de 50 pt, Niebla, texto Pino.
- **BotonAmarillo**: cápsula de 50 pt, Amarillo, texto Pino, punto Pino (en la tarjeta de Análisis).
- **BotonCristal**: círculo de 44 pt o cápsula, cristal, sobre vídeo.
- **FilaColores**: círculos de 26 a 30 pt, separación 7 a 8 pt. Seleccionado: anillo blanco de 2,5 pt y anillo Pino de 2 pt por fuera. VoiceOver: "Rojo TV, seleccionado".
- **InterruptorDistancia**: etiqueta "Distancia" (o el valor, "150 m") y `Toggle` teñido de Pino.
- **TarjetaTracer**: ventana de 180 pt de alto con cielo, arboleda, calle con franjas de corte y carteles de distancia; arco en vivo; debajo título, descripción, fila de colores con interruptor y dos botones.
- **TarjetaAnalisis**: fondo Pino, título blanco, descripción al 72 %, botón amarillo y botón cristal oscuro; a la derecha la figura con líneas de telestrador.
- **FilaAyuda**: icono en cuadrado Niebla de 42 pt con radio 13, título, subtítulo y flecha.
- **Chip**: cápsula de 22 a 32 pt; sobre vídeo con fondo Pino al 42 % y cristal.
- **ListaPasos**: círculo de 24 pt (vacío, activo con punto rojo, hecho con check sobre Pino), título y detalle.
- **Onda**: barras de 3 pt cada 5 pt en Pino al 28 %; el pico del impacto en rojo con línea vertical punteada y etiqueta "Impacto 1,84 s".
- **Deslizador**: pista de 5 pt Línea, relleno Pino, pomo blanco de 24 pt con sombra; valor a la derecha en Archivo.
- **Segmentado**: fondo Niebla radio 12, opción activa en blanco con sombra suave.
- **EtiquetaMedida** (en vídeo): rectángulo Pino al 84 % radio 12, nombre en SF Semibold blanco al 75 %, valor en Archivo amarillo.

## Pantallas
1. **Inicio** (`s01`): marca "Trazo" con el arco rojo que sale de la T (la T es el tee) y cae tras la "o"; botones redondos Tus vídeos y Ajustes. Tarjeta del Tracer, tarjeta de Análisis y fila de Ayuda. Si la app caduca en 2 días o menos, aparece un aviso amarillo bajo la cabecera.
2. **Grabar** (`s02`): escenario negro con la cámara a pantalla completa. Arriba: cerrar, chips de modo y fps, contador. Consejo en cristal bajo la barra superior. Silueta fantasma blanca al 30 % ("Tú aquí"), línea del golpe roja discontinua y círculo "Bola aquí" (Tracer). Nivel en el centro (verde cuando está recto, con el texto "Nivelado"). Abajo: miniatura del último clip, botón de grabar de 78 pt y chip "Corte auto".
3. **Creando tu tracer** (`s03`): título, frase "Mantén la app abierta. Tarda menos de un minuto.", panel de la onda con el impacto, miniatura del vídeo con los puntos encontrados y lista de pasos (Impacto encontrado, Siguiendo la bola, Dibujando el trazo, Exportando el vídeo). Nota al pie: si la bola se pierde, la app dirá en qué momento y se podrá tocar en un fotograma posterior o ajustar a mano.
4. **Ajusta el vuelo** (`s04`): vídeo encajado en negro con tres asas blancas con anillo Pino (Salida, Altura, Caída) y la línea de tiempo con el impacto en rojo. Botón de cristal "Tocar la bola" (icono de diana) abajo a la izquierda del vídeo: al pulsarlo se pausa el vídeo, aparecen los pasos de fotograma y una lupa x3 bajo el dedo; al tocar la bola se vuelve a seguir desde ahí (el trazo se recalcula con un fundido de 0,3 s) y aparece "Deshacer". Si la app perdió la bola, una píldora de cristal bajo la barra superior dice "Perdí la bola a los 0,6 s" y el vídeo empieza en ese fotograma. Hoja inferior: forma (Draw, Recta, Fade), Altura, Tiempo de vuelo, colores con la distancia y "Crear vídeo".
5. **Vídeo listo** (`s05`): vídeo a pantalla completa. Chip "Vídeo listo, 12 s". Tres acciones de cristal: Guardar en Fotos (principal, blanca), Compartir, Editar.
6. **Revisa las posiciones** (`s06`): fotograma grande con esqueleto amarillo y líneas; píldora "Toca la cabeza del palo" con retícula; pasos de fotograma; tira de 7 miniaturas numeradas (la elegida con borde amarillo y Pino); rótulo "1 de 7, Preparación."; "Generar análisis".
7. **Tu análisis** (`s07`): vídeo vertical a la izquierda; a la derecha Nota (78/100 y "Buena base") y Ritmo (2,8 : 1, subida y bajada); "Lo primero a trabajar" con un cuadrado numerado; botones Ver informe y Guardar.
8. **Ayuda** (`s08`): aviso de caducidad con icono amarillo y botón "Cómo renovar"; lista "Guía de uso" con los capítulos de `docs/05`.
9. **Ajustes**: secciones Unidades (m, yd); Tú (mano dominante, estatura); Mis palos (lista editable con distancia); Tracer (color y distancia por defecto, obturación rápida, marca de agua); Análisis (voz, probar voz, duración completa o corta, subtítulos); Avanzado (modo diagnóstico, borrar vídeos antiguos, versión).
10. **Tus vídeos**: rejilla de miniaturas verticales con el tipo (punto rojo o amarillo), fecha y duración. Los golpes en cola muestran su estado sobre la miniatura: "En proceso" con progreso circular, "Listo" o "Falló" (al tocarlo, el motivo en una frase y "Abrir en Ajusta el vuelo"). Al mantener pulsado un clip: "Guardar original en Fotos" (el vídeo tal cual, a sus fps reales, para pasarlo al ordenador), "Abrir en Ajusta el vuelo" (tracer) y "Borrar". Vacía: "Aún no hay vídeos. Graba tu primer golpe desde Inicio."
11. **Informe completo**: lo mismo que la tarjeta de informe del vídeo, en pantalla con desplazamiento.
12. **Historial**: gráfico de nota y ritmo en el tiempo y lista de análisis.

## Movimiento y vibración
- Arranque: el arco del Tracer se dibuja una vez en 1,3 s (sube rápido y frena en el vértice). Al caer, la etiqueta cuenta hasta "150 m" y hay una vibración ligera.
- Cambiar de color: fundido de 0,2 s del arco. Interruptor de distancia: la etiqueta aparece o desaparece con escala y fundido (muelle de 0,25 s).
- Proceso: la onda se rellena de izquierda a derecha; al encontrar el impacto, el pico late una vez y vibra con `.rigid`. Al terminar la exportación, vibración de éxito.
- Con "Reducir movimiento", nada se dibuja ni late: aparece en su estado final.

## Accesibilidad
- Dynamic Type en SF Pro y en Archivo (con `UIFontMetrics`).
- Zonas táctiles de 44 pt como mínimo.
- Contraste de texto de 4,5:1 como mínimo.
- Etiquetas de VoiceOver en español en todos los iconos y muestras de color.

## Textos
- Botones: "Grabar golpe", "Elegir vídeo", "Grabar swing", "Tocar la bola", "Deshacer", "Crear vídeo", "Guardar en Fotos", "Compartir", "Editar", "Generar análisis", "Ver informe", "Cómo renovar".
- Una acción conserva el mismo nombre en todo el flujo: "Guardar en Fotos" termina en "Guardado en Fotos".
- Errores (dicen qué pasó y qué hacer):
  - "No se ha oído el impacto. Arrastra el marcador rojo hasta el momento del golpe."
  - "Perdí la bola a los 0,6 s. Si la ves más adelante, usa Tocar la bola. Si no, ajusta el final con las asas."
  - "Ese toque no encaja con el resto. ¿Seguro que es la bola?" (con "Deshacer")
  - "No se ve a nadie en el vídeo. Graba con el cuerpo entero y el palo dentro del encuadre."
  - "Este vídeo es demasiado corto. Necesita al menos 1 s antes y 1 s después del golpe."
  - "No queda espacio en el iPhone. Libera al menos 1 GB y vuelve a intentarlo."
- Permisos: "Trazo usa la cámara para grabar tus golpes." · "Trazo usa el micrófono para oír el impacto de la bola." · "Trazo guarda en Fotos los vídeos que crees."

## Icono de la app
Fondo Pino, arco rojo con núcleo blanco de abajo a la izquierda hacia la derecha y bola blanca donde cae. Sin texto. Archivo listo: `design/AppIcon-1024.png`.

## Gráficos de los vídeos que genera la app
Medidas en píxeles para un vídeo de 1080x1920. Escalar si la salida es otra.

**Tracer** (`s09`)
- Trazo en capas: halo de 41 px difuminado (desenfoque gaussiano de unos 18 px) al 42 %; capa de color de 18 px con desenfoque ligero; color de 12 px; núcleo blanco de 4 px al 95 %.
- El grosor baja del 125 % en la salida al 50 % en la caída (perspectiva).
- Cabeza de la bola mientras vuela: halo de 25 px del color y núcleo blanco de 9 px.
- Caída: punto blanco de 12 px y anillo de 24 px.
- Etiqueta (si la distancia está activada): rectángulo Pino al 88 % de 270x135 px, radio 28; palo en SF Semibold 30 px blanco al 72 %; distancia en Archivo (anchura 70, peso 800) a 66 px. Línea fina blanca hasta el punto de caída.
- Marca de agua "Trazo" opcional, Archivo 36 px blanco al 55 %, abajo a la derecha.

**Análisis** (`s10`, `s11`)
- Líneas principales amarillas de 9 px sobre una línea negra al 28 % de 17 px (para que se lean sobre cualquier fondo). Secundarias blancas al 85 % de 5 px; discontinuas 5/14 px.
- Articulaciones: círculo blanco de 12 px con anillo amarillo de 6 px.
- Arcos de ángulo amarillos de 7 px con el valor en Archivo de 60 px y contorno oscuro.
- Círculo de cabeza discontinuo amarillo de radio 85 px.
- Zona de plano: triángulo blanco al 13 % entre la línea del palo y la línea bola-cuello.
- Etiquetas de medida: Pino al 84 %, radio 32 px; nombre en SF Semibold 28 px; valor en Archivo 62 px amarillo. Columna a la derecha, en el cielo.
- Chip de fase: cápsula amarilla con "1/7" en Archivo 36 px Pino y el nombre de la fase en Archivo 68 px blanco.
- Estado arriba a la derecha: "Pausa" (cápsula blanca) o "× 0,25" (cámara lenta). Debajo, "F27, 0,90 s" en 26 px blanco al 70 %.
- Subtítulos: Archivo (anchura 92, peso 800) a 68 px, blanco con contorno negro al 55 % de 14 px. Dos líneas como máximo, unas 22 letras por línea, centrados hacia el 75 % de la altura. Palabras ya dichas al 100 %, las que faltan al 42 %.
- Tarjetas de datos: fondo Bola, texto Pino. Nota en Archivo a 340 px; filas en SF 40 px con valores en Archivo 52 px; marcas de círculo y cuadrado de 3 px. Leyenda "Punto fuerte" y "A mejorar". Pie "Medidas aproximadas, vídeo 2D".
- Márgenes de seguridad: 90 px a los lados; nada importante en los 160 px de arriba ni en los 220 px de abajo.
