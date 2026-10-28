# Compilación en GitHub Actions e instalación

## Por qué así
- No hay Mac. Los runners `macos-26` de GitHub traen Xcode y simuladores.
- En repositorios **públicos**, los runners estándar son gratis. En privados, el plan gratuito incluye 2.000 minutos al mes y los de macOS cuestan unas 10 veces más que los de Linux: se agotan en pocas compilaciones. Por eso el repo es público y no lleva nada privado.
- El `.ipa` sale **sin firmar**. Sideloadly lo firma en el PC con el Apple ID gratuito del usuario.

## Requisitos en el PC (los instala el usuario, ver el Word)
- Git for Windows, GitHub CLI (`gh`) con sesión iniciada y permiso `workflow`, VS Code con la extensión Claude Code. Opcional: ffmpeg.
- Comprobar: `git --version`, `gh auth status` (debe listar `workflow` entre los permisos). Si falta: `gh auth refresh -s workflow`.

## Repositorio
- Nombre `trazo`, público. Crear con `gh repo create trazo --public --source . --push`.
- Usuario de GitHub: `gh api user -q .login` (sirve para el identificador `io.github.<usuario>.trazo`).
- `.gitattributes`: `* text=auto eol=lf` (los scripts del CI necesitan finales de línea LF).
- `.gitignore`: `builds/`, `ci-artifacts/`, `feedback/`, `*.ipa`, `*.xcodeproj/`, `build/`, `build-sim/`, `DerivedData/`, `.DS_Store`.

## project.yml (XcodeGen), lo esencial
```yaml
name: Trazo
options:
  bundleIdPrefix: io.github.USUARIO
  deploymentTarget:
    iOS: "26.0"
packages:
  GolfCore:
    path: Packages/GolfCore
targets:
  Trazo:
    type: application
    platform: iOS
    sources: [App]          # XcodeGen trata fuentes, imágenes y catálogos como recursos
    dependencies:
      - package: GolfCore
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: Trazo
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        UIAppFonts: [Archivo-Variable.ttf]
        NSCameraUsageDescription: Trazo usa la cámara para grabar tus golpes.
        NSMicrophoneUsageDescription: Trazo usa el micrófono para oír el impacto de la bola.
        NSPhotoLibraryUsageDescription: Trazo lee tus vídeos de golf de Fotos.
        NSPhotoLibraryAddUsageDescription: Trazo guarda en Fotos los vídeos que crees.
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: io.github.USUARIO.trazo
        SWIFT_VERSION: "6.0"
        TARGETED_DEVICE_FAMILY: "1"
        MARKETING_VERSION: "0.1"
        CURRENT_PROJECT_VERSION: "1"
```
Ajustar las rutas a la estructura real. `Packages/GolfCore/Package.swift` debe declarar `platforms: [.iOS(.v26), .macOS(.v15)]` para que `swift test` funcione en el runner de macOS.

## Flujo de trabajo `.github/workflows/ci.yml` (referencia)
Comprobar la versión de las acciones y de Xcode disponibles cuando se escriba (pueden haber cambiado).
```yaml
name: CI
on:
  push:
    branches: [main]
  workflow_dispatch:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build:
    runs-on: macos-26
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable
      - name: Herramientas
        run: brew install xcodegen xcbeautify
      - name: Generar proyecto
        run: xcodegen generate
      - name: Tests de GolfCore
        run: swift test -c release --package-path Packages/GolfCore   # optimizado: los tests de audio van mucho más rápido
      - name: Compilar IPA sin firmar
        run: |
          set -o pipefail
          xcodebuild -project Trazo.xcodeproj -scheme Trazo -configuration Release \
            -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build | xcbeautify
          mkdir -p Payload
          cp -R build/Build/Products/Release-iphoneos/Trazo.app Payload/
          zip -qry Trazo.ipa Payload
      - uses: actions/upload-artifact@v4
        with:
          name: ipa
          path: Trazo.ipa
          retention-days: 14

  screenshots:
    runs-on: macos-26
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable
      - name: Herramientas
        run: brew install xcodegen xcbeautify
      - name: Generar proyecto
        run: xcodegen generate
      - name: Elegir simulador (tamaño de iPhone 17e si existe)
        run: |
          pick() { xcrun simctl list devices available | sed -nE "s/^ +($1) \(([0-9A-F-]+)\).*/\2/p" | head -1; }
          UDID=$(pick 'iPhone 17e'); [ -z "$UDID" ] && UDID=$(pick 'iPhone 16e'); [ -z "$UDID" ] && UDID=$(pick 'iPhone 17')
          echo "UDID=$UDID" >> "$GITHUB_ENV"
      - name: Compilar para simulador
        run: |
          set -o pipefail
          xcodebuild -project Trazo.xcodeproj -scheme Trazo -configuration Debug \
            -destination "id=$UDID" -derivedDataPath build-sim build | xcbeautify
      - name: Capturas
        run: bash scripts/screenshots.sh "$UDID"
      - uses: actions/upload-artifact@v4
        with:
          name: screenshots
          path: ci-shots/
          retention-days: 14
```

## `scripts/screenshots.sh` (referencia)
```bash
#!/bin/bash
set -euo pipefail
UDID="$1"
APP=build-sim/Build/Products/Debug-iphonesimulator/Trazo.app
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl install "$UDID" "$APP"
mkdir -p ci-shots
for s in home camera-tracer camera-swing processing adjust tracer-result review swing-result help settings library history; do
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -UITestScreen "$s" || true
  sleep 4
  xcrun simctl io "$UDID" screenshot "ci-shots/$s.png"
done
```
- En el simulador no hay cámara: con `-UITestScreen` la app usa las imágenes de `design/demo/` (copiadas a `App/Resources/DemoData/`) como fondo de vídeo.
- Las detecciones de Vision de trayectorias no funcionan en el simulador. Las pantallas de demostración usan datos inventados y marcados como tales.

## Comandos de Claude Code para el bucle
```bash
git add -A && git commit -m "Etapa N: ..." && git push
sleep 15                                         # da tiempo a que GitHub cree el run
RUN=$(gh run list --commit "$(git rev-parse HEAD)" -L 1 --json databaseId -q '.[0].databaseId')
gh run watch "$RUN" --exit-status                # sin argumentos gh pregunta, y aquí no se puede contestar
gh run view "$RUN" --log-failed                  # solo si falla
gh run download "$RUN" -n ipa -D builds/
gh run download "$RUN" -n screenshots -D ci-artifacts/
```
Luego mirar cada PNG de `ci-artifacts/` y compararlo con `design/capturas/`.

## Opcional: tests de GolfCore en el PC con Docker
GolfCore solo usa Foundation, así que sus tests también compilan con Swift para Linux. Con Docker Desktop encendido:
```bash
bash scripts/test-golfcore.sh                  # todos los tests
bash scripts/test-golfcore.sh TracerCurveTests # solo una suite (filtro de `swift test`)
```
Usa la imagen oficial `swift:6.3` (la misma versión de Swift que el CI) y un volumen `golfcore-build` para la compilación. Compila optimizado (`-c release`), igual que el CI: los tests con minutos de audio pasan de unos 20 s a unos 2 s. Tarda segundos en vez de una vuelta de CI. Es un atajo: lo que vale es el CI en verde. Para liberar espacio: `docker rmi swift:6.3` y `docker volume rm golfcore-build`.

## Opcional: probar la app en el navegador
Appetize permite subir una compilación de simulador y usarla en el navegador. El plan gratuito da unos 30 minutos al mes en sesiones de 3 minutos (comprobar en su web). Útil para tocar la interfaz alguna vez; para el día a día bastan las capturas del CI.

## Instalación con Sideloadly (resumen técnico; los pasos para el usuario están en el Word)
- Sideloadly en Windows necesita iTunes e iCloud en su versión de la web de Apple, no las de Microsoft Store.
- Funciona con Apple ID gratuito. La app firmada dura 7 días.
- Usar **siempre el mismo identificador** de app. Las cuentas gratuitas tienen un límite de 10 App IDs nuevos cada 7 días.
- En el iPhone: activar el Modo de desarrollador y confiar en el perfil del Apple ID.
- Sideloadly tiene renovación automática en segundo plano (el PC encendido y el iPhone localizable). La forma segura es renovar a mano cada semana con el cable.
