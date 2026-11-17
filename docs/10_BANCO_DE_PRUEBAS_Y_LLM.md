# Banco de pruebas y análisis con un modelo externo

Para Claude Code. Lee este archivo entero y `CLAUDE.md` antes de empezar. Una fase por sesión: al terminar una, escribe el resumen que pide `CLAUDE.md`, enseña la tabla y espera. Escribe `/clear` entre fases.

## Por qué existe este plan

El 17-11-2026 la app falló con vídeos válidos: "No se ve a nadie", hasta 8 golpes inventados donde hay uno y la cabeza del palo sin encontrar. La causa no es un modelo que falte, sino reglas con números fijos ajustadas con tres vídeos, sin vídeos con la respuesta correcta apuntada. Por eso el orden es: medir primero, probar después un modelo con visión como verificador y, solo si mejora la medida, integrarlo en la app.

## Reglas para todas las fases

1. **Ningún umbral ni constante cambia sin medir.** Antes de tocar una constante, una regla de `GolfCore` o un valor de `App/`, corre `scripts/evaluar.py` y pega en `docs/PROGRESO.md` la tabla de antes y la de después. Sin tabla, no se cambia.
2. **El modelo propone y el código decide.** La respuesta del modelo se pide en JSON con campos fijos, con temperatura 0, y se valida con código antes de usarla (fases en orden, instantes dentro del clip, bajada de 0,1 a 0,6 s). Si el modelo duda o el código no valida, la app pide el toque de refuerzo. Nunca inventes un resultado.
3. **Las etiquetas del usuario son la verdad.** Las propuestas del modelo van en campos con el prefijo `modelo_` y nunca se mezclan con las del usuario. El modelo que preetiqueta tiene que ser distinto del que se evalúa; si fueran el mismo, la medida sale inflada.
4. **Los clips de reserva no se tocan.** Los que estén en `feedback/reserva/` no se abren, no se analizan, no se sacan fotogramas de ellos y no se usan para ajustar nada hasta que el usuario escriba exactamente "prueba final". Puedes comprobar que existen y copiarlos sin abrirlos.
5. **Nada privado al repositorio, que es público.** Vídeos, etiquetas y claves quedan fuera. Antes de cada commit, comprueba con `git status` y `git check-ignore -v feedback lab/.env` que `feedback/` y `lab/.env` están ignorados. Si no lo están, añádelos a `.gitignore` en el mismo commit.
6. **La red.** La app sigue sin llamadas de red hasta que la Fase 0 escriba la excepción y el usuario apruebe la Fase 4. El laboratorio de Python del PC sí llama al modelo externo.
7. **Honestidad con la medida.** El banco son 3 clips que ya se usaron para ajustar la lógica actual: la línea base saldrá mejor de lo que es. Dilo en cada tabla que pegues.
8. Español llano, comentarios en español, Windows. Si algo solo se puede comprobar con un paso del usuario, dile la lista concreta de qué hacer.

## Los vídeos

**Banco (3 clips, ya están en `feedback/`).** Identifícalos por su huella, no por el nombre del archivo. Propón al usuario renombrarlos y espera su sí.

| Nombre propuesto | Huella | Golpes |
| --- | --- | --- |
| `story1-puerta-de-hierro.mp4` | 9,06 s, 390 fotogramas, unos 43 fps variables. Grabación de pantalla de una story (original 1170x1920, copia de WhatsApp 480x784). Con música | 1 |
| `story2-simulador.mp4` | 10,26 s, 384x832, 60 fps variables, 614 fotogramas. Story en un simulador. Con música | 1 |
| `driver-campo.mp4` | 10,87 s, 1024x576 con rotación de -90 grados por metadato, 30 fps. Desde los 10 s el jugador vuelve a ponerse a la bola sin hacer swing | 1 |

Ya renombrados (17-11-2026): los vídeos están en `feedback/<nombre>.mp4`; lo que se sacó de cada uno el 17-11 (audio en float32 a 48 kHz, pose de MediaPipe, fotogramas) está en `feedback/derivados/<nombre>/`, y las capturas del iPhone en `feedback/capturas/`.

**Reserva (2 clips).** El usuario los copiará a `feedback\reserva\` como `driver-tee.mp4` y `open-espana.mp4`. Si te pide copiarlos él, te dará las rutas de origen en el chat: no las escribas en el repositorio, que es público.

## Esquema de las etiquetas

Un archivo por clip en `feedback/etiquetas/<clip>.json`. Los píxeles son los del vídeo ya girado, con el origen arriba a la izquierda. Los tiempos son segundos reales de cada fotograma (los vídeos pueden ser de frecuencia variable).

```json
{
  "clip": "story1-puerta-de-hierro.mp4",
  "musica": true,
  "golpes": 1,
  "swings": [{ "top": null, "impacto": null }],
  "palo": [
    { "fase": "preparacion", "t": null, "x": null, "y": null },
    { "fase": "takeaway", "t": null, "x": null, "y": null },
    { "fase": "mitad_subida", "t": null, "x": null, "y": null },
    { "fase": "top", "t": null, "x": null, "y": null },
    { "fase": "bajada", "t": null, "x": null, "y": null }
  ],
  "picos": [{ "t": 0.0, "es_palo": null, "motivo": "" }],
  "modelo_swings": null,
  "modelo_fases": null,
  "modelo_palo": null
}
```

`picos` lo rellena el detector de audio actual con todos los picos que encuentra; el usuario marca `es_palo` en cada uno. Los campos `modelo_*` solo los escribe `lab/preetiquetar.py`.

## Fase 0. Permiso en el proyecto

1. Edita `CLAUDE.md`: cambia "llamadas de red fuera del alcance" por una excepción escrita. Solo se permite el análisis con un modelo externo con visión, con la clave en el llavero (Keychain), escrita por el usuario en Ajustes, y con un aviso antes de enviar un clip. Corrige lo que choque en "Seguridad y privacidad".
2. Añade a `CLAUDE.md` la regla 1 de este archivo (nada se cambia sin tabla).
3. Añade una línea al mapa de documentos con este archivo.
4. No toques código. Enseña el diff al usuario y haz commit solo cuando él diga que sí.

## Fase 1. Banco de pruebas

Crea la carpeta `lab/` con Python (`requirements.txt`, `README.md` con cómo correr cada script en Windows y `.env.example`; `lab/.env` va en `.gitignore`). Comprueba antes `python --version`, `ffmpeg -version` y que Docker Desktop está abierto; si falta algo, dile al usuario qué instalar y para.

1. **`lab/etiquetar.py`**, herramienta para que el usuario etiquete a mano con OpenCV. Abre un vídeo, muestra el instante real de cada fotograma, avanza y retrocede de uno en uno (A y D) y de diez en diez (W y S). Las teclas I y T marcan impacto y top. Los números 1 a 5 eligen la fase y un clic marca la cabeza del palo en ese fotograma. G guarda el JSON del esquema de arriba. Debe poder reabrir un JSON y corregirlo.
2. **Picos de audio.** Con la lógica real de `GolfCore` (con Docker, como `scripts/test-golfcore.sh`), saca los picos del detector y rellena `picos` en cada JSON. Si hace falta un ejecutable pequeño que exporte JSON, créalo como target aparte de `Packages/GolfCore` sin cambiar la lógica.
3. **`lab/preetiquetar.py`**, para ahorrar trabajo al usuario con el modelo A.
   - Dos pasadas: una hoja gruesa de 12 fotogramas numerados que cubre todo el clip, para encontrar dónde está el swing; y hojas densas de 8 a 12 fotogramas numerados, con el instante impreso en cada uno, alrededor de cada pico y del tramo del swing.
   - Pide JSON con: `hay_swing` (sí, no o no_se), fase de cada fotograma (preparacion, takeaway, mitad_subida, top, transicion, impacto, final o ninguna), `zona_palo` aproximada (caja en píxeles) y `confianza` de 0 a 1.
   - Guarda la respuesta en los campos `modelo_*`. Temperatura 0. Guarda en disco cada respuesta ya recibida y no repitas llamadas iguales. Registra tokens y coste por clip.
   - Clave y modelo salen de `lab/.env`. Pregunta al usuario qué proveedor y qué dos modelos usar (A para preetiquetar, B para evaluar) antes de escribir la llamada.
4. **PARADA 1.** Tras crear las herramientas y correr el preetiquetado, para. Dile al usuario que etiquete los 3 clips con `lab/etiquetar.py` corrigiendo la propuesta del modelo mirando el fotograma, y que apunte cuántas etiquetas del modelo ha corregido. No sigas hasta que confirme.
5. **`scripts/evaluar.py`.** Compara con las etiquetas del usuario y saca una tabla con una columna por método: la lógica actual (`GolfCore` con Docker y MediaPipe en lugar de Vision, como ya se hizo el 17-11) y el modelo B sin ajustar nada. Cifras:
   - Golpes bien contados (de 3 clips).
   - Picos falsos propuestos: picos que el corte automático propone como golpe y el usuario marcó `es_palo: false`.
   - Error del impacto en fotogramas, por clip.
   - Palo encontrado, sobre los 15 fotogramas etiquetados. Propón un criterio (distancia máxima entre la cabeza detectada y la etiquetada) y pregunta al usuario antes de fijarlo. Guarda imágenes con la línea dibujada para revisarlas a ojo.
6. Pega la tabla en `docs/PROGRESO.md` como "Línea base" con el aviso de la regla 7. **PARADA 2.** No cambies nada de la app.

## Fase 2. Laboratorio con el modelo (solo con la línea base hecha)

1. **`lab/verificador.py`.** Para cada pico de audio, genera su hoja de fotogramas y pregunta al modelo B si hay swing. Compara con `picos[].es_palo`. Es la prueba de si el modelo arregla los golpes inventados.
2. Prueba el modelo B para las fases del swing y para una zona aproximada del palo. Para precisar el palo, prueba además SAM 2.1 con el toque del usuario, como describe la etapa 4b de `docs/00_PLAN_Y_PROMPTS.md`.
3. Añade una columna por método a la tabla de `scripts/evaluar.py`. Dime el coste por clip y los segundos por clip.
4. **PARADA 3.** No integres nada en la app. El usuario decide con la tabla qué hace el código, qué el modelo y qué SAM.

## Fases 3 a 5. No empieces sin que el usuario lo pida

- **Fase 3.** El usuario decide el reparto y se escribe en `docs/` con la tabla que lo justifica.
- **Fase 4.** Se integra en la app una función por sesión: primero el verificador de golpes del corte automático, después las fases del swing, al final el palo. Cada una lleva su plan B local, para cuando no hay red o falla el servicio, y cumple las reglas 1 y 2.
- **Fase 5.** Prueba final con los clips de reserva y 3 clips nuevos del usuario. Solo cuando escriba "prueba final". Los pasas una sola vez por la lógica actual y por el modelo, sin ajustar nada, y comparas con las etiquetas que el usuario puso sin ayuda del modelo.
