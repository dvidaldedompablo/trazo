#!/bin/bash
# Hace las capturas del simulador en el CI. Uso: bash scripts/screenshots.sh <UDID>
# Abre cada pantalla con -UITestScreen <nombre> y guarda un PNG en ci-shots/.
set -euo pipefail

UDID="$1"
# Pantallas que ya existen en la app. Se amplía en cada etapa (lista completa en docs/01).
SCREENS=(home components camera-tracer camera-swing library autocut autocut-voice)

APP=build-sim/Build/Products/Debug-iphonesimulator/Trazo.app
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl install "$UDID" "$APP"

# Carpeta de datos de la app en el simulador: ahí deja la marca de "pantalla lista" (UITestHarness).
READY="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)/tmp/uitest-ready"

mkdir -p ci-shots
for s in "${SCREENS[@]}"; do
  rm -f "$READY"
  # SIMCTL_CHILD_TZ pasa la zona horaria a la app: las fechas salen en hora de Madrid, no del runner.
  SIMCTL_CHILD_TZ=Europe/Madrid xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -UITestScreen "$s"
  # Se espera a que la app diga que la pantalla está abierta (hasta 60 s: a veces el runner va lento).
  # Con una espera fija de 5 s, en el run 16 tres capturas salieron con la pantalla de arranque.
  for _ in $(seq 1 60); do
    [ -f "$READY" ] && break
    sleep 1
  done
  if [ ! -f "$READY" ]; then
    echo "La pantalla $s no se ha abierto en 60 s"
    exit 1
  fi
  # Un poco más para que termine de dibujarse (miniaturas, fuentes).
  sleep 3
  xcrun simctl io "$UDID" screenshot "ci-shots/$s.png"
  echo "Captura: ci-shots/$s.png"
done
