# Trazo: reglas del proyecto para Claude Code

Lee este archivo entero al empezar cada sesión. Los detalles de cada tema están en `docs/`.

## Qué es
App de iOS para uso personal de un solo golfista, en su iPhone 17e (iOS 26 o posterior).
Tres apartados en la pantalla de inicio:
1. **Tracer**: dibuja el vuelo de la bola sobre el vídeo del golpe, como en la tele. El usuario elige el color y activa o desactiva la distancia.
2. **Análisis de swing**: graba el swing y genera un vídeo explicado con voz, subtítulos, líneas de telestrador, medidas, ritmo, nota sobre 100 e informe.
3. **Ayuda**: guía de uso dentro de la app.

Fuera del alcance, siempre: App Store, servidores, cuentas de usuario, pagos, analítica, publicidad, llamadas de red. Todo se procesa en el iPhone. Única excepción posible: la integración en la nube de la etapa 4b, y solo si el usuario la aprueba por escrito.

## El tracer y la guía de javiggil
El tracer sigue la guía "El trazo de tu bola de golf, como en la tele" de javiggil, adaptada a una app sin servidor. Sus seis claves están dentro; `docs/09_GUIA_JAVIGGIL.md` dice qué se tomó, qué se cambió y por qué. No reintroduzcas subida de vídeos, servidor ni cobro. SAM 2.1, el modelo de la guía, solo entra por la etapa 4b (prueba de laboratorio en el PC) y no se integra en la app sin el visto bueno del usuario.

## El entorno (léelo dos veces)
- El usuario trabaja en **Windows**. No hay Mac. No puedes ejecutar Xcode ni el simulador en local.
- Se compila en **GitHub Actions** (`runs-on: macos-26`). Repositorio público (los minutos de macOS son gratis en repos públicos).
- Tu bucle de trabajo: escribir código, `git push`, localizar el run del commit y `gh run watch <id> --exit-status`, si falla `gh run view <id> --log-failed`, corregir y repetir. Pasa siempre el id: sin él, `gh` hace preguntas que no puedes contestar (comandos exactos en `docs/06`).
- El CI genera: `Trazo.ipa` sin firmar (artefacto `ipa`), capturas del simulador (artefacto `screenshots`) y resultados de tests.
- Descarga artefactos con `gh run download <id> -n ipa -D builds/` y `-n screenshots -D ci-artifacts/`. **Mira cada captura** (puedes leer imágenes) y compárala con `design/capturas/`.
- El usuario instala el `.ipa` con **Sideloadly** y un Apple ID gratuito. La app caduca a los 7 días y se reinstala.
- Nunca pidas al usuario que use un Mac ni Xcode. Si algo solo se puede comprobar en el iPhone, díselo con una lista concreta de qué mirar.
- Si existe `feedback/`, ahí el usuario deja vídeos o capturas del iPhone. Puedes extraer fotogramas y audio con `ffmpeg` si está instalado.

## Tecnología
- Swift 6, SwiftUI, objetivo de despliegue iOS 26.0. Sin dependencias de terceros salvo que sea imprescindible (pregunta antes).
- Proyecto generado con **XcodeGen** (`project.yml`). El `.xcodeproj` no se sube al repo; se genera en el CI.
- Paquete local `Packages/GolfCore`: lógica pura en Swift (audio, geometría, ajuste de curvas, fases, medidas, nota, guion). Sin UIKit ni SwiftUI. Con tests.
- Frameworks de Apple: Vision (pose corporal y trayectorias), AVFoundation (captura, lectura, composición, exportación), AVFAudio (voz con `AVSpeechSynthesizer`), Accelerate/vDSP (audio), Core Animation (gráficos del vídeo), SwiftData (biblioteca), Swift Charts (historial), PhotosUI, CoreMotion (nivel).
- Firma: compilar sin firmar (`CODE_SIGNING_ALLOWED=NO`). Sideloadly firma al instalar.
- Identificador de la app: `io.github.<usuario-de-github>.trazo`. Un solo target. **Sin extensiones** (widgets, etc.): con Apple ID gratuito cada extensión gasta un App ID y hay límite semanal.
- Sin push, sin iCloud, sin App Groups. Las notificaciones locales sí funcionan.
- Las APIs cambian (Vision, AVFoundation y Swift con cada iOS; `transformers` en la etapa 4b). Antes de usar una API, comprueba su documentación vigente. Si algo no compila por un cambio de API, apúntalo en `docs/PROGRESO.md`.

## Idioma y estilo
- Toda la interfaz en español de España, de tú, con palabras llanas. Términos de golf permitidos: tracer, draw, fade, takeaway, top, carry.
- Nombres de código en inglés. **Comentarios en español** en las partes importantes: el usuario está aprendiendo Swift. Explica el porqué, no lo obvio.
- Al final de cada etapa, explica en español sencillo qué has hecho y qué conceptos de Swift o de iOS has usado (3 a 6 frases).

## Diseño
- Sigue `docs/02_DISENO.md` y `design/maqueta.html` (con capturas en `design/capturas/`). Si hay conflicto, manda el documento.
- Tokens en `App/DesignSystem/`. No inventes colores ni tamaños sueltos en las vistas.
- Fuente Archivo (licencia OFL, se incluye en el proyecto) para títulos y cifras; SF Pro del sistema para el resto.
- Interfaz clara forzada en las pantallas de navegación; negro puro en las pantallas de vídeo.
- No copies la marca, el logotipo ni los colores de ninguna app o cuenta existente, tampoco del vídeo de referencia.

## Honestidad en las medidas
- La distancia del tracer **no se mide**: la introduce el usuario o sale de sus distancias por palo. Nunca escribas "medido" para la distancia.
- Las medidas del swing salen de un vídeo 2D: se muestran como aproximadas ("~2 cm") y el informe lo dice.
- Si algo falla (no se oye el impacto, se pierde la bola), la app lo dice claro, con el momento en que pasó, y ofrece el toque de refuerzo y el ajuste manual. Nunca inventes un resultado.

## Reglas de trabajo en cada etapa
1. Lee la etapa en `docs/00_PLAN_Y_PROMPTS.md` y los documentos que cite.
2. Propón un plan corto antes de tocar código. Si hay una decisión que el usuario debe tomar, pregunta.
3. Commits pequeños con mensajes claros en español.
4. Push y espera al CI. No des una etapa por terminada con el CI en rojo.
5. Revisa las capturas del CI cuando la etapa toque pantallas. Haz una lista de diferencias con la maqueta y corrígelas.
6. Actualiza `docs/PROGRESO.md` (qué se hizo, decisiones, problemas, qué falta).
7. Termina con: resumen, dónde está el `.ipa` nuevo, lista de pruebas para el iPhone y limitaciones conocidas.

## Pruebas
- `GolfCore` tiene tests unitarios con datos sintéticos; deben pasar en el CI.
- La app acepta el argumento de arranque `-UITestScreen <nombre>` para abrir cada pantalla con datos de demostración (sin cámara). El CI lo usa para las capturas.
- Lo que solo funciona en un iPhone real (cámara a 240 fps, detección de trayectorias de Vision) se valida con el usuario siguiendo `docs/07_PRUEBAS.md`.

## Seguridad y privacidad
- Nunca subas secretos, contraseñas, el Apple ID, ni vídeos personales al repo (es público).
- `builds/`, `ci-artifacts/` y `feedback/` están en `.gitignore`.
- Los vídeos se guardan en el contenedor de la app y, si el usuario lo pide, en Fotos. Nada sale del teléfono.
- Si algún día se aprueba la integración en la nube de la etapa 4b: la clave del servicio la escribe el usuario en Ajustes y se guarda en el llavero (Keychain). Nunca en el código ni en el repositorio. La app avisa antes de enviar un clip.

## Mapa de documentos
- `docs/00_PLAN_Y_PROMPTS.md`: etapas, mensajes del usuario y criterios de terminado.
- `docs/01_ARQUITECTURA.md`: carpetas, módulos, flujo de datos, APIs.
- `docs/02_DISENO.md`: sistema de diseño, pantallas, gráficos del vídeo.
- `docs/03_TRACER.md`: tracer completo.
- `docs/04_ANALISIS_SWING.md`: análisis de swing, medidas, nota, guion, voz y montaje.
- `docs/05_AYUDA_CONTENIDO.md`: textos de la guía de uso.
- `docs/06_CI_INSTALACION.md`: GitHub Actions, IPA, capturas, Sideloadly.
- `docs/07_PRUEBAS.md`: pruebas en el iPhone y criterios de aceptación.
- `docs/08_REFERENCIA_VIDEO.md`: desglose del vídeo de referencia (estructura, imagen y audio).
- `docs/09_GUIA_JAVIGGIL.md`: qué se ha tomado de la guía de javiggil, dónde está y qué se dejó fuera.
- `docs/PROGRESO.md`: diario del proyecto.
