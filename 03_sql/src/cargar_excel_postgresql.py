from __future__ import annotations

import argparse
import getpass
import hashlib
import os
import re
import sys
import unicodedata
from datetime import date, datetime
from pathlib import Path

import pandas as pd


COLUMNAS = {
    "FECHA": "fecha_texto",
    "CODIGO": "codigo_texto",
    "ZONA": "zona_texto",
    "VETA": "veta_texto",
    "TITULAR": "titular_texto",
    "GRUPO": "grupo_texto",
    "NV": "nivel_texto",
    "TIPO": "tipo_texto",
    "UBICACION": "ubicacion_texto",
    "LABOR": "labor_texto",
    "LADO": "lado_texto",
    "CANAL": "canal_texto",
    "AL": "ancho_labor_texto",
    "POTM": "potencia_texto",
    "AUGRTM": "au_gr_tm_texto",
    "ESTE": "este_texto",
    "NORTE": "norte_texto",
    "COTA": "cota_texto",
    "AZ": "azimut_texto",
    "DIP": "buzamiento_texto",
    "DESCRIPCION": "descripcion_texto",
}

COLUMNAS_SQL = list(COLUMNAS.values())


def clave_encabezado(valor: object) -> str:
    texto = unicodedata.normalize("NFKD", str(valor).strip().upper())
    texto = "".join(c for c in texto if not unicodedata.combining(c))
    return re.sub(r"[^A-Z0-9]+", "", texto)


def texto_raw(valor: object) -> str | None:
    if valor is None or pd.isna(valor):
        return None
    if isinstance(valor, pd.Timestamp):
        return valor.isoformat()
    if isinstance(valor, (datetime, date)):
        return valor.isoformat()
    if isinstance(valor, float) and valor.is_integer():
        return str(int(valor))
    texto = str(valor).strip()
    return texto if texto else None


def sha256_archivo(ruta: Path) -> str:
    h = hashlib.sha256()
    with ruta.open("rb") as archivo:
        for bloque in iter(lambda: archivo.read(1024 * 1024), b""):
            h.update(bloque)
    return h.hexdigest()


def leer_excel(ruta: Path, hoja: str) -> tuple[pd.DataFrame, dict[str, str]]:
    df = pd.read_excel(ruta, sheet_name=hoja, dtype=object)
    encontrados = {clave_encabezado(c): c for c in df.columns}
    faltantes = [c for c in COLUMNAS if c not in encontrados]
    if faltantes:
        raise ValueError("Faltan encabezados requeridos: " + ", ".join(faltantes))

    seleccion = pd.DataFrame(
        {destino: df[encontrados[origen]] for origen, destino in COLUMNAS.items()}
    )
    seleccion = seleccion.dropna(how="all").reset_index(drop=True)
    return seleccion, encontrados


def resumen_validacion(df: pd.DataFrame) -> dict[str, int]:
    au = pd.to_numeric(df["au_gr_tm_texto"], errors="coerce")
    este = pd.to_numeric(df["este_texto"], errors="coerce")
    norte = pd.to_numeric(df["norte_texto"], errors="coerce")
    cota = pd.to_numeric(df["cota_texto"], errors="coerce")
    codigos = df["codigo_texto"].map(texto_raw)
    return {
        "filas": len(df),
        "au_numerico": int(au.notna().sum()),
        "xyz_completo": int((este.notna() & norte.notna() & cota.notna()).sum()),
        "codigos_duplicados": int(codigos.dropna().duplicated(keep=False).sum()),
    }


def imprimir_resumen(ruta: Path, hoja: str, resumen: dict[str, int], hash_archivo: str) -> None:
    print("\nVALIDACION DEL ARCHIVO")
    print(f"Archivo: {ruta.name}")
    print(f"Hoja: {hoja}")
    print(f"Filas detectadas: {resumen['filas']}")
    print(f"Filas con Au numerico: {resumen['au_numerico']}")
    print(f"Filas con XYZ completo: {resumen['xyz_completo']}")
    print(f"Filas asociadas a codigos duplicados: {resumen['codigos_duplicados']}")
    print(f"SHA-256: {hash_archivo}")


def obtener_conexion(args):
    try:
        import psycopg
    except ImportError as exc:
        raise RuntimeError(
            "Falta psycopg. Ejecuta primero 01_INSTALAR_DEPENDENCIAS.bat"
        ) from exc

    password = os.getenv("PGPASSWORD")
    if not password:
        password = getpass.getpass("Contrasena del usuario PostgreSQL: ")
    return psycopg.connect(
        host=args.host,
        port=args.port,
        dbname=args.database,
        user=args.user,
        password=password,
    )


def cargar_postgresql(args, ruta: Path, df: pd.DataFrame, hash_archivo: str) -> None:
    conn = obtener_conexion(args)
    carga_id = None
    try:
        if args.init_db:
            sql_path = Path(__file__).resolve().parents[1] / "sql" / "01_inicializar_raw_audit.sql"
            with conn.cursor() as cur:
                cur.execute(sql_path.read_text(encoding="utf-8"))
            conn.commit()

        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT carga_id
                FROM audit.cargas_archivo
                WHERE hash_archivo_sha256 = %s
                  AND estado IN ('COMPLETADA', 'COMPLETADA_CON_ALERTAS')
                ORDER BY carga_id DESC
                LIMIT 1
                """,
                (hash_archivo,),
            )
            anterior = cur.fetchone()
            if anterior and not args.force:
                print(f"\nEl archivo ya fue cargado. carga_id existente: {anterior[0]}")
                print("No se duplicaron registros. Usa --force solo si necesitas repetir la carga.")
                return

            cur.execute(
                """
                INSERT INTO audit.cargas_archivo
                    (nombre_archivo, nombre_hoja, hash_archivo_sha256, filas_leidas)
                VALUES (%s, %s, %s, %s)
                RETURNING carga_id
                """,
                (ruta.name, args.sheet, hash_archivo, len(df)),
            )
            carga_id = cur.fetchone()[0]
        conn.commit()

        columnas_insert = ", ".join(["carga_id", "fila_excel", *COLUMNAS_SQL])
        placeholders = ", ".join(["%s"] * (2 + len(COLUMNAS_SQL)))
        sentencia = f"INSERT INTO raw.muestras_excel ({columnas_insert}) VALUES ({placeholders})"

        filas = []
        for indice, row in df.iterrows():
            valores = [texto_raw(row[col]) for col in COLUMNAS_SQL]
            filas.append((carga_id, indice + 2, *valores))

        with conn.cursor() as cur:
            cur.executemany(sentencia, filas)
            cur.execute(
                """
                UPDATE audit.cargas_archivo
                SET fecha_fin = CURRENT_TIMESTAMP,
                    filas_cargadas = %s,
                    filas_rechazadas = 0,
                    estado = 'COMPLETADA',
                    observaciones = 'Carga RAW completada; pendiente transformacion CORE'
                WHERE carga_id = %s
                """,
                (len(filas), carga_id),
            )
        conn.commit()
        print(f"\nCARGA COMPLETADA: {len(filas)} filas. carga_id = {carga_id}")
    except Exception as exc:
        conn.rollback()
        if carga_id is not None:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    UPDATE audit.cargas_archivo
                    SET fecha_fin = CURRENT_TIMESTAMP,
                        estado = 'FALLIDA',
                        observaciones = %s
                    WHERE carga_id = %s
                    """,
                    (str(exc)[:1000], carga_id),
                )
            conn.commit()
        raise
    finally:
        conn.close()


def argumentos():
    parser = argparse.ArgumentParser(description="Carga DATA_ORIGINAL de Excel a PostgreSQL")
    parser.add_argument("--excel", required=True, help="Ruta del archivo XLSX")
    parser.add_argument("--sheet", default="DATA_ORIGINAL", help="Hoja de origen")
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", type=int, default=5432)
    parser.add_argument("--database", default="mineria40_alpacay")
    parser.add_argument("--user", default="postgres")
    parser.add_argument("--dry-run", action="store_true", help="Valida sin conectarse a PostgreSQL")
    parser.add_argument("--init-db", action="store_true", help="Crea esquemas y tablas si faltan")
    parser.add_argument("--force", action="store_true", help="Permite repetir un archivo ya cargado")
    return parser.parse_args()


def main() -> int:
    args = argumentos()
    ruta = Path(args.excel).expanduser().resolve()
    if not ruta.is_file():
        print(f"ERROR: no existe el archivo: {ruta}", file=sys.stderr)
        return 2
    try:
        df, _ = leer_excel(ruta, args.sheet)
        hash_archivo = sha256_archivo(ruta)
        resumen = resumen_validacion(df)
        imprimir_resumen(ruta, args.sheet, resumen, hash_archivo)
        if args.dry_run:
            print("\nPRUEBA EN SECO CORRECTA. No se modifico PostgreSQL.")
            return 0
        cargar_postgresql(args, ruta, df, hash_archivo)
        return 0
    except Exception as exc:
        print(f"\nERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

