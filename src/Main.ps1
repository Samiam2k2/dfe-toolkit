<#
.SYNOPSIS
    Motor principal de DFE Toolkit.
.DESCRIPTION
    Herramienta local para validaciones basicas en Windows con PowerShell 5.1
    o superior.
#>

function Get-SystemInfo {
    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host "Informacion del sistema" -ForegroundColor Cyan
    Write-Host "-----------------------" -ForegroundColor Gray

    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $memoryGb = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)

        Write-Host "Equipo: $($computerSystem.Name)"
        Write-Host "Modelo: $($computerSystem.Model)"
        Write-Host "Sistema operativo: $($operatingSystem.Caption) $($operatingSystem.Version)"
        Write-Host "RAM total: $memoryGb GB"
    }
    catch {
        Write-Host "No se pudo obtener la informacion del sistema: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Test-DFEServer {
    [CmdletBinding()]
    param()

    $dfeIndicators = @(
        @{Name="Indigo"; Path="HKLM:\SOFTWARE\Indigo"},
        @{Name="HP DFE"; Path="HKLM:\SOFTWARE\HP\DFE"},
        @{Name="Production Pro"; Path="HKLM:\SOFTWARE\HP\ProductionPro"},
        @{Name="Matrix"; Path="HKLM:\SOFTWARE\Wow6432Node\Indigo\Matrix"},
        @{Name="ProdFlow"; Path="C:\prodflow"}
    )

    Write-Host ""
    Write-Host "Validacion de servidor DFE" -ForegroundColor Cyan
    Write-Host "--------------------------" -ForegroundColor Gray
    Write-Host "Revisando claves de registro y rutas tipicas de DFE HP Indigo en Windows."
    Write-Host ""

    $foundIndicators = @()

    foreach ($indicator in $dfeIndicators) {
        if (Test-Path -Path $indicator.Path) {
            $foundIndicators += $indicator
            Write-Host "[OK] $($indicator.Name): $($indicator.Path)" -ForegroundColor Green
        }
        else {
            Write-Host "[--] $($indicator.Name): $($indicator.Path)" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    if ($foundIndicators.Count -gt 0) {
        $names = $foundIndicators | ForEach-Object { $_.Name }
        Write-Host "Resultado: posible servidor DFE detectado." -ForegroundColor Green
        Write-Host "Indicadores encontrados: $($names -join ', ')"
    }
    else {
        Write-Host "Resultado: no se detectaron indicadores DFE en este equipo." -ForegroundColor Yellow
    }
}

function Test-Network {
    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host "Validacion de red" -ForegroundColor Cyan
    Write-Host "-----------------" -ForegroundColor Gray

    try {
        $adapters = Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq "Up" }

        if (-not $adapters) {
            Write-Host "No se encontraron adaptadores fisicos activos." -ForegroundColor Yellow
            return
        }

        foreach ($adapter in $adapters) {
            $ipAddresses = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.IPAddress -and $_.IPAddress -notlike "169.254.*" }

            if ($ipAddresses) {
                foreach ($ip in $ipAddresses) {
                    Write-Host "   $($adapter.Name): $($ip.IPAddress)"
                }
            }
            else {
                Write-Host "   $($adapter.Name): sin direccion IPv4 asignada" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "No se pudo validar la red con Get-NetAdapter: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Show-DemoSummary {
    [CmdletBinding()]
    param()

    $chartIcon = [char]::ConvertFromUtf32(0x1F4CA)
    $checkIcon = [char]::ConvertFromUtf32(0x2705)
    $pendingIcon = [char]::ConvertFromUtf32(0x23F3)
    $ideaIcon = [char]::ConvertFromUtf32(0x1F4A1)
    $oAcuteUpper = [char]0x00D3
    $oAcuteLower = [char]0x00F3

    Write-Host ""
    Write-Host "$chartIcon RESUMEN DE LA INSTALACI$($oAcuteUpper)N DEMO:" -ForegroundColor Cyan
    Write-Host "====================================="
    Write-Host "$checkIcon Verificaci$($oAcuteLower)n de hardware: COMPLETADA" -ForegroundColor Green
    Write-Host "$checkIcon Verificaci$($oAcuteLower)n de red: COMPLETADA" -ForegroundColor Green
    Write-Host "$pendingIcon Instalaci$($oAcuteLower)n de prerequisitos: PENDIENTE (modo demo)" -ForegroundColor Yellow
    Write-Host "$pendingIcon Instalaci$($oAcuteLower)n de software principal: PENDIENTE (modo demo)" -ForegroundColor Yellow
    Write-Host "$ideaIcon Este es un modo de demostraci$($oAcuteLower)n." -ForegroundColor Cyan
}

function Show-Menu {
    [CmdletBinding()]
    param()

    do {
        Write-Host ""
        Write-Host "DFE Toolkit" -ForegroundColor Cyan
        Write-Host "==========="
        Write-Host "1. Validar Hardware"
        Write-Host "2. Validar Red"
        Write-Host "3. Salir"
        Write-Host "4. Ver resumen de instalacion"
        Write-Host ""

        $option = Read-Host "Seleccione una opcion"

        switch ($option) {
            "1" {
                Get-SystemInfo
                Test-DFEServer
            }
            "2" {
                Test-Network
            }
            "3" {
                Write-Host "Saliendo de DFE Toolkit."
            }
            "4" {
                Show-DemoSummary
            }
            default {
                Write-Host "Opcion invalida. Intente nuevamente." -ForegroundColor Yellow
            }
        }
    } while ($option -ne "3")
}

Show-Menu
