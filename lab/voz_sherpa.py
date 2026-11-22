"""La voz Kokoro tal como sonará en el iPhone: sherpa-onnx 1.13.8 con el modelo int8 multilingüe.

En el iPhone no hay Python: la app usa sherpa-onnx (la misma versión, 1.13.8, que trae espeak-ng dentro)
con el modelo `kokoro-int8-multi-lang-v1_0`. Este script hace la misma muestra que lab/voz_kokoro.py
con ese motor, para comparar las dos antes de llevarlo al iPhone. Misma limpieza del texto, mismas
pausas y mismo volumen.

Uso:
    lab\\.venv-voz\\Scripts\\python lab\\voz_sherpa.py
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import sherpa_onnx
import soundfile as sf

from voz_kokoro import MUESTRA, MUESTREO, PAUSA_FRASE, PAUSA_PARRAFO, VELOCIDAD, frases, normalizar

RAIZ = Path(__file__).resolve().parent.parent
MODELO = RAIZ / "feedback" / "voz" / "modelo" / "kokoro-int8-multi-lang-v1_0"
VOZ_DORA = 28  # ef_dora en speaker2id del modelo (metadatos del .onnx)


def motor() -> sherpa_onnx.OfflineTts:
    kokoro = sherpa_onnx.OfflineTtsKokoroModelConfig(
        model=str(MODELO / "model.int8.onnx"), voices=str(MODELO / "voices.bin"), tokens=str(MODELO / "tokens.txt"),
        data_dir=str(MODELO / "espeak-ng-data"), lang="es")
    config = sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(kokoro=kokoro, num_threads=2))
    return sherpa_onnx.OfflineTts(config)


def main() -> None:
    tts = motor()
    trozos = []
    parrafos = [p for p in MUESTRA.split("\n\n") if p.strip()]
    for k, parrafo in enumerate(parrafos):
        lista = frases(parrafo)
        for j, frase in enumerate(lista):
            audio = tts.generate(frase, sid=VOZ_DORA, speed=VELOCIDAD)
            trozos.append(np.asarray(audio.samples, dtype=np.float32))
            pausa = PAUSA_PARRAFO if j == len(lista) - 1 and k < len(parrafos) - 1 else PAUSA_FRASE
            trozos.append(np.zeros(int(audio.sample_rate * pausa), np.float32))
    salida = RAIZ / "feedback" / "voz" / "muestra_sherpa.wav"
    crudo = salida.with_suffix(".crudo.wav")
    sf.write(crudo, np.concatenate(trozos), MUESTREO)
    normalizar(crudo, salida)
    crudo.unlink()
    print(f"Voz en {salida}")


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).parent))
    main()
