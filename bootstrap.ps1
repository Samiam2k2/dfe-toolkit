Write-Host "🚀 DFE-Toolkit v0.1" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Gray
Write-Host "📥 Descargando el motor principal..." -ForegroundColor Cyan

$mainScriptUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/src/Main.ps1"

try {
    $scriptContent = Invoke-RestMethod -Uri $mainScriptUrl -ErrorAction Stop
    Write-Host "✅ Script descargado correctamente" -ForegroundColor Green
}
catch {
    Write-Error "❌ Error al descargar el script: $_"
    exit 1
}

Write-Host "▶️  Ejecutando el motor principal..." -ForegroundColor Cyan
Invoke-Expression $scriptContent
