<#
.SYNOPSIS
    Prueba Validate-Storage.ps1 contra los fixtures de sistema simulado.
.DESCRIPTION
    Ejecuta scripts/validation/Validate-Storage.ps1 con -SystemInfoPath apuntando
    a cada JSON de tests/fixtures/storage/, compara el Status esperado (campo
    "expectedStatus" del fixture) contra el Status real obtenido y muestra un
    resumen PASS/FAIL por caso. Sale con codigo distinto de 0 si algun caso falla.

    Compatible con Windows PowerShell 5.1, sin dependencias externas.
.EXAMPLE
    .\tests\Test-ValidateStorage.ps1
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
$validatorPath = Join-Path -Path $projectRoot -ChildPath "scripts\validation\Validate-Storage.ps1"
$manifestPath = Join-Path -Path $projectRoot -ChildPath "manifests\production-pro\8.3\storage.json"
$assessmentPath = Join-Path -Path $projectRoot -ChildPath "manifests\production-pro\8.3\assessment-checks.json"
$hardwareManifestPath = Join-Path -Path $projectRoot -ChildPath "manifests\production-pro\8.3\hardware.json"
$fixturesRoot = Join-Path -Path $testsRoot -ChildPath "fixtures\storage"

if (-not (Test-Path -Path $validatorPath -PathType Leaf)) {
    Write-Host "No se encontro el validador en: $validatorPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -Path $fixturesRoot -PathType Container)) {
    Write-Host "No se encontro la carpeta de fixtures de storage en: $fixturesRoot" -ForegroundColor Red
    exit 1
}

$passIcon = [char]::ConvertFromUtf32(0x2705)
$failIcon = [char]::ConvertFromUtf32(0x274C)

Write-Host ""
Write-Host "Test-ValidateStorage" -ForegroundColor Cyan
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

    try {
        # Como los validadores cargan hardware-requirements.json para saber el validationMode,
        # le pasamos -HardwareManifestPath explicitamente para que apunte al manifiesto local del repo
        $result = & $validatorPath -SystemInfoPath $fixture.FullName -ManifestPath $manifestPath -AssessmentPath $assessmentPath -HardwareManifestPath $hardwareManifestPath
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
# El manifiesto de hardware por defecto esta en validationMode "informational",
# que degrada los Fails bloqueantes a Warning. Probamos con un manifiesto enforcing.
$hardwareEnforcing = Join-Path -Path $testsRoot -ChildPath "fixtures\manifests\hardware-requirements-enforcing.json"
$storageEnforcing = Join-Path -Path $testsRoot -ChildPath "fixtures\manifests\storage-requirements-enforcing.json"
$okFixture = Join-Path -Path $fixturesRoot -ChildPath "storage-ok.json"

if ((Test-Path -Path $hardwareEnforcing -PathType Leaf) -and (Test-Path -Path $storageEnforcing -PathType Leaf) -and (Test-Path -Path $okFixture -PathType Leaf)) {
    $totalCases++
    $expectedEnforcing = "Fail"

    try {
        $enforcingResult = & $validatorPath -SystemInfoPath $okFixture -ManifestPath $storageEnforcing -AssessmentPath $assessmentPath -HardwareManifestPath $hardwareEnforcing
        $actualEnforcing = [string]$enforcingResult.Status

        if ($actualEnforcing -eq $expectedEnforcing) {
            Write-Host "$passIcon storage-ok.json (enforcing): esperado=$expectedEnforcing obtenido=$actualEnforcing" -ForegroundColor Green
        }
        else {
            Write-Host "$failIcon storage-ok.json (enforcing): esperado=$expectedEnforcing obtenido=$actualEnforcing" -ForegroundColor Red
            $failedCases++
        }

        Write-Host "     - RealStatus=$($enforcingResult.RealStatus) ValidationMode=$($enforcingResult.ValidationMode) DegradedByMode=$($enforcingResult.DegradedByMode)" -ForegroundColor DarkGray
    }
    catch {
        Write-Host "$failIcon storage-ok.json (enforcing): error al ejecutar el validador: $($_.Exception.Message)" -ForegroundColor Red
        $failedCases++
    }
    Write-Host ""
}
else {
    Write-Host "$failIcon No se encontro el manifiesto enforcing o el fixture storage-ok para el caso extra." -ForegroundColor Red
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
