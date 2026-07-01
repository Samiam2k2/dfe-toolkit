param(
    [switch]$NoGUI
)

Write-Host "🚀 DFE-Toolkit v0.1" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Gray
Write-Host "📥 Descargando el motor principal..." -ForegroundColor Cyan

$mainScriptBaseUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/src/Main.ps1"
$cacheBust = [DateTime]::UtcNow.Ticks
$mainScriptUrl = "$mainScriptBaseUrl`?cacheBust=$cacheBust"
$headers = @{
    "Cache-Control" = "no-cache"
    "Pragma" = "no-cache"
}

try {
    $scriptContent = Invoke-RestMethod -Uri $mainScriptUrl -Headers $headers -ErrorAction Stop
    Write-Host "✅ Script descargado correctamente" -ForegroundColor Green
}
catch {
    Write-Error "❌ Error al descargar el script: $_"
    exit 1
}

Write-Host "▶️  Ejecutando el motor principal..." -ForegroundColor Cyan
$mainScriptBlock = [scriptblock]::Create($scriptContent)

if ($NoGUI) {
    & $mainScriptBlock -NoGUI
}
else {
    & $mainScriptBlock
}
