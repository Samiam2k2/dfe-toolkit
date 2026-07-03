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
        [string]$Version = "8.3",
        [string]$ManifestPath
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
        $arguments = @{
            Product = $Product
            Version = $Version
        }
        if ($ManifestPath) {
            $arguments["ManifestPath"] = $ManifestPath
        }
        $result = & $validator.Command @arguments
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
    param(
        [string]$ManifestPath,
        [string]$AssessmentPath
    )

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
        $arguments = @{}
        if ($ManifestPath) {
            $arguments["ManifestPath"] = $ManifestPath
        }
        if ($AssessmentPath) {
            $arguments["AssessmentPath"] = $AssessmentPath
        }
        $result = & $validator.Command @arguments
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
        [string]$Version = "8.3",
        [string]$ManifestPath,
        [string]$AssessmentPath
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
        $arguments = @{
            Product = $Product
            Version = $Version
        }
        if ($ManifestPath) {
            $arguments["ManifestPath"] = $ManifestPath
        }
        if ($AssessmentPath) {
            $arguments["AssessmentPath"] = $AssessmentPath
        }
        $result = & $validator.Command @arguments
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
        [string]$Profile = "SystemManager",
        [string]$ManifestPath,
        [string]$AssessmentPath,
        [string]$HardwareManifestPath
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
        $arguments = @{
            Product = $Product
            Version = $Version
            Profile = $Profile
        }
        if ($ManifestPath) {
            $arguments["ManifestPath"] = $ManifestPath
        }
        if ($AssessmentPath) {
            $arguments["AssessmentPath"] = $AssessmentPath
        }
        if ($HardwareManifestPath) {
            $arguments["HardwareManifestPath"] = $HardwareManifestPath
        }
        $result = & $validator.Command @arguments
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

function Get-ValidateSecurityCommand {
    [CmdletBinding()]
    param()

    $localScript = $null
    if ($PSScriptRoot) {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $localScript = Join-Path -Path $projectRoot -ChildPath "scripts\validation\Validate-Security.ps1"
    }

    if ($localScript -and (Test-Path -Path $localScript -PathType Leaf)) {
        return @{
            Command = $localScript
            IsFile = $true
        }
    }

    $scriptUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/scripts/validation/Validate-Security.ps1?cacheBust=$([DateTime]::UtcNow.Ticks)"
    $scriptContent = Invoke-RestMethod -Uri $scriptUrl -Headers @{
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
    } -ErrorAction Stop

    return @{
        Command = [scriptblock]::Create($scriptContent)
        IsFile = $false
    }
}

function Test-DFESecurity {
    [CmdletBinding()]
    param(
        [string]$Product = "Production Pro",
        [string]$Version = "8.3",
        [string]$ManifestPath,
        [string]$AssessmentPath,
        [string]$HardwareManifestPath
    )

    $passIcon = [char]::ConvertFromUtf32(0x2705)
    $failIcon = [char]::ConvertFromUtf32(0x274C)
    $warningIcon = [char]::ConvertFromUtf32(0x26A0) + [char]0xFE0F
    $infoIcon = [char]::ConvertFromUtf32(0x2139) + [char]0xFE0F

    Write-Host ""
    Write-Host "Validacion de seguridad" -ForegroundColor Cyan
    Write-Host "-----------------------" -ForegroundColor Gray
    Write-Host "Evaluando privilegios de administrador, UAC y perfiles de firewall para $Product $Version."
    Write-Host ""

    try {
        $validator = Get-ValidateSecurityCommand
        $arguments = @{
            Product = $Product
            Version = $Version
        }
        if ($ManifestPath) {
            $arguments["ManifestPath"] = $ManifestPath
        }
        if ($AssessmentPath) {
            $arguments["AssessmentPath"] = $AssessmentPath
        }
        if ($HardwareManifestPath) {
            $arguments["HardwareManifestPath"] = $HardwareManifestPath
        }
        $result = & $validator.Command @arguments
    }
    catch {
        Write-Host "No se pudo ejecutar la validacion de seguridad: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    $isAdminStr = if ($result.Security.isAdmin) { "si" } else { "no" }
    Write-Host "Estado de seguridad detectado:"
    Write-Host "   Administrador: ${isAdminStr}"
    
    $uacStr = "desconocido"
    if ($null -ne $result.Security.uacEnabled) {
        $uacStr = if ($result.Security.uacEnabled) { "activo" } else { "desactivado" }
    }
    Write-Host "   UAC: ${uacStr}"

    $firewallDetails = @()
    foreach ($p in @($result.Security.firewallProfiles)) {
        $nameStr = $p.Name
        $stateStr = if ($p.Enabled) { "activo" } else { "desactivado" }
        $firewallDetails += "${nameStr}: ${stateStr}"
    }
    if ($firewallDetails.Count -gt 0) {
        Write-Host "   Firewall: $($firewallDetails -join '; ')"
    }
    else {
        Write-Host "   Firewall: sin perfiles detectados"
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
            Write-Host "Resultado: $passIcon seguridad conforme (Pass)." -ForegroundColor Green
        }
        "Warning" {
            Write-Host "Resultado: $warningIcon seguridad completada con advertencias (Warning)." -ForegroundColor Yellow
        }
        default {
            Write-Host "Resultado: $failIcon seguridad no conforme (Fail)." -ForegroundColor Red
        }
    }

    if ($result.DegradedByMode) {
        Write-Host ""
        Write-Host "Modo informativo (laboratorio): este paso muestra advertencias en vez de bloquear. Cambie validationMode a 'enforcing' en el manifiesto de hardware para validar contra un servidor real." -ForegroundColor Yellow
    }
}

function Get-ValidateBackupCommand {
    [CmdletBinding()]
    param()

    $localScript = $null
    if ($PSScriptRoot) {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $localScript = Join-Path -Path $projectRoot -ChildPath "scripts\validation\Preflight-Backup.ps1"
    }

    if ($localScript -and (Test-Path -Path $localScript -PathType Leaf)) {
        return @{
            Command = $localScript
            IsFile = $true
        }
    }

    $scriptUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/scripts/validation/Preflight-Backup.ps1?cacheBust=$([DateTime]::UtcNow.Ticks)"
    $scriptContent = Invoke-RestMethod -Uri $scriptUrl -Headers @{
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
    } -ErrorAction Stop

    return @{
        Command = [scriptblock]::Create($scriptContent)
        IsFile = $false
    }
}

function Test-DFEBackup {
    [CmdletBinding()]
    param(
        [string]$Product = "Production Pro",
        [string]$Version = "8.3",
        [string]$ManifestPath,
        [string]$HardwareManifestPath
    )

    $passIcon = [char]::ConvertFromUtf32(0x2705)
    $failIcon = [char]::ConvertFromUtf32(0x274C)
    $warningIcon = [char]::ConvertFromUtf32(0x26A0) + [char]0xFE0F
    $infoIcon = [char]::ConvertFromUtf32(0x2139) + [char]0xFE0F

    Write-Host ""
    Write-Host "Seleccione el perfil de backup a validar:"
    Write-Host "1. SystemManager (Production Pro)"
    Write-Host "2. IPC_RIP (nodo IPC o RIP)"
    $profileChoice = Read-Host "Seleccione una opcion (1-2)"

    $profile = "SystemManager"
    if ($profileChoice -eq "2") {
        $profile = "IPC_RIP"
    }

    Write-Host ""
    Write-Host "Preflight de Backup" -ForegroundColor Cyan
    Write-Host "-------------------" -ForegroundColor Gray
    Write-Host "Evaluando origen, destino y herramientas para el perfil ${profile} en $Product $Version."
    Write-Host ""

    try {
        $validator = Get-ValidateBackupCommand
        $arguments = @{
            Product = $Product
            Version = $Version
            Profile = $profile
        }
        if ($ManifestPath) {
            $arguments["ManifestPath"] = $ManifestPath
        }
        if ($HardwareManifestPath) {
            $arguments["HardwareManifestPath"] = $HardwareManifestPath
        }
        $result = & $validator.Command @arguments
    }
    catch {
        Write-Host "No se pudo ejecutar el preflight de backup: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host "Resumen de Origen:"
    Write-Host "   Fuentes totales: $($result.Sources.Total)"
    Write-Host "   Encontradas: $($result.Sources.FoundCount)"
    Write-Host "   Faltantes: $($result.Sources.MissingCount)"
    Write-Host ""

    Write-Host "Resumen de Destino:"
    Write-Host "   Ruta: $($result.Destination.Path)"
    $destExistsStr = if ($result.Destination.Exists) { "si" } else { "no" }
    $destWritableStr = if ($result.Destination.Writable) { "si" } else { "no" }
    Write-Host "   Existe: ${destExistsStr}"
    Write-Host "   Escribible: ${destWritableStr}"
    Write-Host ""

    if ($result.Profile -eq "SystemManager") {
        Write-Host "Resumen de Herramientas:"
        $mobiusHomeStr = if ($result.Tools.MobiusHomeDefined) { "definida" } else { "no definida" }
        Write-Host "   MOBIUS_HOME: ${mobiusHomeStr}"
        Write-Host "   Encontradas: $($result.Tools.Found -join ', ')"
        if ($result.Tools.Missing.Count -gt 0) {
            Write-Host "   Faltantes: $($result.Tools.Missing -join ', ')"
        }
        Write-Host ""
    }

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
            Write-Host "Resultado: $passIcon preflight exitoso (Pass)." -ForegroundColor Green
        }
        "Warning" {
            Write-Host "Resultado: $warningIcon preflight completado con advertencias (Warning)." -ForegroundColor Yellow
        }
        default {
            Write-Host "Resultado: $failIcon preflight fallido (Fail)." -ForegroundColor Red
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
    Write-Host "$checkIcon Verificaci$($oAcuteLower)n de seguridad: COMPLETADA" -ForegroundColor Green
    Write-Host "$checkIcon Preflight de backup: COMPLETADO" -ForegroundColor Green
    Write-Host "$pendingIcon Instalaci$($oAcuteLower)n de prerequisitos: PENDIENTE (modo demo)" -ForegroundColor Yellow
    Write-Host "$pendingIcon Instalaci$($oAcuteLower)n de software principal: PENDIENTE (modo demo)" -ForegroundColor Yellow
    Write-Host "$ideaIcon Este es un modo de demostraci$($oAcuteLower)n." -ForegroundColor Cyan
}

function Get-CatalogManifest {
    [CmdletBinding()]
    param()

    $projectRoot = $null
    if ($PSScriptRoot) {
        $projectRoot = Split-Path -Parent $PSScriptRoot
    }
    else {
        $projectRoot = (Get-Location).Path
    }

    if ($projectRoot) {
        $localPath = Join-Path -Path $projectRoot -ChildPath "manifests\catalog.json"
        if (Test-Path -Path $localPath -PathType Leaf) {
            return Get-Content -Path $localPath -Raw | ConvertFrom-Json
        }
    }

    $catalogUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/manifests/catalog.json?cacheBust=$([DateTime]::UtcNow.Ticks)"
    return Invoke-RestMethod -Uri $catalogUrl -Headers @{
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
    } -ErrorAction Stop
}

function Select-Installation {
    $script:catalog = Get-CatalogManifest

    $validSelection = $false
    while (-not $validSelection) {
        Write-Host ""
        Write-Host "--- Seleccion de instalacion ---" -ForegroundColor Cyan

        # 1. Product Selection
        Write-Host "Seleccione un Producto:"
        $products = @($script:catalog.products)
        for ($i = 0; $i -lt $products.Count; $i++) {
            Write-Host "$($i + 1)) $($products[$i].displayName)"
        }
        $prodIdx = -1
        while ($prodIdx -lt 0 -or $prodIdx -ge $products.Count) {
            $inputVal = Read-Host "Seleccione (1-$($products.Count))"
            if ($inputVal -match "^\d+$") {
                $prodIdx = [int]$inputVal - 1
            }
        }
        $script:selectedProduct = $products[$prodIdx]

        # 2. Model Selection
        Write-Host ""
        Write-Host "Seleccione un Modelo:"
        $models = @($script:selectedProduct.models)
        for ($i = 0; $i -lt $models.Count; $i++) {
            Write-Host "$($i + 1)) $($models[$i].displayName)"
        }
        $modelIdx = -1
        while ($modelIdx -lt 0 -or $modelIdx -ge $models.Count) {
            $inputVal = Read-Host "Seleccione (1-$($models.Count))"
            if ($inputVal -match "^\d+$") {
                $modelIdx = [int]$inputVal - 1
            }
        }
        $script:selectedModel = $models[$modelIdx]

        # 3. Version Selection
        Write-Host ""
        Write-Host "Seleccione una Version:"
        $versions = @($script:selectedModel.versions)
        for ($i = 0; $i -lt $versions.Count; $i++) {
            Write-Host "$($i + 1)) $($versions[$i].displayName)"
        }
        $verIdx = -1
        while ($verIdx -lt 0 -or $verIdx -ge $versions.Count) {
            $inputVal = Read-Host "Seleccione (1-$($versions.Count))"
            if ($inputVal -match "^\d+$") {
                $verIdx = [int]$inputVal - 1
            }
        }
        $script:selectedVersion = $versions[$verIdx]

        # Check stepsAvailable
        if ($script:selectedVersion.stepsAvailable) {
            $validSelection = $true
            # Save selected details globally/script-wide
            $script:selectedProductName = $script:selectedProduct.displayName
            $script:selectedModelName = $script:selectedModel.displayName
            $script:selectedVersionName = $script:selectedVersion.displayName

            # Resolve paths
            $projectRoot = $null
            if ($PSScriptRoot) {
                $projectRoot = Split-Path -Parent $PSScriptRoot
            }
            else {
                $projectRoot = (Get-Location).Path
            }

            $script:hardwareManifestPath = if ($script:selectedVersion.manifests.hardware) { Join-Path -Path $projectRoot -ChildPath $script:selectedVersion.manifests.hardware }
            $script:networkManifestPath = if ($script:selectedVersion.manifests.network) { Join-Path -Path $projectRoot -ChildPath $script:selectedVersion.manifests.network }
            $script:storageManifestPath = if ($script:selectedVersion.manifests.storage) { Join-Path -Path $projectRoot -ChildPath $script:selectedVersion.manifests.storage }
            $script:securityManifestPath = if ($script:selectedVersion.manifests.security) { Join-Path -Path $projectRoot -ChildPath $script:selectedVersion.manifests.security }
            $script:backupManifestPath = if ($script:selectedVersion.manifests.backup) { Join-Path -Path $projectRoot -ChildPath $script:selectedVersion.manifests.backup }
            $script:assessmentPath = if ($script:selectedVersion.manifests.assessment) { Join-Path -Path $projectRoot -ChildPath $script:selectedVersion.manifests.assessment }

            Write-Host ""
            Write-Host "Configuracion cargada con exito para $($script:selectedProductName) $($script:selectedModelName) $($script:selectedVersionName)." -ForegroundColor Green
        }
        else {
            Write-Host ""
            Write-Host "Pasos no disponibles para $($script:selectedProduct.displayName) $($script:selectedModel.displayName) $($script:selectedVersion.displayName). Próximamente." -ForegroundColor Red
        }
    }
}

function Show-Menu {
    [CmdletBinding()]
    param()

    Select-Installation

    do {
        Write-Host ""
        Write-Host "DFE Toolkit" -ForegroundColor Cyan
        Write-Host "==========="
        Write-Host "1. Validar Hardware"
        Write-Host "2. Validar Red"
        Write-Host "3. Validar Sistema Operativo"
        Write-Host "4. Validar Almacenamiento"
        Write-Host "5. Validar Seguridad"
        Write-Host "6. Preflight de Backup"
        Write-Host "7. Salir"
        Write-Host "8. Ver resumen de instalacion"
        Write-Host "9. Abrir interfaz grafica"
        Write-Host ""

        $option = Read-Host "Seleccione una opcion"

        switch ($option) {
            "1" {
                Get-SystemInfo
                Test-DFEHardware -Product $script:selectedProductName -Version $script:selectedVersionName -ManifestPath $script:hardwareManifestPath
            }
            "2" {
                Test-DFENetwork -ManifestPath $script:networkManifestPath -AssessmentPath $script:assessmentPath
            }
            "3" {
                Test-DFEOperatingSystem -Product $script:selectedProductName -Version $script:selectedVersionName -ManifestPath $script:hardwareManifestPath -AssessmentPath $script:assessmentPath
            }
            "4" {
                Test-DFEStorage -Product $script:selectedProductName -Version $script:selectedVersionName -ManifestPath $script:storageManifestPath -AssessmentPath $script:assessmentPath -HardwareManifestPath $script:hardwareManifestPath
            }
            "5" {
                Test-DFESecurity -Product $script:selectedProductName -Version $script:selectedVersionName -ManifestPath $script:securityManifestPath -AssessmentPath $script:assessmentPath -HardwareManifestPath $script:hardwareManifestPath
            }
            "6" {
                Test-DFEBackup -Product $script:selectedProductName -Version $script:selectedVersionName -ManifestPath $script:backupManifestPath -HardwareManifestPath $script:hardwareManifestPath
            }
            "7" {
                Write-Host "Saliendo de DFE Toolkit."
            }
            "8" {
                Show-DemoSummary
            }
            "9" {
                Invoke-DFEGui
            }
            default {
                Write-Host "Opcion invalida. Intente nuevamente." -ForegroundColor Yellow
            }
        }
    } while ($option -ne "7")
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
