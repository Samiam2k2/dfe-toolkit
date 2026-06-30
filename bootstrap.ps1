<#
.SYNOPSIS
    DFE-Toolkit Bootstrap
.DESCRIPTION
    Punto de entrada para la herramienta de instalación de DFE.
    Descarga y ejecuta el script principal desde el repositorio.
#>

Write-Host "🚀 DFE-Toolkit v0.1" -ForegroundColor Cyan
Write-Host "================================`n" -ForegroundColor Gray

# --- Configuración del repositorio ---
$REPO_OWNER = "Samiam2k2"
$REPO_NAME = "dfe-toolkit"
$BRANCH = "main"
$SCRIPT_PATH = "src/Main.ps1"

# --- Construir URL ---
$MAIN_SCRIPT_URL = "https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$BRANCH/$SCRIPT_PATH"

Write-Host "📥 Descargando el motor principal..." -ForegroundColor Cyan
Write-Host "   Fuente: $MAIN_SCRIPT_URL" -ForegroundColor Gray

try {
    $mainScript = Invoke-RestMethod -Uri $MAIN_SCRIPT_URL -ErrorAction Stop
    Write-Host "✅ Script descargado correctamente ($($mainScript.Length) bytes)" -ForegroundColor Green
} catch {
    Write-Error "❌ Error al descargar el script: $_"
    Write-Host "`n💡 Verifica que el repositorio y la ruta sean correctos." -ForegroundColor Yellow
    exit 1
}

Write-Host "`n▶️  Ejecutando el motor principal..." -ForegroundColor Cyan
try {
    Invoke-Expression $mainScript
} catch {
    Write-Error "❌ Error al ejecutar el script: $_"
    exit 1
}
