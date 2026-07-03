<#
.SYNOPSIS
    Prueba Validate-Hardware.ps1 contra los fixtures de sistema simulado.
.DESCRIPTION
    Ejecuta scripts/validation/Validate-Hardware.ps1 con -SystemInfoPath apuntando
    a cada JSON de tests/fixtures/, compara el Status esperado (campo
    "expectedStatus" del fixture) contra el Status real obtenido y muestra un
    resumen PASS/FAIL por caso. Sale con codigo distinto de 0 si algun caso falla.

    Compatible con Windows PowerShell 5.1, sin dependencias externas.
.EXAMPLE
    .\tests\Test-ValidateHardware.ps1
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
$validatorPath = Join-Path -Path $projectRoot -ChildPath "scripts\validation\Validate-Hardware.ps1"
$manifestPath = Join-Path -Path $projectRoot -ChildPath "manifests\production-pro\8.3\hardware.json"
$fixturesRoot = Join-Path -Path $testsRoot -ChildPath "fixtures"

if (-not (Test-Path -Path $validatorPath -PathType Leaf)) {
    Write-Host "No se encontro el validador en: $validatorPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -Path $fixturesRoot -PathType Container)) {
    Write-Host "No se encontro la carpeta de fixtures en: $fixturesRoot" -ForegroundColor Red
    exit 1
}

$passIcon = [char]::ConvertFromUtf32(0x2705)
$failIcon = [char]::ConvertFromUtf32(0x274C)

Write-Host ""
Write-Host "Test-ValidateHardware" -ForegroundColor Cyan
Write-Host "=====================" -ForegroundColor Gray
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

    try {
        $result = & $validatorPath -SystemInfoPath $fixture.FullName -ManifestPath $manifestPath
    }
    catch {
        Write-Host "$failIcon $($fixture.Name): error al ejecutar el validador: $($_.Exception.Message)" -ForegroundColor Red
        $failedCases++
        continue
    }

    $actual = [string]$result.Status

    if ($actual -eq $expected) {
        Write-Host "$passIcon $($fixture.Name): esperado=$expected obtenido=$actual" -ForegroundColor Green
    }
    else {
        Write-Host "$failIcon $($fixture.Name): esperado=$expected obtenido=$actual" -ForegroundColor Red
        $failedCases++
    }

    foreach ($check in @($result.Checks)) {
        Write-Host "     - [$($check.Status)] $($check.Id): $($check.Detail)" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# --- Caso extra: modo enforcing ---
# El manifiesto por defecto esta en validationMode "informational", que degrada
# los Fail bloqueantes a Warning. Para no perder cobertura del caso bloqueante,
# se corre dell-incompatible.json contra un manifiesto de prueba con
# validationMode "enforcing" y se verifica que ahi SI de Fail (RealStatus Fail).
$enforcingManifest = Join-Path -Path $fixturesRoot -ChildPath "manifests\hardware-requirements-enforcing.json"
$dellFixture = Join-Path -Path $fixturesRoot -ChildPath "dell-incompatible.json"

if ((Test-Path -Path $enforcingManifest -PathType Leaf) -and (Test-Path -Path $dellFixture -PathType Leaf)) {
    $totalCases++
    $expectedEnforcing = "Fail"

    try {
        $enforcingResult = & $validatorPath -SystemInfoPath $dellFixture -ManifestPath $enforcingManifest
        $actualEnforcing = [string]$enforcingResult.Status

        if ($actualEnforcing -eq $expectedEnforcing) {
            Write-Host "$passIcon dell-incompatible.json (enforcing): esperado=$expectedEnforcing obtenido=$actualEnforcing" -ForegroundColor Green
        }
        else {
            Write-Host "$failIcon dell-incompatible.json (enforcing): esperado=$expectedEnforcing obtenido=$actualEnforcing" -ForegroundColor Red
            $failedCases++
        }

        Write-Host "     - RealStatus=$($enforcingResult.RealStatus) ValidationMode=$($enforcingResult.ValidationMode) DegradedByMode=$($enforcingResult.DegradedByMode)" -ForegroundColor DarkGray
    }
    catch {
        Write-Host "$failIcon dell-incompatible.json (enforcing): error al ejecutar el validador: $($_.Exception.Message)" -ForegroundColor Red
        $failedCases++
    }
    Write-Host ""
}
else {
    Write-Host "$failIcon No se encontro el manifiesto enforcing o el fixture dell para el caso extra." -ForegroundColor Red
    $totalCases++
    $failedCases++
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
