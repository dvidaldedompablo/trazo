# Laboratorio del PC

Herramientas del banco de pruebas de `docs/10_BANCO_DE_PRUEBAS_Y_LLM.md`. Corren en Windows, en el PC, nunca en la app.
Los vídeos, las etiquetas, las hojas de fotogramas y la caché del modelo viven en `feedback/`, que no se sube al repositorio.
Los clips de `feedback/reserva/` no los abre ningún script (regla 4 de docs/10).

## Qué hace falta

- Python 3.11 (`python --version`)
- ffmpeg y ffprobe en el PATH (`ffmpeg -version`)
- Docker Desktop abierto (para la lógica real de GolfCore)
- Para `preetiquetar.py`: una clave gratuita de Google AI Studio en `lab\.env`

## Instalar (una vez)

Desde la raíz del repo, en PowerShell:

```powershell
python -m venv lab\.venv
lab\.venv\Scripts\python -m pip install -r lab\requirements.txt
copy lab\.env.example lab\.env
notepad lab\.env
```

En `notepad`, pega tu clave detrás de `GEMINI_API_KEY=` y guarda. La clave se saca en https://aistudio.google.com/apikey.

## Los scripts, en orden

### 1. `picos.py`: picos de audio con la lógica real

```powershell
lab\.venv\Scripts\python lab\picos.py
```

Saca el audio como la app (mono, 48 kHz) y lo pasa por `ImpactDetector` y `ClipPlanner` (modo Swing) con el ejecutable `GolfLab` de `Packages/GolfCore`, dentro de Docker.
Escribe `picos` en `feedback\etiquetas\<clip>.json`: cada pico lleva `t`, `fuerza` (frente al más fuerte del clip) y `propuesto` (el corte automático lo propondría como golpe).
`es_palo` y `motivo` son tuyos; si lo vuelves a correr, se conservan.

### 2. `preetiquetar.py`: propuesta del modelo A

```powershell
lab\.venv\Scripts\python lab\preetiquetar.py
lab\.venv\Scripts\python lab\preetiquetar.py --sin-enviar
```

Manda al modelo A una hoja gruesa (12 fotogramas de todo el clip) y después hojas densas de 12 fotogramas: una por cada pico de audio (de 0,6 s antes a 0,2 s después) y otra en el tramo del swing.
Con `--sin-enviar` prepara las hojas en `feedback\derivados\<clip>\preetiquetado\` y no llama a nadie.

- Solo escribe los campos `modelo_*` (`modelo_swings`, `modelo_fases`, `modelo_palo`, `modelo_picos` y `modelo_info`). Tus etiquetas no se tocan.
- La respuesta se valida con código. Lo que no tiene sentido se descarta y se apunta en `registro.json` como aviso.
- Cada respuesta se guarda en `feedback\cache_modelo\`: la misma petición no se repite. Si se agota la cuota diaria, vuelve a lanzarlo al día siguiente y sigue donde lo dejó.
- Al final enseña los tokens y el coste por clip: el real (0 en el plan gratuito) y lo que costaría en el de pago.
- La fase "bajada" de tus etiquetas es la fase `transicion` del modelo (posición 5 de la app).
- La caja del palo se pide de 0 a 1000 en cada fotograma y se guarda en píxeles del vídeo girado.
- `--modelo B` pasa los clips por el modelo B con el mismo camino y deja el resultado en `feedback\derivados\<clip>\modelo_b\resultado.json`, sin tocar las etiquetas: es la columna B de `evaluar.py`.

### 3. `etiquetar.py`: tus etiquetas, que son la verdad

```powershell
lab\.venv\Scripts\python lab\etiquetar.py story1-puerta-de-hierro
lab\.venv\Scripts\python lab\etiquetar.py driver-campo --alto 700
```

`--alto` cambia el tamaño del vídeo en pantalla si la ventana no te cabe.

| Tecla | Qué hace |
| --- | --- |
| A / D (o flechas izquierda y derecha) | Fotograma anterior / siguiente |
| S / W (o flechas abajo y arriba) | 10 fotogramas atrás / adelante |
| I / T | Impacto / top en este fotograma (otra vez en el mismo, se borra) |
| 1 a 5 | Fase del palo: 1 preparación, 2 takeaway, 3 mitad de subida, 4 top, 5 bajada |
| Clic en el vídeo | Cabeza del palo de la fase elegida, en este fotograma |
| X | Borra la marca del palo de la fase elegida |
| J | Salta al fotograma que propone el modelo para la fase elegida |
| P / O | Pico de audio siguiente / anterior |
| Y / N | El pico elegido es / no es el golpe del palo (otra vez la misma, queda sin marcar) |
| M | Con música: sí / no |
| [ / ] y + / - | Swing anterior / siguiente, añadir / quitar swing |
| G | Guardar |
| H | Ayuda en pantalla |
| Q o Esc | Salir (con cambios sin guardar, pulsa dos veces) |

Un clic en la línea de tiempo de abajo salta a ese instante. Los picos que propone el corte automático salen en rojo, los que marcas como palo en verde y los que no, en gris.
Lo del modelo sale en magenta: es solo una pista. Mira el fotograma y corrige.
Cada instante es el real del fotograma (los vídeos pueden ser de frecuencia variable) y cada punto está en píxeles del vídeo girado.

Al guardar, `golpes` se pone solo: los swings que tienen impacto.
En la consola sale la comparación con la propuesta del modelo y cuántas has cambiado. Criterio del recuento: un instante a 2 fotogramas o más, un punto fuera de la caja del modelo o un pico con otra respuesta.
Si cierras la ventana con la X sin guardar, tus cambios quedan en `<clip>.sin-guardar.json`.

`motivo` de cada pico no se puede escribir desde la ventana: si quieres dejar una nota, edítalo en el JSON con el bloc de notas.

### 3b. `claude_web.py`: etiquetas puestas por Claude web (en lugar del paso 3)

Decisión del usuario (21-11-2026). Aviso: así la tabla de `evaluar.py` compara una IA con otra y no dice si aciertan de verdad; las etiquetas quedan marcadas con `"autor_etiquetas": "claude-web (...)"`.

```powershell
lab\.venv\Scripts\python lab\claude_web.py preparar
lab\.venv\Scripts\python lab\claude_web.py importar driver-campo respuesta.txt
```

- `preparar` crea `feedback\para_claude_web\<clip>\` con las hojas de fotogramas (`01-vista-general.jpg`, `NN-swing.jpg` y `NN-impacto.jpg`) y `mensaje.txt`. En claude.ai, un chat nuevo por clip: adjunta todas las hojas de ese clip, pega el texto de `mensaje.txt` y envía.
- A Claude web no se le enseñan las propuestas de Gemini; de ellas solo se usa el impacto para recortar el tramo del swing.
- `importar` valida la respuesta (fotogramas enviados, fases en orden, x e y de 0 a 1000) y, si algo falla, no escribe nada. `golpes` y `musica` salen de la tabla de docs/10; `es_palo` de cada pico se deduce del impacto (Claude web no oye el audio). Deja `revision.jpg` con el palo marcado para mirarlo a ojo.
- Si luego corriges algo con `etiquetar.py`, al guardar el autor pasa a "claude-web (...), revisado por el usuario".

### 4. `scripts\evaluar.py`: la tabla del banco

```powershell
lab\.venv\Scripts\python scripts\evaluar.py
```

Compara con las etiquetas la lógica actual (GolfCore real con la pose de MediaPipe del 17-11, en `feedback\derivados\<clip>\pose\poses.json`) y el modelo B. Saca golpes bien contados, picos falsos, error del impacto y del top en fotogramas y palo encontrado (a no más del 5 % del alto del vídeo de la marca). Deja en `feedback\derivados\<clip>\evaluar\` las imágenes `palo-*.jpg` con lo detectado (cian) y la marca con su círculo (magenta).

## `GolfLab`

Es un ejecutable aparte dentro de `Packages/GolfCore` (`Sources/GolfLab`). Llama a la lógica real y escribe JSON; no cambia nada de ella y la app no lo enlaza.
`picos.py` lo compila y lo lanza con la imagen `swift:6.3`, la misma de `scripts/test-golfcore.sh`.
Órdenes: `picos` (detector de audio y corte automático), `swing` (posiciones con `SwingImpactChooser`, como `SwingAnalyzer` en la app), `linea` (`ClubLineFinder`) y `seguir` (`TemplateTracker`, de la preparación al takeaway).
