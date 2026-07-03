<#
.SYNOPSIS
    Prueba Validate-Specifications.ps1 contra los fixtures de sistema simulado.
.DESCRIPTION
    Ejecuta scripts/validation/Validate-Specifications.ps1 con -SystemInfoPath
    apuntando a los JSON de tests/fixtures/specs/, compara el Status esperado
    contra el obtenido y muestra el reporte checklist consolidado.
    Sale con codigo distinto de 0 si algun caso falla.
.EXAMPLE
    .\tests\Test-ValidateSpecifications.ps1
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
$validatorPath = Join-Path -Path $projectRoot -ChildPath "scripts\validation\Validate-Specifications.ps1"
$fixturesRoot = Join-Path -Path $testsRoot -ChildPath "fixtures\specs"

$manifestPaths = @{
    hardware = Join-Path -Path $projectRoot -ChildPath "manifests\production-pro\8.3\hardware.json"
    network = Join-Path -Path $projectRoot -ChildPath "manifests\production-pro\8.3\network.json"
    storage = Join-Path -Path $projectRoot -ChildPath "manifests\production-pro\8.3\storage.json"
    security = Join-Path -Path $projectRoot -ChildPath "manifests\production-pro\8.3\security.json"
    assessment = Join-Path -Path $projectRoot -ChildPath "manifests\production-pro\8.3\assessment-checks.json"
}

if (-not (Test-Path -Path $validatorPath -PathType Leaf)) {
    Write-Host "No se encontro el validador en: $validatorPath" -ForegroundColor Red
    exit 1
}

$passIcon = [char]::ConvertFromUtf32(0x2705)
$failIcon = [char]::ConvertFromUtf32(0x274C)

Write-Host ""
Write-Host "Test-ValidateSpecifications" -ForegroundColor Cyan
Write-Host "===========================" -ForegroundColor Gray
Write-Host "Orquestador: $validatorPath"
Write-Host ""

$fixtures = @("combined-ok.json", "combined-fail.json")
$failedCases = 0
$totalCases = 0

foreach ($fixtureName in $fixtures) {
    $totalCases++
    $fixturePath = Join-Path -Path $fixturesRoot -ChildPath $fixtureName
    
    if (-not (Test-Path -Path $fixturePath -PathType Leaf)) {
        Write-Host "$failIcon No se encontro el fixture: $fixturePath" -ForegroundColor Red
        $failedCases++
        continue
    }

    $fixtureData = Get-Content -Path $fixturePath -Raw | ConvertFrom-Json
    $expected = [string]$fixtureData.expectedStatus

    try {
        $result = & $validatorPath -Product "Production Pro" -Version "8.3" -Model "commercial" -ManifestPaths $manifestPaths -SystemInfoPath $fixturePath
        $actual = [string]$result.Status

        # Para combined-ok, como es validationMode informational por defecto en el manifiesto,
        # un Fail bloqueante se degradaria pero no tenemos Fails bloqueantes.
        # check-hosts-file puede dar Warning o Pass. En cualquier caso, comparamos contra expectedStatus.
        if ($actual -eq $expected) {
            Write-Host "$passIcon ${fixtureName}: esperado=$expected obtenido=$actual" -ForegroundColor Green
        }
        else {
            Write-Host "$failIcon ${fixtureName}: esperado=$expected obtenido=$actual" -ForegroundColor Red
            $failedCases++
        }

        Write-Host "Checklist devuelto:" -ForegroundColor Gray
        Write-Host $result.Text
        Write-Host ""
    }
    catch {
        Write-Host "$failIcon ${fixtureName}: error al ejecutar el orquestador: $($_.Exception.Message)" -ForegroundColor Red
        $failedCases++
    }
}

Write-Host "----------------------------" -ForegroundColor Gray
$passedCases = $totalCases - $failedCases
Write-Host "Resumen: $passedCases de $totalCases casos correctos." -ForegroundColor Cyan

if ($failedCases -gt 0) {
    exit 1
}
exit 0
