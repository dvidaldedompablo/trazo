# Ejercicios: imágenes y clips

Un fallo del swing por ejercicio, con su imagen (`<id>.png`) y su clip en bucle (`<id>.mp4`).
El catálogo completo, con los textos, está en `catalogo.json`. Lo genera `GolfLab catalogo` a partir de `Packages/GolfCore/Sources/GolfCore/Swing/ExerciseCatalog.swift`, que es el que manda.

- **Para cambiar un clip por uno tuyo:** sustituye `<id>.mp4` por tu vídeo, con el mismo nombre. Mejor cuadrado (1080 x 1080), H.264, de 4 a 8 s y que empiece y acabe en la misma postura, para que el bucle no salte. Haz lo mismo con `<id>.png` si quieres otra imagen fija. No hay que tocar código: la app y el vídeo del análisis los leen por su nombre.
- **Para volver a generar los dibujos:** `lab\.venv\Scripts\python lab\ejercicios_animacion.py` (o con los ids que quieras rehacer). Ojo: pisa los archivos de esta carpeta.
- Ninguno lo ha revisado un profesor (`revisado_por_profesional: false`). Son consejos generales.
