#!/bin/bash
# Descarga la voz Kokoro para la app: la librería sherpa-onnx para iPhone y el modelo.
# No se suben al repositorio (unos 150 MB): los baja el CI (con caché) y también vale en el PC.
# Uso (desde la raíz del repo): bash scripts/descargar-kokoro.sh
#
# - sherpa-onnx 1.13.8: la última versión que trae espeak-ng dentro (pasa el texto a fonemas);
#   desde la 2.0 hay que hacerlo aparte. Variante "shared-onnxruntime-static": un solo framework.
# - kokoro-int8-multi-lang-v1_0: Kokoro-82M v1.0 comprimido a int8, con las 54 voces (ef_dora = 28).
#   Solo se copia lo que hace falta para el español: el modelo, las voces, los tokens y espeak-ng.
set -euo pipefail

SHERPA=1.13.8
MODELO=kokoro-int8-multi-lang-v1_0
BASE=https://github.com/k2-fsa/sherpa-onnx/releases/download
TMP="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/kokoro-descarga"
mkdir -p Vendor "$TMP"

if [ ! -d Vendor/SherpaOnnxC.xcframework ]; then
  echo "Descargando sherpa-onnx $SHERPA para iOS..."
  curl -fsSL -o "$TMP/sherpa.zip" "$BASE/xcframework/sherpa-onnx-v$SHERPA-ios-shared-onnxruntime-static.xcframework.zip"
  unzip -q -o "$TMP/sherpa.zip" -d Vendor
fi

if [ ! -f Vendor/Kokoro/model.int8.onnx ]; then
  echo "Descargando el modelo $MODELO..."
  curl -fsSL -o "$TMP/modelo.tar.bz2" "$BASE/tts-models/$MODELO.tar.bz2"
  tar xjf "$TMP/modelo.tar.bz2" -C "$TMP"
  rm -rf Vendor/Kokoro && mkdir -p Vendor/Kokoro
  for f in model.int8.onnx voices.bin tokens.txt LICENSE; do cp "$TMP/$MODELO/$f" Vendor/Kokoro/; done
  cp -R "$TMP/$MODELO/espeak-ng-data" Vendor/Kokoro/
fi
du -sh Vendor/SherpaOnnxC.xcframework Vendor/Kokoro
