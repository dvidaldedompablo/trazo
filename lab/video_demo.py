"""Clip de swing de demostración para el vídeo de análisis que genera el CI en el simulador.

El simulador no tiene cámara ni vídeos: para comprobar el montaje completo (voz Kokoro, "A mejorar",
subtítulos y compresión) hace falta un clip. Este script lo dibuja con la figura propia siguiendo
exactamente la pose del swing de demostración de GolfCore (`GolfLab demo-poses`), así las líneas del
análisis caen sobre la figura. Nada se descarga.

Salida: App/Resources/demo_swing.mp4 (1080 x 1920, 30 fps, 3,3 s, H.264).
Uso: lab\\.venv\\Scripts\\python lab\\video_demo.py demo_poses.json
"""
from __future__ import annotations

import json
import math
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

RAIZ = Path(__file__).resolve().parent.parent
SALIDA = RAIZ / "App" / "Resources" / "demo_swing.mp4"
W, H, FPS = 1080, 1920, 30
CIELO_ARRIBA, CIELO_ABAJO = (143, 188, 214), (230, 238, 234)
HIERBA_ARRIBA, HIERBA_ABAJO = (127, 168, 102), (92, 142, 72)
FIGURA, PALO = (44, 61, 54), (21, 26, 24)
HORIZONTE = 1180


def fondo() -> Image.Image:
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        if y < HORIZONTE:
            f = y / HORIZONTE
            c = tuple(int(a + (b - a) * f) for a, b in zip(CIELO_ARRIBA, CIELO_ABAJO))
        else:
            f = (y - HORIZONTE) / (H - HORIZONTE)
            c = tuple(int(a + (b - a) * f) for a, b in zip(HIERBA_ARRIBA, HIERBA_ABAJO))
        d.line([(0, y), (W, y)], fill=c)
    for k in range(0, W + 60, 60):   # árboles al fondo
        d.ellipse([k - 50, HORIZONTE - 70, k + 50, HORIZONTE + 20], fill=(60, 90, 71))
    d.polygon([(300, H), (1080, H), (1080, 1600), (520, 1560)], fill=(59, 116, 70))   # el tee
    d.ellipse([885, 1735, 905, 1755], fill=(253, 253, 251))                            # la bola
    return img


def angulo_palo(t: float) -> float:
    """Ángulo del palo (radianes, desde abajo hacia la derecha) a lo largo del swing de demo:
    preparación hacia la bola, takeaway por dentro, top horizontal, impacto y final."""
    claves = [(0.0, 34), (0.893, 34), (1.10, 95), (1.35, 160), (1.73, 230), (1.88, 150), (1.99, 34), (2.30, -60), (3.3, -60)]
    for (t0, a0), (t1, a1) in zip(claves, claves[1:]):
        if t0 <= t <= t1:
            u = (t - t0) / max(t1 - t0, 1e-6)
            u = 0.5 - 0.5 * math.cos(u * math.pi)
            return math.radians(a0 + (a1 - a0) * u)
    return math.radians(claves[-1][1])


def main() -> None:
    poses = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    base = fondo()
    n = int(poses[-1]["time"] * FPS) + 1
    proceso = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
                                "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "slow", "-crf", "22",
                                "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(SALIDA)], stdin=subprocess.PIPE)
    assert proceso.stdin is not None
    for k in range(n):
        t = k / FPS
        pose = min(poses, key=lambda p: abs(p["time"] - t))["joints"]
        img = base.copy()
        d = ImageDraw.Draw(img)
        j = {name: tuple(v) for name, v in pose.items()}

        def seg(a, b, w):
            if a in j and b in j:
                d.line([j[a], j[b]], fill=FIGURA, width=w)
                for p in (j[a], j[b]):
                    d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=FIGURA)
        for a, b, w in [("rightHip", "rightKnee", 52), ("rightKnee", "rightAnkle", 44), ("leftHip", "leftKnee", 52),
                        ("leftKnee", "leftAnkle", 44), ("root", "neck", 76), ("leftShoulder", "rightShoulder", 50),
                        ("rightShoulder", "rightElbow", 32), ("rightElbow", "rightWrist", 28),
                        ("leftShoulder", "leftElbow", 32), ("leftElbow", "leftWrist", 28)]:
            seg(a, b, w)
        if "nose" in j:
            cx, cy = j["nose"][0] - 18, j["nose"][1] - 4
            d.ellipse([cx - 44, cy - 50, cx + 44, cy + 46], fill=FIGURA)
        if "leftWrist" in j and "rightWrist" in j:
            manos = ((j["leftWrist"][0] + j["rightWrist"][0]) / 2, (j["leftWrist"][1] + j["rightWrist"][1]) / 2)
            a = angulo_palo(t)
            cabeza = (manos[0] + 377 * math.sin(a), manos[1] + 377 * math.cos(a))
            d.line([manos, cabeza], fill=PALO, width=9)
            d.ellipse([cabeza[0] - 13, cabeza[1] - 9, cabeza[0] + 13, cabeza[1] + 9], fill=PALO)
        proceso.stdin.write(img.tobytes())
    proceso.stdin.close()
    proceso.wait()
    print(f"{SALIDA}: {SALIDA.stat().st_size // 1024} KB, {n} fotogramas")


if __name__ == "__main__":
    main()
