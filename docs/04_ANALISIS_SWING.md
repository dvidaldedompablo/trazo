# Análisis de swing

El resultado es un vídeo vertical explicado con voz, que sigue la estructura del vídeo de referencia (`docs/08_REFERENCIA_VIDEO.md`) con la identidad visual propia de la app.

## Grabación
- Vista desde detrás (en la línea de los pies y de las manos, mirando al objetivo), como el vídeo de referencia. Todas las medidas de este documento son para esta vista.
- Móvil quieto a la altura de las manos (alrededor de 1 m), a 3 o 4 m del jugador. Cuerpo entero y palo dentro del encuadre también en el top.
- 240 fps (120 vale). Buena luz. Que no pase gente por detrás.
- Mano dominante en Ajustes (diestro o zurdo). Para zurdos, se reflejan las reglas en horizontal.
- La vista de frente queda para más adelante (las medidas son otras).

## 1. Pose y suavizado
- `DetectHumanBodyPoseRequest` (revisión 2) a 120 fps (uno de cada dos fotogramas a 240).
- Articulaciones: nariz, orejas, cuello, hombros, codos, muñecas, centro de cadera, caderas, rodillas, tobillos. Desde detrás, el lado de atrás (derecho en un diestro) es el que mejor se ve: usarlo para rodilla y brazo cuando el otro esté tapado.
- Descartar puntos con confianza < 0,3 e interpolar huecos cortos (hasta 4 fotogramas).
- Suavizar posiciones con Savitzky-Golay (ventana 9, orden 3) o One Euro. Las velocidades se calculan sobre la serie suavizada.
- Manos H(t) = punto medio de las muñecas. Longitud del tronco = distancia cuello-centro de cadera en la preparación.

## 2. Escala en centímetros (aproximada)
px por cm = (tobillo-rodilla + rodilla-cadera + cadera-cuello + cuello-nariz, en la preparación) / (0,87 × estatura en cm).
Desde detrás, el plano del cuerpo queda casi paralelo a la imagen y las longitudes de los segmentos se conservan bastante. Todo valor en cm se muestra con "~".

## 3. Las 7 posiciones (PhaseDetector)
| # | Nombre en pantalla | Regla principal | Alternativa |
|---|---|---|---|
| — | Inicio de la subida (B) | Primer fotograma en que las manos se alejan más del 2 % de la estatura de su posición de preparación y siguen alejándose | — |
| 1 | Preparación | Último fotograma antes de B con las manos quietas al menos 0,3 s | 0,2 s antes de B |
| 2 | Takeaway | Las manos han recorrido el 22 % del camino entre B y el top | Palo paralelo al suelo, si hay punto de cabeza del palo |
| 3 | Mitad de subida | Brazo de delante paralelo al suelo (±10°) entre 2 y el top | 55 % del recorrido |
| 4 | Top | Manos en su punto más alto entre B y el impacto, donde cambian de sentido | Velocidad mínima de manos cerca del punto más alto |
| 5 | Transición | Brazo de delante paralelo al suelo en la bajada | Manos a la altura que tenían en 3 |
| 6 | Impacto | Instante del sonido del impacto (`ImpactDetector`) | Manos en su punto más bajo tras el top con velocidad máxima |
| 7 | Final | Primer fotograma tras el impacto con las manos quietas 0,4 s | Impacto + 1,0 s |

Comprobación: B < 2 < 3 < 4 < 5 < 6 < 7. Si no se cumple, marcar las posiciones dudosas en la pantalla de revisión.

Ritmo: subida = top − B; bajada = impacto − top; ritmo = subida / bajada.

## 4. Pantalla de revisión
- El usuario ve las 7 posiciones y puede moverlas fotograma a fotograma.
- En la preparación toca la cabeza del palo. Con ese punto y las manos sale la línea del palo.
- En 2, la cabeza del palo se sigue con `TrackObjectRequest` desde la preparación (la subida es lenta al principio). Si se pierde, el usuario la coloca.
- En 3 y 5 la app propone la línea del palo (bordes alrededor de las manos y votación de rectas). El usuario puede arrastrar el extremo.

## 5. Medidas
Coordenadas de imagen con y hacia abajo. En un diestro visto desde detrás, la bola queda a la derecha del jugador ("hacia la bola" = +x).

| Fase | Medida | Cálculo | Bien | Qué se dice si no |
|---|---|---|---|---|
| 1 | Inclinación | Ángulo entre centro de cadera→cuello y la vertical | 28° a 42° | "Estás algo erguido" (< 28°) o "Te inclinas demasiado" (> 42°) |
| 1 | Flexión de rodilla | 180° − ángulo cadera-rodilla-tobillo | 15° a 30° | "Rodillas casi rectas" o "Demasiado sentado" |
| 1 | Brazos bajo los hombros | (muñeca.x − hombro.x) / tronco | −0,05 a 0,20 | "Manos lejos del cuerpo" o "Manos muy pegadas" |
| 1 | Plano del palo | Ángulo de la línea cabeza del palo→manos con la horizontal | Informativo | Define la línea de plano para comparar |
| 1 | Cabeza | Posición de referencia (nariz u orejas) y radio del círculo | — | — |
| 1 | Línea de cadera | x de la parte de atrás de la cadera ≈ centro de cadera − 0,12 × estatura en px | — | Referencia para el impacto |
| 2 | Cabeza del palo y manos | Distancia horizontal cabeza del palo − manos, normalizada | Entre −0,05 y +0,10 del tronco | "Se va por dentro, detrás de las manos" o "Sale hacia fuera" |
| 3 | Palo a mitad de subida | Ángulo del palo frente al plano del address, y a dónde apunta la empuñadura (hacia la línea de la bola) | Diferencia ≤ 10° | "Palo plano" (más bajo que el plano) o "Palo vertical" |
| 4 | Duración de la subida | top − B | Informativo | — |
| 4 | Manos altas | (hombro.y − manos.y) / tronco | > 0,35 | "Subida corta" (< 0,10) |
| 4 | Cabeza estable | Desplazamiento de la cabeza desde la preparación | ≤ ~5 cm | "La cabeza se mueve unos N cm" |
| 5 | Palo en la bajada | Ángulo del palo en 5 frente a 3 y al plano | Dentro de ±8° del plano | "Más vertical al bajar" o "Más plano al bajar" |
| 6 | Inclinación en el impacto | Inclinación en 6 − inclinación en 1 | Pérdida ≤ 8° | "Te levantas: pasas de A a B grados" |
| 6 | Cadera hacia la bola | Avance de la parte de atrás de la cadera hacia la bola entre 1 y 6 | ≤ ~3 cm | "La cadera se acerca a la bola" |
| 6 | Cabeza en el impacto | Desplazamiento desde la preparación | ≤ ~5 cm | "La cabeza sube" o "baja" |
| 7 | Final equilibrado | Articulaciones casi quietas 0,8 s tras el final | Sí | "Pierdes el equilibrio al terminar" |
| 7 | Final completo | Manos por encima del hombro de delante | Sí | "El final se queda corto" |
| R | Ritmo | subida / bajada | 2,6 a 3,4 | "Subes demasiado rápido" (< 2,4) o "Subes muy despacio" (> 3,8) |

Referencia del ritmo: los profesionales rondan 3 : 1.

## 6. Nota (Scoring)
- Cada fase y el ritmo reciben una nota de 0 a 10. Se empieza en 10 y se resta por cada medida fuera de rango, de forma proporcional a cuánto se sale (por ejemplo, 0,25 puntos por grado fuera en la inclinación), con un mínimo de 2.
- Pesos: Preparación 1, Takeaway 1, Mitad de subida 1, Top 1, Transición 2, Impacto 2, Final 1, Ritmo 1,5.
- Nota total = suma de (peso × nota) / suma de pesos × 10, redondeada.
- Etiquetas: 90 o más "Nivel muy alto"; 80 a 89 "Muy sólido"; 70 a 79 "Buena base"; 60 a 69 "Con margen de mejora"; menos de 60 "A construir".
- Puntos fuertes: fases con 8 o más (hasta 4).
- A mejorar: las 3 notas más bajas por debajo de 7, cada una con su fallo.
- Prioridad nº 1: el fallo con mayor (peso × (10 − nota)), pero si hay una cadena de causa, se elige la causa. Ejemplo: takeaway por dentro y palo plano a mitad de subida: la prioridad es el takeaway, y la frase de la fase 3 empieza por "Por eso,".
- Todas las constantes en un solo archivo para afinarlas con el profesor.

## 7. Fallos y ejercicios (FaultLibrary)
| Fallo | Etiqueta del informe | Ejercicio |
|---|---|---|
| Postura erguida | Postura demasiado recta | Palo apoyado en la espalda: cabeza, espalda alta y coxis tocándolo mientras te inclinas desde la cadera. |
| Demasiado inclinado o sentado | Postura demasiado baja | Frente al espejo: rodillas un poco flexionadas y peso en la mitad del pie. |
| Manos lejos del cuerpo | Brazos lejos | Deja caer los brazos relajados y agarra el palo donde caen las manos. |
| Takeaway por dentro | Takeaway por dentro | Varilla en el suelo paralela a la línea: la cabeza del palo va por encima de ella hasta que el palo está paralelo al suelo. |
| Takeaway por fuera | Takeaway por fuera | Misma varilla: que la cabeza del palo no salga por fuera de ella. |
| Palo plano a mitad de subida | Subida plana | Para en mitad de la subida: la punta del palo mira al cielo y la empuñadura apunta a la línea de la bola. |
| Palo vertical a mitad de subida | Subida vertical | Swings lentos sintiendo que las manos van más alrededor del cuerpo. |
| Subida corta | Subida corta | Swings con pausa arriba, girando la espalda hacia el objetivo. |
| Cabeza que se mueve | Cabeza inestable | Graba con tu sombra delante: mantén la cabeza dentro de una marca hasta el impacto. |
| Palo vertical al bajar | Bajada vertical | Swings a medio ritmo sintiendo que el palo cae por detrás de las manos al empezar a bajar. |
| Se levanta en el impacto | Te levantas en el impacto | Silla o bolsa tocando el glúteo: mantén el contacto hasta pasar el impacto. |
| Ritmo rápido | Ritmo rápido | Cuenta "uno, dos, tres" en la subida y "cuatro" en el impacto. |
| Final sin equilibrio | Final inestable | Aguanta el final 3 segundos con el peso en el pie de delante y el pecho mirando al objetivo. |

Son consejos generales. La Ayuda recomienda revisar el informe con el profesor.

## 8. Guion (ScriptWriter)
Estilo: frases de 4 a 14 palabras, de tú, una idea por frase, en español de España. Números escritos para que suenen bien: "2,8 a 1", "78 sobre 100", "30 grados", duraciones redondeadas a décimas al hablar ("siete décimas") aunque la pantalla muestre "0,73 s". Varias variantes por frase para no repetir siempre lo mismo.

| Bloque | Plantillas (ejemplos) |
|---|---|
| Gancho | ≥ 80: "Muy buen swing. Solo hay un detalle. ¿Lo ves?" · 70 a 79: "Casi todo encaja, pero hay un detalle. ¿Lo ves?" · 60 a 69: "Hay buena base y un par de cosas que cambiar." · < 60: "Vamos a ordenar este swing paso a paso." |
| Cámara lenta | "Ahora, a cámara lenta y con líneas: plano, cadera y cabeza." |
| 1 Preparación | Bien: "Buena preparación. Postura atlética, rodillas flexionadas y brazos relajados." · Mal: "Estás algo erguido. Inclínate un poco más desde la cadera." |
| 2 Takeaway | Bien: "El palo arranca recto hacia atrás." · Mal: "El palo se va por dentro muy pronto, detrás de las manos." |
| 3 Mitad de subida | Bien: "A mitad de subida, el palo está en su plano." · Mal: "Por eso, a mitad de subida, el palo queda plano." |
| 4 Top | Bien: "Arriba, compacto y controlado. Manos altas y la cabeza quieta." · Mal: "La cabeza se mueve unos {n} centímetros. Intenta mantenerla." |
| 5 Transición | "Al bajar, el palo se pone más vertical, pero vuelve cerca de su plano." · "Al bajar, el palo se queda vertical. Déjalo caer por detrás de las manos." |
| 6 Impacto | Bien: "En el impacto mantienes la postura. Muy bien." · Mal: "En el impacto pierdes inclinación: pasas de {a} a {b} grados. Intenta quedarte más abajo." |
| 7 Final | Bien: "Y el final, completo y equilibrado." · Mal: "El final se queda corto. Termina mirando al objetivo y aguanta tres segundos." |
| Ritmo | "Tu ritmo es de {r} a 1. Muy cerca del 3 a 1 de los profesionales." · "Tu ritmo es de {r} a 1. Subes demasiado rápido: tómate más tiempo arriba." |
| Nota | "¿Acertaste? Tu nota: {n} sobre 100. {Etiqueta}." |
| Informe | "Lo primero a trabajar: {prioridad}. Practícalo con estos ejercicios." |

## 9. Voz y audio
Lo que se aprendió del audio del vídeo de referencia (detalle en `docs/08`):
- Solo voz: sin música, sin efectos y sin el sonido del golpe. Silencio total entre frases.
- Unas 160 palabras por minuto mientras habla; la voz ocupa alrededor del 70 % del vídeo.
- Frases cortas de 1 a 5 s. Silencios de 0,4 a 0,8 s dentro de un bloque y de 1 a 2,6 s entre bloques.
- Volumen muy constante: unos −16,6 LUFS integrados y un rango de sonoridad de 3,6 LU.

Objetivos para la app:
- Voz con `AVSpeechSynthesizer` (ver `docs/01`), velocidad ajustada a unas 155 palabras por minuto.
- Pausas: 0,45 s entre frases del mismo bloque y 1,2 s entre bloques.
- Normalizar a −16 LUFS integrados, pico real ≤ −1 dBTP.
- Opción "Sonido del golpe en el gancho": el audio original del impacto a −12 dB por debajo de la voz (desactivada por defecto). Sin música por defecto.
- Subtítulos palabra a palabra con los tiempos de los marcadores de la voz.

## 10. Montaje del vídeo
Duración de cada bloque = máximo entre su mínimo visual y su narración + 0,6 s.

| Bloque | Imagen | Mínimo |
|---|---|---|
| Gancho | Swing a velocidad real. Título "¿Qué nota le pones a este swing?", insignia "?/100" y barra inferior con la frase del gancho y su progreso. | 3 s |
| Cámara lenta | Swing a × 0,25. Chip con el nombre de la fase que va pasando. Zona de plano, círculo de cabeza, línea de cadera y trayectoria de las manos dibujándose (subida en blanco, bajada en amarillo). | Duración del swing × 4 |
| 1 a 7 Pausas | Fotograma congelado con las líneas y medidas de su fase (tabla del punto 5), chip "n/7 Nombre", "Pausa" y "F{fotograma}, {t} s". Las etiquetas aparecen escalonadas cada 0,15 s. | 2,5 s cada una |
| Ritmo | "2,8 : 1" grande, barras de subida y bajada que crecen en 0,8 s, referencia "Profesionales ≈ 3 : 1" y pie "Medido a 240 fps: subida N fotogramas, bajada M". | 4 s |
| Nota | Cuenta de 0 a la nota en 1,2 s, etiqueta, filas por fase con círculo (≥ 8) o cuadrado (< 6), leyenda y pie "Transición e impacto cuentan doble; el ritmo, 1,5 veces." | 5 s |
| Informe | Puntos fuertes, a mejorar (cuadrados 1 a 3), ejercicios, prioridad nº 1 y pie "Medidas aproximadas, vídeo 2D a N fps" con la fecha. | 6 s |
| Cierre | Marca "Trazo" pequeña con la fecha (opcional en ajustes). | 2 s |

- Entre bloques, fundido de 0,2 s. Nada de transiciones llamativas.
- Versión corta (ajustes): gancho, cámara lenta a × 0,5, las 3 fases más importantes para la nota, nota y prioridad. Entre 30 y 40 s.
- Versión completa: entre 60 y 90 s.
- Subtítulos en todos los bloques; sobre las tarjetas claras, en Pino con contorno blanco.

## 11. Honestidad
- Pie fijo en el informe: "Medidas aproximadas, vídeo 2D a N fps".
- Si una medida no se puede calcular (articulación tapada, palo sin marcar), se omite y se dice en el informe, sin inventar.
