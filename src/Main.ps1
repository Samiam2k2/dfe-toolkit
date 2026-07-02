<#
.SYNOPSIS
    Motor principal de DFE Toolkit.
.DESCRIPTION
    Herramienta local para validaciones basicas en Windows con PowerShell 5.1
    o superior.
#>

param(
    [switch]$NoGUI
)

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

function Get-ValidateHardwareCommand {
    [CmdletBinding()]
    param()

    $localScript = $null
    if ($PSScriptRoot) {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $localScript = Join-Path -Path $projectRoot -ChildPath "scripts\validation\Validate-Hardware.ps1"
    }

    if ($localScript -and (Test-Path -Path $localScript -PathType Leaf)) {
        return @{
            Command = $localScript
            IsFile = $true
        }
    }

    $scriptUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/scripts/validation/Validate-Hardware.ps1?cacheBust=$([DateTime]::UtcNow.Ticks)"
    $scriptContent = Invoke-RestMethod -Uri $scriptUrl -Headers @{
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
    } -ErrorAction Stop

    return @{
        Command = [scriptblock]::Create($scriptContent)
        IsFile = $false
    }
}

function Test-DFEHardware {
    [CmdletBinding()]
    param(
        [string]$Product = "Production Pro",
        [string]$Version = "8.3"
    )

    $passIcon = [char]::ConvertFromUtf32(0x2705)
    $failIcon = [char]::ConvertFromUtf32(0x274C)
    $warningIcon = [char]::ConvertFromUtf32(0x26A0) + [char]0xFE0F

    Write-Host ""
    Write-Host "Validacion de hardware" -ForegroundColor Cyan
    Write-Host "----------------------" -ForegroundColor Gray
    Write-Host "Evaluando el servidor contra los requisitos aprobados para $Product $Version."
    Write-Host ""

    try {
        $validator = Get-ValidateHardwareCommand
        $result = & $validator.Command -Product $Product -Version $Version
    }
    catch {
        Write-Host "No se pudo ejecutar la validacion de hardware: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host "Servidor detectado:"
    Write-Host "   Fabricante: $($result.Manufacturer)"
    Write-Host "   Modelo: $($result.Model)"
    Write-Host "   Sistema operativo: $($result.OperatingSystem)"
    Write-Host "   Memoria: $($result.MemoryGB) GB"
    Write-Host "   CPU: sockets $($result.CpuSockets), nucleos $($result.CpuCores)"
    Write-Host ""

    foreach ($check in @($result.Checks)) {
        switch ($check.Status) {
            "Pass" {
                Write-Host "$passIcon [$($check.Status)] $($check.Name)" -ForegroundColor Green
            }
            "Fail" {
                Write-Host "$failIcon [$($check.Status)] $($check.Name)" -ForegroundColor Red
            }
            default {
                Write-Host "$warningIcon [$($check.Status)] $($check.Name)" -ForegroundColor Yellow
            }
        }
        Write-Host "      $($check.Detail)" -ForegroundColor Gray
    }

    Write-Host ""
    switch ($result.Status) {
        "Pass" {
            Write-Host "Resultado: $passIcon hardware compatible (Pass)." -ForegroundColor Green
        }
        "Warning" {
            Write-Host "Resultado: $warningIcon hardware con advertencias (Warning)." -ForegroundColor Yellow
        }
        default {
            Write-Host "Resultado: $failIcon hardware no compatible (Fail)." -ForegroundColor Red
        }
    }

    if ($result.DegradedByMode) {
        Write-Host ""
        Write-Host "Modo informativo (laboratorio): este paso muestra advertencias en vez de bloquear. Cambie validationMode a 'enforcing' en el manifiesto para validar contra un servidor real." -ForegroundColor Yellow
    }
}

function Get-ValidateNetworkCommand {
    [CmdletBinding()]
    param()

    $localScript = $null
    if ($PSScriptRoot) {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $localScript = Join-Path -Path $projectRoot -ChildPath "scripts\validation\Validate-Network.ps1"
    }

    if ($localScript -and (Test-Path -Path $localScript -PathType Leaf)) {
        return @{
            Command = $localScript
            IsFile = $true
        }
    }

    $scriptUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/scripts/validation/Validate-Network.ps1?cacheBust=$([DateTime]::UtcNow.Ticks)"
    $scriptContent = Invoke-RestMethod -Uri $scriptUrl -Headers @{
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
    } -ErrorAction Stop

    return @{
        Command = [scriptblock]::Create($scriptContent)
        IsFile = $false
    }
}

function Test-DFENetwork {
    [CmdletBinding()]
    param()

    $passIcon = [char]::ConvertFromUtf32(0x2705)
    $failIcon = [char]::ConvertFromUtf32(0x274C)
    $warningIcon = [char]::ConvertFromUtf32(0x26A0) + [char]0xFE0F

    Write-Host ""
    Write-Host "Validacion de red" -ForegroundColor Cyan
    Write-Host "-----------------" -ForegroundColor Gray
    Write-Host "Evaluando adaptadores, IP estatica, metricas y archivo hosts contra el manifiesto."
    Write-Host ""

    try {
        $validator = Get-ValidateNetworkCommand
        $result = & $validator.Command
    }
    catch {
        Write-Host "No se pudo ejecutar la validacion de red: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host "Adaptadores:"
    Write-Host "   Esperados: $($result.Adapters.Expected -join ', ')"
    if ($result.Adapters.MissingExpected.Count -gt 0) {
        Write-Host "   Faltantes: $($result.Adapters.MissingExpected -join ', ')" -ForegroundColor Yellow
    }
    else {
        Write-Host "   Faltantes: ninguno"
    }
    if ($result.Adapters.Unexpected.Count -gt 0) {
        Write-Host "   No esperados: $($result.Adapters.Unexpected -join ', ')"
    }
    else {
        Write-Host "   No esperados: ninguno"
    }
    Write-Host ""

    foreach ($check in @($result.Checks)) {
        switch ($check.Status) {
            "Pass" {
                Write-Host "$passIcon [$($check.Status)] $($check.Name)" -ForegroundColor Green
            }
            "Fail" {
                Write-Host "$failIcon [$($check.Status)] $($check.Name)" -ForegroundColor Red
            }
            default {
                Write-Host "$warningIcon [$($check.Status)] $($check.Name)" -ForegroundColor Yellow
            }
        }
        Write-Host "      $($check.Detail)" -ForegroundColor Gray
    }

    Write-Host ""
    switch ($result.Status) {
        "Pass" {
            Write-Host "Resultado: $passIcon red conforme (Pass)." -ForegroundColor Green
        }
        "Warning" {
            Write-Host "Resultado: $warningIcon red completada con advertencias (Warning)." -ForegroundColor Yellow
        }
        default {
            Write-Host "Resultado: $failIcon red no conforme (Fail)." -ForegroundColor Red
        }
    }
}

function Get-ValidateOperatingSystemCommand {
    [CmdletBinding()]
    param()

    $localScript = $null
    if ($PSScriptRoot) {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $localScript = Join-Path -Path $projectRoot -ChildPath "scripts\validation\Validate-OperatingSystem.ps1"
    }

    if ($localScript -and (Test-Path -Path $localScript -PathType Leaf)) {
        return @{
            Command = $localScript
            IsFile = $true
        }
    }

    $scriptUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/scripts/validation/Validate-OperatingSystem.ps1?cacheBust=$([DateTime]::UtcNow.Ticks)"
    $scriptContent = Invoke-RestMethod -Uri $scriptUrl -Headers @{
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
    } -ErrorAction Stop

    return @{
        Command = [scriptblock]::Create($scriptContent)
        IsFile = $false
    }
}

function Test-DFEOperatingSystem {
    [CmdletBinding()]
    param(
        [string]$Product = "Production Pro",
        [string]$Version = "8.3"
    )

    $passIcon = [char]::ConvertFromUtf32(0x2705)
    $failIcon = [char]::ConvertFromUtf32(0x274C)
    $warningIcon = [char]::ConvertFromUtf32(0x26A0) + [char]0xFE0F

    Write-Host ""
    Write-Host "Validacion de sistema operativo" -ForegroundColor Cyan
    Write-Host "-------------------------------" -ForegroundColor Gray
    Write-Host "Evaluando version y arquitectura del SO contra el hardware detectado para $Product $Version."
    Write-Host ""

    try {
        $validator = Get-ValidateOperatingSystemCommand
        $result = & $validator.Command -Product $Product -Version $Version
    }
    catch {
        Write-Host "No se pudo ejecutar la validacion de sistema operativo: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host "Servidor detectado:"
    Write-Host "   Fabricante: $($result.Manufacturer)"
    Write-Host "   Modelo: $($result.Model)"
    Write-Host "   Sistema operativo: $($result.OperatingSystem)"
    Write-Host "   Arquitectura: $($result.OSArchitecture)"
    Write-Host ""

    foreach ($check in @($result.Checks)) {
        switch ($check.Status) {
            "Pass" {
                Write-Host "$passIcon [$($check.Status)] $($check.Name)" -ForegroundColor Green
            }
            "Fail" {
                Write-Host "$failIcon [$($check.Status)] $($check.Name)" -ForegroundColor Red
            }
            default {
                Write-Host "$warningIcon [$($check.Status)] $($check.Name)" -ForegroundColor Yellow
            }
        }
        Write-Host "      $($check.Detail)" -ForegroundColor Gray
    }

    Write-Host ""
    switch ($result.Status) {
        "Pass" {
            Write-Host "Resultado: $passIcon sistema operativo conforme (Pass)." -ForegroundColor Green
        }
        "Warning" {
            Write-Host "Resultado: $warningIcon sistema operativo con advertencias (Warning)." -ForegroundColor Yellow
        }
        default {
            Write-Host "Resultado: $failIcon sistema operativo no conforme (Fail)." -ForegroundColor Red
        }
    }

    if ($result.DegradedByMode) {
        Write-Host ""
        Write-Host "Modo informativo (laboratorio): este paso muestra advertencias en vez de bloquear. Cambie validationMode a 'enforcing' en el manifiesto para validar contra un servidor real." -ForegroundColor Yellow
    }
}

function Get-ValidateStorageCommand {
    [CmdletBinding()]
    param()

    $localScript = $null
    if ($PSScriptRoot) {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $localScript = Join-Path -Path $projectRoot -ChildPath "scripts\validation\Validate-Storage.ps1"
    }

    if ($localScript -and (Test-Path -Path $localScript -PathType Leaf)) {
        return @{
            Command = $localScript
            IsFile = $true
        }
    }

    $scriptUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/scripts/validation/Validate-Storage.ps1?cacheBust=$([DateTime]::UtcNow.Ticks)"
    $scriptContent = Invoke-RestMethod -Uri $scriptUrl -Headers @{
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
    } -ErrorAction Stop

    return @{
        Command = [scriptblock]::Create($scriptContent)
        IsFile = $false
    }
}

function Test-DFEStorage {
    [CmdletBinding()]
    param(
        [string]$Product = "Production Pro",
        [string]$Version = "8.3",
        [string]$Profile = "SystemManager"
    )

    $passIcon = [char]::ConvertFromUtf32(0x2705)
    $failIcon = [char]::ConvertFromUtf32(0x274C)
    $warningIcon = [char]::ConvertFromUtf32(0x26A0) + [char]0xFE0F
    $infoIcon = [char]::ConvertFromUtf32(0x2139) + [char]0xFE0F

    Write-Host ""
    Write-Host "Validacion de almacenamiento" -ForegroundColor Cyan
    Write-Host "----------------------------" -ForegroundColor Gray
    Write-Host "Evaluando espacio libre, layout y ruta de backup contra el manifiesto para $Product $Version ($Profile)."
    Write-Host ""

    try {
        $validator = Get-ValidateStorageCommand
        $result = & $validator.Command -Product $Product -Version $Version -Profile $Profile
    }
    catch {
        Write-Host "No se pudo ejecutar la validacion de almacenamiento: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host "Unidades detectadas:"
    Write-Host "   Esperadas: $($result.Drives.Expected -join ', ')"
    if ($result.Drives.MissingExpected.Count -gt 0) {
        Write-Host "   Faltantes: $($result.Drives.MissingExpected -join ', ')" -ForegroundColor Yellow
    }
    else {
        Write-Host "   Faltantes: ninguna"
    }
    if ($result.Drives.Unexpected.Count -gt 0) {
        Write-Host "   No esperadas: $($result.Drives.Unexpected -join ', ')"
    }
    else {
        Write-Host "   No esperadas: ninguna"
    }
    Write-Host ""

    foreach ($check in @($result.Checks)) {
        switch ($check.Status) {
            "Pass" {
                Write-Host "$passIcon [$($check.Status)] $($check.Name)" -ForegroundColor Green
            }
            "Fail" {
                Write-Host "$failIcon [$($check.Status)] $($check.Name)" -ForegroundColor Red
            }
            "Info" {
                Write-Host "$infoIcon [$($check.Status)] $($check.Name)" -ForegroundColor Cyan
            }
            default {
                Write-Host "$warningIcon [$($check.Status)] $($check.Name)" -ForegroundColor Yellow
            }
        }
        Write-Host "      $($check.Detail)" -ForegroundColor Gray
    }

    Write-Host ""
    switch ($result.Status) {
        "Pass" {
            Write-Host "Resultado: $passIcon almacenamiento conforme (Pass)." -ForegroundColor Green
        }
        "Warning" {
            Write-Host "Resultado: $warningIcon almacenamiento completado con advertencias (Warning)." -ForegroundColor Yellow
        }
        default {
            Write-Host "Resultado: $failIcon almacenamiento no conforme (Fail)." -ForegroundColor Red
        }
    }

    if ($result.DegradedByMode) {
        Write-Host ""
        Write-Host "Modo informativo (laboratorio): este paso muestra advertencias en vez de bloquear. Cambie validationMode a 'enforcing' en el manifiesto de hardware para validar contra un servidor real." -ForegroundColor Yellow
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
    Write-Host "$checkIcon Verificaci$($oAcuteLower)n de almacenamiento: COMPLETADA" -ForegroundColor Green
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
        Write-Host "3. Validar Sistema Operativo"
        Write-Host "4. Validar Almacenamiento"
        Write-Host "5. Salir"
        Write-Host "6. Ver resumen de instalacion"
        Write-Host "7. Abrir interfaz grafica"
        Write-Host ""

        $option = Read-Host "Seleccione una opcion"

        switch ($option) {
            "1" {
                Get-SystemInfo
                Test-DFEHardware
            }
            "2" {
                Test-DFENetwork
            }
            "3" {
                Test-DFEOperatingSystem
            }
            "4" {
                Test-DFEStorage
            }
            "5" {
                Write-Host "Saliendo de DFE Toolkit."
            }
            "6" {
                Show-DemoSummary
            }
            "7" {
                Invoke-DFEGui
            }
            default {
                Write-Host "Opcion invalida. Intente nuevamente." -ForegroundColor Yellow
            }
        }
    } while ($option -ne "5")
}

function Invoke-DFEGui {
    [CmdletBinding()]
    param()

    $guiScript = $null
    if ($PSScriptRoot) {
        $guiScript = Join-Path -Path $PSScriptRoot -ChildPath "Gui.ps1"
    }

    if ($guiScript -and (Test-Path -Path $guiScript -PathType Leaf)) {
        & $guiScript
        return
    }

    $guiScriptBaseUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/src/Gui.ps1"
    $cacheBust = [DateTime]::UtcNow.Ticks
    $guiScriptUrl = "$guiScriptBaseUrl`?cacheBust=$cacheBust"
    $headers = @{
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
    }

    Write-Host "Descargando interfaz grafica desde GitHub..." -ForegroundColor Cyan
    $guiContent = Invoke-RestMethod -Uri $guiScriptUrl -Headers $headers -ErrorAction Stop
    $guiBlock = [scriptblock]::Create($guiContent)
    & $guiBlock
}

if ($NoGUI) {
    Show-Menu
}
else {
    try {
        Invoke-DFEGui
    }
    catch {
        Write-Host ""
        Write-Host "No se pudo abrir la interfaz grafica: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Puede ejecutar el menu de texto como alternativa." -ForegroundColor Yellow
        $answer = Read-Host "Desea abrir el menu de texto ahora? (S/N)"

        if ($answer -match "^[sSyY]") {
            Show-Menu
        }
        else {
            Write-Host "Ejecucion finalizada." -ForegroundColor Gray
        }
    }
}
