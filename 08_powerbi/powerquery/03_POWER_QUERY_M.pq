// Crear un parámetro de texto llamado RutaBase que apunte a data/interno o data/publico.
// Función fxCsv
(NombreArchivo as text) as table =>
let
    Ruta = RutaBase & "\\" & NombreArchivo,
    Origen = Csv.Document(File.Contents(Ruta), [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Encabezados = Table.PromoteHeaders(Origen, [PromoteAllScalars=true])
in
    Encabezados

// Consultas sugeridas
// Fact_Muestras = fxCsv("Fact_Muestras.csv")
// Fact_Celdas = fxCsv("Fact_Celdas.csv")
// Fact_Objetivos = fxCsv("Fact_Objetivos.csv")
// Fact_Nodos = fxCsv("Fact_Nodos.csv")
// Fact_Tramos = fxCsv("Fact_Tramos.csv")
// Metricas_Validacion = fxCsv("Metricas_Validacion.csv")
// Sensibilidad_Umbrales = fxCsv("Sensibilidad_Umbrales.csv")
// Preparacion_Deswik = fxCsv("Preparacion_Deswik.csv")
// Dim_ClaseAu = fxCsv("Dim_ClaseAu.csv")
// Dim_Bloque = fxCsv("Dim_Bloque.csv")
// Dim_Tramo = fxCsv("Dim_Tramo.csv")
// Dim_Labor = fxCsv("Dim_Labor.csv")
