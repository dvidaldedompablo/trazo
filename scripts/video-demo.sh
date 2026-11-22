#!/bin/bash
# Genera en el simulador el vídeo de análisis completo de demostración (Fase 4) y lo copia a ci-video/.
# Uso (en el CI, después de scripts/screenshots.sh): bash scripts/video-demo.sh <UDID>
set -uo pipefail

UDID="$1"
APP=build-sim/Build/Products/Debug-iphonesimulator/Trazo.app
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)"
mkdir -p ci-video
rm -f "$DATA/tmp/export-done"
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -UITestScreen export-demo
# Kokoro, el montaje y la recompresión pueden tardar varios minutos en el runner.
for _ in $(seq 1 1320); do
  [ -f "$DATA/tmp/export-done" ] && break
  sleep 1
done
if [ -f "$DATA/tmp/export-done" ]; then
  cp "$DATA/tmp/export-done" ci-video/resultado.txt
else
  echo "no terminó en 22 minutos" > ci-video/resultado.txt
fi
cat ci-video/resultado.txt
cp "$DATA"/Documents/*.mp4 ci-video/ 2>/dev/null || true
xcrun simctl io "$UDID" screenshot ci-video/pantalla-final.png || true
ls -la ci-video
grep -q "^ok" ci-video/resultado.txt
