<#
.SYNOPSIS
    DFE-Toolkit Main Engine
.DESCRIPTION
    Motor principal de la herramienta de instalación de DFE.
#>

Write-Host "`n📋 DFE-Toolkit Main Engine v0.1" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Gray

# --- Información del Sistema ---
Write-Host "`n💻 Información del Sistema:" -ForegroundColor Yellow

try {
    $computerInfo = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $biosInfo = Get-CimInstance -ClassName Win32_BIOS -ErrorAction SilentlyContinue
} catch {
    Write-Error "❌ No se pudo obtener información del sistema: $_"
    exit 1
}

Write-Host "   Equipo: $($computerInfo.Name)" -ForegroundColor White
Write-Host "   Modelo: $($computerInfo.Model)" -ForegroundColor White
Write-Host "   Fabricante: $($computerInfo.Manufacturer)" -ForegroundColor White
Write-Host "   Serial: $($biosInfo.SerialNumber)" -ForegroundColor White
Write-Host "   SO: $($osInfo.Caption)" -ForegroundColor White
Write-Host "   RAM Total: $([math]::Round($computerInfo.TotalPhysicalMemory / 1GB, 2)) GB" -ForegroundColor White

# --- Detección de servidor DFE ---
Write-Host "`n🔍 Verificando si es un servidor DFE..." -ForegroundColor Yellow

$dfeIndicators = @(
    @{Name="Indigo"; Path="HKLM:\SOFTWARE\Indigo"},
    @{Name="HP DFE"; Path="HKLM:\SOFTWARE\HP\DFE"},
    @{Name="Production Pro"; Path="HKLM:\SOFTWARE\HP\ProductionPro"},
    @{Name="Matrix"; Path="HKLM:\SOFTWARE\Wow6432Node\Indigo\Matrix"},
    @{Name="ProdFlow"; Path="C:\prodflow"}
)

$isDFE = $false
$foundIndicators = @()

foreach ($indicator in $dfeIndicators) {
    if (Test-Path $indicator.Path) {
        $isDFE = $true
        $foundIndicators += $indicator.Name
    }
}

if ($isDFE) {
    Write-Host "✅ ¡ESTE ES UN SERVIDOR DFE!" -ForegroundColor Green
    Write-Host "   Indicadores encontrados: $($foundIndicators -join ', ')" -ForegroundColor Gray
} else {
    Write-Host "⚠️  No se detectaron indicadores DFE" -ForegroundColor Yellow
    Write-Host "   Este servidor NO parece ser un DFE o está sin instalar." -ForegroundColor Yellow
}

Write-Host "`n✅ Verificación completada!" -ForegroundColor Green
