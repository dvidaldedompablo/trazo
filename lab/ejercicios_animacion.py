"""Imágenes y clips en bucle de los 15 ejercicios (Fase 2 de los cambios del análisis, 22-11-2026).

Una plantilla de animación reutilizable con una figura propia, en el mismo estilo para todos:
  - fondo verde oscuro, figura clara, el palo gris claro y un color de acento (amarillo) para lo que
    hay que mirar: la parte que se mueve lleva un punto amarillo y una flecha o un rastro;
  - el camino que hay que evitar va en rojo, discontinuo y tenue;
  - movimiento lento (todo a cámara lenta) y figura grande, para quien no sabe de golf.
Tres vistas:
  - "frente": el jugador de cara (ritmo, pausa, cadera, hombros, paso, equilibrio, cabeza, manos);
  - "detras": de perfil, como la cámara de la app (subida, silla, toalla);
  - "arriba": vista desde arriba (takeaway y bajada: dentro y fuera se ven claros).
Todo el contenido visual lo genera este script: no se descarga nada.

Salida: assets/ejercicios/<id>.mp4 (H.264, 1080 x 1080, 30 fps, en bucle) y <id>.png (el momento clave).
Para cambiar un clip por uno propio basta con sustituir el archivo con el mismo nombre.

Uso: lab\\.venv\\Scripts\\python lab\\ejercicios_animacion.py [id ...]
"""
from __future__ import annotations

import math
import subprocess
import sys
from dataclasses import dataclass, field, replace
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

RAIZ = Path(__file__).resolve().parent.parent
SALIDA = RAIZ / "assets" / "ejercicios"
FUENTE = RAIZ / "App" / "Resources" / "Fonts" / "Lato-Black.ttf"

LADO = 1080
SS = 2                      # se dibuja al doble y se reduce: bordes suaves
FPS = 30
SUELO = 900

FONDO = (15, 42, 32)
FONDO_SUELO = (22, 58, 44)
FIGURA = (244, 241, 232)
SOMBRA = (10, 30, 23)
PALO = (205, 212, 207)
ACENTO = (255, 208, 46)
MAL = (255, 90, 78)
OBJETO = (159, 179, 168)
BIEN = (124, 240, 169)

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


# ---------------------------------------------------------------- utilidades de dibujo

def s(v):
    """De coordenadas a 1080 al lienzo al doble."""
    return v * SS


def P(p):
    return (s(p[0]), s(p[1]))


def suave(x: float) -> float:
    """Entrada y salida suaves (smoothstep)."""
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def linea(d: ImageDraw.ImageDraw, a, b, color, ancho):
    d.line([P(a), P(b)], fill=color, width=s(ancho))
    r = ancho / 2
    for q in (a, b):
        d.ellipse([s(q[0] - r), s(q[1] - r), s(q[0] + r), s(q[1] + r)], fill=color)


def punto(d, c, r, color, borde=None):
    d.ellipse([s(c[0] - r), s(c[1] - r), s(c[0] + r), s(c[1] + r)], fill=color,
              outline=borde, width=s(4) if borde else 0)


def discontinua(d, puntos, color, ancho=6, trazo=22, hueco=16):
    """Polilínea discontinua (el camino que hay que evitar)."""
    acumulado, pintando = 0.0, True
    for a, b in zip(puntos, puntos[1:]):
        largo = math.dist(a, b)
        pos = 0.0
        while pos < largo:
            limite = (trazo if pintando else hueco) - acumulado
            paso = min(limite, largo - pos)
            if pintando:
                p0 = (a[0] + (b[0] - a[0]) * pos / largo, a[1] + (b[1] - a[1]) * pos / largo)
                p1 = (a[0] + (b[0] - a[0]) * (pos + paso) / largo, a[1] + (b[1] - a[1]) * (pos + paso) / largo)
                d.line([P(p0), P(p1)], fill=color, width=s(ancho))
            pos += paso
            acumulado += paso
            if acumulado >= (trazo if pintando else hueco) - 1e-6:
                acumulado, pintando = 0.0, not pintando


def flecha(d, puntos, color, ancho=9, punta=30):
    """Flecha que sigue una polilínea, con la punta al final."""
    if len(puntos) < 2:
        return
    d.line([P(p) for p in puntos], fill=color, width=s(ancho), joint="curve")
    a, b = puntos[-2], puntos[-1]
    ang = math.atan2(b[1] - a[1], b[0] - a[0])
    izq = (b[0] - punta * math.cos(ang - 0.45), b[1] - punta * math.sin(ang - 0.45))
    der = (b[0] - punta * math.cos(ang + 0.45), b[1] - punta * math.sin(ang + 0.45))
    d.polygon([P(b), P(izq), P(der)], fill=color)


def texto(d, t, centro, tam, color):
    fuente = ImageFont.truetype(str(FUENTE), s(tam))
    caja = d.textbbox((0, 0), t, font=fuente)
    d.text((s(centro[0]) - (caja[2] - caja[0]) / 2, s(centro[1]) - (caja[3] - caja[1]) / 2 - caja[1]), t, font=fuente, fill=color)


def arco(cx, cy, r, a0, a1, n=24):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * k / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * k / n)))
            for k in range(n + 1)]


# ---------------------------------------------------------------- la figura

@dataclass
class Pose:
    """Postura de la figura. Ángulos en grados. En "frente", brazo positivo = hacia la izquierda de
    la imagen (la subida de un diestro de cara); en "detras", brazo positivo = hacia la bola."""
    cadera: float = 0       # desplazamiento lateral de la cadera (px)
    tronco: float = 4       # inclinación del tronco
    cabeza: float = 0       # desplazamiento de la cabeza (px)
    brazo: float = 0        # brazos desde los hombros (0 = colgando)
    muneca: float = 0       # ángulo del palo respecto a los brazos
    giro: float = 0         # giro de hombros de 0 a 1 (frente)
    rodilla: float = 0      # rodilla delantera (px)
    pie: float = 0          # pie delantero, desplazamiento (px)
    pie_alto: float = 0     # pie delantero levantado (px)
    talon: float = 0        # talón de atrás levantado en el final (px)
    palo: float = 1         # largo aparente del palo (escorzo: en el top, desde detrás, apunta al fondo)

    def mezcla(self, otra: "Pose", x: float) -> "Pose":
        return Pose(**{k: getattr(self, k) + (getattr(otra, k) - getattr(self, k)) * x for k in self.__dataclass_fields__})


@dataclass
class Geometria:
    puntos: dict = field(default_factory=dict)


def figura_frente(d, p: Pose, palo=True, brazos_cruzados=False) -> Geometria:
    cx = 540
    g = Geometria()
    cad = (cx + p.cadera, 600)
    ci, cd = (cad[0] - 55, cad[1]), (cad[0] + 55, cad[1])           # cadera de atrás (izq.), de delante (der.)
    tob_atras = (cx - 125, 892 - p.talon)
    tob_del = (cx + 125 + p.pie, 892 - p.pie_alto)
    rod_atras = ((ci[0] + tob_atras[0]) / 2 + 10, (ci[1] + tob_atras[1]) / 2)
    rod_del = ((cd[0] + tob_del[0]) / 2 - 10 + p.rodilla, (cd[1] + tob_del[1]) / 2)
    t = math.radians(p.tronco)
    hombro = (cad[0] + 200 * math.sin(t), cad[1] - 200 * math.cos(t))
    ancho = 95 * (1 - 0.6 * p.giro)
    h_del = (hombro[0] + ancho - 45 * p.giro, hombro[1] + 14 * p.giro)
    h_atras = (hombro[0] - ancho, hombro[1] - 8 * p.giro)
    cabeza = (hombro[0] + p.cabeza, hombro[1] - 74)
    b = math.radians(p.brazo)
    manos = (hombro[0] - 195 * math.sin(b), hombro[1] + 195 * math.cos(b))
    if brazos_cruzados:
        manos = (hombro[0], hombro[1] + 60)
    c = math.radians(p.brazo + p.muneca)
    cabeza_palo = (manos[0] - 290 * math.sin(c), manos[1] + 290 * math.cos(c))
    # Piernas, cadera y tronco.
    for a, bb, cc in ((ci, rod_atras, tob_atras), (cd, rod_del, tob_del)):
        linea(d, a, bb, FIGURA, 44)
        linea(d, bb, cc, FIGURA, 38)
    linea(d, (tob_atras[0] - 30, tob_atras[1] + 8 + p.talon * 0.3), (tob_atras[0] + 25, tob_atras[1] + 8), FIGURA, 22)
    linea(d, (tob_del[0] - 25, tob_del[1] + 8), (tob_del[0] + 30, tob_del[1] + 8), FIGURA, 22)
    linea(d, ci, cd, FIGURA, 50)
    d.polygon([P(ci), P(cd), P(h_del), P(h_atras)], fill=FIGURA)
    linea(d, h_atras, h_del, FIGURA, 46)
    punto(d, cabeza, 46, FIGURA)
    linea(d, ((h_atras[0] + h_del[0]) / 2, hombro[1]), cabeza, FIGURA, 30)
    # Brazos y palo.
    if brazos_cruzados:
        linea(d, h_atras, (hombro[0] + 30, hombro[1] + 50), FIGURA, 30)
        linea(d, h_del, (hombro[0] - 30, hombro[1] + 50), FIGURA, 30)
    else:
        linea(d, h_atras, manos, FIGURA, 30)
        linea(d, h_del, manos, FIGURA, 30)
        if palo:
            linea(d, manos, cabeza_palo, PALO, 10)
            linea(d, cabeza_palo, (cabeza_palo[0] + 26, cabeza_palo[1] + 4), PALO, 18)
        punto(d, manos, 18, FIGURA)
    g.puntos.update(cadera=cad, cadera_atras=ci, cadera_del=cd, hombro=hombro, hombro_del=h_del, hombro_atras=h_atras,
                    cabeza=cabeza, manos=manos, cabeza_palo=cabeza_palo, pie_del=tob_del, pie_atras=tob_atras)
    return g


def figura_detras(d, p: Pose) -> Geometria:
    """De perfil, mirando a la derecha (la bola, a la derecha de los pies)."""
    cx = 500
    g = Geometria()
    cad = (cx - 80 + p.cadera, 560)
    tob = (cx - 40, 892)
    rod = (cx + 12 + p.rodilla, 735)
    t = math.radians(p.tronco)
    hombro = (cad[0] + 240 * math.sin(t), cad[1] - 240 * math.cos(t))
    tc = math.radians(p.tronco - 12)
    cabeza = (hombro[0] + 74 * math.sin(tc) + p.cabeza, hombro[1] - 74 * math.cos(tc))
    b = math.radians(p.brazo)
    manos = (hombro[0] + 225 * math.sin(b), hombro[1] + 225 * math.cos(b))
    c = math.radians(p.brazo + p.muneca)
    cabeza_palo = (manos[0] + 380 * p.palo * math.sin(c), manos[1] + 380 * p.palo * math.cos(c))
    linea(d, (tob[0] - 20, tob[1] + 8), (tob[0] + 70, tob[1] + 8), FIGURA, 24)
    linea(d, cad, rod, FIGURA, 50)
    linea(d, rod, tob, FIGURA, 42)
    punto(d, (cad[0] - 12, cad[1] + 4), 40, FIGURA)       # el culo
    linea(d, cad, hombro, FIGURA, 64)
    punto(d, cabeza, 46, FIGURA)
    linea(d, hombro, manos, FIGURA, 32)
    linea(d, manos, cabeza_palo, PALO, 10)
    linea(d, cabeza_palo, (cabeza_palo[0] + 28, cabeza_palo[1] + 2), PALO, 18)
    punto(d, manos, 18, FIGURA)
    g.puntos.update(cadera=cad, culo=(cad[0] - 52, cad[1]), hombro=hombro, cabeza=cabeza, manos=manos, cabeza_palo=cabeza_palo)
    return g


# Posturas de frente.
F_PREP = Pose()
F_MEDIA = Pose(brazo=60, muneca=60, giro=0.5, tronco=6)
F_TOP = Pose(brazo=125, muneca=95, giro=1.0, tronco=8, rodilla=-12)
F_BAJADA = Pose(brazo=70, muneca=85, giro=0.6, tronco=6, cadera=10)
F_IMPACTO = Pose(brazo=-6, muneca=-4, giro=0.3, tronco=-2, cadera=18)
F_SALIDA = Pose(brazo=-70, muneca=-50, giro=0.6, tronco=-6, cadera=30)
F_FINAL = Pose(brazo=-135, muneca=-80, giro=1.0, tronco=-12, cadera=40, talon=26)
# Posturas de perfil (detrás).
D_PREP = Pose(tronco=38, brazo=18, muneca=22)
D_TOP = Pose(tronco=36, brazo=-165, muneca=65, palo=0.4)   # el palo apunta al fondo: se ve corto
D_IMPACTO = Pose(tronco=36, brazo=16, muneca=22, cadera=0)


# ---------------------------------------------------------------- animaciones

@dataclass
class Clave:
    t: float
    pose: Pose


def pose_en(claves: list[Clave], t: float) -> Pose:
    if t <= claves[0].t:
        return claves[0].pose
    for a, b in zip(claves, claves[1:]):
        if a.t <= t <= b.t:
            return a.pose.mezcla(b.pose, suave((t - a.t) / max(b.t - a.t, 1e-6)))
    return claves[-1].pose


def lienzo(vista: str) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGB", (s(LADO), s(LADO)), FONDO)
    d = ImageDraw.Draw(img)
    if vista == "arriba":
        d.rectangle([0, 0, s(LADO), s(LADO)], fill=FONDO_SUELO)
    else:
        d.rectangle([0, s(SUELO + 8), s(LADO), s(LADO)], fill=FONDO_SUELO)
    return img, d


@dataclass
class Ejercicio:
    id: str
    vista: str
    duracion: float
    claves: list[Clave] = field(default_factory=list)
    instante_imagen: float = 0
    dibujar: object = None       # función(d, t, pose) que dibuja figura y marcas


def rastro(claves, desde, hasta, clave_punto, vista, n=40):
    """Camino de un punto de la figura (manos, cabeza del palo) entre dos instantes."""
    pts = []
    for k in range(n + 1):
        t = desde + (hasta - desde) * k / n
        img, d = Image.new("RGB", (8, 8)), None
        p = pose_en(claves, t)
        g = (geom_frente if vista == "frente" else geom_detras)(p)
        pts.append(g[clave_punto])
    return pts


def geom_frente(p: Pose) -> dict:
    d = ImageDraw.Draw(Image.new("RGB", (8, 8)))
    return figura_frente(d, p).puntos


def geom_detras(p: Pose) -> dict:
    d = ImageDraw.Draw(Image.new("RGB", (8, 8)))
    return figura_detras(d, p).puntos


# --- vista desde arriba (takeaway y bajada) ---

BOLA_A = (600, 470)
MANOS_A = (560, 650)


def jugador_arriba(d):
    """El jugador visto desde arriba: pies, hombros y cabeza, por debajo de la línea de la bola."""
    for x in (450, 650):
        d.rounded_rectangle([s(x - 34), s(800 - 62), s(x + 34), s(800 + 62)], radius=s(30), fill=SOMBRA)
    d.ellipse([s(390), s(650), s(730), s(770)], fill=FIGURA)
    punto(d, (560, 712), 52, FIGURA, borde=SOMBRA)


def escena_arriba(d, cabeza_palo, objeto=None, varilla=None):
    discontinua(d, [(80, BOLA_A[1]), (1000, BOLA_A[1])], OBJETO, ancho=3, trazo=14, hueco=14)
    flecha(d, [(900, 140), (1010, 140)], OBJETO, ancho=6, punta=22)     # hacia el objetivo
    if varilla:
        linea(d, varilla[0], varilla[1], OBJETO, 14)
    if objeto:
        d.rounded_rectangle([s(objeto[0] - 34), s(objeto[1] - 46), s(objeto[0] + 34), s(objeto[1] + 46)], radius=s(26), fill=OBJETO)
    punto(d, BOLA_A, 15, (255, 255, 255))
    jugador_arriba(d)
    linea(d, MANOS_A, cabeza_palo, PALO, 10)
    punto(d, MANOS_A, 20, FIGURA)
    d.rounded_rectangle([s(cabeza_palo[0] - 26), s(cabeza_palo[1] - 14), s(cabeza_palo[0] + 26), s(cabeza_palo[1] + 14)],
                        radius=s(10), fill=PALO)
    punto(d, cabeza_palo, 12, ACENTO)


def recorrido(pts, x):
    """Punto a una fracción x (0 a 1) de una polilínea."""
    largos = [math.dist(a, b) for a, b in zip(pts, pts[1:])]
    total = sum(largos)
    objetivo = total * min(max(x, 0), 1)
    for (a, b), l in zip(zip(pts, pts[1:]), largos):
        if objetivo <= l:
            f = objetivo / max(l, 1e-6)
            return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
        objetivo -= l
    return pts[-1]


def curva(p0, p1, p2, n=30):
    return [((1 - u) ** 2 * p0[0] + 2 * (1 - u) * u * p1[0] + u * u * p2[0],
             (1 - u) ** 2 * p0[1] + 2 * (1 - u) * u * p1[1] + u * u * p2[1]) for u in (k / n for k in range(n + 1))]


def ida_y_vuelta(t, duracion, ida=0.45, pausa=0.12):
    """De 0 a 1 en la ida, quieto un momento y vuelta a 0: el bucle de los caminos."""
    x = t / duracion
    if x < ida:
        return suave(x / ida)
    if x < ida + pausa:
        return 1.0
    return 1 - suave((x - ida - pausa) / (1 - ida - pausa))


def ej_arriba(id_, camino_bien, camino_mal, objeto=None, varilla=None, solo_ida=False):
    def dibujar(d, t, _):
        x = ida_y_vuelta(t, 5.0) if not solo_ida else suave(min(t / 3.6, 1))
        discontinua(d, camino_mal, MAL, ancho=6)
        cab = recorrido(camino_bien, x)
        # Rastro amarillo del camino bueno hasta donde va la cabeza del palo.
        hecho = [p for p in camino_bien if math.dist(camino_bien[0], p) <= math.dist(camino_bien[0], cab) + 1]
        escena_arriba(d, cab, objeto, varilla)
        if len(hecho) > 1:
            d.line([P(p) for p in hecho + [cab]], fill=ACENTO, width=s(7), joint="curve")
        flecha(d, camino_bien[-6:], ACENTO + (0,), ancho=0) if False else None
    return Ejercicio(id_, "arriba", 5.0, instante_imagen=2.4 if not solo_ida else 3.4, dibujar=dibujar)


# --- de frente ---

def ej_frente(id_, claves, duracion, imagen, extra=None, palo=True, cruzados=False):
    def dibujar(d, t, pose):
        if extra:
            extra(d, t, pose, "antes")
        g = figura_frente(d, pose, palo=palo, brazos_cruzados=cruzados).puntos
        if extra:
            extra(d, t, pose, "despues", g)
    return Ejercicio(id_, "frente", duracion, claves, imagen, dibujar)


def ej_detras(id_, claves, duracion, imagen, extra=None):
    def dibujar(d, t, pose):
        if extra:
            extra(d, t, pose, "antes")
        g = figura_detras(d, pose).puntos
        punto(d, D_BOLA, 15, (255, 255, 255))
        if extra:
            extra(d, t, pose, "despues", g)
    return Ejercicio(id_, "detras", duracion, claves, imagen, dibujar)


D_BOLA = (geom_detras(D_PREP)["cabeza_palo"][0] + 12, SUELO - 6)
F_BOLA = (geom_frente(F_PREP)["cabeza_palo"][0] + 12, SUELO - 4)


def bola_frente(d):
    punto(d, F_BOLA, 14, (255, 255, 255))


def swing_completo(t0=0.6, subida=1.8, bajada=0.6, final=0.9, pausa_arriba=0.0, quieto_final=0.8, vuelta=1.1):
    t = t0
    claves = [Clave(0, F_PREP), Clave(t, F_PREP)]
    t += subida * 0.45
    claves.append(Clave(t, F_MEDIA))
    t += subida * 0.55
    claves.append(Clave(t, F_TOP))
    if pausa_arriba:
        t += pausa_arriba
        claves.append(Clave(t, F_TOP))
    t += bajada * 0.6
    claves.append(Clave(t, F_BAJADA))
    t += bajada * 0.4
    claves.append(Clave(t, F_IMPACTO))
    t += final * 0.4
    claves.append(Clave(t, F_SALIDA))
    t += final * 0.6
    claves.append(Clave(t, F_FINAL))
    t += quieto_final
    claves.append(Clave(t, F_FINAL))
    t += vuelta
    claves.append(Clave(t, F_PREP))
    return claves, t


def instante(claves, pose):
    return next(c.t for c in claves if c.pose is pose)


def ejercicios() -> list[Ejercicio]:
    lista: list[Ejercicio] = []

    # 1. Takeaway por dentro: varilla paralela a la línea; la cabeza del palo va por encima de ella.
    bien1 = [BOLA_A, (480, 474), (360, 482), (250, 492)]
    mal1 = curva(BOLA_A, (430, 520), (300, 640))
    lista.append(ej_arriba("takeaway_dentro", bien1, mal1, varilla=((220, 492), (560, 474))))

    # 2. Takeaway por fuera: funda justo fuera y detrás de la bola; la subida no la toca.
    bien2 = curva(BOLA_A, (430, 478), (260, 520))
    mal2 = curva(BOLA_A, (460, 430), (320, 360))
    lista.append(ej_arriba("takeaway_fuera", bien2, mal2, objeto=(470, 395)))

    # 15. Bajada por fuera: funda por fuera de la bola; la bajada llega desde dentro sin tocarla.
    bien15 = curva((220, 650), (380, 560), BOLA_A) + [(760, 455)]
    mal15 = curva((230, 330), (420, 380), BOLA_A)
    lista.append(ej_arriba("bajada_por_fuera", bien15, mal15, objeto=(455, 395), solo_ida=True))

    # 3 y 4. La subida: el camino de las manos, bien (amarillo) y el que hay que evitar (rojo).
    def subida(id_, mitad_bien, mitad_mal):
        # El palo de la mitad de la subida, casi horizontal hacia atrás (que no se salga del cuadro).
        prep, mitad, top = D_PREP, Pose(tronco=37, brazo=mitad_bien, muneca=-100 - mitad_bien), D_TOP
        claves = [Clave(0, prep), Clave(0.6, prep), Clave(2.4, mitad), Clave(3.8, top), Clave(4.4, top), Clave(6.0, prep)]
        otra = Pose(tronco=37, brazo=mitad_mal, muneca=-100 - mitad_mal)
        mal = [geom_detras(prep.mezcla(otra, x))["manos"] for x in (k / 12 for k in range(13))] + \
              [geom_detras(otra.mezcla(top, x))["manos"] for x in (k / 12 for k in range(13))]
        bien = rastro(claves, 0.6, 3.8, "manos", "detras")

        def extra(d, t, pose, fase, g=None):
            if fase == "antes":
                discontinua(d, mal, MAL, ancho=6)
                hecho = [p for k, p in enumerate(bien) if 0.6 + 3.2 * k / (len(bien) - 1) <= min(t, 3.8)]
                if len(hecho) > 1 and t <= 4.4:
                    flecha(d, hecho, ACENTO, ancho=8, punta=26)
            else:
                punto(d, g["manos"], 14, ACENTO)
        return ej_detras(id_, claves, 6.0, 2.4, extra)

    lista.append(subida("subida_vertical", -75, -125))   # bien: más alrededor del cuerpo
    lista.append(subida("subida_plana", -120, -70))      # bien: más cerca de la cabeza

    # 5. Ritmo rápido: uno, dos, tres en la subida y cuatro en el impacto.
    claves5, fin5 = swing_completo(subida=2.4, bajada=0.8)
    t_ini = claves5[1].t
    t_top = instante(claves5, F_TOP)
    t_imp = instante(claves5, F_IMPACTO)

    def extra5(d, t, pose, fase, g=None):
        if fase == "antes":
            bola_frente(d)
            return
        cuenta = None
        for k in range(3):
            if t_ini + k * (t_top - t_ini) / 3 <= t < t_ini + (k + 1) * (t_top - t_ini) / 3:
                cuenta = str(k + 1)
        if t_imp - 0.15 <= t < t_imp + 0.7:
            cuenta = "4"
        if cuenta:
            texto(d, cuenta, (880, 220), 200, ACENTO)
    lista.append(ej_frente("ritmo_rapido", claves5, fin5, t_top - 0.4, extra5))

    # 6. Transición brusca: pausa de un segundo arriba antes de bajar.
    claves6, fin6 = swing_completo(pausa_arriba=1.0)
    t_top6 = instante(claves6, F_TOP)

    def extra6(d, t, pose, fase, g=None):
        if fase == "antes":
            bola_frente(d)
            return
        if t_top6 <= t <= t_top6 + 1.0:
            x = (t - t_top6) / 1.0
            d.ellipse([s(800), s(140), s(960), s(300)], outline=OBJETO, width=s(8))
            d.line([P(p) for p in arco(880, 220, 80, -90, -90 + 360 * x)], fill=ACENTO, width=s(12))
            texto(d, "1 s", (880, 220), 54, ACENTO)
    lista.append(ej_frente("transicion_brusca", claves6, fin6, t_top6 + 0.5, extra6))

    # 7. Cadera hacia la bola: silla tocando el culo; el contacto se mantiene subiendo y bajando.
    claves7 = [Clave(0, D_PREP), Clave(0.6, D_PREP), Clave(2.6, D_TOP), Clave(3.0, D_TOP), Clave(3.8, D_IMPACTO),
               Clave(4.3, Pose(tronco=34, brazo=60, muneca=-25)), Clave(5.4, D_PREP)]
    culo = geom_detras(D_PREP)["culo"]

    def extra7(d, t, pose, fase, g=None):
        if fase == "antes":
            x = culo[0] - 40
            linea(d, (x, 470), (x, SUELO), OBJETO, 18)                # respaldo
            linea(d, (x, 640), (x - 150, 640), OBJETO, 18)            # asiento
            linea(d, (x - 150, 640), (x - 150, SUELO), OBJETO, 14)
        else:
            punto(d, (culo[0] - 8, culo[1]), 16, BIEN)
    lista.append(ej_detras("cadera_adelante", claves7, 5.4, 3.6, extra7))

    # 8. Cadera que se desliza: varilla clavada fuera de la cadera de atrás; la cadera gira sin tocarla.
    claves8 = [Clave(0, F_PREP), Clave(0.6, F_PREP), Clave(2.0, F_MEDIA), Clave(3.0, F_TOP), Clave(3.8, F_TOP), Clave(5.4, F_PREP)]
    x_varilla = geom_frente(F_PREP)["cadera_atras"][0] - 60

    def extra8(d, t, pose, fase, g=None):
        if fase == "antes":
            bola_frente(d)
            linea(d, (x_varilla, 430), (x_varilla, SUELO + 6), ACENTO, 12)
        else:
            punto(d, g["cadera_atras"], 14, ACENTO)
            if 0.6 <= t <= 3.8:
                flecha(d, arco(g["cadera"][0], 640, 110, 200, 330), ACENTO, ancho=8, punta=24)
    lista.append(ej_frente("deslizamiento_cadera", claves8, 5.4, 3.2, extra8))

    # 9. Brazos separados: toalla bajo las axilas; swing corto sin que se caiga.
    claves9 = [Clave(0, D_PREP), Clave(0.5, D_PREP), Clave(2.0, Pose(tronco=37, brazo=-70, muneca=-60)), Clave(2.5, Pose(tronco=37, brazo=-70, muneca=-60)),
               Clave(3.5, D_IMPACTO), Clave(4.4, Pose(tronco=35, brazo=75, muneca=-35)), Clave(5.6, D_PREP)]

    def extra9(d, t, pose, fase, g=None):
        if fase == "despues":
            h = g["hombro"]
            d.rounded_rectangle([s(h[0] - 8), s(h[1] + 22), s(h[0] + 56), s(h[1] + 62)], radius=s(10), fill=ACENTO)
    lista.append(ej_detras("brazos_separados", claves9, 5.6, 2.2, extra9))

    # 10. Poco giro de hombros: palo cruzado sobre el pecho; el hombro de delante llega bajo la barbilla.
    giro = Pose(giro=1.0, tronco=6)
    claves10 = [Clave(0, F_PREP), Clave(0.6, F_PREP), Clave(2.4, giro), Clave(3.4, giro), Clave(5.0, F_PREP)]

    def extra10(d, t, pose, fase, g=None):
        if fase == "despues":
            ha, hd = g["hombro_atras"], g["hombro_del"]
            linea(d, (ha[0] - 70, ha[1] + 26), (hd[0] + 70, hd[1] + 26), PALO, 12)
            punto(d, hd, 16, ACENTO)
            discontinua(d, [(g["cabeza"][0], g["cabeza"][1] + 40), (g["cabeza"][0], g["cabeza"][1] + 150)], ACENTO, ancho=5)
            if 0.6 <= t <= 2.4:
                flecha(d, [(hd[0] + 40, hd[1] - 60), (hd[0] - 10, hd[1] - 80), (hd[0] - 40, hd[1] - 60)], ACENTO, ancho=8, punta=24)
    lista.append(ej_frente("poco_giro_hombros", claves10, 5.0, 3.0, extra10, palo=False, cruzados=True))

    # 11. Poca transferencia de peso: pies juntos y, al empezar a bajar, un paso hacia el objetivo.
    juntos = replace(F_PREP, pie=-170)
    top11 = replace(F_TOP, pie=-170)
    paso = replace(F_BAJADA, pie=-80, pie_alto=34, cadera=14)
    claves11 = [Clave(0, juntos), Clave(0.6, juntos), Clave(2.6, top11), Clave(3.1, paso), Clave(3.5, replace(F_IMPACTO, cadera=26)),
                Clave(4.4, F_FINAL), Clave(5.0, F_FINAL), Clave(6.2, juntos)]

    def extra11(d, t, pose, fase, g=None):
        if fase == "antes":
            bola_frente(d)
        else:
            punto(d, g["pie_del"], 14, ACENTO)
            if 2.5 <= t <= 3.6:
                p = g["pie_del"]
                flecha(d, [(p[0] - 70, p[1] - 70), (p[0] + 20, p[1] - 90), (p[0] + 90, p[1] - 60)], ACENTO, ancho=8, punta=24)
    lista.append(ej_frente("transferencia_peso", claves11, 6.2, 3.1, extra11))

    # 12. Pérdida de equilibrio: aguantar el final tres segundos.
    claves12, fin12 = swing_completo(quieto_final=3.0)
    t_fin = instante(claves12, F_FINAL)

    def extra12(d, t, pose, fase, g=None):
        if fase == "antes":
            bola_frente(d)
            return
        if t_fin <= t < t_fin + 3.0:
            texto(d, str(int(t - t_fin) + 1), (880, 220), 200, ACENTO)
    lista.append(ej_frente("equilibrio_final", claves12, fin12, t_fin + 1.5, extra12))

    # 13. La cabeza se mueve: vista fija en la bola hasta después del impacto.
    claves13, fin13 = swing_completo()
    cab0 = geom_frente(F_PREP)["cabeza"]

    def extra13(d, t, pose, fase, g=None):
        if fase == "antes":
            bola_frente(d)
            discontinua(d, [cab0, F_BOLA], ACENTO, ancho=4, trazo=10, hueco=12)
        else:
            dentro = math.dist(g["cabeza"], cab0) <= 60
            d.ellipse([s(cab0[0] - 74), s(cab0[1] - 74), s(cab0[0] + 74), s(cab0[1] + 74)],
                      outline=BIEN if dentro else MAL, width=s(7))
    lista.append(ej_frente("cabeza_se_mueve", claves13, fin13, instante(claves13, F_IMPACTO), extra13))

    # 14. Manos atrás en el impacto: golpes cortos con el mango por delante de la bola.
    corto_atras = Pose(brazo=55, muneca=50, giro=0.4, tronco=6)
    impacto_adelante = Pose(brazo=-14, muneca=12, giro=0.3, tronco=-2, cadera=20)
    corto_salida = Pose(brazo=-55, muneca=-30, giro=0.4, tronco=-4, cadera=26)
    claves14 = [Clave(0, F_PREP), Clave(0.6, F_PREP), Clave(2.0, corto_atras), Clave(3.0, impacto_adelante), Clave(3.6, impacto_adelante),
                Clave(4.4, corto_salida), Clave(5.6, F_PREP)]

    def extra14(d, t, pose, fase, g=None):
        if fase == "antes":
            bola_frente(d)
            discontinua(d, [(F_BOLA[0], 420), (F_BOLA[0], SUELO)], OBJETO, ancho=4)
        else:
            punto(d, g["manos"], 16, ACENTO)
            if 2.8 <= t <= 3.8:
                m = g["manos"]
                flecha(d, [(m[0] - 120, m[1] - 70), (m[0] - 30, m[1] - 20)], ACENTO, ancho=8, punta=24)
    lista.append(ej_frente("manos_atras", claves14, 5.6, 3.3, extra14))

    return lista


# ---------------------------------------------------------------- render

def fotograma(e: Ejercicio, t: float) -> Image.Image:
    img, d = lienzo(e.vista)
    pose = pose_en(e.claves, t) if e.claves else None
    e.dibujar(d, t, pose)
    return img.resize((LADO, LADO), Image.LANCZOS)


def render(e: Ejercicio) -> None:
    SALIDA.mkdir(parents=True, exist_ok=True)
    n = int(round(e.duracion * FPS))
    mp4 = SALIDA / f"{e.id}.mp4"
    proceso = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{LADO}x{LADO}", "-r", str(FPS), "-i", "-",
         "-c:v", "libx264", "-preset", "slow", "-crf", "24", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(mp4)],
        stdin=subprocess.PIPE)
    assert proceso.stdin is not None
    for k in range(n):
        proceso.stdin.write(fotograma(e, k / FPS).tobytes())
    proceso.stdin.close()
    proceso.wait()
    fotograma(e, e.instante_imagen).save(SALIDA / f"{e.id}.png", optimize=True)
    print(f"{e.id}: {mp4.stat().st_size // 1024} KB, {e.duracion:.1f} s")


def main() -> None:
    pedidos = set(sys.argv[1:])
    for e in ejercicios():
        if not pedidos or e.id in pedidos:
            render(e)


if __name__ == "__main__":
    main()
