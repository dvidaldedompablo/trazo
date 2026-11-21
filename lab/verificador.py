"""El verificador de golpes de la app, medido en el PC antes de llegar al iPhone (docs/10, Fase 2, paso 1).

Para cada clip del banco hace lo mismo que la app (`ShotCheck` en GolfCore, `ShotChecker` en la app):
  1. GolfLab saca los sonidos fuertes (los 12 más fuertes) y el plan de hojas: qué fotogramas van en cada una.
  2. Aquí se dibujan las hojas con OpenCV, con la misma disposición que en la app.
  3. GolfLab arma el cuerpo exacto de la petición (texto, esquema, semilla) y se manda a Gemini Flash.
     Cada respuesta se guarda en la caché (feedback/cache_modelo/): la misma petición no se repite.
  4. GolfLab valida la respuesta y decide qué clips propone, con la misma lógica que la app.
El resultado queda en feedback/derivados/<clip>/verificador/resultado.json y evaluar.py lo pone en su columna.

Uso (desde la raíz del repo, con Docker Desktop abierto y la clave en lab\\.env):
    lab\\.venv\\Scripts\\python lab\\verificador.py                 (los 3 clips del banco)
    lab\\.venv\\Scripts\\python lab\\verificador.py driver-campo
"""
from __future__ import annotations

import argparse
import json

import cv2
import numpy as np

from comun import DERIVADOS, FEEDBACK, RAIZ, clips_del_banco, decodificar, extraer_audio, leer_fotogramas, leer_info, resolver_clip
from picos import compilar, docker
from preetiquetar import Cliente, Config, CuotaAgotada, Registro


def en_docker(ruta) -> str:
    return "/data/" + ruta.relative_to(FEEDBACK).as_posix()


def dibujar_hoja(hoja: dict, plan: dict, info, fotogramas: list[bytes]) -> np.ndarray:
    """La hoja con la disposición de ShotCheck.layout: número arriba a la izquierda, instante abajo."""
    columnas, gap, cabecera = plan["columns"], plan["gap"], plan["header"]
    ancho, alto = plan["cellWidth"], plan["cellHeight"]
    lienzo = np.full((cabecera + plan["rows"] * (alto + gap) + gap, columnas * (ancho + gap) + gap, 3), 255, np.uint8)
    cv2.rectangle(lienzo, (0, 0), (lienzo.shape[1], cabecera), (40, 40, 40), -1)
    cv2.putText(lienzo, hoja["caption"], (10, 27), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2, cv2.LINE_AA)
    for k, (t, numero) in enumerate(zip(hoja["frameTimes"], hoja["numbers"])):
        indice = info.indice_mas_cercano(t)
        fila, columna = divmod(k, columnas)
        x, y = gap + columna * (ancho + gap), cabecera + gap + fila * (alto + gap)
        celda = cv2.resize(decodificar(fotogramas[indice]), (ancho, alto), interpolation=cv2.INTER_AREA)
        etiqueta = str(numero)
        (an, al), _ = cv2.getTextSize(etiqueta, cv2.FONT_HERSHEY_SIMPLEX, 0.8, 2)
        cv2.rectangle(celda, (0, 0), (an + 10, al + 12), (0, 0, 0), -1)
        cv2.putText(celda, etiqueta, (5, al + 6), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2, cv2.LINE_AA)
        instante = f"{info.tiempos[indice]:.3f} s"
        (an, al), _ = cv2.getTextSize(instante, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)
        cv2.rectangle(celda, (0, alto - al - 10), (an + 8, alto), (0, 0, 0), -1)
        cv2.putText(celda, instante, (4, alto - 5), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1, cv2.LINE_AA)
        lienzo[y:y + alto, x:x + ancho] = celda
    return lienzo


def verificar(clip, cfg: Config) -> Registro:
    info = leer_info(clip)
    fotogramas = leer_fotogramas(info)
    audio = extraer_audio(clip, DERIVADOS / clip.stem / "audio48k.f32")
    carpeta = DERIVADOS / clip.stem / "verificador"
    carpeta.mkdir(parents=True, exist_ok=True)
    duracion = f"{info.duracion:.6f}"
    plan = json.loads(docker("/build/release/GolfLab", "verificar-plan", en_docker(audio), duracion,
                             str(info.ancho), str(info.alto)))
    if plan["model"] != cfg.modelo:
        raise SystemExit(f"La app usa {plan['model']} y lab\\.env dice MODELO_A={cfg.modelo}: tienen que ser el mismo.")
    registro = Registro()
    cliente = Cliente(cfg, registro, enviar=True)
    hojas = sum(len(r["sheets"]) for r in plan["requests"])
    print(f"\n{clip.name}: {hojas} sonidos en {len(plan['requests'])} peticiones")

    respuestas = []
    for k, peticion in enumerate(plan["requests"]):
        rutas = []
        for hoja in peticion["sheets"]:
            ruta = carpeta / f"hoja-{hoja['name']}.jpg"
            cv2.imwrite(str(ruta), dibujar_hoja(hoja, plan, info, fotogramas), [cv2.IMWRITE_JPEG_QUALITY, 85])
            rutas.append(en_docker(ruta))
        cuerpo = json.loads(docker("/build/release/GolfLab", "verificar-cuerpo", en_docker(audio), duracion, str(k), *rutas))
        respuesta = cliente.pedir(f"verificador {k + 1}", cuerpo)
        ruta = carpeta / f"respuesta-{k + 1}.json"
        ruta.write_text(json.dumps(respuesta or {}, ensure_ascii=False), encoding="utf-8")
        respuestas.append(en_docker(ruta))

    decision = json.loads(docker("/build/release/GolfLab", "verificar-decidir", en_docker(audio), duracion, *respuestas))
    (carpeta / "resultado.json").write_text(json.dumps({"modelo": plan["model"], "isShotSeries": plan["isShotSeries"],
                                                        "original": plan["original"], **decision,
                                                        "registro": registro.totales()},
                                                       ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for v in decision["verdicts"]:
        print(f"  sonido {v['soundTime']:.3f} s: ¿impacto? {v['soundIsImpact']} ({v['confidence']:.2f})")
    elegidos = [w for w in decision["windows"] if w["selected"]]
    print(f"  propone {len(elegidos)} clip(s): " + ", ".join(f"{w['window']['impactTime']:.3f} s" for w in elegidos))
    for aviso in decision["warnings"]:
        print(f"  Aviso: {aviso}")
    return registro


def main() -> None:
    argumentos = argparse.ArgumentParser(description="Mide el verificador de golpes de la app con los clips del banco.")
    argumentos.add_argument("clips", nargs="*", help="nombres de clip; sin nada, los del banco")
    a = argumentos.parse_args()
    cfg = Config.leer(True, "A")
    clips = [resolver_clip(c) for c in a.clips] or clips_del_banco()
    compilar()
    print(f"Verificador con {cfg.modelo} (plan gratuito, semilla y razonamiento de la app)")
    resumen = []
    try:
        for clip in clips:
            resumen.append((clip.name, verificar(clip, cfg).totales()))
    except CuotaAgotada as error:
        print(f"\nCuota del plan gratuito agotada ({error}). Lo recibido está en la caché: vuelve a lanzarlo mañana.")
    if resumen:
        print("\nTokens y tiempo por clip (lo que sale de la caché no cuenta):")
        print(f"  {'clip':<30} {'llamadas':>8} {'entrada':>9} {'salida':>8} {'razon.':>8} {'coste pago':>11} {'segundos':>9}")
        for nombre, t in resumen:
            print(f"  {nombre:<30} {t['llamadas_nuevas']:>8} {t['tokens_entrada']:>9} {t['tokens_salida']:>8} "
                  f"{t['tokens_razonamiento']:>8} {t['coste_equivalente_usd']:>10.4f}$ {t['segundos']:>9}")
    print(f"\nResultado en {(DERIVADOS / '<clip>' / 'verificador').relative_to(RAIZ)}; la tabla, con scripts\\evaluar.py")


if __name__ == "__main__":
    main()
