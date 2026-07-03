<#
.SYNOPSIS
    Prueba Preflight-Backup.ps1 contra los fixtures de sistema simulado.
.DESCRIPTION
    Ejecuta scripts/validation/Preflight-Backup.ps1 con -SystemInfoPath apuntando
    a cada JSON de tests/fixtures/backup/, compara el Status esperado (campo
    "expectedStatus" del fixture) contra el Status real obtenido y muestra un
    resumen PASS/FAIL por caso. Sale con codigo distinto de 0 si algun caso falla.

    Compatible con Windows PowerShell 5.1, sin dependencias externas.
.EXAMPLE
    .\tests\Test-PreflightBackup.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

if ($PSScriptRoot) {
    $testsRoot = $PSScriptRoot
}
else {
    $testsRoot = (Get-Location).Path
}

$projectRoot = Split-Path -Parent $testsRoot
$validatorPath = Join-Path -Path $projectRoot -ChildPath "scripts\validation\Preflight-Backup.ps1"
$manifestPath = Join-Path -Path $projectRoot -ChildPath "manifests\backup-manifest.json"
$hardwareManifestPath = Join-Path -Path $projectRoot -ChildPath "manifests\hardware-requirements.json"
$fixturesRoot = Join-Path -Path $testsRoot -ChildPath "fixtures\backup"

if (-not (Test-Path -Path $validatorPath -PathType Leaf)) {
    Write-Host "No se encontro el validador en: $validatorPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -Path $fixturesRoot -PathType Container)) {
    Write-Host "No se encontro la carpeta de fixtures de backup en: $fixturesRoot" -ForegroundColor Red
    exit 1
}

$passIcon = [char]::ConvertFromUtf32(0x2705)
$failIcon = [char]::ConvertFromUtf32(0x274C)

Write-Host ""
Write-Host "Test-PreflightBackup" -ForegroundColor Cyan
Write-Host "====================" -ForegroundColor Gray
Write-Host "Validador: $validatorPath"
Write-Host "Manifiesto: $manifestPath"
Write-Host ""

$fixtures = @(Get-ChildItem -Path $fixturesRoot -Filter "*.json" | Sort-Object Name)

if ($fixtures.Count -eq 0) {
    Write-Host "No se encontraron fixtures (*.json) en $fixturesRoot" -ForegroundColor Red
    exit 1
}

$totalCases = 0
$failedCases = 0

foreach ($fixture in $fixtures) {
    $totalCases++
    $fixtureData = Get-Content -Path $fixture.FullName -Raw | ConvertFrom-Json
    $expected = [string]$fixtureData.expectedStatus

    if (-not $expected) {
        Write-Host "$failIcon $($fixture.Name): el fixture no define 'expectedStatus'." -ForegroundColor Red
        $failedCases++
        continue
    }

    # Determine profile based on file name
    $profile = "SystemManager"
    if ($fixture.Name -match "ipc") {
        $profile = "IPC_RIP"
    }

    try {
        $result = & $validatorPath -SystemInfoPath $fixture.FullName -ManifestPath $manifestPath -HardwareManifestPath $hardwareManifestPath -Profile $profile
    }
    catch {
        Write-Host "$failIcon $($fixture.Name): error al ejecutar el validador: $($_.Exception.Message)" -ForegroundColor Red
        $failedCases++
        continue
    }

    $actual = [string]$result.Status

    if ($actual -eq $expected) {
        Write-Host "$passIcon $($fixture.Name) (${profile}): esperado=$expected obtenido=$actual" -ForegroundColor Green
    }
    else {
        Write-Host "$failIcon $($fixture.Name) (${profile}): esperado=$expected obtenido=$actual" -ForegroundColor Red
        $failedCases++
    }

    # Verify structured fields
    if ($result.Sources.Total -le 0) {
        Write-Host "     $failIcon Error: total de fuentes es cero o negativo" -ForegroundColor Red
        $failedCases++
    }
    else {
        Write-Host "     - Fuentes: $($result.Sources.FoundCount) encontradas, $($result.Sources.MissingCount) faltantes de $($result.Sources.Total) totales" -ForegroundColor DarkGray
    }

    if (-not $result.Destination.Path) {
        Write-Host "     $failIcon Error: ruta de destino vacia" -ForegroundColor Red
        $failedCases++
    }
    else {
        Write-Host "     - Destino: $($result.Destination.Path) (Existe: $($result.Destination.Exists), Writable: $($result.Destination.Writable))" -ForegroundColor DarkGray
    }

    if ($profile -eq "SystemManager") {
        Write-Host "     - Herramientas: MOBIUS_HOME definida=$($result.Tools.MobiusHomeDefined), encontradas=$($result.Tools.Found.Count), faltantes=$($result.Tools.Missing.Count)" -ForegroundColor DarkGray
    }

    foreach ($check in @($result.Checks)) {
        Write-Host "       * [$($check.Status)] $($check.Name) -> $($check.Detail)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

Write-Host "---------------------" -ForegroundColor Gray
$passedCases = $totalCases - $failedCases
Write-Host "Resumen: $passedCases de $totalCases casos correctos." -ForegroundColor Cyan

if ($failedCases -gt 0) {
    Write-Host "$failIcon Fallaron $failedCases casos." -ForegroundColor Red
    exit 1
}

Write-Host "$passIcon Todos los casos pasaron." -ForegroundColor Green
exit 0
