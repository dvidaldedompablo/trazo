# Trazo

App de iOS de uso personal para un golfista. No está en la App Store: se compila en GitHub Actions y se instala con Sideloadly.

## Qué hace
- **Tracer**: dibuja el vuelo de la bola sobre el vídeo del golpe, como en la tele. Puedes elegir el color del trazo y si sale la distancia. La distancia no se mide: la escribes tú o sale de tus distancias por palo.
- **Análisis de swing**: busca siete posiciones del swing y genera un vídeo explicado con voz (Dora, de Kokoro, dentro de la app), subtítulos, líneas, medidas aproximadas, ritmo, nota sobre 100 e informe. Al final del vídeo hay un apartado "A mejorar" con tres ejercicios.
- **Ejercicios**: un catálogo de 15 fallos, cada uno con su ejercicio y un clip animado.
- **Ayuda**: la guía de uso, con el aviso de caducidad de la instalación.

Todo se procesa en el iPhone. La única excepción es Gemini, y es opcional. Si escribes tu clave gratuita de Google AI Studio en Ajustes, la app le manda hojas de fotogramas (nunca el vídeo ni el sonido) para comprobar los golpes y analizar el swing. Sin clave o sin red, la app hace ese trabajo por su cuenta.

## Requisitos
- iPhone con iOS 26 o posterior.
- Un PC con Windows, Sideloadly y un Apple ID gratuito.
- No hace falta Mac: compila GitHub Actions (`runs-on: macos-26`).

## Cómo se compila
Cada `git push` a `main` lanza `.github/workflows/ci.yml`:
1. Baja la voz Kokoro y sherpa-onnx 1.13.8 (`scripts/descargar-kokoro.sh`). No se suben al repositorio.
2. Genera el proyecto con XcodeGen (`project.yml`).
3. Pasa los tests de `Packages/GolfCore` y compila sin firmar.
4. Deja tres artefactos:
   - `ipa`: `Trazo.ipa` sin firmar;
   - `screenshots`: capturas del simulador;
   - `video-demo`: un vídeo de análisis de demostración.

Para descargarlos (comandos completos en `docs/06_CI_INSTALACION.md`):

```bash
gh run list --limit 1
gh run download <id> -n ipa -D builds/
```

Los tests de `GolfCore` también se pueden pasar en el PC con Docker y la imagen `swift:6.3`.

## Cómo se instala
1. Conecta el iPhone al PC con el cable.
2. Abre Sideloadly y arrastra `builds/Trazo.ipa`.
3. Escribe tu Apple ID y pulsa Start.
4. En el iPhone, ve a Ajustes > General > VPN y gestión de dispositivos y confía en tu Apple ID.

Con un Apple ID gratuito, la app caduca a los 7 días. La app avisa un día antes; para renovarla se repiten estos pasos con el mismo Apple ID, y los vídeos y los ajustes se conservan.

## Carpetas
| Carpeta | Qué hay |
|---|---|
| `App/` | La app en SwiftUI: pantallas, cámara, montaje de vídeo y sistema de diseño (`App/DesignSystem/`) |
| `Packages/GolfCore/` | Lógica pura en Swift (audio, geometría, curvas, fases, medidas, nota, guion), con tests |
| `assets/ejercicios/` | Clips e imágenes de los ejercicios, generados en el PC (`lab/ejercicios_animacion.py`) |
| `lab/` | Laboratorio en Python del PC: banco de pruebas, etiquetas y pruebas con Gemini |
| `scripts/` | CI, capturas, vídeo de demostración y `evaluar.py` (ninguna constante cambia sin su tabla) |
| `docs/` | Plan, diseño, especificaciones, pruebas y diario (`docs/PROGRESO.md`) |
| `design/` | Maqueta y capturas de referencia |

## Privacidad
- El repositorio es público. No contiene claves, Apple ID ni vídeos personales.
- `builds/`, `ci-artifacts/`, `feedback/` y `lab/.env` están en `.gitignore`.
- La clave de Gemini se guarda en el llavero del iPhone.

## Licencias
- Fuente Lato: SIL Open Font License.
- Kokoro-82M: Apache 2.0.
- sherpa-onnx: Apache 2.0.
- Los clips de los ejercicios están generados por el proyecto.
