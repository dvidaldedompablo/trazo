"""Piezas compartidas por los scripts del laboratorio (docs/10).

Vídeo: los fotogramas se sacan con ffmpeg ya girados (como los ve la app) y con el instante real
de cada uno, porque los vídeos del banco pueden ser de frecuencia variable. Los píxeles de las
etiquetas son los del vídeo girado, con el origen arriba a la izquierda.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from bisect import bisect_left
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

RAIZ = Path(__file__).resolve().parent.parent
FEEDBACK = RAIZ / "feedback"
ETIQUETAS = FEEDBACK / "etiquetas"
DERIVADOS = FEEDBACK / "derivados"
CACHE_MODELO = FEEDBACK / "cache_modelo"
LAB = RAIZ / "lab"

# En Windows, la consola de Git Bash recibe la salida como cp1252 y las tildes salen rotas.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# Las cinco fases que marca el usuario (teclas 1 a 5). "bajada" es la posición 5 de la app
# (docs/04: brazo de delante paralelo al suelo al bajar).
FASES_PALO = ["preparacion", "takeaway", "mitad_subida", "top", "bajada"]


# ---------------------------------------------------------------- reserva

def comprobar_no_reserva(ruta: Path) -> None:
    """Regla 4 de docs/10: los clips de reserva no se abren hasta la "prueba final"."""
    partes = [p.lower() for p in Path(ruta).resolve().parts]
    if "reserva" in partes:
        raise SystemExit(f"{ruta} es un clip de reserva: no se abre hasta la prueba final (docs/10, regla 4).")


def clips_del_banco() -> list[Path]:
    """Los vídeos de feedback/ (solo el primer nivel: así nunca entra feedback/reserva/)."""
    return sorted(p for p in FEEDBACK.glob("*.mp4") if p.is_file())


def resolver_clip(texto: str) -> Path:
    """Acepta una ruta o solo el nombre del clip (con o sin .mp4)."""
    ruta = Path(texto)
    if not ruta.exists():
        nombre = ruta.name if ruta.suffix else ruta.name + ".mp4"
        ruta = FEEDBACK / nombre
    if not ruta.exists():
        raise SystemExit(f"No encuentro el vídeo {texto}")
    comprobar_no_reserva(ruta)
    return ruta


# ---------------------------------------------------------------- vídeo

@dataclass
class InfoVideo:
    ruta: Path
    ancho: int          # ya girado
    alto: int           # ya girado
    rotacion: int       # la del metadato, en grados
    tiempos: list[float]  # instante real de cada fotograma (s)
    duracion: float
    tiene_audio: bool

    @property
    def n(self) -> int:
        return len(self.tiempos)

    def indice_mas_cercano(self, t: float) -> int:
        """El fotograma cuyo instante está más cerca de t."""
        i = bisect_left(self.tiempos, t)
        if i <= 0:
            return 0
        if i >= self.n:
            return self.n - 1
        return i if self.tiempos[i] - t < t - self.tiempos[i - 1] else i - 1


def _ffprobe_json(argumentos: list[str]) -> dict:
    salida = subprocess.run(["ffprobe", "-v", "error", "-of", "json", *argumentos],
                            capture_output=True, text=True, check=True)
    return json.loads(salida.stdout)


def leer_info(ruta: Path) -> InfoVideo:
    comprobar_no_reserva(ruta)
    datos = _ffprobe_json(["-show_entries", "stream=index,codec_type,width,height:stream_side_data=rotation"
                           ":format=duration", str(ruta)])
    video = next(s for s in datos["streams"] if s["codec_type"] == "video")
    rotacion = 0
    for lado in video.get("side_data_list", []):
        if "rotation" in lado:
            rotacion = int(round(float(lado["rotation"])))
    ancho, alto = int(video["width"]), int(video["height"])
    if rotacion % 180 != 0:
        ancho, alto = alto, ancho
    # Instante de cada fotograma tal como sale del decodificador (con la lista de edición aplicada).
    marcos = _ffprobe_json(["-select_streams", "v:0", "-show_entries",
                            "frame=best_effort_timestamp_time,pts_time", str(ruta)])["frames"]
    tiempos = []
    for m in marcos:
        valor = m.get("best_effort_timestamp_time", m.get("pts_time"))
        if valor in (None, "N/A"):
            continue
        tiempos.append(float(valor))
    return InfoVideo(ruta=ruta, ancho=ancho, alto=alto, rotacion=rotacion, tiempos=tiempos,
                     duracion=float(datos["format"]["duration"]),
                     tiene_audio=any(s["codec_type"] == "audio" for s in datos["streams"]))


def leer_fotogramas(info: InfoVideo, calidad_jpeg: int = 92) -> list[bytes]:
    """Todos los fotogramas, girados, guardados en memoria como JPEG (un clip de 10 s ocupa unos 30 MB).

    `-fps_mode passthrough` evita que ffmpeg duplique o quite fotogramas en los vídeos de frecuencia
    variable: así el fotograma i corresponde a info.tiempos[i].
    """
    comprobar_no_reserva(info.ruta)
    proceso = subprocess.Popen(["ffmpeg", "-v", "error", "-i", str(info.ruta), "-map", "0:v:0",
                                "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "bgr24", "-"],
                               stdout=subprocess.PIPE)
    tamano = info.ancho * info.alto * 3
    fotogramas: list[bytes] = []
    assert proceso.stdout is not None
    while True:
        bloque = proceso.stdout.read(tamano)
        if len(bloque) < tamano:
            break
        imagen = np.frombuffer(bloque, dtype=np.uint8).reshape(info.alto, info.ancho, 3)
        ok, jpeg = cv2.imencode(".jpg", imagen, [cv2.IMWRITE_JPEG_QUALITY, calidad_jpeg])
        if ok:
            fotogramas.append(jpeg.tobytes())
    proceso.wait()
    if len(fotogramas) != info.n:
        print(f"Aviso: ffmpeg dio {len(fotogramas)} fotogramas y ffprobe {info.n} instantes. "
              "Uso los que coinciden.")
        n = min(len(fotogramas), info.n)
        fotogramas = fotogramas[:n]
        info.tiempos = info.tiempos[:n]
    return fotogramas


def decodificar(jpeg: bytes) -> np.ndarray:
    return cv2.imdecode(np.frombuffer(jpeg, dtype=np.uint8), cv2.IMREAD_COLOR)


def extraer_audio(ruta: Path, destino: Path) -> Path:
    """Audio mono a 48 kHz en float32: lo mismo que AudioExtractor en la app (mezcla de canales)."""
    comprobar_no_reserva(ruta)
    destino.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(ruta), "-vn", "-ac", "1", "-ar", "48000",
                    "-f", "f32le", str(destino)], check=True)
    return destino


# ---------------------------------------------------------------- etiquetas

def ruta_etiquetas(clip: Path) -> Path:
    return ETIQUETAS / (clip.stem + ".json")


def etiqueta_vacia(clip: Path) -> dict:
    """El esquema de docs/10. Los campos modelo_* solo los escribe preetiquetar.py."""
    return {
        "clip": clip.name,
        "musica": None,
        "golpes": None,
        "swings": [{"top": None, "impacto": None}],
        "palo": [{"fase": f, "t": None, "x": None, "y": None} for f in FASES_PALO],
        "picos": [],
        "modelo_swings": None,
        "modelo_fases": None,
        "modelo_palo": None,
    }


def cargar_etiquetas(clip: Path) -> dict:
    ruta = ruta_etiquetas(clip)
    if ruta.exists():
        with open(ruta, encoding="utf-8") as f:
            datos = json.load(f)
        # Completa lo que falte (por si el archivo es de una versión anterior del esquema).
        base = etiqueta_vacia(clip)
        for clave, valor in base.items():
            datos.setdefault(clave, valor)
        presentes = {p.get("fase") for p in datos["palo"]}
        datos["palo"] += [p for p in base["palo"] if p["fase"] not in presentes]
        datos["palo"].sort(key=lambda p: FASES_PALO.index(p["fase"]) if p["fase"] in FASES_PALO else 99)
        return datos
    return etiqueta_vacia(clip)


def guardar_etiquetas(clip: Path, datos: dict, ruta: Path | None = None) -> Path:
    """Escribe a un temporal y lo cambia de nombre: si algo falla a medias, el archivo bueno no se rompe."""
    ruta = ruta or ruta_etiquetas(clip)
    ruta.parent.mkdir(parents=True, exist_ok=True)
    temporal = ruta.with_suffix(".tmp")
    with open(temporal, "w", encoding="utf-8") as f:
        json.dump(datos, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(temporal, ruta)
    return ruta


# ---------------------------------------------------------------- .env

def leer_env() -> dict[str, str]:
    """Lee lab/.env (CLAVE=valor por línea; # para comentarios). Las variables del sistema mandan."""
    valores: dict[str, str] = {}
    ruta = LAB / ".env"
    if ruta.exists():
        for linea in ruta.read_text(encoding="utf-8").splitlines():
            linea = linea.strip()
            if not linea or linea.startswith("#") or "=" not in linea:
                continue
            clave, valor = linea.split("=", 1)
            valores[clave.strip()] = valor.strip().strip('"').strip("'")
    for clave in CLAVES_ENV:
        if os.environ.get(clave):
            valores[clave] = os.environ[clave]
    return valores


# El usuario no quiere ningún gasto: solo modelos con plan gratuito en la página de precios de Google
# (consultada el 18-11-2026). Si Google cambia la lista, se revisa aquí antes de usar otro modelo.
MODELOS_GRATUITOS = {
    "gemini-4-hydrogen", "gemini-3.8-flash", "gemini-3.6-flash", "gemini-3.5-flash-lite",
    "gemini-3.1-flash-lite", "gemini-3-flash-preview", "gemini-2.5-flash", "gemini-2.5-flash-lite",
}


def comprobar_gratuito(modelo: str, plan_gratuito: str) -> None:
    """Para antes de llamar si el modelo o el plan podrían costar dinero."""
    if plan_gratuito == "0":
        raise SystemExit("PLAN_GRATUITO=0: este laboratorio solo usa el plan gratuito (sin gasto).")
    if modelo not in MODELOS_GRATUITOS:
        raise SystemExit(f"{modelo} no está en la lista de modelos gratuitos ({', '.join(sorted(MODELOS_GRATUITOS))}). "
                         "No se usa para no gastar nada.")


# Las que se pueden poner también como variables del sistema (ver lab/.env.example).
CLAVES_ENV = ["GEMINI_API_KEY", "MODELO_A", "MODELO_B", "PRECIO_A_ENTRADA", "PRECIO_A_SALIDA",
              "PRECIO_B_ENTRADA", "PRECIO_B_SALIDA", "PLAN_GRATUITO", "NIVEL_RAZONAMIENTO", "SEMILLA",
              "SEGUNDOS_ENTRE_LLAMADAS", "RESOLUCION_IMAGEN"]
