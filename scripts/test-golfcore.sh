#!/bin/bash
# Pasa los tests de GolfCore en el PC con la imagen oficial de Swift para Linux (Docker).
# Uso (desde la raíz del repo, en Git Bash): bash scripts/test-golfcore.sh [filtro]
# Ejemplo: bash scripts/test-golfcore.sh ImpactDetectorTests
#
# Es solo un atajo para no esperar al CI en cada cambio: GolfCore no usa nada de Apple,
# así que compila igual en Linux. El que manda sigue siendo el CI (macOS, el mismo Swift).
# La carpeta de compilación vive en un volumen de Docker (golfcore-build) para no llenar el repo
# y para que la segunda vez solo recompile lo que ha cambiado.
# Se compila optimizado (-c release), como en el CI: los tests de audio van unas 10 veces más rápido.
set -euo pipefail

IMAGE="swift:6.3"   # la misma versión de Swift que el Xcode del CI (6.3.3 en la etapa 2)
ROOT="$(cd "$(dirname "$0")/.." && (pwd -W 2>/dev/null || pwd))"
FILTER=()
if [ $# -gt 0 ]; then FILTER=(--filter "$1"); fi

# Git Bash convierte las rutas que empiezan por / en rutas de Windows: aquí no debe hacerlo.
export MSYS_NO_PATHCONV=1
docker run --rm \
  -v "$ROOT/Packages/GolfCore:/pkg" \
  -v golfcore-build:/build \
  -w /pkg "$IMAGE" \
  swift test -c release --scratch-path /build "${FILTER[@]}"
