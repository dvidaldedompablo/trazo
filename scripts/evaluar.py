"""Línea base del banco de pruebas (docs/10, Fase 1, paso 5).

Compara cada método con las etiquetas de feedback/etiquetas/<clip>.json y saca una tabla con una
columna por método:
  - Lógica actual: el código real de GolfCore (GolfLab en Docker), con la pose de MediaPipe que se
    sacó en el PC el 17-11 en lugar de la de Vision, que solo existe en el iPhone.
  - Modelo B: lo que dio `lab/preetiquetar.py --modelo B`, sin ajustar nada
    (feedback/derivados/<clip>/modelo_b/resultado.json).

Cifras (docs/10):
  - Golpes bien contados (de 3): los picos que el método da por golpe frente a `golpes`.
  - Picos falsos propuestos: picos dados por golpe que la etiqueta marca `es_palo: false`.
  - Error del impacto en fotogramas, por clip (+ = el método va tarde).
  - Palo encontrado: la cabeza del palo a no más del 5 % del alto del vídeo de la marca (criterio
    elegido por el usuario el 21-11-2026), sobre las marcas con punto.
  Además, el error del top, para ver de dónde vienen los fallos del palo.

Cómo se mide el palo: de punta a punta, como lo vería el usuario. Cada método usa sus propios
fotogramas (la app, los de sus posiciones; el modelo, los que eligió) y se compara con la marca en el
fotograma de la etiqueta; el error de las posiciones va dentro y por eso la tabla trae también el del top.
  - Preparación: en la app la toca el usuario, así que no cuenta como detección.
  - Takeaway: la app sigue el toque de la preparación (TemplateTracker) hasta su takeaway. El toque
    es la marca de la preparación de la etiqueta.
  - Mitad de subida y bajada: la línea del palo de la app (ClubLineFinder) desde las manos.
  - Top: la app no busca el palo ahí.
Las imágenes con lo detectado y la marca quedan en feedback/derivados/<clip>/evaluar/ para revisarlas a ojo.

Uso (desde la raíz del repo, con Docker Desktop abierto):
    lab\\.venv\\Scripts\\python scripts\\evaluar.py
"""
from __future__ import annotations

import json
import math
import shutil
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "lab"))

import cv2  # noqa: E402
import numpy as np  # noqa: E402

from comun import (DERIVADOS, FASES_PALO, FEEDBACK, InfoVideo, cargar_etiquetas, clips_del_banco,  # noqa: E402
                   comprobar_no_reserva, extraer_audio, leer_info)
from picos import compilar, docker  # noqa: E402

CRITERIO_PALO = 0.05     # fracción del alto del vídeo (decisión del usuario, 21-11-2026)
MANO = "right"           # los tres jugadores del banco son diestros
# Posición de la app que corresponde a cada fase de la etiqueta (docs/04).
POSICION_DE_FASE = {"preparacion": "address", "takeaway": "takeaway", "mitad_subida": "midBackswing",
                    "top": "top", "bajada": "transition"}


# ---------------------------------------------------------------- utilidades

def leer_grises(info: InfoVideo, indices: set[int]) -> dict[int, np.ndarray]:
    """La luminancia de los fotogramas pedidos, ya girados (como la lee la app del búfer del vídeo)."""
    comprobar_no_reserva(info.ruta)
    proceso = subprocess.Popen(["ffmpeg", "-v", "error", "-i", str(info.ruta), "-map", "0:v:0",
                                "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "gray", "-"],
                               stdout=subprocess.PIPE)
    tamano = info.ancho * info.alto
    salida: dict[int, np.ndarray] = {}
    assert proceso.stdout is not None
    i = 0
    while True:
        bloque = proceso.stdout.read(tamano)
        if len(bloque) < tamano:
            break
        if i in indices:
            salida[i] = np.frombuffer(bloque, dtype=np.uint8).reshape(info.alto, info.ancho).copy()
        i += 1
    proceso.wait()
    return salida


def escribir_pgm(ruta: Path, imagen: np.ndarray) -> None:
    """PGM binario sin comentarios: lo que lee GolfLab."""
    alto, ancho = imagen.shape
    ruta.write_bytes(f"P5\n{ancho} {alto}\n255\n".encode("ascii") + imagen.tobytes())


def en_docker(ruta: Path) -> str:
    return "/data/" + ruta.relative_to(FEEDBACK).as_posix()


def distancia(a, b) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def fotogramas_de_error(info: InfoVideo, t_metodo: float | None, t_etiqueta: float | None) -> int | None:
    if t_metodo is None or t_etiqueta is None:
        return None
    return info.indice_mas_cercano(t_metodo) - info.indice_mas_cercano(t_etiqueta)


# ---------------------------------------------------------------- lógica actual

def logica_actual(clip: Path, info: InfoVideo, datos: dict, carpeta: Path) -> dict:
    poses = DERIVADOS / clip.stem / "pose" / "poses.json"
    audio = extraer_audio(clip, DERIVADOS / clip.stem / "audio48k.f32")
    swing = json.loads(docker("/build/release/GolfLab", "swing", en_docker(poses), en_docker(audio), MANO))
    lista_poses = json.loads(poses.read_text(encoding="utf-8"))

    picos = datos["picos"]
    propuestos = [p for p in picos if p.get("propuesto")]
    resultado = {
        "golpes": len(propuestos),
        "picos_falsos": sum(1 for p in propuestos if p.get("es_palo") is False),
        "swing_ok": swing["ok"], "fallo": swing.get("failure"),
        "impacto": swing.get("impactTime"), "desfase": swing.get("syncOffset", 0),
        "posiciones": {}, "palo": [],
    }
    # El índice de GolfLab es el de la lista de poses: se pasa al del vídeo por el instante.
    for p in swing.get("positions", []):
        indice = info.indice_mas_cercano(lista_poses[p["frameIndex"]]["time"])
        resultado["posiciones"][p["position"]] = {"t": info.tiempos[indice], "indice": indice,
                                                  "manos": p.get("hands"), "dudosa": p["doubtful"]}
    resultado["top"] = resultado["posiciones"].get("top", {}).get("t")

    etiqueta = {p["fase"]: p for p in datos["palo"]}
    pos = resultado["posiciones"]
    necesarios = set()
    if swing["ok"]:
        necesarios |= {v["indice"] for v in pos.values()}
        necesarios |= set(range(pos["address"]["indice"], pos["takeaway"]["indice"] + 1))
    grises = leer_grises(info, necesarios) if necesarios else {}
    temporal = carpeta / "tmp"
    temporal.mkdir(parents=True, exist_ok=True)

    for fase in FASES_PALO:
        marca = etiqueta.get(fase, {})
        if marca.get("x") is None:
            continue
        caso = {"fase": fase, "marca": (marca["x"], marca["y"]), "t_marca": marca["t"], "punto": None,
                "linea": None, "indice": None, "cuenta": True, "nota": ""}
        if fase == "preparacion":
            caso.update(cuenta=False, nota="la toca el usuario")
        elif not swing["ok"]:
            caso["nota"] = "sin swing"
        elif fase == "top":
            caso["nota"] = "la app no busca el palo en el top"
        elif fase == "takeaway":
            prep = etiqueta.get("preparacion", {})
            if prep.get("x") is None:
                caso["nota"] = "sin toque de la preparación"
            else:
                rutas = []
                for i in range(pos["address"]["indice"], pos["takeaway"]["indice"] + 1):
                    ruta = temporal / f"seguir-{i:04d}.pgm"
                    escribir_pgm(ruta, grises[i])
                    rutas.append(en_docker(ruta))
                seguido = json.loads(docker("/build/release/GolfLab", "seguir", str(prep["x"]), str(prep["y"]), *rutas))
                caso["indice"] = pos["takeaway"]["indice"]
                caso["punto"] = seguido.get("found")
                caso["nota"] = f"parecido mínimo {seguido['minimumScore']:.2f}" + ("" if seguido.get("found") else " (perdido)")
        else:
            p = pos[POSICION_DE_FASE[fase]]
            caso["indice"] = p["indice"]
            if p["manos"] is None:
                caso["nota"] = "sin manos"
            else:
                # Como la app: media resolución, manos / 2 y largo máximo del 35 % del alto / 2; el resultado × 2.
                gris = grises[p["indice"]]
                mitad = cv2.resize(gris, (gris.shape[1] // 2, gris.shape[0] // 2), interpolation=cv2.INTER_AREA)
                ruta = temporal / f"linea-{fase}.pgm"
                escribir_pgm(ruta, mitad)
                linea = json.loads(docker("/build/release/GolfLab", "linea", en_docker(ruta),
                                          f"{p['manos'][0] / 2:.3f}", f"{p['manos'][1] / 2:.3f}",
                                          f"{info.alto * 0.35 / 2:.3f}"))
                if linea.get("head"):
                    caso["punto"] = [linea["head"][0] * 2, linea["head"][1] * 2]
                    caso["linea"] = ([linea["grip"][0] * 2, linea["grip"][1] * 2], caso["punto"])
                else:
                    caso["nota"] = "no encuentra la línea"
        resultado["palo"].append(caso)
    shutil.rmtree(temporal, ignore_errors=True)
    return resultado


# ---------------------------------------------------------------- modelo B

def de_modelo(m: dict, info: InfoVideo, datos: dict) -> dict:
    """Las cifras de un modelo a partir de su resumen (modelo_swings, modelo_palo, modelo_picos)."""
    respuestas = {round(p["t"], 3): p for p in m.get("modelo_picos") or []}
    dados = [p for p in datos["picos"] if respuestas.get(round(p["t"], 3), {}).get("sonido_es_impacto") == "si"]
    sw = (m.get("modelo_swings") or [None])[0] or {}
    resultado = {"golpes": len(dados), "picos_falsos": sum(1 for p in dados if p.get("es_palo") is False),
                 "impacto": sw.get("impacto"), "top": sw.get("top"), "modelo": m.get("modelo_info", {}).get("modelo"),
                 "info": m.get("modelo_info", {}), "palo": []}
    propuestas = {p["fase"]: p for p in m.get("modelo_palo") or []}
    for marca in datos["palo"]:
        if marca.get("x") is None:
            continue
        caso = {"fase": marca["fase"], "marca": (marca["x"], marca["y"]), "t_marca": marca["t"], "punto": None,
                "linea": None, "indice": None, "cuenta": True, "nota": ""}
        propuesta = propuestas.get(marca["fase"])
        if not propuesta or propuesta.get("t") is None:
            caso["nota"] = "no propone nada"
        else:
            caso["indice"] = info.indice_mas_cercano(propuesta["t"])
            if propuesta.get("x") is not None:
                caso["punto"] = [propuesta["x"], propuesta["y"]]
            elif propuesta.get("caja"):
                x0, y0, x1, y1 = propuesta["caja"]
                caso["punto"] = [(x0 + x1) / 2, (y0 + y1) / 2]
            else:
                caso["nota"] = "no ve la cabeza del palo"
        resultado["palo"].append(caso)
    return resultado


def modelo_a(clip: Path, info: InfoVideo, datos: dict) -> dict | None:
    """El modelo A, que preetiquetó. Medirlo es limpio solo porque las etiquetas las puso Claude web
    sin ver sus propuestas (la regla 3 de docs/10 lo prohíbe cuando el usuario corrige a A)."""
    if not datos.get("modelo_swings") and not datos.get("modelo_palo"):
        return None
    return de_modelo(datos, info, datos)


def modelo_b(clip: Path, info: InfoVideo, datos: dict) -> dict | None:
    ruta = DERIVADOS / clip.stem / "modelo_b" / "resultado.json"
    if not ruta.exists():
        return None
    return de_modelo(json.loads(ruta.read_text(encoding="utf-8")), info, datos)


# ---------------------------------------------------------------- tabla e imágenes

def puntuar_palo(casos: list[dict], info: InfoVideo) -> None:
    tope = CRITERIO_PALO * info.alto
    for c in casos:
        c["distancia"] = distancia(c["punto"], c["marca"]) if c["punto"] else None
        c["encontrado"] = c["distancia"] is not None and c["distancia"] <= tope
        c["fotogramas"] = (c["indice"] - info.indice_mas_cercano(c["t_marca"])) if c["indice"] is not None else None


def dibujar_casos(nombre: str, casos: list[dict], info: InfoVideo, carpeta: Path) -> None:
    if not casos:
        return
    indices = {c["indice"] if c["indice"] is not None else info.indice_mas_cercano(c["t_marca"]) for c in casos}
    color = {i: cv2.cvtColor(g, cv2.COLOR_GRAY2BGR) for i, g in leer_grises(info, indices).items()}
    tope = CRITERIO_PALO * info.alto
    celdas = []
    for c in casos:
        i = c["indice"] if c["indice"] is not None else info.indice_mas_cercano(c["t_marca"])
        img = color[i].copy()
        marca = tuple(int(round(v)) for v in c["marca"])
        cv2.circle(img, marca, int(round(tope)), (255, 0, 255), 1, cv2.LINE_AA)
        cv2.drawMarker(img, marca, (255, 0, 255), cv2.MARKER_CROSS, 14, 2)
        if c["linea"]:
            a, b = (tuple(int(round(v)) for v in p) for p in c["linea"])
            cv2.line(img, a, b, (255, 255, 0), 2, cv2.LINE_AA)
        if c["punto"]:
            cv2.circle(img, tuple(int(round(v)) for v in c["punto"]), 6, (255, 255, 0), -1)
        estado = "lo toca el usuario" if not c["cuenta"] else ("SI" if c["encontrado"] else "NO")
        textos = [f"{c['fase']}: {estado}",
                  f"fot. {i} (etiqueta {info.indice_mas_cercano(c['t_marca'])})",
                  (f"{c['distancia']:.0f} px de la marca" if c["distancia"] is not None else c["nota"])]
        cv2.rectangle(img, (0, 0), (img.shape[1], 22 * len(textos) + 6), (0, 0, 0), -1)
        for k, t in enumerate(textos):
            cv2.putText(img, t, (6, 20 + 22 * k), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1, cv2.LINE_AA)
        celdas.append(img)
    hueco = np.full((info.alto, 6, 3), 255, np.uint8)
    hoja = np.hstack([x for c in celdas for x in (c, hueco)][:-1])
    cv2.imwrite(str(carpeta / f"palo-{nombre}.jpg"), hoja, [cv2.IMWRITE_JPEG_QUALITY, 90])


def firmar(n: int | None) -> str:
    return "—" if n is None else f"{n:+d}"


# Columnas de la tabla: (clave, título, función). La lógica actual siempre; cada modelo si hay resultado.
METODOS = [("actual", "Lógica actual (GolfCore + MediaPipe)", None),
           ("a", "Modelo A", modelo_a),
           ("b", "Modelo B", modelo_b)]


def main() -> None:
    clips = clips_del_banco()
    compilar()
    filas = []
    for clip in clips:
        datos = cargar_etiquetas(clip)
        info = leer_info(clip)
        carpeta = DERIVADOS / clip.stem / "evaluar"
        carpeta.mkdir(parents=True, exist_ok=True)
        fila = {"clip": clip.stem, "golpes": datos["golpes"], "autor": datos.get("autor_etiquetas", "usuario"),
                "alto": info.alto}
        sw = datos["swings"][0]
        for clave, _, funcion in METODOS:
            r = logica_actual(clip, info, datos, carpeta) if funcion is None else funcion(clip, info, datos)
            fila[clave] = r
            if r is None:
                continue
            puntuar_palo(r["palo"], info)
            r["error_impacto"] = fotogramas_de_error(info, r["impacto"], sw["impacto"])
            r["error_top"] = fotogramas_de_error(info, r["top"], sw["top"])
            dibujar_casos(clave, r["palo"], info, carpeta)
        filas.append(fila)
        (carpeta / "resultado.json").write_text(json.dumps({k: fila[k] for k, _, _ in METODOS}, ensure_ascii=False,
                                                           indent=2, default=str) + "\n", encoding="utf-8")

    def resumen(clave: str) -> dict | None:
        rs = [f[clave] for f in filas]
        if any(r is None for r in rs):
            return None
        contables = [c for r in rs for c in r["palo"] if c["cuenta"]]
        usuario = sum(1 for r in rs for c in r["palo"] if not c["cuenta"])
        return {
            "golpes": str(sum(1 for f, r in zip(filas, rs) if r["golpes"] == f["golpes"])),
            "falsos": str(sum(r["picos_falsos"] for r in rs)),
            "impacto": " / ".join(firmar(r["error_impacto"]) for r in rs),
            "top": " / ".join(firmar(r["error_top"]) for r in rs),
            "palo": f"{sum(c['encontrado'] for c in contables)} de {len(contables)}"
                    + (f" (+{usuario} que toca el usuario)" if usuario else ""),
            "modelo": rs[0].get("modelo"),
        }

    resumenes = {clave: resumen(clave) for clave, _, _ in METODOS}
    # Un método sin datos en ningún clip (p. ej. sin modelo B configurado) no saca columna.
    activos = [m for m in METODOS if m[0] == "actual" or any(f[m[0]] is not None for f in filas)]
    titulos = [t + (f" ({resumenes[c]['modelo']})" if resumenes[c] and resumenes[c].get("modelo") else "")
               for c, t, _ in activos]
    nombres = " / ".join(f["clip"].split("-")[0] for f in filas)

    def fila_tabla(titulo: str, campo: str) -> str:
        return f"| {titulo} | " + " | ".join(resumenes[c][campo] if resumenes[c] else "—" for c, _, _ in activos) + " |"

    print("\n| Cifra | " + " | ".join(titulos) + " |")
    print("| --- |" + " --- |" * len(activos))
    print(fila_tabla(f"Golpes bien contados (de {len(filas)})", "golpes"))
    print(fila_tabla("Picos falsos propuestos", "falsos"))
    print(fila_tabla(f"Error del impacto en fotogramas ({nombres})", "impacto"))
    print(fila_tabla(f"Error del top en fotogramas ({nombres})", "top"))
    print(fila_tabla(f"Palo encontrado (≤ {CRITERIO_PALO:.0%} del alto)", "palo"))

    print("\nDetalle del palo (distancia a la marca en px; fotogramas del método frente a la etiqueta):")
    for f in filas:
        print(f"  {f['clip']} (tope {CRITERIO_PALO * f['alto']:.0f} px):")
        for clave, _, _ in METODOS:
            r = f[clave]
            if r is None:
                continue
            partes = []
            for c in r["palo"]:
                if not c["cuenta"]:
                    partes.append(f"{c['fase']} usuario")
                elif c["distancia"] is None:
                    partes.append(f"{c['fase']} NO ({c['nota']})")
                else:
                    partes.append(f"{c['fase']} {'SI' if c['encontrado'] else 'NO'} {c['distancia']:.0f} px "
                                  f"({firmar(c['fotogramas'])} fot.)")
            print(f"    {clave:<7} " + "; ".join(partes))
    autores = sorted({f["autor"] for f in filas})
    print(f"\nEtiquetas: {', '.join(autores)}.")
    print("Aviso (regla 7 de docs/10): son los 3 clips con los que se ajustó la lógica actual; la medida sale mejor de lo que es.")
    for clave, titulo, _ in activos:
        if resumenes[clave] is None:
            print(f"Faltan datos de {titulo} en algún clip: esa columna sale con guiones.")
    print("Imágenes para revisar a ojo: feedback/derivados/<clip>/evaluar/palo-*.jpg")


if __name__ == "__main__":
    main()
