#!/bin/bash
# Hace las capturas del simulador en el CI. Uso: bash scripts/screenshots.sh <UDID>
# Abre cada pantalla con -UITestScreen <nombre> y guarda un PNG en ci-shots/.
set -euo pipefail

UDID="$1"
# Pantallas que ya existen en la app. Se amplía en cada etapa (lista completa en docs/01).
SCREENS=(home components camera-tracer camera-swing library autocut)

APP=build-sim/Build/Products/Debug-iphonesimulator/Trazo.app
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl install "$UDID" "$APP"

mkdir -p ci-shots
for s in "${SCREENS[@]}"; do
  # SIMCTL_CHILD_TZ pasa la zona horaria a la app: las fechas salen en hora de Madrid, no del runner.
  SIMCTL_CHILD_TZ=Europe/Madrid xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -UITestScreen "$s"
  sleep 5
  xcrun simctl io "$UDID" screenshot "ci-shots/$s.png"
  echo "Captura: ci-shots/$s.png"
done
