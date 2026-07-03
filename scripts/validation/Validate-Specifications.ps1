<#
.SYNOPSIS
    Orquestador que ejecuta las 5 validaciones de especificaciones del DFE en secuencia.
.DESCRIPTION
    Ejecuta en secuencia los scripts Validate-Hardware.ps1, Validate-Network.ps1,
    Validate-OperatingSystem.ps1, Validate-Storage.ps1 y Validate-Security.ps1.
    Consolida todos los checks y genera un reporte checklist formateado.
.PARAMETER Product
    Nombre del producto a evaluar. Por defecto "Production Pro".
.PARAMETER Version
    Version del producto. Por defecto "8.3".
.PARAMETER Model
    Modelo del servidor. Por defecto "commercial".
.PARAMETER ManifestPaths
    Hashtable con las rutas de los manifiestos: hardware, network, storage, security, assessment.
.PARAMETER SystemInfoPath
    Ruta opcional a un JSON con datos de sistema simulados para pruebas.
.PARAMETER TestMode
    Fuerza el resultado general a Pass.
.OUTPUTS
    [pscustomobject] con Status, Product, Version, Model, Sections (checklist), Text (formateado).
#>

[CmdletBinding()]
param(
    [string]$Product = "Production Pro",
    [string]$Version = "8.3",
    [string]$Model = "commercial",
    [hashtable]$ManifestPaths = @{},
    [string]$SystemInfoPath,
    [switch]$TestMode
)

$ErrorActionPreference = "Stop"

function Get-CheckDisplayInfo {
    param(
        [string]$Id,
        [object]$CheckObj,
        [object]$HwRes,
        [object]$NetRes,
        [object]$OsRes,
        [object]$StorageRes,
        [object]$SecRes
    )

    $name = $CheckObj.Name
    $val = "Ok"

    switch ($Id) {
        # Hardware
        "check-hardware-manufacturer" {
            $name = "Fabricante"
            $val = if ($HwRes.Manufacturer) { $HwRes.Manufacturer } else { "Desconocido" }
        }
        "check-hardware-model" {
            $name = "Modelo"
            $val = if ($HwRes.Model) { $HwRes.Model } else { "Desconocido" }
        }
        "check-hardware-generation" {
            $name = "Generacion"
            $val = "N/D"
            if ($HwRes.Model) {
                if ($HwRes.Model -like "*G5*") { $val = "G5" }
                elseif ($HwRes.Model -like "*Gen10*") { $val = "Gen10" }
                elseif ($HwRes.Model -like "*Gen11*") { $val = "Gen11" }
            }
        }
        "check-memory-capacity" {
            $name = "Memoria"
            $val = if ($HwRes.MemoryGB) { "$($HwRes.MemoryGB) GB" } else { "Desconocido" }
        }
        "check-cpu-inventory" {
            $name = "CPU"
            $val = if ($HwRes.CpuName) { $HwRes.CpuName } else { "Desconocido" }
        }

        # Network
        "check-network-adapter-names" {
            $name = "Nombres de adaptadores"
            if ($NetRes.Adapters.Found.Count -gt 0) {
                $val = $NetRes.Adapters.Found -join ", "
            } else {
                $val = "Ninguno"
            }
        }
        "check-network-adapter-state" {
            $name = "Estado de adaptadores"
            $val = "Activos"
        }
        "check-network-static-ip" {
            $name = "IP estatica"
            $val = "Configurada"
        }
        "check-network-metrics" {
            $name = "Metricas de red"
            $val = "OK"
        }
        "check-hosts-file" {
            $name = "Archivo hosts"
            $val = "OK"
        }

        # OS
        "check-operating-system-version" {
            $name = "Version"
            $val = if ($OsRes.OperatingSystem) { $OsRes.OperatingSystem } else { "Desconocido" }
        }
        "check-os-architecture" {
            $name = "Arquitectura"
            $val = if ($OsRes.OSArchitecture) { $OsRes.OSArchitecture } else { "Desconocido" }
        }
        "check-os-build" {
            $name = "Build"
            $val = if ($OsRes.OSVersion) { $OsRes.OSVersion } else { "Desconocido" }
        }

        # Storage
        "check-storage-free-space" {
            $name = "Espacio libre"
            $val = "Verificar"
            if ($CheckObj.Detail -match "unidad ([A-Za-z]):\s*([\d\.,]+)\s*GB libres") {
                $val = "$($Matches[1]): $($Matches[2]) GB libres"
            }
            elseif ($CheckObj.Detail -match "C:\s*([\d\.,]+)\s*GB libres") {
                $val = "C: $($Matches[1]) GB libres"
            }
        }
        "check-storage-drive-layout" {
            $name = "Unidades y layout"
            $val = "OK"
            if ($StorageRes.Drives.FoundExpected.Count -gt 0) {
                $val = $StorageRes.Drives.FoundExpected -join ", "
            }
        }
        "check-storage-backup-location" {
            $name = "Ubicacion de backup"
            $val = "OK"
        }

        # Security
        "check-admin-privileges" {
            $name = "Administrador"
            $val = if ($SecRes.Security.isAdmin) { "Si" } else { "No" }
        }
        "check-uac-policy" {
            $name = "UAC"
            $val = if ($SecRes.Security.uacEnabled) { "Activado" } else { "Desactivado" }
        }
        "check-firewall-profile" {
            $name = "Firewall"
            $val = "Configurado"
        }
    }

    return [pscustomobject]@{
        Name = $name
        Value = $val
        Status = $CheckObj.Status
        Detail = $CheckObj.Detail
    }
}

# Resolver rutas locales de los validadores individuales
$hwScript = Join-Path -Path $PSScriptRoot -ChildPath "Validate-Hardware.ps1"
$netScript = Join-Path -Path $PSScriptRoot -ChildPath "Validate-Network.ps1"
$osScript = Join-Path -Path $PSScriptRoot -ChildPath "Validate-OperatingSystem.ps1"
$storageScript = Join-Path -Path $PSScriptRoot -ChildPath "Validate-Storage.ps1"
$securityScript = Join-Path -Path $PSScriptRoot -ChildPath "Validate-Security.ps1"

# Ejecución secuencial de los validadores individuales
$hwRes = $null
try {
    $hwRes = & $hwScript -Product $Product -Version $Version -ManifestPath $ManifestPaths["hardware"] -SystemInfoPath $SystemInfoPath -TestMode:$TestMode
} catch {
    Write-Warning "Fallo la ejecucion de Validate-Hardware.ps1: $_"
}

$netRes = $null
try {
    $netRes = & $netScript -ManifestPath $ManifestPaths["network"] -AssessmentPath $ManifestPaths["assessment"] -SystemInfoPath $SystemInfoPath -TestMode:$TestMode
} catch {
    Write-Warning "Fallo la ejecucion de Validate-Network.ps1: $_"
}

$osRes = $null
try {
    $osRes = & $osScript -Product $Product -Version $Version -ManifestPath $ManifestPaths["hardware"] -AssessmentPath $ManifestPaths["assessment"] -SystemInfoPath $SystemInfoPath -TestMode:$TestMode
} catch {
    Write-Warning "Fallo la ejecucion de Validate-OperatingSystem.ps1: $_"
}

$storageRes = $null
try {
    # Por defecto usamos el perfil SystemManager para almacenamiento
    $storageRes = & $storageScript -Product $Product -Version $Version -Profile "SystemManager" -ManifestPath $ManifestPaths["storage"] -AssessmentPath $ManifestPaths["assessment"] -HardwareManifestPath $ManifestPaths["hardware"] -SystemInfoPath $SystemInfoPath -TestMode:$TestMode
} catch {
    Write-Warning "Fallo la ejecucion de Validate-Storage.ps1: $_"
}

$secRes = $null
try {
    $secRes = & $securityScript -Product $Product -Version $Version -ManifestPath $ManifestPaths["security"] -AssessmentPath $ManifestPaths["assessment"] -HardwareManifestPath $ManifestPaths["hardware"] -SystemInfoPath $SystemInfoPath -TestMode:$TestMode
} catch {
    Write-Warning "Fallo la ejecucion de Validate-Security.ps1: $_"
}

# Consolidador de secciones
$sections = @(
    [pscustomobject]@{ Name = "Hardware"; Checks = @() }
    [pscustomobject]@{ Name = "Red"; Checks = @() }
    [pscustomobject]@{ Name = "Sistema Operativo"; Checks = @() }
    [pscustomobject]@{ Name = "Almacenamiento"; Checks = @() }
    [pscustomobject]@{ Name = "Seguridad"; Checks = @() }
)

if ($hwRes -and $hwRes.Checks) {
    foreach ($c in $hwRes.Checks) {
        $sections[0].Checks += Get-CheckDisplayInfo -Id $c.Id -CheckObj $c -HwRes $hwRes
    }
}
if ($netRes -and $netRes.Checks) {
    foreach ($c in $netRes.Checks) {
        $sections[1].Checks += Get-CheckDisplayInfo -Id $c.Id -CheckObj $c -NetRes $netRes
    }
}
if ($osRes -and $osRes.Checks) {
    foreach ($c in $osRes.Checks) {
        $sections[2].Checks += Get-CheckDisplayInfo -Id $c.Id -CheckObj $c -OsRes $osRes
    }
}
if ($storageRes -and $storageRes.Checks) {
    foreach ($c in $storageRes.Checks) {
        $sections[3].Checks += Get-CheckDisplayInfo -Id $c.Id -CheckObj $c -StorageRes $storageRes
    }
}
if ($secRes -and $secRes.Checks) {
    foreach ($c in $secRes.Checks) {
        $sections[4].Checks += Get-CheckDisplayInfo -Id $c.Id -CheckObj $c -SecRes $secRes
    }
}

# Determinar el estado general
$generalStatus = "Pass"
$hasFail = $false
$hasWarning = $false

foreach ($section in $sections) {
    foreach ($check in $section.Checks) {
        if ($check.Status -eq "Fail") {
            $hasFail = $true
        }
        elseif ($check.Status -eq "Warning") {
            $hasWarning = $true
        }
    }
}

if ($hasFail) {
    $generalStatus = "Fail"
}
elseif ($hasWarning) {
    $generalStatus = "Warning"
}

# Si TestMode está activado, forzar a Pass
if ($TestMode) {
    $generalStatus = "Pass"
}

# Generar reporte textual en formato de checklist
$statusIcons = @{
    "Pass" = "✅ Ok"
    "Warning" = "⚠️ Warning"
    "Fail" = "❌ Fail"
    "Info" = "ℹ️ Info"
}

$lines = @()
foreach ($section in $sections) {
    if ($lines.Count -gt 0) { $lines += "" }
    $lines += $section.Name.ToUpper()
    
    foreach ($check in $section.Checks) {
        $icon = $statusIcons[$check.Status]
        if (-not $icon) { $icon = "❓ Unknown" }
        
        $itemText = "  $($check.Name): $($check.Value)"
        # Pad con puntos para alineación
        $dotCount = 45 - $itemText.Length
        if ($dotCount -lt 2) { $dotCount = 2 }
        $dots = "." * $dotCount
        
        $lines += "$itemText $dots $icon"
    }
}

$overallStatusText = "✅ Completado"
if ($generalStatus -eq "Fail") {
    $overallStatusText = "❌ Fallido"
}
elseif ($generalStatus -eq "Warning") {
    $overallStatusText = "⚠️ Completado con advertencias"
}

$lines += ""
$lines += "  Estado general: $overallStatusText"

$outputText = $lines -join [Environment]::NewLine

# Retornar el objeto estructurado
$result = [pscustomobject]@{
    Status = $generalStatus
    Product = $Product
    Version = $Version
    Model = $Model
    Sections = $sections
    Text = $outputText
}

Write-Output $result
