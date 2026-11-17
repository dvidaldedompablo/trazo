"""Etiquetado a mano de un clip del banco de pruebas (docs/10, Fase 1, paso 1).

Uso (desde la raíz del repo):
    lab\\.venv\\Scripts\\python lab\\etiquetar.py story1-puerta-de-hierro
    lab\\.venv\\Scripts\\python lab\\etiquetar.py driver-campo --alto 700   (si la ventana no cabe)

Teclas (con la ventana del vídeo activa):
    A / D       fotograma anterior / siguiente (también flechas izquierda y derecha)
    S / W       10 fotogramas atrás / adelante (también flechas abajo y arriba)
    I / T       impacto / top del swing elegido en este fotograma (otra vez en el mismo: lo borra)
    1 a 5       fase del palo: 1 preparación, 2 takeaway, 3 mitad de subida, 4 top, 5 bajada
    clic        marca la cabeza del palo de la fase elegida en este fotograma
    X           borra la marca del palo de la fase elegida
    J           salta al fotograma que propone el modelo para la fase elegida
    P / O       siguiente / anterior pico de audio
    Y / N       el pico elegido es / no es el golpe del palo (otra vez la misma: sin marcar)
    M           con música: sí / no
    [ / ]       swing anterior / siguiente;  +  añade un swing;  -  quita el swing elegido
    G           guarda el JSON
    H           enseña u oculta la ayuda
    Q o Esc     sale (con cambios sin guardar, hay que pulsarla dos veces)
Un clic en la línea de tiempo de abajo salta a ese instante.

Lo del modelo (campos modelo_*) se ve en magenta y solo es una pista: lo que tú marcas va en los
campos sin prefijo, que son la verdad del banco. Este script nunca escribe los campos modelo_*.
"""
from __future__ import annotations

import argparse

import cv2
import numpy as np

from comun import (FASES_PALO, RAIZ, cargar_etiquetas, decodificar, guardar_etiquetas, leer_fotogramas,
                   leer_info, resolver_clip, ruta_etiquetas)

ANCHO_PANEL = 480
ALTO_LINEA_TIEMPO = 70
VENTANA = "Trazo - etiquetar"
FUENTE = cv2.FONT_HERSHEY_SIMPLEX  # sin tildes: OpenCV no las dibuja, por eso los textos van sin ellas

# Colores en BGR
BLANCO = (255, 255, 255)
GRIS = (150, 150, 150)
AMARILLO = (0, 220, 255)
CIAN = (255, 220, 0)
VERDE = (90, 220, 90)
ROJO = (60, 60, 240)
MAGENTA = (220, 80, 220)
AZUL = (255, 150, 60)

# Teclas especiales de waitKeyEx en Windows
IZQUIERDA, ARRIBA, DERECHA, ABAJO = 2424832, 2490368, 2555904, 2621440

AYUDA = [
    "A/D: -1/+1 fotograma   S/W: -10/+10",
    "I: impacto   T: top (otra vez: borra)",
    "1-5: fase del palo   clic: cabeza del palo",
    "X: borra la marca   J: ir a la del modelo",
    "P/O: pico siguiente/anterior",
    "Y/N: el pico es / no es el palo",
    "M: musica   [ ]: swing   + -: anade/quita",
    "G: guardar   H: ayuda   Q/Esc: salir",
]


class Etiquetador:
    def __init__(self, clip, alto_video: int):
        self.clip = clip
        self.info = leer_info(clip)
        print(f"Leyendo {self.info.n} fotogramas de {clip.name}...")
        self.fotogramas = leer_fotogramas(self.info)
        self.datos = cargar_etiquetas(clip)
        self.alto_video = alto_video
        self.escala = alto_video / self.info.alto
        self.ancho_video = round(self.info.ancho * self.escala)
        self.i = 0
        self.fase = 0          # índice en FASES_PALO
        self.swing = 0
        self.pico: int | None = None
        self.cambios = False
        self.ayuda = True
        self.aviso = ""
        self.salida_pedida = False
        self.arrastrando = False

    # ------------------------------------------------------------ utilidades

    @property
    def t(self) -> float:
        return self.info.tiempos[self.i]

    def indice(self, t: float | None) -> int | None:
        return None if t is None else self.info.indice_mas_cercano(t)

    def ir_a(self, i: int) -> None:
        self.i = max(0, min(self.info.n - 1, i))
        self.salida_pedida = False

    def x_de_tiempo(self, t: float) -> int:
        ancho = self.ancho_video + ANCHO_PANEL - 20
        return 10 + round(ancho * t / max(self.info.duracion, 1e-6))

    def tiempo_de_x(self, x: int) -> float:
        ancho = self.ancho_video + ANCHO_PANEL - 20
        return max(0.0, (x - 10) / ancho * self.info.duracion)

    def modelo_aqui(self) -> list[dict]:
        return [m for m in (self.datos.get("modelo_fases") or []) if self.indice(m.get("t")) == self.i]

    def modelo_de_fase(self) -> dict | None:
        nombre = FASES_PALO[self.fase]
        return next((m for m in (self.datos.get("modelo_palo") or []) if m.get("fase") == nombre), None)

    def cambiar(self, aviso: str = "") -> None:
        self.cambios = True
        self.salida_pedida = False
        self.aviso = aviso

    # ------------------------------------------------------------ dibujo

    def texto(self, lienzo, x, y, s, color=BLANCO, escala=0.5, grosor=1):
        cv2.putText(lienzo, s, (x, y), FUENTE, escala, (0, 0, 0), grosor + 2, cv2.LINE_AA)
        cv2.putText(lienzo, s, (x, y), FUENTE, escala, color, grosor, cv2.LINE_AA)

    def dibujar(self) -> np.ndarray:
        alto, ancho = self.alto_video + ALTO_LINEA_TIEMPO, self.ancho_video + ANCHO_PANEL
        lienzo = np.zeros((alto, ancho, 3), np.uint8)
        interpolacion = cv2.INTER_AREA if self.escala < 1 else cv2.INTER_LINEAR
        imagen = cv2.resize(decodificar(self.fotogramas[self.i]), (self.ancho_video, self.alto_video),
                            interpolation=interpolacion)
        s = self.escala

        # Pista del modelo en este fotograma: la caja aproximada de la cabeza del palo.
        for m in self.modelo_aqui():
            if m.get("caja"):
                x0, y0, x1, y1 = m["caja"]
                cv2.rectangle(imagen, (round(x0 * s), round(y0 * s)), (round(x1 * s), round(y1 * s)), MAGENTA, 1)
                self.texto(imagen, round(x0 * s), max(14, round(y0 * s) - 4),
                           f"modelo: {m.get('fase')} {m.get('confianza') or 0:.2f}", MAGENTA, 0.45)
        # Marcas del usuario en este fotograma.
        for k, p in enumerate(self.datos["palo"]):
            if p.get("t") is not None and p.get("x") is not None and self.indice(p["t"]) == self.i:
                centro = (round(p["x"] * s), round(p["y"] * s))
                color = AMARILLO if k == self.fase else CIAN
                cv2.circle(imagen, centro, 10, color, 2, cv2.LINE_AA)
                cv2.circle(imagen, centro, 2, color, -1, cv2.LINE_AA)
                self.texto(imagen, centro[0] + 12, centro[1] - 8, str(k + 1), color, 0.6, 2)
        # Aviso grande si hay un pico de audio en este fotograma.
        for p in self.datos["picos"]:
            if self.indice(p["t"]) == self.i:
                self.texto(imagen, 10, self.alto_video - 16, f"PICO {p['t']:.3f} s", ROJO, 0.8, 2)
        if self.ayuda:
            capa = imagen.copy()
            cv2.rectangle(capa, (0, 0), (min(self.ancho_video, 420), 30 + 22 * len(AYUDA)), (0, 0, 0), -1)
            imagen = cv2.addWeighted(capa, 0.65, imagen, 0.35, 0)
            for n, linea in enumerate(AYUDA):
                self.texto(imagen, 10, 24 + 22 * n, linea, BLANCO, 0.5)
        lienzo[:self.alto_video, :self.ancho_video] = imagen

        self.dibujar_panel(lienzo)
        self.dibujar_linea_tiempo(lienzo)
        return lienzo

    def dibujar_panel(self, lienzo) -> None:
        x = self.ancho_video + 14
        y = 26
        paso = 21

        def linea(s, color=BLANCO, escala=0.5, grosor=1):
            nonlocal y
            self.texto(lienzo, x, y, s, color, escala, grosor)
            y += paso

        linea(self.clip.name, BLANCO, 0.55, 1)
        linea(f"Fotograma {self.i + 1}/{self.info.n}    t = {self.t:.3f} s", AMARILLO, 0.6, 2)
        musica = {None: "sin marcar", True: "si", False: "no"}[self.datos.get("musica")]
        linea(f"Musica (M): {musica}")
        y += 6
        swings = self.datos["swings"]
        linea(f"Swing {self.swing + 1} de {len(swings)}  ([ ] cambia, + anade)", BLANCO)
        sw = swings[self.swing]
        linea(f"  top (T): {fmt(sw.get('top'))}    impacto (I): {fmt(sw.get('impacto'))}", AZUL)
        ms = (self.datos.get("modelo_swings") or [None])[0]
        if ms:
            linea(f"  modelo: top {fmt(ms.get('top'))}  impacto {fmt(ms.get('impacto'))}", MAGENTA, 0.45)
        y += 6
        linea("Cabeza del palo (1-5 elige, clic marca):", BLANCO)
        for k, p in enumerate(self.datos["palo"]):
            elegido = k == self.fase
            marca = f"t={p['t']:.3f} ({p['x']},{p['y']})" if p.get("t") is not None else "--"
            linea(f"{'>' if elegido else ' '} {k + 1} {p['fase']:<13} {marca}", AMARILLO if elegido else GRIS)
        modelo = self.modelo_de_fase()
        if modelo and modelo.get("t") is not None:
            linea(f"  modelo ({FASES_PALO[self.fase]}): t={modelo['t']:.3f}  conf "
                  f"{modelo.get('confianza') or 0:.2f}  (J va)", MAGENTA, 0.45)
        for m in self.modelo_aqui():
            linea(f"  modelo en este fotograma: {m.get('fase')} ({m.get('confianza') or 0:.2f})", MAGENTA, 0.45)
        y += 6
        picos = self.datos["picos"]
        linea(f"Picos de audio: {len(picos)}  (P/O va, Y/N marca)", BLANCO)
        modelo_picos = {round(m["t"], 3): m for m in (self.datos.get("modelo_picos") or [])}
        for k, p in enumerate(picos):
            if y > self.alto_video - 70:
                linea("  ...", GRIS)
                break
            es = {None: "?", True: "PALO", False: "no"}[p.get("es_palo")]
            color = VERDE if p.get("es_palo") else (GRIS if p.get("es_palo") is False else BLANCO)
            if k == self.pico:
                color = AMARILLO
            corte = "corte" if p.get("propuesto") else "     "
            pista = modelo_picos.get(round(p["t"], 3))
            pista_txt = f"  mod:{pista.get('sonido_es_impacto')}" if pista else ""
            linea(f"{'>' if k == self.pico else ' '} {p['t']:6.3f}  f {p.get('fuerza', 0):.2f} {corte}  {es}{pista_txt}",
                  color, 0.45)
        y = self.alto_video - 30
        if self.aviso:
            self.texto(lienzo, x, y, self.aviso[:52], AMARILLO, 0.45)
        y += paso
        self.texto(lienzo, x, y, "SIN GUARDAR (G guarda)" if self.cambios else "Guardado", ROJO if self.cambios else VERDE,
                   0.5, 1)

    def dibujar_linea_tiempo(self, lienzo) -> None:
        arriba = self.alto_video
        base = arriba + ALTO_LINEA_TIEMPO - 22
        derecha = self.x_de_tiempo(self.info.duracion)
        cv2.line(lienzo, (10, base), (derecha, base), GRIS, 1)
        for segundo in range(int(self.info.duracion) + 1):
            xs = self.x_de_tiempo(segundo)
            cv2.line(lienzo, (xs, base), (xs, base + 5), GRIS, 1)
            self.texto(lienzo, xs - 4, base + 18, str(segundo), GRIS, 0.4)
        for p in self.datos["picos"]:
            xp = self.x_de_tiempo(p["t"])
            altura = 6 + round(30 * min(1.0, p.get("fuerza", 0.3)))
            color = VERDE if p.get("es_palo") else (GRIS if p.get("es_palo") is False else (ROJO if p.get("propuesto") else BLANCO))
            cv2.line(lienzo, (xp, base), (xp, base - altura), color, 2)
        for sw in self.datos["swings"]:
            for clave, color, letra in (("top", AZUL, "T"), ("impacto", AMARILLO, "I")):
                if sw.get(clave) is not None:
                    xs = self.x_de_tiempo(sw[clave])
                    self.texto(lienzo, xs - 5, arriba + 14, letra, color, 0.45, 1)
        for ms in self.datos.get("modelo_swings") or []:
            for clave in ("top", "impacto"):
                if ms.get(clave) is not None:
                    xs = self.x_de_tiempo(ms[clave])
                    cv2.drawMarker(lienzo, (xs, arriba + 24), MAGENTA, cv2.MARKER_TRIANGLE_DOWN, 9, 1)
        for p in self.datos["palo"]:
            if p.get("t") is not None:
                cv2.circle(lienzo, (self.x_de_tiempo(p["t"]), base - 3), 3, CIAN, -1)
        xa = self.x_de_tiempo(self.t)
        cv2.line(lienzo, (xa, arriba + 4), (xa, base + 4), BLANCO, 1)

    # ------------------------------------------------------------ acciones

    def raton(self, evento, x, y, banderas, _param) -> None:
        if evento == cv2.EVENT_LBUTTONDOWN:
            if y < self.alto_video and x < self.ancho_video:
                self.marcar_palo(x, y)
            elif y >= self.alto_video:
                self.arrastrando = True
                self.ir_a(self.info.indice_mas_cercano(self.tiempo_de_x(x)))
        elif evento == cv2.EVENT_MOUSEMOVE and self.arrastrando and banderas & cv2.EVENT_FLAG_LBUTTON:
            self.ir_a(self.info.indice_mas_cercano(self.tiempo_de_x(x)))
        elif evento == cv2.EVENT_LBUTTONUP:
            self.arrastrando = False

    def marcar_palo(self, x, y) -> None:
        p = self.datos["palo"][self.fase]
        p["t"] = round(self.t, 4)
        p["x"] = min(self.info.ancho - 1, max(0, round(x / self.escala)))
        p["y"] = min(self.info.alto - 1, max(0, round(y / self.escala)))
        self.cambiar(f"{p['fase']}: cabeza del palo en ({p['x']}, {p['y']})")

    def marcar_swing(self, clave: str) -> None:
        sw = self.datos["swings"][self.swing]
        if sw.get(clave) is not None and self.indice(sw[clave]) == self.i:
            sw[clave] = None
            self.cambiar(f"{clave} borrado")
        else:
            sw[clave] = round(self.t, 4)
            self.cambiar(f"{clave} en {self.t:.3f} s")

    def ir_a_pico(self, sentido: int) -> None:
        picos = self.datos["picos"]
        if not picos:
            self.aviso = "Este clip no tiene picos de audio"
            return
        if self.pico is None:
            orden = [k for k, p in enumerate(picos) if (p["t"] > self.t + 1e-6 if sentido > 0 else p["t"] < self.t - 1e-6)]
            self.pico = (orden[0] if sentido > 0 else orden[-1]) if orden else (0 if sentido > 0 else len(picos) - 1)
        else:
            self.pico = (self.pico + sentido) % len(picos)
        self.ir_a(self.info.indice_mas_cercano(picos[self.pico]["t"]))
        self.aviso = f"Pico {self.pico + 1} de {len(picos)}: {picos[self.pico]['t']:.3f} s"

    def marcar_pico(self, es_palo: bool) -> None:
        picos = self.datos["picos"]
        k = self.pico
        if k is None:
            cercanos = [j for j, p in enumerate(picos) if abs(p["t"] - self.t) < 0.1]
            k = min(cercanos, key=lambda j: abs(picos[j]["t"] - self.t)) if cercanos else None
        if k is None:
            self.aviso = "Elige un pico con P u O"
            return
        p = picos[k]
        p["es_palo"] = None if p.get("es_palo") is es_palo else es_palo
        self.cambiar(f"Pico {p['t']:.3f} s: {'palo' if p['es_palo'] else ('no' if p['es_palo'] is False else 'sin marcar')}")

    def guardar(self) -> None:
        self.datos["golpes"] = sum(1 for sw in self.datos["swings"] if sw.get("impacto") is not None)
        ruta = guardar_etiquetas(self.clip, self.datos)
        self.cambios = False
        self.aviso = "Guardado"
        print(f"\nGuardado en {ruta.relative_to(RAIZ)}")
        comparar_con_modelo(self.datos, self.info)

    # ------------------------------------------------------------ bucle

    def correr(self) -> None:
        cv2.namedWindow(VENTANA, cv2.WINDOW_AUTOSIZE)
        cv2.setMouseCallback(VENTANA, self.raton)
        while True:
            cv2.imshow(VENTANA, self.dibujar())
            tecla = cv2.waitKeyEx(30)
            if cv2.getWindowProperty(VENTANA, cv2.WND_PROP_VISIBLE) < 1:
                if self.cambios:
                    copia = ruta_etiquetas(self.clip).with_suffix(".sin-guardar.json")
                    guardar_etiquetas(self.clip, self.datos, copia)
                    print(f"Has cerrado la ventana sin guardar. Copia de tus cambios en {copia.relative_to(RAIZ)}")
                break
            if tecla == -1:
                continue
            c = chr(tecla).lower() if 0 <= tecla < 256 else ""
            if tecla in (27,) or c == "q":
                if self.cambios and not self.salida_pedida:
                    self.salida_pedida = True
                    self.aviso = "Hay cambios sin guardar: G guarda, Q otra vez sale"
                    continue
                break
            if c == "d" or tecla == DERECHA:
                self.ir_a(self.i + 1)
            elif c == "a" or tecla == IZQUIERDA:
                self.ir_a(self.i - 1)
            elif c == "w" or tecla == ARRIBA:
                self.ir_a(self.i + 10)
            elif c == "s" or tecla == ABAJO:
                self.ir_a(self.i - 10)
            elif c == "i":
                self.marcar_swing("impacto")
            elif c == "t":
                self.marcar_swing("top")
            elif c and c in "12345":
                self.fase = int(c) - 1
                self.aviso = f"Fase {c}: {FASES_PALO[self.fase]}"
            elif c == "x":
                p = self.datos["palo"][self.fase]
                p.update(t=None, x=None, y=None)
                self.cambiar(f"{p['fase']}: marca borrada")
            elif c == "j":
                m = self.modelo_de_fase()
                if m and m.get("t") is not None:
                    self.ir_a(self.info.indice_mas_cercano(m["t"]))
                else:
                    self.aviso = "El modelo no propone nada para esta fase"
            elif c == "p":
                self.ir_a_pico(+1)
            elif c == "o":
                self.ir_a_pico(-1)
            elif c == "y":
                self.marcar_pico(True)
            elif c == "n":
                self.marcar_pico(False)
            elif c == "m":
                self.datos["musica"] = not bool(self.datos.get("musica"))
                self.cambiar(f"Musica: {'si' if self.datos['musica'] else 'no'}")
            elif c == "[":
                self.swing = max(0, self.swing - 1)
            elif c == "]":
                self.swing = min(len(self.datos["swings"]) - 1, self.swing + 1)
            elif c == "+":
                self.datos["swings"].append({"top": None, "impacto": None})
                self.swing = len(self.datos["swings"]) - 1
                self.cambiar(f"Swing {self.swing + 1} anadido")
            elif c == "-":
                if len(self.datos["swings"]) > 1:
                    self.datos["swings"].pop(self.swing)
                    self.swing = max(0, self.swing - 1)
                    self.cambiar("Swing quitado")
            elif c == "g":
                self.guardar()
            elif c == "h":
                self.ayuda = not self.ayuda
        cv2.destroyAllWindows()


def fmt(t) -> str:
    return "--" if t is None else f"{t:.3f}"


def comparar_con_modelo(datos: dict, info) -> None:
    """Cuenta qué propuestas del modelo has cambiado, para la PARADA 1 de docs/10.

    Criterio (solo para el recuento, no es la medida del banco): un instante cuenta como cambiado si
    está a 2 fotogramas o más del tuyo; una marca del palo, si además tu punto cae fuera de su caja;
    un pico, si tu "es palo" no coincide con lo que dijo el modelo.
    """
    if not any(datos.get(k) for k in ("modelo_swings", "modelo_palo", "modelo_picos")):
        return
    filas, cambiadas, total = [], 0, 0

    def fotogramas(a, b):
        return abs(info.indice_mas_cercano(a) - info.indice_mas_cercano(b))

    ms = (datos.get("modelo_swings") or [None])[0]
    sw = datos["swings"][0] if datos["swings"] else {}
    for clave in ("top", "impacto"):
        if ms and ms.get(clave) is not None and sw.get(clave) is not None:
            d = fotogramas(ms[clave], sw[clave])
            total += 1
            cambiadas += d >= 2
            filas.append(f"  {clave:<13} modelo {ms[clave]:.3f}  tú {sw[clave]:.3f}  ({d} fotogramas)")
    modelo_palo = {m["fase"]: m for m in datos.get("modelo_palo") or []}
    for p in datos["palo"]:
        m = modelo_palo.get(p["fase"])
        if not m or m.get("t") is None or p.get("t") is None:
            continue
        d = fotogramas(m["t"], p["t"])
        dentro = bool(m.get("caja")) and m["caja"][0] <= p["x"] <= m["caja"][2] and m["caja"][1] <= p["y"] <= m["caja"][3]
        total += 1
        cambiadas += d >= 2 or not dentro
        filas.append(f"  {p['fase']:<13} modelo {m['t']:.3f}  tú {p['t']:.3f}  ({d} fotogramas, "
                     f"{'dentro' if dentro else 'fuera'} de su caja)")
    modelo_picos = {round(m["t"], 3): m for m in datos.get("modelo_picos") or []}
    for p in datos["picos"]:
        m = modelo_picos.get(round(p["t"], 3))
        if not m or p.get("es_palo") is None or m.get("sonido_es_impacto") not in ("si", "no"):
            continue
        total += 1
        distinto = (m["sonido_es_impacto"] == "si") != p["es_palo"]
        cambiadas += distinto
        filas.append(f"  pico {p['t']:.3f}    modelo {m['sonido_es_impacto']:<3} tú {'sí' if p['es_palo'] else 'no'}")
    print("Comparación con la propuesta del modelo:")
    print("\n".join(filas) if filas else "  (aún no hay nada que comparar)")
    print(f"Propuestas del modelo que has cambiado: {cambiadas} de {total} comparables "
          "(instante a 2 fotogramas o más, punto fuera de la caja o pico distinto).")


def main() -> None:
    argumentos = argparse.ArgumentParser(description="Etiqueta a mano un clip del banco de pruebas.")
    argumentos.add_argument("clip", help="nombre del clip (p. ej. driver-campo) o ruta al .mp4")
    argumentos.add_argument("--alto", type=int, default=860, help="alto del vídeo en pantalla (píxeles)")
    a = argumentos.parse_args()
    Etiquetador(resolver_clip(a.clip), a.alto).correr()


if __name__ == "__main__":
    main()
