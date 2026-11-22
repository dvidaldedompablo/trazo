#!/bin/bash
# Genera en el simulador el vídeo de análisis de demostración (Fase 4) y lo copia a ci-video/.
# Primero el vídeo de verdad (variante 0). Si falla o la app se cierra, prueba variantes cortas que
# quitan una pieza cada una (capas, ejercicios, voz) para saber cuál rompe el montaje.
# Cada variante es un arranque distinto: si la app se cierra de golpe, se guarda su informe de fallo.
# Uso (en el CI, después de scripts/screenshots.sh): bash scripts/video-demo.sh <UDID>
set -uo pipefail

UDID="$1"
APP=build-sim/Build/Products/Debug-iphonesimulator/Trazo.app
BUNDLE=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)"
REPORTS="$HOME/Library/Logs/DiagnosticReports"
mkdir -p ci-video
: > ci-video/resultado.txt

run_variant() {
  local variant="$1" limit="$2"
  rm -f "$DATA/tmp/export-done" "$DATA/tmp/export-progress"
  local marker
  marker=$(mktemp)
  local out
  out=$(xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -UITestScreen export-demo -DemoVariant "$variant")
  local pid="${out##*: }"
  local state="no terminó en $limit s"
  for _ in $(seq 1 "$limit"); do
    if [ -f "$DATA/tmp/export-done" ]; then state="terminó"; break; fi
    if ! kill -0 "$pid" 2>/dev/null; then sleep 2; [ -f "$DATA/tmp/export-done" ] && state="terminó" || state="la app se cerró"; break; fi
    sleep 1
  done
  {
    echo "== variante $variant: $state"
    [ -f "$DATA/tmp/export-done" ] && cat "$DATA/tmp/export-done" && echo
    [ -f "$DATA/tmp/export-progress" ] && echo "último avance: $(cat "$DATA/tmp/export-progress")"
  } >> ci-video/resultado.txt
  if [ "$state" = "la app se cerró" ]; then
    # El informe de fallo más reciente de Trazo, posterior al arranque.
    local report
    report=$(find "$REPORTS" -name 'Trazo*' -newer "$marker" 2>/dev/null | head -1)
    if [ -n "$report" ]; then
      cp "$report" "ci-video/fallo-variante-$variant.ips"
      echo "informe de fallo: fallo-variante-$variant.ips" >> ci-video/resultado.txt
    fi
  fi
  rm -f "$marker"
  [ "$state" = "terminó" ] && grep -q "^ok" "$DATA/tmp/export-done"
}

if run_variant 0 900; then
  ok=0
else
  ok=1
  for v in 1 2 3 4; do run_variant "$v" 240 || true; done
fi
cat ci-video/resultado.txt
cp "$DATA"/Documents/*.mp4 ci-video/ 2>/dev/null || true
xcrun simctl io "$UDID" screenshot ci-video/pantalla-final.png || true
ls -la ci-video
exit $ok
