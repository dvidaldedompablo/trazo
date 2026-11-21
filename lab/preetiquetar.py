"""Preetiquetado con el modelo A para ahorrar trabajo al usuario (docs/10, Fase 1, paso 3).

Dos pasadas por clip:
  1. Hoja gruesa: 12 fotogramas numerados que cubren todo el clip, para encontrar el swing.
  2. Hojas densas de 12 fotogramas, con el instante impreso en cada uno: una alrededor de cada pico
     de audio (de 0,6 s antes a 0,2 s después, para que entren el top y el impacto) y otra en el tramo
     del swing que vio la pasada 1. Van varias hojas por llamada para gastar menos cuota gratuita.

El modelo propone y el código decide: la respuesta se pide en JSON con campos fijos y se valida
antes de guardarla (números de fotograma enviados, fases conocidas, cajas dentro del fotograma,
confianza de 0 a 1). Lo que no valida se descarta y se apunta; nunca se rellena a ojo.
Solo se escriben los campos modelo_* de feedback/etiquetas/<clip>.json; las etiquetas del usuario no se tocan.

Uso (desde la raíz del repo; necesita lab\\.env con la clave, ver lab\\.env.example):
    lab\\.venv\\Scripts\\python lab\\preetiquetar.py                 (todos los clips de feedback/)
    lab\\.venv\\Scripts\\python lab\\preetiquetar.py driver-campo
    lab\\.venv\\Scripts\\python lab\\preetiquetar.py --sin-enviar    (prepara las hojas y no llama al modelo)
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import math
import time
from dataclasses import dataclass, field
from datetime import datetime

import cv2
import numpy as np
import requests

from comun import (CACHE_MODELO, DERIVADOS, FASES_PALO, RAIZ, InfoVideo, cargar_etiquetas, clips_del_banco,
                   comprobar_gratuito, decodificar, guardar_etiquetas, leer_env, leer_fotogramas, leer_info,
                   resolver_clip)

# API Interactions de Gemini (la recomendada por Google desde 2026; generateContent queda como antigua).
URL = "https://generativelanguage.googleapis.com/v1beta/interactions"
REVISION_API = "2026-05-20"

FASES_MODELO = ["preparacion", "takeaway", "mitad_subida", "top", "transicion", "impacto", "final", "ninguna"]
# Fase de la etiqueta del palo -> fase del modelo. "bajada" es la posición 5 de la app (transición).
FASE_MODELO_DE = {"preparacion": "preparacion", "takeaway": "takeaway", "mitad_subida": "mitad_subida",
                  "top": "top", "bajada": "transicion"}
FASES_DE_SWING = {"takeaway", "mitad_subida", "top", "transicion", "impacto", "final"}

FOTOGRAMAS_GRUESA = 12
FOTOGRAMAS_DENSA = 12
ANTES_DEL_PICO_S = 0.6    # la bajada dura de 0,1 a 0,6 s: así el top entra en la hoja del pico
DESPUES_DEL_PICO_S = 0.2
HOJAS_POR_LLAMADA = 6
LADO_MAXIMO_HOJA = 1536   # píxeles del lado largo de cada hoja

INSTRUCCIONES = """Eres un analista de swing de golf. Te paso hojas con fotogramas de un vídeo de un golfista, en orden de tiempo. Cada fotograma lleva su número arriba a la izquierda (en un recuadro negro) y su instante en segundos abajo a la izquierda.

Fases posibles de cada fotograma:
- preparacion: el golfista está quieto ante la bola, con el palo detrás de ella.
- takeaway: empieza la subida; desde que el palo se mueve hasta que queda paralelo al suelo.
- mitad_subida: en la subida, con el brazo de delante más o menos paralelo al suelo.
- top: el final de la subida, cuando el palo cambia de sentido.
- transicion: la bajada, desde el top hasta justo antes del impacto.
- impacto: el palo toca la bola (el fotograma más cercano al golpe).
- final: después del impacto, hasta que termina el swing.
- ninguna: no hay un golfista preparándose o haciendo un swing (camina, coloca la bola, mira, no hay jugador...).

zona_palo: si ves la cabeza del palo, su caja aproximada como [ymin, xmin, ymax, xmax] con valores de 0 a 1000, relativos a ESE fotograma (0,0 es su esquina de arriba a la izquierda y 1000,1000 la de abajo a la derecha). Si no la ves, una lista vacía [].

confianza: de 0 a 1. Si dudas, pon una confianza baja; no inventes. Es mejor decir no_se o ninguna con confianza baja que adivinar."""

ESQUEMA_FOTOGRAMA = {
    "type": "object",
    "properties": {
        "n": {"type": "integer", "description": "número del fotograma"},
        "fase": {"type": "string", "enum": FASES_MODELO},
        "zona_palo": {"type": "array", "items": {"type": "integer"},
                      "description": "[ymin, xmin, ymax, xmax] de 0 a 1000, o [] si no se ve"},
        "confianza": {"type": "number"},
    },
    "required": ["n", "fase", "zona_palo", "confianza"],
}
ESQUEMA_GRUESA = {
    "type": "object",
    "properties": {
        "hay_swing": {"type": "string", "enum": ["si", "no", "no_se"]},
        "confianza": {"type": "number"},
        "fotogramas": {"type": "array", "items": ESQUEMA_FOTOGRAMA},
    },
    "required": ["hay_swing", "confianza", "fotogramas"],
}
ESQUEMA_DENSA = {
    "type": "object",
    "properties": {
        "hojas": {"type": "array", "items": {
            "type": "object",
            "properties": {
                "hoja": {"type": "string"},
                "hay_swing": {"type": "string", "enum": ["si", "no", "no_se"]},
                "sonido_es_impacto": {"type": "string", "enum": ["si", "no", "no_se", "no_aplica"]},
                "confianza": {"type": "number"},
            },
            "required": ["hoja", "hay_swing", "sonido_es_impacto", "confianza"],
        }},
        "fotogramas": {"type": "array", "items": ESQUEMA_FOTOGRAMA},
    },
    "required": ["hojas", "fotogramas"],
}


class CuotaAgotada(Exception):
    pass


@dataclass
class Config:
    clave: str
    modelo: str
    precio_entrada: float   # dólares por millón de tokens, plan de pago
    precio_salida: float
    gratuito: bool
    razonamiento: str
    semilla: int
    pausa: float
    resolucion: str

    @staticmethod
    def leer(enviar: bool) -> "Config":
        env = leer_env()
        clave = env.get("GEMINI_API_KEY", "")
        if enviar and not clave:
            raise SystemExit("Falta GEMINI_API_KEY en lab\\.env (copia lab\\.env.example y pon tu clave).")
        # Sin .env valen los de lab/.env.example (así --sin-enviar funciona sin clave).
        modelo_a, modelo_b = env.get("MODELO_A", "gemini-3.6-flash"), env.get("MODELO_B", "gemini-4-hydrogen")
        if modelo_a == modelo_b:
            # Regla 3 de docs/10: si preetiqueta el mismo que se evalúa, la medida sale inflada.
            raise SystemExit("MODELO_A y MODELO_B tienen que ser distintos (docs/10, regla 3).")
        for modelo in (modelo_a, modelo_b):
            comprobar_gratuito(modelo, env.get("PLAN_GRATUITO", "1"))
        return Config(clave=clave, modelo=modelo_a,
                      precio_entrada=float(env.get("PRECIO_A_ENTRADA", "0") or 0),
                      precio_salida=float(env.get("PRECIO_A_SALIDA", "0") or 0),
                      gratuito=True,
                      razonamiento=env.get("NIVEL_RAZONAMIENTO", ""),
                      semilla=int(env.get("SEMILLA", "7") or 7),
                      pausa=float(env.get("SEGUNDOS_ENTRE_LLAMADAS", "13") or 13),
                      resolucion=env.get("RESOLUCION_IMAGEN", "high"))


@dataclass
class Hoja:
    nombre: str                 # "gruesa", "S" (swing) o "P1", "P2"... (picos)
    descripcion: str
    indices: list[int]          # fotogramas del vídeo
    numeros: list[int]          # número impreso en cada uno
    pico_t: float | None = None
    imagen: np.ndarray | None = None


@dataclass
class Registro:
    llamadas: list[dict] = field(default_factory=list)
    avisos: list[str] = field(default_factory=list)

    def totales(self) -> dict:
        nuevas = [c for c in self.llamadas if not c["de_cache"]]
        return {
            "llamadas": len(self.llamadas),
            "llamadas_nuevas": len(nuevas),
            "tokens_entrada": sum(c["tokens_entrada"] for c in nuevas),
            "tokens_salida": sum(c["tokens_salida"] for c in nuevas),
            "tokens_razonamiento": sum(c["tokens_razonamiento"] for c in nuevas),
            "coste_equivalente_usd": round(sum(c["coste_equivalente_usd"] for c in nuevas), 5),
            "coste_real_usd": round(sum(c["coste_real_usd"] for c in nuevas), 5),
            "segundos": round(sum(c["segundos"] for c in nuevas), 1),
        }


# ---------------------------------------------------------------- hojas de fotogramas

def repartir(info: InfoVideo, t0: float, t1: float, cuantos: int) -> list[int]:
    """Índices de fotograma repartidos por igual en el tiempo entre t0 y t1 (sin repetir)."""
    t0, t1 = max(0.0, t0), min(info.tiempos[-1], t1)
    if cuantos <= 1 or t1 <= t0:
        return [info.indice_mas_cercano(t0)]
    return sorted({info.indice_mas_cercano(t0 + k * (t1 - t0) / (cuantos - 1)) for k in range(cuantos)})


def dibujar_hoja(hoja: Hoja, info: InfoVideo, fotogramas: list[bytes]) -> np.ndarray:
    n = len(hoja.indices)
    # Más columnas si el vídeo es vertical; menos si es apaisado.
    columnas = max(2, min(n, round(math.sqrt(n * info.alto / info.ancho))))
    filas = math.ceil(n / columnas)
    hueco, cabecera = 6, 40
    escala = min((LADO_MAXIMO_HOJA - hueco * (columnas + 1)) / (columnas * info.ancho),
                 (LADO_MAXIMO_HOJA - cabecera - hueco * (filas + 1)) / (filas * info.alto))
    ancho_celda, alto_celda = int(info.ancho * escala), int(info.alto * escala)
    lienzo = np.full((cabecera + filas * (alto_celda + hueco) + hueco, columnas * (ancho_celda + hueco) + hueco, 3),
                     255, np.uint8)
    cv2.rectangle(lienzo, (0, 0), (lienzo.shape[1], cabecera), (40, 40, 40), -1)
    cv2.putText(lienzo, hoja.descripcion, (10, 27), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2, cv2.LINE_AA)
    for k, (indice, numero) in enumerate(zip(hoja.indices, hoja.numeros)):
        fila, columna = divmod(k, columnas)
        x = hueco + columna * (ancho_celda + hueco)
        y = cabecera + hueco + fila * (alto_celda + hueco)
        celda = cv2.resize(decodificar(fotogramas[indice]), (ancho_celda, alto_celda), interpolation=cv2.INTER_AREA)
        # Número arriba a la izquierda y el instante abajo a la izquierda, en recuadros negros pequeños.
        etiqueta = str(numero)
        (an, al), _ = cv2.getTextSize(etiqueta, cv2.FONT_HERSHEY_SIMPLEX, 0.8, 2)
        cv2.rectangle(celda, (0, 0), (an + 10, al + 12), (0, 0, 0), -1)
        cv2.putText(celda, etiqueta, (5, al + 6), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2, cv2.LINE_AA)
        instante = f"{info.tiempos[indice]:.3f} s"
        (an, al), _ = cv2.getTextSize(instante, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)
        cv2.rectangle(celda, (0, alto_celda - al - 10), (an + 8, alto_celda), (0, 0, 0), -1)
        cv2.putText(celda, instante, (4, alto_celda - 5), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1, cv2.LINE_AA)
        lienzo[y:y + alto_celda, x:x + ancho_celda] = celda
    return lienzo


def jpeg_base64(imagen: np.ndarray) -> str:
    ok, datos = cv2.imencode(".jpg", imagen, [cv2.IMWRITE_JPEG_QUALITY, 90])
    assert ok
    return base64.b64encode(datos.tobytes()).decode("ascii")


# ---------------------------------------------------------------- llamada al modelo

def cuerpo_peticion(cfg: Config, texto: str, hojas: list[Hoja], esquema: dict) -> dict:
    entrada: list[dict] = [{"type": "text", "text": texto}]
    for hoja in hojas:
        entrada.append({"type": "text", "text": f"Hoja {hoja.nombre}: {hoja.descripcion}"})
        entrada.append({"type": "image", "mime_type": "image/jpeg", "data": jpeg_base64(hoja.imagen),
                        "resolution": cfg.resolucion})
    configuracion: dict = {"seed": cfg.semilla}
    if cfg.razonamiento:
        configuracion["thinking_level"] = cfg.razonamiento
    # Temperatura: docs/10 pide 0, pero en Gemini 3.6 Flash y posteriores ya no existe (la API la ignora
    # y la API Interactions ni la tiene). Para repetir el resultado se fija la semilla y el nivel de
    # razonamiento, y cada respuesta queda en la caché: la misma petición nunca se manda dos veces.
    return {
        "model": cfg.modelo,
        "system_instruction": INSTRUCCIONES,
        "input": entrada,
        "generation_config": configuracion,
        "response_format": {"type": "text", "mime_type": "application/json", "schema": esquema},
        "store": False,  # que Google no guarde la conversación para continuarla después
    }


def texto_de(respuesta: dict) -> str:
    if isinstance(respuesta.get("output_text"), str):
        return respuesta["output_text"]
    partes = []
    for paso in respuesta.get("steps", []):
        if paso.get("type") == "model_output":
            partes += [c.get("text", "") for c in paso.get("content", []) if c.get("type") == "text"]
    return "".join(partes)


class Cliente:
    def __init__(self, cfg: Config, registro: Registro, enviar: bool):
        self.cfg = cfg
        self.registro = registro
        self.enviar = enviar
        self.ultima = 0.0

    def pedir(self, tipo: str, cuerpo: dict) -> dict | None:
        """Devuelve el JSON de la respuesta del modelo, de la caché si la petición ya se hizo."""
        huella = hashlib.sha256(json.dumps(cuerpo, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()
        ruta = CACHE_MODELO / f"{huella}.json"
        if ruta.exists():
            guardado = json.loads(ruta.read_text(encoding="utf-8"))
            self.apuntar(tipo, guardado["respuesta"], guardado.get("segundos", 0), de_cache=True)
            return guardado["respuesta"]
        if not self.enviar:
            return None
        espera = self.cfg.pausa - (time.monotonic() - self.ultima)
        if espera > 0:
            time.sleep(espera)  # el plan gratuito limita las peticiones por minuto
        inicio = time.monotonic()
        respuesta = self.post(cuerpo)
        segundos = time.monotonic() - inicio
        self.ultima = time.monotonic()
        CACHE_MODELO.mkdir(parents=True, exist_ok=True)
        ruta.write_text(json.dumps({"fecha": datetime.now().isoformat(timespec="seconds"), "modelo": self.cfg.modelo,
                                    "segundos": round(segundos, 2), "respuesta": respuesta},
                                   ensure_ascii=False, indent=1), encoding="utf-8")
        self.apuntar(tipo, respuesta, segundos, de_cache=False)
        return respuesta

    def post(self, cuerpo: dict) -> dict:
        cabeceras = {"x-goog-api-key": self.cfg.clave, "Content-Type": "application/json", "Api-Revision": REVISION_API}
        for intento in range(5):
            r = requests.post(URL, headers=cabeceras, json=cuerpo, timeout=600)
            if r.status_code == 200:
                return r.json()
            try:
                error = r.json().get("error", {})
            except ValueError:
                error = {}
            codigo, mensaje = error.get("code", ""), error.get("message", r.text[:400])
            if r.status_code == 429 and codigo == "quota_exceeded":
                raise CuotaAgotada(mensaje)
            if r.status_code == 503:
                # Modelo saturado en Google (pasa con los recién salidos). Dos esperas cortas y se para:
                # mejor probar más tarde u otro modelo gratuito que esperar un cuarto de hora.
                if intento >= 2:
                    raise SystemExit(f"{self.cfg.modelo} está saturado en Google ({mensaje}). "
                                     "Prueba más tarde u otro modelo gratuito en MODELO_A.")
                espera = int(r.headers.get("Retry-After", "30") or 30)
                print(f"    {self.cfg.modelo} saturado; espero {espera} s y lo intento otra vez.")
                time.sleep(espera)
                continue
            if r.status_code in (429, 500, 504):
                espera = 30 * 2 ** intento
                print(f"    La API responde {r.status_code} {codigo}; espero {espera} s y lo intento otra vez.")
                time.sleep(espera)
                continue
            raise SystemExit(f"La API respondió {r.status_code} {codigo}: {mensaje}")
        raise CuotaAgotada("la API sigue rechazando las peticiones tras 5 intentos")

    def apuntar(self, tipo: str, respuesta: dict, segundos: float, de_cache: bool) -> None:
        uso = respuesta.get("usage", {})
        entrada = int(uso.get("total_input_tokens", 0))
        salida = int(uso.get("total_output_tokens", 0))
        razonamiento = int(uso.get("total_thought_tokens", 0))
        # El razonamiento se cobra como salida.
        coste = (entrada * self.cfg.precio_entrada + (salida + razonamiento) * self.cfg.precio_salida) / 1e6
        self.registro.llamadas.append({
            "tipo": tipo, "modelo": respuesta.get("model", self.cfg.modelo), "de_cache": de_cache,
            "estado": respuesta.get("status"), "tokens_entrada": entrada, "tokens_salida": salida,
            "tokens_razonamiento": razonamiento, "coste_equivalente_usd": round(coste, 6),
            "coste_real_usd": 0.0 if self.cfg.gratuito else round(coste, 6), "segundos": round(segundos, 2),
        })


# ---------------------------------------------------------------- validación

def leer_json_modelo(respuesta: dict | None, registro: Registro, tipo: str) -> dict | None:
    if respuesta is None:
        return None
    if respuesta.get("status") != "completed":
        registro.avisos.append(f"{tipo}: la respuesta no está completa (estado {respuesta.get('status')})")
        return None
    try:
        return json.loads(texto_de(respuesta))
    except json.JSONDecodeError:
        registro.avisos.append(f"{tipo}: la respuesta no es un JSON válido; se descarta")
        return None


def confianza_valida(valor) -> float | None:
    return float(valor) if isinstance(valor, (int, float)) and 0 <= valor <= 1 else None


def validar_fotogramas(lista, numero_a_indice: dict[int, int], info: InfoVideo, registro: Registro,
                       tipo: str) -> list[dict]:
    """Se queda con lo que tiene sentido y apunta lo que no. El código decide, no el modelo."""
    validos = []
    vistos = set()
    for f in lista or []:
        n = f.get("n")
        if n not in numero_a_indice or n in vistos:
            registro.avisos.append(f"{tipo}: fotograma {n} no enviado o repetido; se descarta")
            continue
        vistos.add(n)
        if f.get("fase") not in FASES_MODELO:
            registro.avisos.append(f"{tipo}: fase desconocida '{f.get('fase')}' en el {n}; se descarta")
            continue
        confianza = confianza_valida(f.get("confianza"))
        if confianza is None:
            registro.avisos.append(f"{tipo}: confianza fuera de 0 a 1 en el {n}; se descarta")
            continue
        caja = None
        z = f.get("zona_palo") or []
        if len(z) == 4 and all(isinstance(v, (int, float)) and 0 <= v <= 1000 for v in z) and z[0] < z[2] and z[1] < z[3]:
            ymin, xmin, ymax, xmax = z
            caja = [round(xmin / 1000 * info.ancho), round(ymin / 1000 * info.alto),
                    round(xmax / 1000 * info.ancho), round(ymax / 1000 * info.alto)]
        elif z:
            registro.avisos.append(f"{tipo}: caja del palo imposible {z} en el {n}; se queda sin caja")
        indice = numero_a_indice[n]
        validos.append({"indice": indice, "t": round(info.tiempos[indice], 4), "fase": f["fase"],
                        "confianza": confianza, "caja": caja})
    return validos


# ---------------------------------------------------------------- de las respuestas a modelo_*

def mejor(candidatos: list[dict], preferir_tarde: bool) -> dict | None:
    """El de más confianza; si empatan, el más tarde (top) o el más temprano (impacto)."""
    if not candidatos:
        return None
    return max(candidatos, key=lambda f: (f["confianza"], f["t"] if preferir_tarde else -f["t"]))


def resumir(por_fotograma: dict[int, dict], hay_swing: bool, picos: list[dict]) -> dict:
    fases = sorted(por_fotograma.values(), key=lambda f: f["t"])
    swings = []
    if hay_swing:
        top = mejor([f for f in fases if f["fase"] == "top"], preferir_tarde=True)
        impacto = mejor([f for f in fases if f["fase"] == "impacto"], preferir_tarde=False)
        if top or impacto:
            swings.append({"top": top["t"] if top else None, "impacto": impacto["t"] if impacto else None,
                           "confianza": min(f["confianza"] for f in (top, impacto) if f)})
    palo = []
    for fase in FASES_PALO:
        candidatos = [f for f in fases if f["fase"] == FASE_MODELO_DE[fase]]
        elegido = mejor([f for f in candidatos if f["caja"]], preferir_tarde=False) or mejor(candidatos, False)
        if elegido is None:
            palo.append({"fase": fase, "t": None, "x": None, "y": None, "caja": None, "confianza": None})
            continue
        caja = elegido["caja"]
        palo.append({"fase": fase, "t": elegido["t"],
                     "x": round((caja[0] + caja[2]) / 2) if caja else None,
                     "y": round((caja[1] + caja[3]) / 2) if caja else None,
                     "caja": caja, "confianza": elegido["confianza"]})
    return {
        "modelo_swings": swings,
        "modelo_fases": [{"t": f["t"], "fase": f["fase"], "confianza": f["confianza"], "caja": f["caja"],
                          "hoja": f["hoja"]} for f in fases],
        "modelo_palo": palo,
        "modelo_picos": picos,
    }


# ---------------------------------------------------------------- un clip

def preetiquetar(clip, cfg: Config, enviar: bool) -> Registro | None:
    info = leer_info(clip)
    fotogramas = leer_fotogramas(info)
    datos = cargar_etiquetas(clip)
    carpeta = DERIVADOS / clip.stem / "preetiquetado"
    carpeta.mkdir(parents=True, exist_ok=True)
    registro = Registro()
    cliente = Cliente(cfg, registro, enviar)
    print(f"\n{clip.name}: {info.n} fotogramas, {info.duracion:.2f} s, {len(datos['picos'])} picos de audio")

    # Pasada 1: hoja gruesa.
    indices = repartir(info, 0, info.tiempos[-1], FOTOGRAMAS_GRUESA)
    gruesa = Hoja("gruesa", f"{clip.stem}: {len(indices)} fotogramas de todo el clip", indices,
                  list(range(1, len(indices) + 1)))
    gruesa.imagen = dibujar_hoja(gruesa, info, fotogramas)
    cv2.imwrite(str(carpeta / "hoja-gruesa.jpg"), gruesa.imagen)
    texto = (f"Hoja gruesa: {len(indices)} fotogramas repartidos por todo el clip ({info.duracion:.2f} s). "
             "Di si en el clip hay un swing completo que golpea la bola (hay_swing: si, no o no_se) y tu confianza "
             "general. Para cada fotograma, su fase, zona_palo y confianza.")
    respuesta = leer_json_modelo(cliente.pedir("gruesa", cuerpo_peticion(cfg, texto, [gruesa], ESQUEMA_GRUESA)),
                                 registro, "gruesa")
    if respuesta is None and enviar:
        print("  Sin respuesta válida de la hoja gruesa: este clip se queda sin preetiquetar.")
        return registro
    # Con --sin-enviar no hay respuesta: se preparan igual las hojas de los picos (la del swing no,
    # porque sale de la respuesta de la gruesa).
    respuesta = respuesta or {}
    numeros = dict(zip(gruesa.numeros, gruesa.indices))
    vistos_gruesa = validar_fotogramas(respuesta.get("fotogramas"), numeros, info, registro, "gruesa")
    hay_swing_gruesa = respuesta.get("hay_swing") if respuesta.get("hay_swing") in ("si", "no", "no_se") else "no_se"

    # Pasada 2: hojas densas, una por pico y otra en el tramo del swing que vio la gruesa.
    hojas: list[Hoja] = []
    for k, pico in enumerate(datos["picos"], start=1):
        indices = repartir(info, pico["t"] - ANTES_DEL_PICO_S, pico["t"] + DESPUES_DEL_PICO_S, FOTOGRAMAS_DENSA)
        hojas.append(Hoja(f"P{k}", f"P{k}: sonido fuerte en {pico['t']:.3f} s", indices, [], pico_t=pico["t"]))
    de_swing = [f for f in vistos_gruesa if f["fase"] in FASES_DE_SWING]
    if de_swing:
        paso = info.tiempos[-1] / (FOTOGRAMAS_GRUESA - 1)
        t0, t1 = min(f["t"] for f in de_swing) - paso, max(f["t"] for f in de_swing) + paso
        indices = repartir(info, t0, t1, FOTOGRAMAS_DENSA)
        hojas.append(Hoja("S", f"S: tramo del swing, de {info.tiempos[indices[0]]:.2f} a "
                               f"{info.tiempos[indices[-1]]:.2f} s", indices, []))

    por_fotograma: dict[int, dict] = {}
    for f in vistos_gruesa:
        por_fotograma[f["indice"]] = {**f, "hoja": "gruesa"}
    modelo_picos = []
    for inicio in range(0, len(hojas), HOJAS_POR_LLAMADA):
        tanda = hojas[inicio:inicio + HOJAS_POR_LLAMADA]
        numero = 1
        numeros = {}
        for hoja in tanda:
            hoja.numeros = list(range(numero, numero + len(hoja.indices)))
            numero += len(hoja.indices)
            numeros.update(dict(zip(hoja.numeros, hoja.indices)))
            hoja.imagen = dibujar_hoja(hoja, info, fotogramas)
            cv2.imwrite(str(carpeta / f"hoja-{hoja.nombre}.jpg"), hoja.imagen)
        lista = []
        for hoja in tanda:
            if hoja.pico_t is not None:
                cerca = hoja.numeros[hoja.indices.index(info.indice_mas_cercano(hoja.pico_t))] \
                    if info.indice_mas_cercano(hoja.pico_t) in hoja.indices else None
                lista.append(f"- {hoja.nombre}: alrededor de un sonido fuerte en {hoja.pico_t:.3f} s"
                             + (f" (el fotograma más cercano al sonido es el {cerca})." if cerca else "."))
            else:
                lista.append(f"- {hoja.nombre}: el tramo donde parece estar el swing.")
        texto = ("Hojas densas: fotogramas seguidos de tramos concretos del mismo clip. Los números de fotograma "
                 "son únicos en todo el mensaje.\n" + "\n".join(lista) +
                 "\nPara cada hoja: hay_swing (¿se ve en esa hoja un swing que golpea la bola?), sonido_es_impacto "
                 "(en las hojas P: ¿el sonido coincide con el impacto del palo con la bola? si, no o no_se; en la "
                 "hoja S: no_aplica) y confianza. Para cada fotograma: fase, zona_palo y confianza.")
        tipo = "densa " + ",".join(h.nombre for h in tanda)
        respuesta = leer_json_modelo(cliente.pedir(tipo, cuerpo_peticion(cfg, texto, tanda, ESQUEMA_DENSA)),
                                     registro, tipo)
        if respuesta is None:
            continue
        for f in validar_fotogramas(respuesta.get("fotogramas"), numeros, info, registro, tipo):
            hoja = next(h.nombre for h in tanda if f["indice"] in h.indices)
            anterior = por_fotograma.get(f["indice"])
            # Lo denso manda sobre lo grueso; entre dos densas, la de más confianza.
            if anterior is None or anterior["hoja"] == "gruesa" or f["confianza"] > anterior["confianza"]:
                por_fotograma[f["indice"]] = {**f, "hoja": hoja}
        por_nombre = {h.nombre: h for h in tanda}
        for r in respuesta.get("hojas") or []:
            hoja = por_nombre.get(r.get("hoja"))
            if hoja is None or hoja.pico_t is None:
                continue
            if r.get("hay_swing") not in ("si", "no", "no_se") or r.get("sonido_es_impacto") not in ("si", "no", "no_se") \
                    or confianza_valida(r.get("confianza")) is None:
                registro.avisos.append(f"{tipo}: respuesta imposible para la hoja {hoja.nombre}; se descarta")
                continue
            modelo_picos.append({"t": hoja.pico_t, "hay_swing": r["hay_swing"],
                                 "sonido_es_impacto": r["sonido_es_impacto"], "confianza": r["confianza"]})

    if not enviar:
        print(f"  --sin-enviar: {1 + len(hojas)} hojas en {carpeta.relative_to(RAIZ)}; "
              f"serían {1 + math.ceil(len(hojas) / HOJAS_POR_LLAMADA)} llamadas o más (falta la hoja del swing).")
        return None
    hay_swing = hay_swing_gruesa != "no" or any(p["hay_swing"] == "si" for p in modelo_picos)
    resumen = resumir(por_fotograma, hay_swing, sorted(modelo_picos, key=lambda p: p["t"]))
    datos = cargar_etiquetas(clip)  # otra vez, por si el usuario lo ha guardado mientras tanto
    datos.update(resumen)
    datos["modelo_info"] = {
        "modelo": cfg.modelo, "fecha": datetime.now().isoformat(timespec="seconds"), "semilla": cfg.semilla,
        "razonamiento": cfg.razonamiento or "por defecto", "resolucion_imagen": cfg.resolucion,
        "hay_swing_gruesa": hay_swing_gruesa, **registro.totales(),
    }
    guardar_etiquetas(clip, datos)
    (carpeta / "registro.json").write_text(json.dumps({"llamadas": registro.llamadas, "avisos": registro.avisos,
                                                       "totales": registro.totales()}, ensure_ascii=False, indent=2),
                                           encoding="utf-8")
    sw = resumen["modelo_swings"][0] if resumen["modelo_swings"] else None
    print(f"  hay swing (gruesa): {hay_swing_gruesa}; top {sw and sw['top']}, impacto {sw and sw['impacto']}")
    for p in resumen["modelo_picos"]:
        print(f"  pico {p['t']:.3f} s: ¿es el impacto? {p['sonido_es_impacto']} ({p['confianza']:.2f})")
    for aviso in registro.avisos:
        print(f"  Aviso: {aviso}")
    return registro


def main() -> None:
    argumentos = argparse.ArgumentParser(description="Preetiqueta los clips del banco con el modelo A.")
    argumentos.add_argument("clips", nargs="*", help="nombres de clip; sin nada, todos los de feedback/")
    argumentos.add_argument("--sin-enviar", action="store_true", help="prepara las hojas y no llama al modelo")
    a = argumentos.parse_args()
    enviar = not a.sin_enviar
    cfg = Config.leer(enviar)
    clips = [resolver_clip(c) for c in a.clips] or clips_del_banco()
    print(f"Modelo A: {cfg.modelo}  (plan {'gratuito' if cfg.gratuito else 'de pago'}, semilla {cfg.semilla}, "
          f"razonamiento {cfg.razonamiento or 'por defecto'})")
    resumen = []
    try:
        for clip in clips:
            registro = preetiquetar(clip, cfg, enviar)
            if registro:
                resumen.append((clip.name, registro.totales()))
    except CuotaAgotada as error:
        print(f"\nCuota del plan gratuito agotada ({error}). Lo ya recibido está guardado en la caché: "
              "vuelve a lanzarlo mañana y seguirá donde lo dejó.")
    if resumen:
        print("\nTokens y coste por clip (las respuestas sacadas de la caché no cuentan):")
        print(f"  {'clip':<30} {'llamadas':>8} {'entrada':>9} {'salida':>8} {'razon.':>8} {'coste pago':>11} "
              f"{'coste real':>11} {'segundos':>9}")
        for nombre, t in resumen:
            print(f"  {nombre:<30} {t['llamadas_nuevas']:>8} {t['tokens_entrada']:>9} {t['tokens_salida']:>8} "
                  f"{t['tokens_razonamiento']:>8} {t['coste_equivalente_usd']:>10.4f}$ {t['coste_real_usd']:>10.4f}$ "
                  f"{t['segundos']:>9}")


if __name__ == "__main__":
    main()
