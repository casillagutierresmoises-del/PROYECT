BEGIN;

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS audit;

CREATE TABLE IF NOT EXISTS audit.cargas_archivo (
    carga_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_archivo TEXT NOT NULL,
    nombre_hoja TEXT NOT NULL DEFAULT 'DATA_ORIGINAL',
    hash_archivo_sha256 CHAR(64),
    fecha_inicio TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_fin TIMESTAMPTZ,
    filas_leidas INTEGER NOT NULL DEFAULT 0,
    filas_cargadas INTEGER NOT NULL DEFAULT 0,
    filas_rechazadas INTEGER NOT NULL DEFAULT 0,
    estado VARCHAR(30) NOT NULL DEFAULT 'INICIADA',
    observaciones TEXT,
    CONSTRAINT chk_estado_carga CHECK (
        estado IN ('INICIADA', 'COMPLETADA', 'COMPLETADA_CON_ALERTAS', 'FALLIDA')
    )
);

-- Ajusta instalaciones creadas previamente con VARCHAR(20).
ALTER TABLE audit.cargas_archivo
    ALTER COLUMN estado TYPE VARCHAR(30);

CREATE TABLE IF NOT EXISTS raw.muestras_excel (
    raw_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    carga_id BIGINT NOT NULL REFERENCES audit.cargas_archivo(carga_id),
    fila_excel INTEGER NOT NULL,
    fecha_texto TEXT,
    codigo_texto TEXT,
    zona_texto TEXT,
    veta_texto TEXT,
    titular_texto TEXT,
    grupo_texto TEXT,
    nivel_texto TEXT,
    tipo_texto TEXT,
    ubicacion_texto TEXT,
    labor_texto TEXT,
    lado_texto TEXT,
    canal_texto TEXT,
    ancho_labor_texto TEXT,
    potencia_texto TEXT,
    au_gr_tm_texto TEXT,
    este_texto TEXT,
    norte_texto TEXT,
    cota_texto TEXT,
    azimut_texto TEXT,
    buzamiento_texto TEXT,
    descripcion_texto TEXT,
    importado_en TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_raw_carga_fila UNIQUE (carga_id, fila_excel)
);

CREATE INDEX IF NOT EXISTS idx_raw_codigo ON raw.muestras_excel(codigo_texto);
CREATE INDEX IF NOT EXISTS idx_raw_labor ON raw.muestras_excel(labor_texto);
CREATE INDEX IF NOT EXISTS idx_raw_carga ON raw.muestras_excel(carga_id);
CREATE INDEX IF NOT EXISTS idx_audit_hash ON audit.cargas_archivo(hash_archivo_sha256);

COMMIT;
