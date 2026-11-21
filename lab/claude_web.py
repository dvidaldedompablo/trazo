"""Etiquetas puestas por Claude web en lugar de a mano (decisión del usuario, 21-11-2026).

Aviso: docs/10 (regla 3) dice que las etiquetas del usuario son la verdad del banco. El usuario ha
elegido que las ponga Claude web sabiendo que entonces la tabla de evaluar.py compara una IA con otra
y no dice si aciertan de verdad. Para que esa comparación valga lo más posible:
  - a Claude web no se le enseñan las propuestas de Gemini (modelo A): así no las copia;
  - las etiquetas importadas llevan "autor_etiquetas": "claude-web (...)" y la tabla lo dirá;
  - golpes y musica salen de la tabla de docs/10, que escribió el usuario, no de la IA;
  - picos[].es_palo se deduce del impacto que marca Claude web, porque no puede oír el audio.

Dos pasos:
  preparar   crea feedback/para_claude_web/<clip>/ con las hojas de fotogramas (JPG) y mensaje.txt,
             el texto que el usuario pega en claude.ai junto con las hojas.
  importar   lee el JSON que contesta Claude web, lo valida y lo escribe en feedback/etiquetas/<clip>.json.
             Si algo no valida, no escribe nada y dice qué falla.

Uso (desde la raíz del repo):
    lab\\.venv\\Scripts\\python lab\\claude_web.py preparar                      (los 3 clips)
    lab\\.venv\\Scripts\\python lab\\claude_web.py importar driver-campo respuesta.txt
"""
from __future__ import annotations

import argparse
import json
import math
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

import cv2
import numpy as np

from comun import (FASES_PALO, FEEDBACK, RAIZ, InfoVideo, cargar_etiquetas, clips_del_banco, decodificar,
                   guardar_etiquetas, leer_fotogramas, leer_info, resolver_clip)
from etiquetar import comparar_con_modelo

CARPETA = FEEDBACK / "para_claude_web"

# Lo que el usuario apuntó en la tabla de docs/10 ("Los vídeos"). Del driver no dice que tenga música.
DE_DOCS10 = {
    "story1-puerta-de-hierro": {"musica": True, "golpes": 1},
    "story2-simulador": {"musica": True, "golpes": 1},
    "driver-campo": {"musica": False, "golpes": 1},
}

# claude.ai reduce las imágenes con el lado largo por encima de unos 1568 píxeles: así llegan enteras.
LADO_MAXIMO_HOJA = 1568
POR_HOJA = 8                 # 4 columnas x 2 filas: con vídeos verticales cada fotograma sale casi a tamaño real
ANTES_DEL_IMPACTO_S = 2.0    # cabe la preparación: en los 3 clips el swing dura de 0,8 a 1,3 s antes del impacto
DESPUES_DEL_IMPACTO_S = 0.3
FPS_OBJETIVO = 30            # en el tramo del swing, un fotograma cada 1/30 s; el impacto va sin saltos aparte
TOLERANCIA_PICO_S = 0.15     # el pico de audio del golpe cae a menos de esto del fotograma del impacto


# ---------------------------------------------------------------- preparar

def dibujar_hoja(indices: list[int], columnas: int, titulo: str, info: InfoVideo, fotos: list[bytes]) -> np.ndarray:
    filas = math.ceil(len(indices) / columnas)
    hueco, cabecera = 6, 40
    escala = min(1.0,
                 (LADO_MAXIMO_HOJA - hueco * (columnas + 1)) / (columnas * info.ancho),
                 (LADO_MAXIMO_HOJA - cabecera - hueco * (filas + 1)) / (filas * info.alto))
    ancho, alto = int(info.ancho * escala), int(info.alto * escala)
    lienzo = np.full((cabecera + filas * (alto + hueco) + hueco, columnas * (ancho + hueco) + hueco, 3), 255, np.uint8)
    cv2.rectangle(lienzo, (0, 0), (lienzo.shape[1], cabecera), (40, 40, 40), -1)
    cv2.putText(lienzo, titulo, (10, 27), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2, cv2.LINE_AA)
    for k, indice in enumerate(indices):
        fila, columna = divmod(k, columnas)
        x = hueco + columna * (ancho + hueco)
        y = cabecera + hueco + fila * (alto + hueco)
        celda = cv2.resize(decodificar(fotos[indice]), (ancho, alto), interpolation=cv2.INTER_AREA)
        # Marcas en los bordes cada 100 de una escala de 0 a 1000 (la de 500, más larga): ayudan a dar
        # la posición de la cabeza del palo relativa al fotograma sin tapar el centro de la imagen.
        for paso in range(1, 10):
            largo = 12 if paso == 5 else 6
            px, py = round(paso * ancho / 10), round(paso * alto / 10)
            for p1, p2 in (((px, 0), (px, largo)), ((px, alto - 1), (px, alto - 1 - largo)),
                           ((0, py), (largo, py)), ((ancho - 1, py), (ancho - 1 - largo, py))):
                cv2.line(celda, p1, p2, (0, 0, 0), 3)
                cv2.line(celda, p1, p2, (0, 255, 255), 1)
        # El número del fotograma (su índice en el vídeo) arriba a la izquierda y el instante abajo.
        etiqueta = str(indice)
        (an, al), _ = cv2.getTextSize(etiqueta, cv2.FONT_HERSHEY_SIMPLEX, 0.8, 2)
        cv2.rectangle(celda, (0, 0), (an + 10, al + 12), (0, 0, 0), -1)
        cv2.putText(celda, etiqueta, (5, al + 6), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2, cv2.LINE_AA)
        instante = f"{info.tiempos[indice]:.3f} s"
        (an, al), _ = cv2.getTextSize(instante, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)
        cv2.rectangle(celda, (0, alto - al - 10), (an + 8, alto), (0, 0, 0), -1)
        cv2.putText(celda, instante, (4, alto - 5), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1, cv2.LINE_AA)
        lienzo[y:y + alto, x:x + ancho] = celda
    return lienzo


def plantilla_respuesta(nombre: str) -> str:
    palo = ",\n".join(f'    {{"fase": "{f}", "fotograma": 0, "x": 0, "y": 0, "nota": ""}}' for f in FASES_PALO)
    return ("{\n"
            f'  "clip": "{nombre}",\n'
            '  "modelo": "el nombre exacto del modelo de Claude que eres",\n'
            '  "top": 0,\n'
            '  "impacto": 0,\n'
            '  "palo": [\n' + palo + "\n  ],\n"
            '  "confianza": "alta, media o baja",\n'
            '  "dudas": ""\n'
            "}")


def mensaje(nombre: str, hojas: list[dict], paso: int) -> str:
    lista = "\n".join(f"- {h['archivo']}: {h['para']}" for h in hojas)
    salto = "todos los fotogramas" if paso == 1 else f"uno de cada {paso} fotogramas (unos 30 por segundo)"
    return f"""Te paso {len(hojas)} imágenes de un vídeo de golf ("{nombre}") para etiquetar su swing. Es para un banco de pruebas: sé preciso y, si algo no se ve, dilo en vez de adivinar.

Las imágenes:
{lista}
En el tramo del swing van {salto}. Cada fotograma lleva su número arriba a la izquierda (recuadro negro) y su instante en segundos abajo a la izquierda. Las marcas amarillas de los bordes de cada fotograma van cada 100 en una escala de 0 a 1000 (la más larga es 500).

En este vídeo hay un solo swing. Quiero:

1. top: el fotograma en que las manos están en su punto más alto y el palo cambia de sentido.
2. impacto: el fotograma más cercano al momento en que la cabeza del palo toca la bola.
3. La cabeza del palo en 5 momentos. Para cada uno, el número del fotograma y el centro de la cabeza del palo:
   - preparacion: el último fotograma quieto ante la bola, justo antes de que el palo empiece a ir hacia atrás.
   - takeaway: en la subida, el fotograma en que el palo queda paralelo al suelo.
   - mitad_subida: en la subida, el fotograma en que el brazo de delante queda paralelo al suelo.
   - top: el mismo fotograma del punto 1.
   - bajada: en la bajada, el fotograma en que el brazo de delante vuelve a quedar paralelo al suelo.
   x e y van de 0 a 1000 y son relativos a ESE fotograma, no a la hoja entera: 0,0 es la esquina de arriba a la izquierda del fotograma y 1000,1000 la de abajo a la derecha.
   Si en ese fotograma no se ve la cabeza del palo (tapada, borrosa o fuera de la imagen), pon x e y a null y explícalo en "nota".

Usa solo números de fotograma que aparezcan en las imágenes. El orden tiene que ser: preparacion < takeaway < mitad_subida < top < bajada < impacto.

Contesta solo con este JSON, sin texto antes ni después:

{plantilla_respuesta(nombre)}
"""


def preparar(ruta: Path) -> None:
    info = leer_info(ruta)
    fotos = leer_fotogramas(info)
    datos = cargar_etiquetas(ruta)
    nombre = ruta.stem
    fin = info.tiempos[-1]

    # La ventana del swing se centra en el impacto que propuso el modelo A. De A solo se usa ese
    # instante para recortar; sus etiquetas no se enseñan. Sin propuesta, se cubre todo el clip.
    impacto = ((datos.get("modelo_swings") or [{}])[0] or {}).get("impacto")
    t0, t1 = (0.0, fin) if impacto is None else (max(0.0, impacto - ANTES_DEL_IMPACTO_S),
                                                  min(fin, impacto + DESPUES_DEL_IMPACTO_S))
    en_ventana = [i for i, t in enumerate(info.tiempos) if t0 <= t <= t1]
    fps = (len(en_ventana) - 1) / max(1e-6, t1 - t0)
    paso = max(1, round(fps / FPS_OBJETIVO))
    tramo = en_ventana[::paso]

    general = sorted({info.indice_mas_cercano(k * fin / 11) for k in range(12)})
    trozos = [tramo[k:k + POR_HOJA] for k in range(0, len(tramo), POR_HOJA)]
    detalle = []
    if paso > 1 and impacto is not None:
        centro = info.indice_mas_cercano(impacto)
        detalle = list(range(max(0, centro - 5), min(info.n, centro + 3)))

    total = 1 + len(trozos) + (1 if detalle else 0)
    destino = CARPETA / nombre
    if destino.exists():
        shutil.rmtree(destino)
    destino.mkdir(parents=True)

    hojas: list[dict] = []

    def guardar(indices: list[int], columnas: int, tipo: str, para: str) -> None:
        n = len(hojas) + 1
        archivo = f"{n:02d}-{tipo}.jpg"
        titulo = f"{nombre} - hoja {n} de {total} - fotogramas {indices[0]} a {indices[-1]}"
        imagen = dibujar_hoja(indices, columnas, titulo, info, fotos)
        cv2.imwrite(str(destino / archivo), imagen, [cv2.IMWRITE_JPEG_QUALITY, 90])
        hojas.append({"archivo": archivo, "para": para, "fotogramas": indices})

    guardar(general, 6, "vista-general", "12 fotogramas repartidos por todo el vídeo, para que veas qué pasa")
    for k, trozo in enumerate(trozos):
        guardar(trozo, 4, "swing", "el tramo del swing, en orden de tiempo")
    if detalle:
        guardar(detalle, 4, "impacto", "los fotogramas de alrededor del impacto, sin saltos")

    enviados = sorted({i for h in hojas for i in h["fotogramas"]})
    with open(destino / "fotogramas.json", "w", encoding="utf-8") as f:
        json.dump({"clip": ruta.name, "ancho": info.ancho, "alto": info.alto, "paso": paso,
                   "ventana_s": [round(t0, 4), round(t1, 4)],
                   "enviados": {str(i): round(info.tiempos[i], 4) for i in enviados},
                   "hojas": hojas}, f, ensure_ascii=False, indent=2)
    (destino / "mensaje.txt").write_text(mensaje(nombre, hojas, paso), encoding="utf-8")
    print(f"{nombre}: {len(hojas)} imágenes y mensaje.txt en {destino.relative_to(RAIZ)}")


# ---------------------------------------------------------------- importar

def leer_respuesta(texto: str) -> dict:
    """Saca el JSON aunque venga dentro de ```json ... ``` o con algo de texto alrededor."""
    bloque = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", texto, re.S)
    if bloque:
        texto = bloque.group(1)
    inicio, fin = texto.find("{"), texto.rfind("}")
    if inicio < 0 or fin < inicio:
        raise SystemExit("No encuentro un JSON en la respuesta.")
    try:
        return json.loads(texto[inicio:fin + 1])
    except json.JSONDecodeError as e:
        raise SystemExit(f"La respuesta no es un JSON válido: {e}")


def validar(resp: dict, enviados: dict[int, float]) -> tuple[list[str], list[str]]:
    """Devuelve (errores, avisos). Con un error no se importa nada: nunca se rellena a ojo."""
    errores, avisos = [], []

    def fotograma(valor, que: str):
        if isinstance(valor, bool) or not isinstance(valor, int):
            errores.append(f"{que}: '{valor}' no es un número de fotograma")
            return None
        if valor not in enviados:
            errores.append(f"{que}: el fotograma {valor} no está en las imágenes")
            return None
        return valor

    top = fotograma(resp.get("top"), "top")
    impacto = fotograma(resp.get("impacto"), "impacto")
    palo = {p.get("fase"): p for p in resp.get("palo") or [] if isinstance(p, dict)}
    faltan = [f for f in FASES_PALO if f not in palo]
    if faltan:
        errores.append(f"faltan fases del palo: {', '.join(faltan)}")
    orden = []
    for fase in FASES_PALO:
        p = palo.get(fase)
        if not p:
            continue
        f = fotograma(p.get("fotograma"), f"palo {fase}")
        orden.append((fase, f))
        x, y = p.get("x"), p.get("y")
        if (x is None) != (y is None):
            errores.append(f"palo {fase}: x e y tienen que ir los dos con número o los dos a null")
        elif x is not None and not all(isinstance(v, (int, float)) and not isinstance(v, bool) and 0 <= v <= 1000
                                       for v in (x, y)):
            errores.append(f"palo {fase}: x e y tienen que estar entre 0 y 1000 (llegan {x}, {y})")
    orden.append(("impacto", impacto))
    tiempos = [(fase, enviados[f]) for fase, f in orden if f is not None]
    for (fa, ta), (fb, tb) in zip(tiempos, tiempos[1:]):
        if not ta < tb:
            errores.append(f"orden: {fa} ({ta:.3f} s) tiene que ir antes que {fb} ({tb:.3f} s)")
    if top is not None and palo.get("top", {}).get("fotograma") not in (None, top):
        avisos.append(f"el top del palo ({palo['top']['fotograma']}) no es el fotograma del top ({top}); uso cada uno donde va")
    if top is not None and impacto is not None:
        bajada = enviados[impacto] - enviados[top]
        if bajada <= 0:
            errores.append(f"el top ({enviados[top]:.3f} s) tiene que ir antes que el impacto ({enviados[impacto]:.3f} s)")
        elif not 0.1 <= bajada <= 0.6:
            avisos.append(f"del top al impacto van {bajada:.3f} s; lo normal es de 0,1 a 0,6 s")
    return errores, avisos


def hay_etiquetas_a_mano(datos: dict) -> bool:
    if str(datos.get("autor_etiquetas", "")).startswith("claude-web"):
        return False
    return (any(sw.get("top") is not None or sw.get("impacto") is not None for sw in datos["swings"])
            or any(p.get("t") is not None for p in datos["palo"])
            or any(p.get("es_palo") is not None for p in datos["picos"]))


def dibujar_revision(destino: Path, info: InfoVideo, fotos: list[bytes], datos: dict) -> Path:
    """Una hoja con los 5 fotogramas del palo y un círculo donde Claude web dice que está la cabeza."""
    marcas = [p for p in datos["palo"] if p.get("t") is not None]
    indices = [info.indice_mas_cercano(p["t"]) for p in marcas]
    columnas = len(indices)
    escala = min(1.0, (LADO_MAXIMO_HOJA - 6 * (columnas + 1)) / (columnas * info.ancho))
    ancho, alto = int(info.ancho * escala), int(info.alto * escala)
    lienzo = np.full((alto + 12, columnas * (ancho + 6) + 6, 3), 255, np.uint8)
    for k, (p, i) in enumerate(zip(marcas, indices)):
        celda = cv2.resize(decodificar(fotos[i]), (ancho, alto), interpolation=cv2.INTER_AREA)
        if p.get("x") is not None:
            centro = (round(p["x"] * escala), round(p["y"] * escala))
            cv2.circle(celda, centro, 14, (0, 0, 0), 4)
            cv2.circle(celda, centro, 14, (255, 0, 255), 2)
        cv2.rectangle(celda, (0, 0), (ancho, 26), (0, 0, 0), -1)
        cv2.putText(celda, f"{p['fase']} {i}", (5, 19), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1, cv2.LINE_AA)
        x = 6 + k * (ancho + 6)
        lienzo[6:6 + alto, x:x + ancho] = celda
    ruta = destino / "revision.jpg"
    cv2.imwrite(str(ruta), lienzo, [cv2.IMWRITE_JPEG_QUALITY, 90])
    return ruta


def importar(ruta: Path, archivo_respuesta: str, sobrescribir: bool) -> None:
    nombre = ruta.stem
    destino = CARPETA / nombre
    if not (destino / "fotogramas.json").exists():
        raise SystemExit(f"Antes: lab\\.venv\\Scripts\\python lab\\claude_web.py preparar {nombre}")
    with open(destino / "fotogramas.json", encoding="utf-8") as f:
        preparado = json.load(f)
    enviados = {int(k): v for k, v in preparado["enviados"].items()}

    texto = sys.stdin.read() if archivo_respuesta == "-" else Path(archivo_respuesta).read_text(encoding="utf-8")
    resp = leer_respuesta(texto)
    if resp.get("clip") not in (None, nombre, ruta.name):
        raise SystemExit(f"La respuesta es del clip '{resp.get('clip')}', no de '{nombre}'.")
    errores, avisos = validar(resp, enviados)
    if errores:
        print("No importo nada. Lo que no valida:")
        for e in errores:
            print(f"  - {e}")
        raise SystemExit(1)

    datos = cargar_etiquetas(ruta)
    if hay_etiquetas_a_mano(datos) and not sobrescribir:
        raise SystemExit("Este clip ya tiene etiquetas puestas a mano. No las piso (usa --sobrescribir si de verdad quieres).")

    info = leer_info(ruta)
    fotos = leer_fotogramas(info)
    t_top, t_impacto = enviados[resp["top"]], enviados[resp["impacto"]]
    datos["swings"] = [{"top": t_top, "impacto": t_impacto}]
    palo = {p["fase"]: p for p in resp["palo"]}
    for p in datos["palo"]:
        r = palo[p["fase"]]
        # De 0-1000 relativo al fotograma a píxeles del vídeo girado.
        p["t"] = enviados[r["fotograma"]]
        p["x"] = None if r.get("x") is None else min(info.ancho - 1, round(r["x"] / 1000 * info.ancho))
        p["y"] = None if r.get("y") is None else min(info.alto - 1, round(r["y"] / 1000 * info.alto))
        p["nota"] = str(r.get("nota") or "")

    # Claude web no oye el audio: el pico del golpe es el más cercano a su impacto, si está cerca.
    cercanos = [k for k, p in enumerate(datos["picos"]) if abs(p["t"] - t_impacto) <= TOLERANCIA_PICO_S]
    golpe = min(cercanos, key=lambda k: abs(datos["picos"][k]["t"] - t_impacto)) if cercanos else None
    for k, p in enumerate(datos["picos"]):
        p["es_palo"] = k == golpe
        p["motivo"] = ("deducido: el pico más cercano al impacto de Claude web" if k == golpe
                       else "deducido: lejos del impacto de Claude web")
    if golpe is None and datos["picos"]:
        avisos.append(f"ningún pico de audio cae a menos de {TOLERANCIA_PICO_S} s del impacto: todos quedan como no-palo")

    datos.update(DE_DOCS10.get(nombre, {}))
    datos["autor_etiquetas"] = f"claude-web ({resp.get('modelo') or 'modelo sin nombre'})"
    datos["claude_web"] = {"fecha": datetime.now().isoformat(timespec="seconds"),
                           "confianza": resp.get("confianza"), "dudas": resp.get("dudas"),
                           "avisos": avisos}
    salida = guardar_etiquetas(ruta, datos)
    (destino / "respuesta.json").write_text(json.dumps(resp, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    revision = dibujar_revision(destino, info, fotos, datos)

    print(f"Importado en {salida.relative_to(RAIZ)} ({datos['autor_etiquetas']}).")
    pico = f"{datos['picos'][golpe]['t']:.3f} s" if golpe is not None else "ninguno"
    print(f"  top {t_top:.3f} s, impacto {t_impacto:.3f} s; pico del golpe: {pico}")
    for a in avisos:
        print(f"  Aviso: {a}")
    print(f"  Revisa a ojo el palo en {revision.relative_to(RAIZ)}")
    print("Cuánto coincide Claude web con Gemini (modelo A):")
    comparar_con_modelo(datos, info, quien="Claude web")


def main() -> None:
    parser = argparse.ArgumentParser(description="Etiquetas con Claude web: preparar las hojas e importar la respuesta.")
    sub = parser.add_subparsers(dest="orden", required=True)
    p = sub.add_parser("preparar", help="crea las hojas y el mensaje para claude.ai")
    p.add_argument("clips", nargs="*", help="nombres de clip (sin nada: los 3 del banco)")
    i = sub.add_parser("importar", help="valida y guarda la respuesta de Claude web")
    i.add_argument("clip")
    i.add_argument("respuesta", help="archivo con la respuesta, o - para leerla de la entrada")
    i.add_argument("--sobrescribir", action="store_true", help="pisa etiquetas puestas a mano")
    args = parser.parse_args()
    if args.orden == "preparar":
        for ruta in ([resolver_clip(c) for c in args.clips] or clips_del_banco()):
            preparar(ruta)
    else:
        importar(resolver_clip(args.clip), args.respuesta, args.sobrescribir)


if __name__ == "__main__":
    main()
