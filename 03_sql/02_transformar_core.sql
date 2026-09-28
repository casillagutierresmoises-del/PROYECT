-- Proyecto ALPACAY - Fase 11.2
-- Transforma la carga RAW mas reciente en datos tipados y validados en CORE.
-- Es idempotente: puede ejecutarse nuevamente sin duplicar registros.

BEGIN;

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS audit;

CREATE OR REPLACE FUNCTION core.texto_limpio(valor TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT NULLIF(BTRIM(valor), '');
$$;

CREATE OR REPLACE FUNCTION core.numero_seguro(valor TEXT)
RETURNS DOUBLE PRECISION
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
    limpio TEXT;
BEGIN
    limpio := REPLACE(core.texto_limpio(valor), ',', '.');
    IF limpio IS NULL THEN
        RETURN NULL;
    END IF;

    IF limpio ~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$' THEN
        RETURN limpio::DOUBLE PRECISION;
    END IF;

    RETURN NULL;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION core.fecha_segura(valor TEXT)
RETURNS DATE
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
    limpio TEXT;
BEGIN
    limpio := core.texto_limpio(valor);
    IF limpio IS NULL THEN
        RETURN NULL;
    END IF;

    IF limpio ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}' THEN
        RETURN SUBSTRING(limpio FROM 1 FOR 10)::DATE;
    END IF;

    IF limpio ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' THEN
        RETURN TO_DATE(limpio, 'DD/MM/YYYY');
    END IF;

    RETURN NULL;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

CREATE TABLE IF NOT EXISTS core.muestras (
    muestra_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    raw_id BIGINT NOT NULL UNIQUE REFERENCES raw.muestras_excel(raw_id),
    carga_id BIGINT NOT NULL REFERENCES audit.cargas_archivo(carga_id),
    fila_excel INTEGER NOT NULL,
    fecha DATE,
    codigo TEXT,
    zona TEXT,
    veta TEXT,
    titular TEXT,
    grupo TEXT,
    nivel DOUBLE PRECISION,
    tipo TEXT,
    ubicacion TEXT,
    labor TEXT,
    lado TEXT,
    canal TEXT,
    ancho_labor_m DOUBLE PRECISION,
    potencia_m DOUBLE PRECISION,
    au_gr_tm DOUBLE PRECISION,
    este DOUBLE PRECISION,
    norte DOUBLE PRECISION,
    cota DOUBLE PRECISION,
    azimut_grados DOUBLE PRECISION,
    buzamiento_grados DOUBLE PRECISION,
    descripcion TEXT,
    es_qaqc BOOLEAN NOT NULL,
    estado_coordenadas VARCHAR(20) NOT NULL,
    estado_au VARCHAR(20) NOT NULL,
    estado_codigo VARCHAR(20) NOT NULL,
    estado_potencia VARCHAR(20) NOT NULL,
    estado_nivel VARCHAR(20) NOT NULL,
    incluir_ml BOOLEAN NOT NULL,
    motivo_exclusion VARCHAR(30) NOT NULL,
    procesado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_core_coord CHECK (
        estado_coordenadas IN ('OK', 'FALTA_COORD', 'PARCIAL_REVISAR')
    ),
    CONSTRAINT chk_core_au CHECK (
        estado_au IN ('OK', 'TRAZA', 'FALTA_AU', 'REVISAR_AU')
    ),
    CONSTRAINT chk_core_codigo CHECK (
        estado_codigo IN ('OK', 'DUPLICADO', 'FALTA_CODIGO')
    ),
    CONSTRAINT chk_core_potencia CHECK (
        estado_potencia IN ('OK', 'FALTA_POT', 'REVISAR_POT')
    ),
    CONSTRAINT chk_core_nivel CHECK (
        estado_nivel IN ('OK', 'FALTA_NIVEL', 'REVISAR_NIVEL')
    )
);

CREATE TABLE IF NOT EXISTS audit.transformaciones_core (
    carga_id BIGINT PRIMARY KEY REFERENCES audit.cargas_archivo(carga_id),
    ejecutado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    filas_raw INTEGER NOT NULL,
    filas_core INTEGER NOT NULL,
    candidatos_ml INTEGER NOT NULL,
    estado VARCHAR(20) NOT NULL,
    observaciones TEXT,
    CONSTRAINT chk_transformacion_estado CHECK (estado IN ('COMPLETADA', 'FALLIDA'))
);

CREATE INDEX IF NOT EXISTS idx_core_muestras_carga ON core.muestras(carga_id);
CREATE INDEX IF NOT EXISTS idx_core_muestras_codigo ON core.muestras(codigo);
CREATE INDEX IF NOT EXISTS idx_core_muestras_labor ON core.muestras(labor);
CREATE INDEX IF NOT EXISTS idx_core_muestras_xyz ON core.muestras(este, norte, cota);
CREATE INDEX IF NOT EXISTS idx_core_muestras_ml ON core.muestras(carga_id, incluir_ml);

DO $$
DECLARE
    v_carga_id BIGINT;
    v_filas_raw INTEGER;
    v_filas_core INTEGER;
    v_candidatos_ml INTEGER;
BEGIN
    SELECT carga_id
    INTO v_carga_id
    FROM audit.cargas_archivo
    WHERE estado IN ('COMPLETADA', 'COMPLETADA_CON_ALERTAS')
    ORDER BY carga_id DESC
    LIMIT 1;

    IF v_carga_id IS NULL THEN
        RAISE EXCEPTION 'No existe una carga RAW completada para transformar';
    END IF;

    WITH base AS (
        SELECT
            r.raw_id,
            r.carga_id,
            r.fila_excel,
            core.fecha_segura(r.fecha_texto) AS fecha,
            core.texto_limpio(r.codigo_texto) AS codigo,
            UPPER(core.texto_limpio(r.zona_texto)) AS zona,
            UPPER(core.texto_limpio(r.veta_texto)) AS veta,
            UPPER(core.texto_limpio(r.titular_texto)) AS titular,
            UPPER(core.texto_limpio(r.grupo_texto)) AS grupo,
            core.texto_limpio(r.nivel_texto) AS nivel_texto_limpio,
            core.numero_seguro(r.nivel_texto) AS nivel,
            UPPER(core.texto_limpio(r.tipo_texto)) AS tipo,
            UPPER(core.texto_limpio(r.ubicacion_texto)) AS ubicacion,
            UPPER(core.texto_limpio(r.labor_texto)) AS labor,
            UPPER(core.texto_limpio(r.lado_texto)) AS lado,
            UPPER(core.texto_limpio(r.canal_texto)) AS canal,
            core.numero_seguro(r.ancho_labor_texto) AS ancho_labor_m,
            core.texto_limpio(r.potencia_texto) AS potencia_texto_limpio,
            core.numero_seguro(r.potencia_texto) AS potencia_m,
            core.texto_limpio(r.au_gr_tm_texto) AS au_texto_limpio,
            core.numero_seguro(r.au_gr_tm_texto) AS au_gr_tm,
            core.texto_limpio(r.este_texto) AS este_texto_limpio,
            core.texto_limpio(r.norte_texto) AS norte_texto_limpio,
            core.texto_limpio(r.cota_texto) AS cota_texto_limpio,
            core.numero_seguro(r.este_texto) AS este,
            core.numero_seguro(r.norte_texto) AS norte,
            core.numero_seguro(r.cota_texto) AS cota,
            core.numero_seguro(r.azimut_texto) AS azimut_grados,
            core.numero_seguro(r.buzamiento_texto) AS buzamiento_grados,
            core.texto_limpio(r.descripcion_texto) AS descripcion
        FROM raw.muestras_excel r
        WHERE r.carga_id = v_carga_id
    ),
    tipada AS (
        SELECT
            b.*,
            COUNT(b.codigo) OVER (PARTITION BY b.carga_id, b.codigo) AS repeticiones_codigo
        FROM base b
    ),
    evaluada AS (
        SELECT
            t.*,
            COALESCE(t.tipo IN ('BLANCO', 'DUPLICADO'), FALSE) AS es_qaqc,
            CASE
                WHEN t.este IS NOT NULL AND t.norte IS NOT NULL AND t.cota IS NOT NULL THEN 'OK'
                WHEN t.este_texto_limpio IS NULL
                 AND t.norte_texto_limpio IS NULL
                 AND t.cota_texto_limpio IS NULL THEN 'FALTA_COORD'
                ELSE 'PARCIAL_REVISAR'
            END AS estado_coordenadas,
            CASE
                WHEN t.au_gr_tm IS NOT NULL THEN 'OK'
                WHEN t.au_texto_limpio IS NULL THEN 'FALTA_AU'
                WHEN UPPER(t.au_texto_limpio) IN ('TRAZA', 'TRAZ') THEN 'TRAZA'
                ELSE 'REVISAR_AU'
            END AS estado_au,
            CASE
                WHEN t.codigo IS NULL THEN 'FALTA_CODIGO'
                WHEN t.repeticiones_codigo > 1 THEN 'DUPLICADO'
                ELSE 'OK'
            END AS estado_codigo,
            CASE
                WHEN t.potencia_m > 0 THEN 'OK'
                WHEN t.potencia_texto_limpio IS NULL THEN 'FALTA_POT'
                ELSE 'REVISAR_POT'
            END AS estado_potencia,
            CASE
                WHEN t.nivel IS NOT NULL THEN 'OK'
                WHEN t.nivel_texto_limpio IS NULL THEN 'FALTA_NIVEL'
                ELSE 'REVISAR_NIVEL'
            END AS estado_nivel
        FROM tipada t
    ),
    calificada AS (
        SELECT
            e.*,
            (
                e.estado_coordenadas = 'OK'
                AND e.estado_au = 'OK'
                AND NOT e.es_qaqc
                AND e.estado_codigo = 'OK'
            ) AS incluir_ml,
            CASE
                WHEN e.estado_codigo = 'FALTA_CODIGO' THEN 'FALTA_CODIGO'
                WHEN e.estado_codigo = 'DUPLICADO' THEN 'CODIGO_DUPLICADO'
                WHEN e.es_qaqc THEN 'REGISTRO_QAQC'
                WHEN e.estado_coordenadas = 'FALTA_COORD' THEN 'FALTA_COORD'
                WHEN e.estado_coordenadas = 'PARCIAL_REVISAR' THEN 'COORD_PARCIAL'
                WHEN e.estado_au = 'TRAZA' THEN 'AU_TRAZA'
                WHEN e.estado_au = 'FALTA_AU' THEN 'FALTA_AU'
                WHEN e.estado_au = 'REVISAR_AU' THEN 'REVISAR_AU'
                ELSE 'APTO_ML'
            END AS motivo_exclusion
        FROM evaluada e
    )
    INSERT INTO core.muestras (
        raw_id, carga_id, fila_excel, fecha, codigo, zona, veta, titular, grupo,
        nivel, tipo, ubicacion, labor, lado, canal, ancho_labor_m, potencia_m,
        au_gr_tm, este, norte, cota, azimut_grados, buzamiento_grados, descripcion,
        es_qaqc, estado_coordenadas, estado_au, estado_codigo, estado_potencia,
        estado_nivel, incluir_ml, motivo_exclusion, procesado_en
    )
    SELECT
        raw_id, carga_id, fila_excel, fecha, codigo, zona, veta, titular, grupo,
        nivel, tipo, ubicacion, labor, lado, canal, ancho_labor_m, potencia_m,
        au_gr_tm, este, norte, cota, azimut_grados, buzamiento_grados, descripcion,
        es_qaqc, estado_coordenadas, estado_au, estado_codigo, estado_potencia,
        estado_nivel, incluir_ml, motivo_exclusion, CURRENT_TIMESTAMP
    FROM calificada
    ON CONFLICT (raw_id) DO UPDATE SET
        carga_id = EXCLUDED.carga_id,
        fila_excel = EXCLUDED.fila_excel,
        fecha = EXCLUDED.fecha,
        codigo = EXCLUDED.codigo,
        zona = EXCLUDED.zona,
        veta = EXCLUDED.veta,
        titular = EXCLUDED.titular,
        grupo = EXCLUDED.grupo,
        nivel = EXCLUDED.nivel,
        tipo = EXCLUDED.tipo,
        ubicacion = EXCLUDED.ubicacion,
        labor = EXCLUDED.labor,
        lado = EXCLUDED.lado,
        canal = EXCLUDED.canal,
        ancho_labor_m = EXCLUDED.ancho_labor_m,
        potencia_m = EXCLUDED.potencia_m,
        au_gr_tm = EXCLUDED.au_gr_tm,
        este = EXCLUDED.este,
        norte = EXCLUDED.norte,
        cota = EXCLUDED.cota,
        azimut_grados = EXCLUDED.azimut_grados,
        buzamiento_grados = EXCLUDED.buzamiento_grados,
        descripcion = EXCLUDED.descripcion,
        es_qaqc = EXCLUDED.es_qaqc,
        estado_coordenadas = EXCLUDED.estado_coordenadas,
        estado_au = EXCLUDED.estado_au,
        estado_codigo = EXCLUDED.estado_codigo,
        estado_potencia = EXCLUDED.estado_potencia,
        estado_nivel = EXCLUDED.estado_nivel,
        incluir_ml = EXCLUDED.incluir_ml,
        motivo_exclusion = EXCLUDED.motivo_exclusion,
        procesado_en = CURRENT_TIMESTAMP;

    SELECT COUNT(*)::INTEGER
    INTO v_filas_raw
    FROM raw.muestras_excel
    WHERE carga_id = v_carga_id;

    SELECT
        COUNT(*)::INTEGER,
        COUNT(*) FILTER (WHERE incluir_ml)::INTEGER
    INTO v_filas_core, v_candidatos_ml
    FROM core.muestras
    WHERE carga_id = v_carga_id;

    IF v_filas_core <> v_filas_raw THEN
        RAISE EXCEPTION
            'Control fallido: RAW tiene % filas y CORE tiene % filas',
            v_filas_raw, v_filas_core;
    END IF;

    INSERT INTO audit.transformaciones_core (
        carga_id, ejecutado_en, filas_raw, filas_core, candidatos_ml, estado, observaciones
    )
    VALUES (
        v_carga_id, CURRENT_TIMESTAMP, v_filas_raw, v_filas_core,
        v_candidatos_ml, 'COMPLETADA', 'Transformacion RAW a CORE validada'
    )
    ON CONFLICT (carga_id) DO UPDATE SET
        ejecutado_en = EXCLUDED.ejecutado_en,
        filas_raw = EXCLUDED.filas_raw,
        filas_core = EXCLUDED.filas_core,
        candidatos_ml = EXCLUDED.candidatos_ml,
        estado = EXCLUDED.estado,
        observaciones = EXCLUDED.observaciones;

    RAISE NOTICE
        'Carga % transformada: % filas CORE y % candidatos ML',
        v_carga_id, v_filas_core, v_candidatos_ml;
END;
$$;

CREATE OR REPLACE VIEW core.vw_registros_qaqc AS
SELECT
    muestra_id,
    carga_id,
    fila_excel,
    fecha,
    codigo,
    tipo,
    labor,
    au_gr_tm,
    estado_au,
    estado_coordenadas
FROM core.muestras
WHERE es_qaqc;

CREATE OR REPLACE VIEW analytics.vw_muestras_ml AS
SELECT
    muestra_id,
    carga_id,
    fila_excel,
    fecha,
    codigo,
    zona,
    veta,
    grupo,
    nivel,
    tipo,
    labor,
    potencia_m,
    au_gr_tm,
    este,
    norte,
    cota,
    azimut_grados
FROM core.muestras
WHERE incluir_ml;

CREATE OR REPLACE VIEW analytics.vw_resumen_calidad_carga AS
SELECT
    carga_id,
    COUNT(*)::INTEGER AS total_core,
    COUNT(*) FILTER (WHERE estado_coordenadas = 'OK')::INTEGER AS xyz_completo,
    COUNT(*) FILTER (WHERE estado_au = 'OK')::INTEGER AS au_numerico,
    COUNT(*) FILTER (WHERE estado_au = 'TRAZA')::INTEGER AS au_traza,
    COUNT(*) FILTER (WHERE es_qaqc)::INTEGER AS registros_qaqc,
    COUNT(*) FILTER (WHERE incluir_ml)::INTEGER AS candidatos_ml,
    COUNT(*) FILTER (WHERE estado_codigo = 'DUPLICADO')::INTEGER AS codigos_duplicados
FROM core.muestras
GROUP BY carga_id;

COMMENT ON TABLE core.muestras IS
'Datos de muestreo tipados y validados, con trazabilidad hacia RAW.';
COMMENT ON VIEW analytics.vw_muestras_ml IS
'Registros aptos para el primer analisis espacial y modelos ML; no representa recursos ni reservas.';

COMMIT;

SELECT
    carga_id,
    total_core,
    xyz_completo,
    au_numerico,
    au_traza,
    registros_qaqc,
    candidatos_ml,
    codigos_duplicados
FROM analytics.vw_resumen_calidad_carga
ORDER BY carga_id DESC
LIMIT 1;
