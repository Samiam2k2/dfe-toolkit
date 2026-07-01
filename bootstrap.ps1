<#
.SYNOPSIS
    Punto de entrada local para DFE Toolkit.
.DESCRIPTION
    Muestra un mensaje de bienvenida y ejecuta src/Main.ps1 desde la carpeta
    local del proyecto.
#>

$ErrorActionPreference = "Stop"

$projectRoot = $PSScriptRoot
$mainScript = Join-Path -Path $projectRoot -ChildPath "src/Main.ps1"

Write-Host ""
Write-Host "Bienvenido a DFE Toolkit" -ForegroundColor Cyan
Write-Host "Ejecutando herramienta local..." -ForegroundColor Gray
Write-Host ""

if (-not (Test-Path -Path $mainScript -PathType Leaf)) {
    Write-Error "No se encontro el script principal en: $mainScript"
    exit 1
}

& $mainScript
