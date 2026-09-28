-- Proyecto ALPACAY - Fase 11.3
-- Crea vistas analiticas para Power BI y exportacion 3D.
-- No modifica RAW ni CORE y puede ejecutarse nuevamente sin duplicar datos.

BEGIN;

CREATE SCHEMA IF NOT EXISTS analytics;

-- Evita duplicar muestras cuando en el futuro se carguen nuevas versiones del Excel.
CREATE OR REPLACE VIEW analytics.vw_ultima_carga AS
SELECT MAX(carga_id) AS carga_id
FROM audit.transformaciones_core
WHERE estado = 'COMPLETADA';

CREATE OR REPLACE VIEW analytics.vw_powerbi_muestras AS
SELECT
    m.muestra_id,
    m.carga_id,
    m.fila_excel,
    m.fecha,
    EXTRACT(YEAR FROM m.fecha)::INTEGER AS anio,
    EXTRACT(MONTH FROM m.fecha)::INTEGER AS mes_numero,
    DATE_TRUNC('month', m.fecha)::DATE AS periodo_mes,
    m.codigo,
    'ALPACAY'::TEXT AS unidad_proyecto,
    m.zona AS zona_fuente,
    m.veta,
    m.grupo,
    m.nivel,
    m.tipo,
    m.ubicacion,
    m.labor,
    m.lado,
    m.canal,
    m.ancho_labor_m,
    m.potencia_m,
    m.au_gr_tm,
    m.este,
    m.norte,
    m.cota,
    m.azimut_grados,
    m.buzamiento_grados,
    m.descripcion,
    m.es_qaqc,
    m.estado_coordenadas,
    m.estado_au,
    m.estado_codigo,
    m.estado_potencia,
    m.estado_nivel,
    m.incluir_ml,
    m.motivo_exclusion,
    CASE
        WHEN m.au_gr_tm IS NULL THEN 'SIN_DATO'
        WHEN m.au_gr_tm < 1 THEN 'MENOR_1'
        WHEN m.au_gr_tm < 5 THEN '1_A_5'
        WHEN m.au_gr_tm < 10 THEN '5_A_10'
        WHEN m.au_gr_tm < 30 THEN '10_A_30'
        ELSE 'MAYOR_IGUAL_30'
    END AS rango_au_descriptivo,
    CASE
        WHEN m.au_gr_tm IS NOT NULL AND m.potencia_m > 0
        THEN m.au_gr_tm * m.potencia_m
        ELSE NULL
    END AS factor_au_potencia_gt_m
FROM core.muestras m
JOIN analytics.vw_ultima_carga u ON u.carga_id = m.carga_id;

CREATE OR REPLACE VIEW analytics.vw_powerbi_calidad AS
SELECT
    m.carga_id,
    COUNT(*)::INTEGER AS total_registros,
    COUNT(*) FILTER (WHERE m.estado_coordenadas = 'OK')::INTEGER AS xyz_completo,
    COUNT(*) FILTER (WHERE m.estado_coordenadas = 'FALTA_COORD')::INTEGER AS sin_coordenadas,
    COUNT(*) FILTER (WHERE m.estado_coordenadas = 'PARCIAL_REVISAR')::INTEGER AS coordenadas_revisar,
    COUNT(*) FILTER (WHERE m.estado_au = 'OK')::INTEGER AS au_numerico,
    COUNT(*) FILTER (WHERE m.estado_au = 'TRAZA')::INTEGER AS au_traza,
    COUNT(*) FILTER (WHERE m.estado_au = 'FALTA_AU')::INTEGER AS au_faltante,
    COUNT(*) FILTER (WHERE m.estado_au = 'REVISAR_AU')::INTEGER AS au_revisar,
    COUNT(*) FILTER (WHERE m.es_qaqc)::INTEGER AS registros_qaqc,
    COUNT(*) FILTER (WHERE m.estado_potencia = 'FALTA_POT')::INTEGER AS potencia_faltante,
    COUNT(*) FILTER (WHERE m.estado_potencia = 'REVISAR_POT')::INTEGER AS potencia_revisar,
    COUNT(*) FILTER (WHERE m.estado_nivel = 'FALTA_NIVEL')::INTEGER AS nivel_faltante,
    COUNT(*) FILTER (WHERE m.estado_nivel = 'REVISAR_NIVEL')::INTEGER AS nivel_revisar,
    COUNT(*) FILTER (WHERE m.incluir_ml)::INTEGER AS candidatos_ml,
    COUNT(*) FILTER (WHERE m.estado_codigo = 'DUPLICADO')::INTEGER AS codigos_duplicados,
    COUNT(*) FILTER (WHERE m.incluir_ml)::DOUBLE PRECISION
        / NULLIF(COUNT(*), 0) AS proporcion_candidatos_ml,
    COUNT(*) FILTER (WHERE m.estado_coordenadas = 'OK')::DOUBLE PRECISION
        / NULLIF(COUNT(*), 0) AS cobertura_espacial
FROM analytics.vw_powerbi_muestras m
GROUP BY m.carga_id;

CREATE OR REPLACE VIEW analytics.vw_powerbi_resumen_labor AS
SELECT
    m.carga_id,
    m.unidad_proyecto,
    m.veta,
    m.labor,
    COUNT(*)::INTEGER AS total_muestras,
    COUNT(m.au_gr_tm)::INTEGER AS muestras_con_au,
    COUNT(*) FILTER (WHERE m.estado_coordenadas = 'OK')::INTEGER AS muestras_con_xyz,
    COUNT(*) FILTER (WHERE m.incluir_ml)::INTEGER AS candidatos_ml,
    AVG(m.au_gr_tm) AS au_promedio_gt,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY m.au_gr_tm) AS au_mediana_gt,
    MIN(m.au_gr_tm) AS au_minimo_gt,
    MAX(m.au_gr_tm) AS au_maximo_gt,
    AVG(m.potencia_m) FILTER (WHERE m.potencia_m > 0) AS potencia_promedio_m,
    SUM(m.au_gr_tm * m.potencia_m)
        FILTER (WHERE m.au_gr_tm IS NOT NULL AND m.potencia_m > 0)
        / NULLIF(
            SUM(m.potencia_m)
                FILTER (WHERE m.au_gr_tm IS NOT NULL AND m.potencia_m > 0),
            0
        ) AS au_promedio_ponderado_potencia_gt
FROM analytics.vw_powerbi_muestras m
WHERE NOT m.es_qaqc
GROUP BY m.carga_id, m.unidad_proyecto, m.veta, m.labor;

CREATE OR REPLACE VIEW analytics.vw_powerbi_resumen_veta AS
SELECT
    m.carga_id,
    m.unidad_proyecto,
    m.veta,
    COUNT(*)::INTEGER AS total_muestras,
    COUNT(DISTINCT m.labor)::INTEGER AS total_labores,
    COUNT(m.au_gr_tm)::INTEGER AS muestras_con_au,
    COUNT(*) FILTER (WHERE m.estado_coordenadas = 'OK')::INTEGER AS muestras_con_xyz,
    COUNT(*) FILTER (WHERE m.incluir_ml)::INTEGER AS candidatos_ml,
    AVG(m.au_gr_tm) AS au_promedio_gt,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY m.au_gr_tm) AS au_mediana_gt,
    MIN(m.au_gr_tm) AS au_minimo_gt,
    MAX(m.au_gr_tm) AS au_maximo_gt,
    AVG(m.potencia_m) FILTER (WHERE m.potencia_m > 0) AS potencia_promedio_m,
    SUM(m.au_gr_tm * m.potencia_m)
        FILTER (WHERE m.au_gr_tm IS NOT NULL AND m.potencia_m > 0)
        / NULLIF(
            SUM(m.potencia_m)
                FILTER (WHERE m.au_gr_tm IS NOT NULL AND m.potencia_m > 0),
            0
        ) AS au_promedio_ponderado_potencia_gt
FROM analytics.vw_powerbi_muestras m
WHERE NOT m.es_qaqc
GROUP BY m.carga_id, m.unidad_proyecto, m.veta;

CREATE OR REPLACE VIEW analytics.vw_powerbi_qaqc AS
SELECT
    m.muestra_id,
    m.carga_id,
    m.fila_excel,
    m.fecha,
    m.codigo,
    m.tipo,
    m.unidad_proyecto,
    m.zona_fuente,
    m.veta,
    m.labor,
    m.au_gr_tm,
    m.estado_au,
    m.estado_coordenadas,
    m.motivo_exclusion
FROM analytics.vw_powerbi_muestras m
WHERE m.es_qaqc;

-- Vista local para exportar puntos a AutoCAD, Leapfrog y Deswik.
-- Las coordenadas son sensibles y no deben publicarse en GitHub.
CREATE OR REPLACE VIEW analytics.vw_exportacion_3d AS
SELECT
    m.codigo,
    m.fecha,
    m.unidad_proyecto,
    m.zona_fuente,
    m.veta,
    m.labor,
    m.canal,
    m.este AS x_este,
    m.norte AS y_norte,
    m.cota AS z_cota,
    m.au_gr_tm,
    m.potencia_m,
    m.azimut_grados,
    m.buzamiento_grados,
    m.factor_au_potencia_gt_m,
    m.rango_au_descriptivo
FROM analytics.vw_powerbi_muestras m
WHERE m.incluir_ml;

COMMENT ON VIEW analytics.vw_powerbi_muestras IS
'Dataset vigente para Power BI. ALPACAY se trata como una unidad; zona_fuente conserva la etiqueta original. Los rangos de Au son descriptivos y no son cut-off economico.';
COMMENT ON VIEW analytics.vw_powerbi_calidad IS
'Indicadores de integridad, QA/QC y elegibilidad ML de la ultima carga transformada.';
COMMENT ON VIEW analytics.vw_powerbi_resumen_labor IS
'Estadisticas descriptivas por labor; no constituyen estimacion de recursos o reservas.';
COMMENT ON VIEW analytics.vw_powerbi_resumen_veta IS
'Estadisticas descriptivas por veta dentro de la unidad ALPACAY; no constituyen estimacion de recursos o reservas.';
COMMENT ON VIEW analytics.vw_exportacion_3d IS
'Puntos con XYZ y Au validos para intercambio local con software 3D. No publicar coordenadas reales.';

COMMIT;

SELECT
    carga_id,
    total_registros,
    xyz_completo,
    au_numerico,
    au_traza,
    registros_qaqc,
    candidatos_ml,
    codigos_duplicados,
    cobertura_espacial,
    proporcion_candidatos_ml
FROM analytics.vw_powerbi_calidad;
