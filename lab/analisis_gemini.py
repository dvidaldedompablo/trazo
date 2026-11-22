"""El análisis de swing con Gemini de la app, medido en el PC antes de llegar al iPhone (docs/10, Fase 4).

Para cada clip del banco hace lo mismo que la app (`SwingCheck` en GolfCore, `SwingGeminiAnalyzer` en la app):
  1. GolfLab da el plan de las hojas (de 2,5 s antes a 1,5 s después del impacto, un fotograma cada 0,04 s).
     El impacto de partida es el que confirmó el verificador de golpes (lab/verificador.py), como en la app.
  2. Petición de posiciones (las hojas dibujadas aquí, con la disposición de la app) y validación con GolfLab.
  3. Petición del cuerpo y el palo con los 7 fotogramas elegidos, y el resultado con GolfLab: posiciones,
     articulaciones, palo y las medidas de SwingMetrics.
Cada respuesta va a la caché (feedback/cache_modelo/). El resultado queda en
feedback/derivados/<clip>/analisis_gemini/ y evaluar.py lo pone en su columna.

Uso (desde la raíz del repo, con Docker Desktop abierto y la clave en lab\\.env):
    lab\\.venv\\Scripts\\python lab\\analisis_gemini.py
"""
from __future__ import annotations

import argparse
import json

import cv2

from comun import DERIVADOS, FEEDBACK, clips_del_banco, leer_fotogramas, leer_info, resolver_clip
from picos import compilar, docker
from preetiquetar import Cliente, Config, CuotaAgotada, Registro
from verificador import dibujar_hoja


def en_docker(ruta) -> str:
    return "/data/" + ruta.relative_to(FEEDBACK).as_posix()


def impacto_de_partida(clip) -> float | None:
    """El impacto que confirmó el verificador (el que la app guarda en el clip)."""
    ruta = DERIVADOS / clip.stem / "verificador" / "resultado.json"
    if not ruta.exists():
        return None
    v = json.loads(ruta.read_text(encoding="utf-8"))
    elegidos = [w["window"]["impactTime"] for w in v["windows"] if w["selected"]]
    return elegidos[0] if elegidos else None


def analizar(clip, cfg: Config) -> Registro:
    info = leer_info(clip)
    fotos = leer_fotogramas(info)
    carpeta = DERIVADOS / clip.stem / "analisis_gemini"
    carpeta.mkdir(parents=True, exist_ok=True)
    impacto = impacto_de_partida(clip)
    args = [f"{info.duracion:.6f}", "-" if impacto is None else f"{impacto:.6f}"]
    plan = json.loads(docker("/build/release/GolfLab", "analisis-plan", *args, str(info.ancho), str(info.alto)))
    registro = Registro()
    cliente = Cliente(cfg, registro, enviar=True)
    print(f"\n{clip.name}: impacto de partida {impacto}, {len(plan['frameTimes'])} fotogramas en {len(plan['sheets'])} hojas")

    # Petición 1: posiciones.
    rutas = []
    for k, hoja in enumerate(plan["sheets"]):
        datos = {"caption": plan["captions"][k], "frameTimes": [plan["frameTimes"][i] for i in hoja],
                 "numbers": [i + 1 for i in hoja]}
        ruta = carpeta / f"hoja-{k + 1:02d}.jpg"
        cv2.imwrite(str(ruta), dibujar_hoja(datos, plan, info, fotos), [cv2.IMWRITE_JPEG_QUALITY, 85])
        rutas.append(en_docker(ruta))
    cuerpo = json.loads(docker("/build/release/GolfLab", "analisis-cuerpo-posiciones", *args, *rutas))
    respuesta = cliente.pedir("posiciones", cuerpo)
    r1 = carpeta / "respuesta-posiciones.json"
    r1.write_text(json.dumps(respuesta or {}, ensure_ascii=False), encoding="utf-8")
    elegidas = json.loads(docker("/build/release/GolfLab", "analisis-elegidas", *args, en_docker(r1)))
    if not elegidas["ok"]:
        print(f"  Posiciones no válidas: {elegidas['failure']}")
        (carpeta / "resultado.json").write_text(json.dumps({"ok": False, "failure": elegidas["failure"]}, ensure_ascii=False),
                                                encoding="utf-8")
        return registro

    # Petición 2: cuerpo y palo en los 7 fotogramas elegidos (sueltos, a su resolución).
    rutas = []
    for k, t in enumerate(elegidas["bodyTimes"]):
        ruta = carpeta / f"posicion-{k + 1}.jpg"
        ruta.write_bytes(fotos[info.indice_mas_cercano(t)])
        rutas.append(en_docker(ruta))
    cuerpo = json.loads(docker("/build/release/GolfLab", "analisis-cuerpo-cuerpo", *rutas))
    respuesta = cliente.pedir("cuerpo", cuerpo)
    r2 = carpeta / "respuesta-cuerpo.json"
    r2.write_text(json.dumps(respuesta or {}, ensure_ascii=False), encoding="utf-8")

    decision = json.loads(docker("/build/release/GolfLab", "analisis-decidir", *args, str(info.ancho), str(info.alto),
                                 en_docker(r1), en_docker(r2)))
    decision["registro"] = registro.totales()
    (carpeta / "resultado.json").write_text(json.dumps(decision, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if decision["ok"]:
        tiempos = ", ".join(f"{m['position']} {m['time']:.3f}" for m in decision["marks"])
        print(f"  posiciones: {tiempos}")
        print(f"  medidas: {len(decision['measurements'])}")
    else:
        print(f"  No vale: {decision['failure']}")
    return registro


def main() -> None:
    argumentos = argparse.ArgumentParser(description="Mide el análisis de swing con Gemini de la app con los clips del banco.")
    argumentos.add_argument("clips", nargs="*")
    a = argumentos.parse_args()
    cfg = Config.leer(True, "A")
    compilar()
    resumen = []
    try:
        for clip in [resolver_clip(c) for c in a.clips] or clips_del_banco():
            resumen.append((clip.name, analizar(clip, cfg).totales()))
    except CuotaAgotada as error:
        print(f"\nCuota del plan gratuito agotada ({error}). Lo recibido está en la caché.")
    print("\nTokens y tiempo por clip (lo que sale de la caché no cuenta):")
    for nombre, t in resumen:
        print(f"  {nombre:<30} llamadas {t['llamadas_nuevas']}  entrada {t['tokens_entrada']}  salida {t['tokens_salida']}  "
              f"razon. {t['tokens_razonamiento']}  coste pago {t['coste_equivalente_usd']:.4f}$  {t['segundos']} s")


if __name__ == "__main__":
    main()
