"""Voz del análisis con Kokoro-82M (voz ef_dora, español), en el laboratorio del PC.

Fase 1 de los cambios del análisis (22-11-2026): sustituir la voz del iPhone por Kokoro. Este script
genera audio a partir de un texto, con las reglas pedidas:
  - Kokoro-82M, voz ef_dora, lang_code "e" (español), velocidad 0,95;
  - frases cortas, con una pausa natural entre frase y frase (más larga entre párrafos);
  - sin leer signos: el texto se limpia antes (nada de "virgulilla", "por ciento" escrito como signo, etc.);
  - volumen normalizado con ffmpeg (loudnorm a -16 LUFS, pico a -1,5 dB).

Uso (desde la raíz del repo, con el entorno lab\\.venv-voz):
    lab\\.venv-voz\\Scripts\\python lab\\voz_kokoro.py --muestra
    lab\\.venv-voz\\Scripts\\python lab\\voz_kokoro.py --texto texto.txt --salida voz.wav
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

RAIZ = Path(__file__).resolve().parent.parent
VOZ = "ef_dora"
IDIOMA = "e"            # español en Kokoro
VELOCIDAD = 0.95
MUESTREO = 24_000       # Kokoro da audio a 24 kHz
PAUSA_FRASE = 0.35      # segundos entre frases
PAUSA_PARRAFO = 0.7     # segundos entre párrafos (línea en blanco)

MUESTRA = """Este es el análisis de tu swing.

Empiezas bien colocado frente a la bola. Al subir, el palo se va un poco hacia dentro.

Bajas con buen ritmo. Lo primero que puedes mejorar es la subida."""


def limpiar(texto: str) -> str:
    """Quita lo que no se debe leer en voz alta y deja frases normales."""
    t = texto.replace("~", "unos ").replace("%", " por ciento").replace("º", " grados").replace("°", " grados")
    t = re.sub(r"[\"“”«»()\[\]{}*_#/\\|<>]", " ", t)
    t = t.replace(";", ".").replace(":", ".")
    return re.sub(r"\s+", " ", t).strip()


def frases(parrafo: str) -> list[str]:
    """Parte un párrafo en frases cortas (por el punto, la interrogación o la exclamación)."""
    partes = re.split(r"(?<=[.!?¿¡])\s+", limpiar(parrafo))
    return [p for p in partes if p.strip(" .")]


def sintetizar(texto: str) -> np.ndarray:
    from kokoro import KPipeline  # import aquí: tarda en cargar

    tubo = KPipeline(lang_code=IDIOMA)
    trozos: list[np.ndarray] = []
    parrafos = [p for p in texto.split("\n\n") if p.strip()]
    for k, parrafo in enumerate(parrafos):
        for j, frase in enumerate(frases(parrafo)):
            for _, _, audio in tubo(frase, voice=VOZ, speed=VELOCIDAD):
                trozos.append(np.asarray(audio, dtype=np.float32))
            ultima = j == len(frases(parrafo)) - 1
            trozos.append(np.zeros(int(MUESTREO * (PAUSA_PARRAFO if ultima and k < len(parrafos) - 1 else PAUSA_FRASE)), np.float32))
    return np.concatenate(trozos)


def normalizar(entrada: Path, salida: Path) -> None:
    """Volumen igualado: loudnorm de ffmpeg a -16 LUFS integrados, pico verdadero a -1,5 dB."""
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(entrada), "-af", "loudnorm=I=-16:TP=-1.5:LRA=11",
                    "-ar", str(MUESTREO), str(salida)], check=True)


def main() -> None:
    argumentos = argparse.ArgumentParser(description="Voz Kokoro (ef_dora) para el análisis.")
    argumentos.add_argument("--muestra", action="store_true", help="la muestra de unos 15 s")
    argumentos.add_argument("--texto", type=Path, help="archivo de texto (párrafos separados por una línea en blanco)")
    argumentos.add_argument("--salida", type=Path, default=RAIZ / "feedback" / "voz" / "muestra_kokoro.wav")
    a = argumentos.parse_args()
    texto = MUESTRA if a.muestra or not a.texto else a.texto.read_text(encoding="utf-8")
    a.salida.parent.mkdir(parents=True, exist_ok=True)
    crudo = a.salida.with_suffix(".crudo.wav")
    sf.write(crudo, sintetizar(texto), MUESTREO)
    normalizar(crudo, a.salida)
    crudo.unlink()
    print(f"Voz en {a.salida}")


if __name__ == "__main__":
    main()
