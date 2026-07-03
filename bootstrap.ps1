Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
Write-Host "* DFE-Toolkit v0.1" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Gray
Write-Host "+ Descargando la interfaz grafica (GUI)..." -ForegroundColor Cyan

$guiScriptBaseUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/src/Gui.ps1"
$cacheBust = [DateTime]::UtcNow.Ticks
$guiScriptUrl = "$guiScriptBaseUrl`?cacheBust=$cacheBust"
$headers = @{
    "Cache-Control" = "no-cache"
    "Pragma" = "no-cache"
}

try {
    $scriptContent = Invoke-RestMethod -Uri $guiScriptUrl -Headers $headers -ErrorAction Stop
    Write-Host "+ Interfaz grafica descargada correctamente" -ForegroundColor Green
}
catch {
    Write-Error "- Error al descargar la interfaz grafica: $_"
    exit 1
}

Write-Host ">  Ejecutando la interfaz grafica..." -ForegroundColor Cyan
$guiScriptBlock = [scriptblock]::Create($scriptContent)
& $guiScriptBlock
