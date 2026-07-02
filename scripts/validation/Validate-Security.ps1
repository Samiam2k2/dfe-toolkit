<#
.SYNOPSIS
    Valida la seguridad del servidor DFE contra los requisitos aprobados.
.DESCRIPTION
    Script independiente compatible con Windows PowerShell 5.1 (sin dependencias
    externas). Ejecuta los 3 checks de categoria "security" definidos en
    manifests/assessment-checks.json:
        - check-admin-privileges
        - check-uac-policy
        - check-firewall-profile

    Devuelve al pipeline un objeto estructurado con el estado general y el
    detalle por check. Puede leer los datos del sistema real o de un JSON
    simulado (-SystemInfoPath) para pruebas en laboratorio/VM.

    El nombre y el flag "blocking" de cada check se leen de assessment-checks.json.
.PARAMETER Product
    Nombre del producto a evaluar. Por defecto "Production Pro".
.PARAMETER Version
    Version del producto. Por defecto "8.3".
.PARAMETER ManifestPath
    Ruta local a security-requirements.json. Si no se provee y no existe la copia
    local, se descarga de raw.githubusercontent con cache-bust.
.PARAMETER AssessmentPath
    Ruta local a assessment-checks.json (de donde se toma name/blocking de cada
    check). Si no se provee y no existe la copia local, se descarga con cache-bust.
.PARAMETER HardwareManifestPath
    Ruta local a hardware-requirements.json. Se usa para determinar validationMode.
.PARAMETER SystemInfoPath
    Ruta opcional a un JSON con datos de seguridad simulados.
.PARAMETER TestMode
    Si se especifica, el Status general se fuerza a Pass y se agrega
    TestModeApplied=true, dejando visibles los resultados reales por check.
.OUTPUTS
    [pscustomobject] con: Status, RealStatus, ValidationMode, DegradedByMode,
    TestModeApplied, Product, Version, Checks (arreglo de objetos
    Id/Name/Status/Detail/Blocking), Security y SimulatedSource.
#>

[CmdletBinding()]
param(
    [string]$Product = "Production Pro",
    [string]$Version = "8.3",
    [string]$ManifestPath,
    [string]$AssessmentPath,
    [string]$HardwareManifestPath,
    [string]$SystemInfoPath,
    [switch]$TestMode
)

function Get-SecurityRequirementsManifest {
    param(
        [string]$ManifestPath
    )

    if ($ManifestPath) {
        if (-not (Test-Path -Path $ManifestPath -PathType Leaf)) {
            throw "No se encontro el manifiesto de seguridad en la ruta indicada: $ManifestPath"
        }
        return Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json
    }

    $projectRoot = $null
    if ($PSScriptRoot) {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }

    if ($projectRoot) {
        $localPath = Join-Path -Path $projectRoot -ChildPath "manifests\security-requirements.json"
        if (Test-Path -Path $localPath -PathType Leaf) {
            return Get-Content -Path $localPath -Raw | ConvertFrom-Json
        }
    }

    $requirementsUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/manifests/security-requirements.json?cacheBust=$([DateTime]::UtcNow.Ticks)"
    return Invoke-RestMethod -Uri $requirementsUrl -Headers @{
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
    } -ErrorAction Stop
}

function Get-AssessmentChecksManifest {
    param(
        [string]$AssessmentPath
    )

    if ($AssessmentPath) {
        if (-not (Test-Path -Path $AssessmentPath -PathType Leaf)) {
            throw "No se encontro el manifiesto de assessment en la ruta indicada: $AssessmentPath"
        }
        return Get-Content -Path $AssessmentPath -Raw | ConvertFrom-Json
    }

    $projectRoot = $null
    if ($PSScriptRoot) {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }

    if ($projectRoot) {
        $localPath = Join-Path -Path $projectRoot -ChildPath "manifests\assessment-checks.json"
        if (Test-Path -Path $localPath -PathType Leaf) {
            return Get-Content -Path $localPath -Raw | ConvertFrom-Json
        }
    }

    $assessmentUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/manifests/assessment-checks.json?cacheBust=$([DateTime]::UtcNow.Ticks)"
    return Invoke-RestMethod -Uri $assessmentUrl -Headers @{
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
    } -ErrorAction Stop
}

function Get-HardwareRequirementsManifest {
    param(
        [string]$HardwareManifestPath
    )

    if ($HardwareManifestPath) {
        if (-not (Test-Path -Path $HardwareManifestPath -PathType Leaf)) {
            throw "No se encontro el manifiesto de hardware en la ruta indicada: $HardwareManifestPath"
        }
        return Get-Content -Path $HardwareManifestPath -Raw | ConvertFrom-Json
    }

    $projectRoot = $null
    if ($PSScriptRoot) {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }

    if ($projectRoot) {
        $localPath = Join-Path -Path $projectRoot -ChildPath "manifests\hardware-requirements.json"
        if (Test-Path -Path $localPath -PathType Leaf) {
            return Get-Content -Path $localPath -Raw | ConvertFrom-Json
        }
    }

    $requirementsUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/manifests/hardware-requirements.json?cacheBust=$([DateTime]::UtcNow.Ticks)"
    return Invoke-RestMethod -Uri $requirementsUrl -Headers @{
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
    } -ErrorAction Stop
}

function Get-SecurityInventory {
    param(
        [string]$SystemInfoPath
    )

    if ($SystemInfoPath) {
        if (-not (Test-Path -Path $SystemInfoPath -PathType Leaf)) {
            throw "No se encontro el JSON de sistema simulado: $SystemInfoPath"
        }

        $simulated = Get-Content -Path $SystemInfoPath -Raw | ConvertFrom-Json

        $isAdmin = $false
        if ($null -ne $simulated.isAdmin) { $isAdmin = [bool]$simulated.isAdmin }

        $uacEnabled = $null
        if ($null -ne $simulated.uacEnabled) { $uacEnabled = [bool]$simulated.uacEnabled }

        $firewallProfiles = @()
        foreach ($profile in @($simulated.firewallProfiles)) {
            $firewallProfiles += [pscustomobject]@{
                Name = [string]$profile.name
                Enabled = [bool]$profile.enabled
            }
        }

        return [pscustomobject]@{
            IsAdmin = $isAdmin
            UacEnabled = $uacEnabled
            FirewallProfiles = $firewallProfiles
            Simulated = $true
        }
    }

    # Query local security state
    # 1. Admin privileges check
    $isAdmin = $false
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        $isAdmin = $false
    }

    # 2. UAC check (EnableLUA key)
    $uacEnabled = $null
    $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    if (Test-Path -Path $registryPath) {
        try {
            $luaValue = Get-ItemPropertyValue -Path $registryPath -Name "EnableLUA" -ErrorAction SilentlyContinue
            if ($null -ne $luaValue) {
                $uacEnabled = ($luaValue -eq 1)
            }
        }
        catch {
            $uacEnabled = $null
        }
    }

    # 3. Firewall profiles check
    $firewallProfiles = @()
    try {
        if (Get-Command -Name Get-NetFirewallProfile -ErrorAction SilentlyContinue) {
            $profiles = Get-NetFirewallProfile -ErrorAction Stop
            foreach ($profile in $profiles) {
                $enabled = $false
                if ($profile.Enabled -eq "True" -or $profile.Enabled -eq $true -or $profile.Enabled -eq 1) {
                    $enabled = $true
                }
                $firewallProfiles += [pscustomobject]@{
                    Name = [string]$profile.Name
                    Enabled = $enabled
                }
            }
        }
    }
    catch {
        # Catch errors from Get-NetFirewallProfile and proceed with empty list
    }

    return [pscustomobject]@{
        IsAdmin = $isAdmin
        UacEnabled = $uacEnabled
        FirewallProfiles = $firewallProfiles
        Simulated = $false
    }
}

function Get-CheckMeta {
    param(
        [object]$Assessment,
        [string]$Id
    )

    $check = $Assessment.checks | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $check) {
        throw "No se encontro el check '$Id' en el manifiesto de assessment."
    }

    $blocking = $false
    if ($check.blocking) { $blocking = [bool]$check.blocking }

    return [pscustomobject]@{
        Id = [string]$check.id
        Name = [string]$check.name
        Blocking = $blocking
    }
}

function New-CheckResult {
    param(
        [object]$Meta,
        [string]$Status,
        [string]$Detail
    )

    return [pscustomobject]@{
        Id = $Meta.Id
        Name = $Meta.Name
        Status = $Status
        Detail = $Detail
        Blocking = $Meta.Blocking
    }
}

# --- Carga de manifiestos y datos de sistema ---
$requirements = Get-SecurityRequirementsManifest -ManifestPath $ManifestPath
$assessment = Get-AssessmentChecksManifest -AssessmentPath $AssessmentPath
$system = Get-SecurityInventory -SystemInfoPath $SystemInfoPath

$checks = @()

# --- check-admin-privileges ---
$adminMeta = Get-CheckMeta -Assessment $assessment -Id "check-admin-privileges"
if ($requirements.adminPrivileges.required) {
    if ($system.IsAdmin) {
        $checks += New-CheckResult -Meta $adminMeta -Status "Pass" -Detail "La herramienta se esta ejecutando con privilegios de Administrador."
    }
    else {
        $checks += New-CheckResult -Meta $adminMeta -Status "Fail" -Detail "La herramienta no se esta ejecutando como Administrador. Ejecute PowerShell como Administrador."
    }
}
else {
    $checks += New-CheckResult -Meta $adminMeta -Status "Pass" -Detail "Ejecucion normal. Privilegios de administrador no requeridos en el manifiesto."
}

# --- check-uac-policy ---
$uacMeta = Get-CheckMeta -Assessment $assessment -Id "check-uac-policy"
if ($null -eq $system.UacEnabled) {
    $checks += New-CheckResult -Meta $uacMeta -Status "Info" -Detail "No se pudo determinar la configuracion de UAC. El manifiesto no define un estado esperado (expectedState) para comparar."
}
else {
    if ($system.UacEnabled) {
        $checks += New-CheckResult -Meta $uacMeta -Status "Info" -Detail "UAC activado. El manifiesto no define un estado esperado (expectedState) para comparar."
    }
    else {
        $checks += New-CheckResult -Meta $uacMeta -Status "Info" -Detail "UAC desactivado. El manifiesto no define un estado esperado (expectedState) para comparar."
    }
}

# --- check-firewall-profile ---
$firewallMeta = Get-CheckMeta -Assessment $assessment -Id "check-firewall-profile"
if ($system.FirewallProfiles.Count -eq 0) {
    $checks += New-CheckResult -Meta $firewallMeta -Status "Info" -Detail "No se pudo determinar el estado de los perfiles de firewall (el cmdlet Get-NetFirewallProfile no esta disponible o no devolvio datos)."
}
else {
    $profileDetails = @()
    foreach ($p in $system.FirewallProfiles) {
        $pName = [string]$p.Name
        $pState = if ($p.Enabled) { "activado" } else { "desactivado" }
        $profileDetails += "${pName}: ${pState}"
    }
    $detailStr = $profileDetails -join "; "
    $checks += New-CheckResult -Meta $firewallMeta -Status "Info" -Detail "${detailStr}."
}

# --- Estado general ---
$hwRequirements = Get-HardwareRequirementsManifest -HardwareManifestPath $HardwareManifestPath
$validationMode = "enforcing"
if ($hwRequirements.validationMode) {
    $validationMode = [string]$hwRequirements.validationMode
}

$realStatus = "Pass"
$hasBlockingFail = $false
$hasWarningOrNonBlockingFail = $false
foreach ($check in $checks) {
    if ($check.Status -eq "Fail" -and $check.Blocking) {
        $hasBlockingFail = $true
    }
    elseif ($check.Status -eq "Warning" -or ($check.Status -eq "Fail" -and -not $check.Blocking)) {
        $hasWarningOrNonBlockingFail = $true
    }
}

if ($hasBlockingFail) {
    $realStatus = "Fail"
}
elseif ($hasWarningOrNonBlockingFail) {
    $realStatus = "Warning"
}

$finalStatus = $realStatus
$degradedByMode = $false
if ($validationMode -eq "informational" -and $realStatus -eq "Fail") {
    $finalStatus = "Warning"
    $degradedByMode = $true
}

$testModeApplied = $false
if ($TestMode) {
    $testModeApplied = $true
    $finalStatus = "Pass"
}

$securityInventory = [pscustomobject]@{
    isAdmin = $system.IsAdmin
    uacEnabled = $system.UacEnabled
    firewallProfiles = $system.FirewallProfiles
    SimulatedSource = $system.Simulated
}

$result = [pscustomobject]@{
    Status = $finalStatus
    RealStatus = $realStatus
    ValidationMode = $validationMode
    DegradedByMode = $degradedByMode
    TestModeApplied = $testModeApplied
    Product = $Product
    Version = $Version
    Checks = $checks
    Security = $securityInventory
    SimulatedSource = $system.Simulated
}

Write-Output $result
