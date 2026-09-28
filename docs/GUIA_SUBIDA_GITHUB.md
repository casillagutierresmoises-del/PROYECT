# Guía rápida para publicar ALPACAY Mining 4.0

## 1. Ajustar el repositorio

Nombre recomendado: `alpacay-mining-4.0`

Descripción recomendada:

> Caso anonimizado de Minería 4.0 para QA/QC, PostgreSQL, Python/ML, AutoCAD, Leapfrog, Deswik y Power BI aplicado al control de leyes de Au.

Temas recomendados:

`mining` `mining-engineering` `geology` `qa-qc` `python` `machine-learning` `postgresql` `power-bi` `autocad` `spatial-analysis`

## 2. Sustituir el README actual

1. Abrir `README.md`.
2. Pulsar el icono del lápiz.
3. Borrar el contenido actual, incluida la línea `None`.
4. Copiar todo el contenido del nuevo `README.md`.
5. Escribir el mensaje: `docs: actualizar presentación profesional del proyecto`.
6. Pulsar `Commit changes`.

El enlace del video ya está incluido en el README y no es necesario volver a cargar el MP4.

## 3. Subir los archivos

Descomprimir este paquete. En GitHub, usar `Add file` > `Upload files` y arrastrar las carpetas o usar GitHub Desktop.

Orden recomendado de publicación:

1. `.gitignore` y `docs/`.
2. `01_data_publica/` y `02_qaqc/`.
3. `03_sql/` y `04_python_ml/`.
4. `05_autocad/`, `06_leapfrog/` y `07_deswik/`.
5. `08_powerbi/` y `09_reportes/`.

## 4. No publicar

- Excel original de muestreo o QA/QC.
- Archivos con coordenadas UTM reales.
- Archivos cuyo nombre contenga `INTERNO`.
- DWG originales de topografía o labores.
- PBIX conectado a PostgreSQL local o con datos internos incrustados.
- Contraseñas, archivos `.env`, credenciales o cadenas de conexión.
- Modelos `.joblib` o archivos temporales.

## 5. Mensajes de commit sugeridos

- `docs: actualizar README y metodología`
- `data: agregar conjunto público anonimizado`
- `feat: agregar notebooks de QAQC y ML`
- `feat: agregar arquitectura PostgreSQL`
- `feat: agregar entregables CAD y modelamiento 3D`
- `feat: agregar recursos de Power BI`
- `docs: agregar informe técnico del proyecto`

## 6. Revisión antes de publicar

- Abrir cada CSV y comprobar que no tenga coordenadas reales.
- Buscar las palabras `password`, `contraseña`, `INTERNO` y nombres de empresa.
- Confirmar que todas las imágenes del README carguen correctamente.
- Abrir el video y verificar que el reproductor funcione.
- Revisar el repositorio desde una ventana privada del navegador.

