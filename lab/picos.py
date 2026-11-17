"""Rellena `picos` en las etiquetas con el detector de audio real de GolfCore (docs/10, Fase 1, paso 2).

Para cada clip del banco: saca el audio como la app (mono, 48 kHz, float32), lo pasa por
`ImpactDetector` y `ClipPlanner` (modo Swing) con el ejecutable GolfLab dentro de Docker, y escribe
cada pico en feedback/etiquetas/<clip>.json. Lo que el usuario ya marcó (es_palo, motivo) se conserva.

Uso (desde la raíz del repo, con Docker Desktop abierto):
    lab\\.venv\\Scripts\\python lab\\picos.py            (todos los clips de feedback/)
    lab\\.venv\\Scripts\\python lab\\picos.py driver-campo
"""
from __future__ import annotations

import json
import subprocess
import sys

from comun import (DERIVADOS, FEEDBACK, RAIZ, cargar_etiquetas, clips_del_banco, extraer_audio,
                   guardar_etiquetas, leer_info, resolver_clip, ruta_etiquetas)

IMAGEN_SWIFT = "swift:6.3"  # la misma que scripts/test-golfcore.sh
# Dos picos son el mismo si están a menos de esto (el detector da el mismo instante cada vez;
# el margen es por si un cambio futuro de la lógica los mueve un poco).
MISMO_PICO_S = 0.02


def docker(*argumentos: str) -> str:
    orden = ["docker", "run", "--rm",
             "-v", f"{RAIZ / 'Packages' / 'GolfCore'}:/pkg",
             "-v", "golfcore-build:/build",
             "-v", f"{FEEDBACK}:/data:ro",
             "-w", "/pkg", IMAGEN_SWIFT, *argumentos]
    resultado = subprocess.run(orden, capture_output=True, text=True, encoding="utf-8")
    if resultado.returncode != 0:
        raise SystemExit(f"Docker falló:\n{resultado.stderr.strip()}")
    return resultado.stdout


def compilar() -> None:
    print("Compilando GolfLab en Docker (la primera vez tarda un par de minutos)...")
    docker("swift", "build", "-c", "release", "--scratch-path", "/build", "--product", "GolfLab")


def picos_de(clip) -> dict:
    info = leer_info(clip)
    audio = extraer_audio(clip, DERIVADOS / clip.stem / "audio48k.f32")
    ruta_en_docker = "/data/" + audio.relative_to(FEEDBACK).as_posix()
    return json.loads(docker("/build/release/GolfLab", "picos", ruta_en_docker, f"{info.duracion:.6f}"))


def mezclar(anteriores: list[dict], nuevos: list[dict]) -> tuple[list[dict], list[dict]]:
    """Pone los picos nuevos y les pasa las marcas del usuario de los anteriores que coinciden."""
    perdidos = []
    usados = set()
    for viejo in anteriores:
        if viejo.get("es_palo") is None and not viejo.get("motivo"):
            continue
        cercano = min(range(len(nuevos)), key=lambda i: abs(nuevos[i]["t"] - viejo["t"]), default=None)
        if cercano is not None and cercano not in usados and abs(nuevos[cercano]["t"] - viejo["t"]) < MISMO_PICO_S:
            nuevos[cercano]["es_palo"] = viejo.get("es_palo")
            nuevos[cercano]["motivo"] = viejo.get("motivo", "")
            usados.add(cercano)
        else:
            perdidos.append(viejo)
    return nuevos, perdidos


def main() -> None:
    clips = [resolver_clip(a) for a in sys.argv[1:]] or clips_del_banco()
    if not clips:
        raise SystemExit("No hay vídeos en feedback/.")
    compilar()
    for clip in clips:
        informe = picos_de(clip)
        nuevos = [{
            "t": round(p["time"], 4),
            "es_palo": None,
            "motivo": "",
            # Lo que da el detector (no son etiquetas del usuario):
            "fuerza": round(p["relativeStrength"], 3),   # fuerza / la del pico más fuerte del clip
            "propuesto": p["suggested"],                  # el corte automático lo propone como golpe
        } for p in informe["peaks"]]
        datos = cargar_etiquetas(clip)
        datos["picos"], perdidos = mezclar(datos.get("picos", []), nuevos)
        guardar_etiquetas(clip, datos)
        propuestos = [p for p in nuevos if p["propuesto"]]
        print(f"\n{clip.name}: {len(nuevos)} picos, {len(propuestos)} propuestos por el corte automático"
              f"{'' if informe['isShotSeries'] else ' (no parece una tanda de golpes: no propone ninguno)'}")
        for p in nuevos:
            print(f"  {p['t']:7.3f} s  fuerza {p['fuerza']:.2f}  {'PROPUESTO' if p['propuesto'] else ''}")
        for p in perdidos:
            print(f"  Aviso: tu marca del pico de {p['t']:.3f} s ya no tiene pico; la he quitado "
                  f"(es_palo={p.get('es_palo')}, motivo='{p.get('motivo', '')}').")
        print(f"  Guardado en {ruta_etiquetas(clip).relative_to(RAIZ)}")


if __name__ == "__main__":
    main()
