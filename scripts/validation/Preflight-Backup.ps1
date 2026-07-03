<#
.SYNOPSIS
    Ejecuta un analisis preflight para verificar la disponibilidad de origen,
    destino y herramientas antes de realizar un backup.
.DESCRIPTION
    Script independiente compatible con Windows PowerShell 5.1 (sin dependencias
    externas). Soporta dos perfiles: "SystemManager" e "IPC_RIP".
    
    Define internamente 3 checks:
        - check-backup-sources
        - check-backup-destination
        - check-backup-tools
.PARAMETER Product
    Nombre del producto a evaluar. Por defecto "Production Pro".
.PARAMETER Version
    Version del producto. Por defecto "8.3".
.PARAMETER ManifestPath
    Ruta local a backup-manifest.json. Si no se provee y no existe la copia
    local, se descarga de raw.githubusercontent con cache-bust.
.PARAMETER HardwareManifestPath
    Ruta local a hardware-requirements.json. Se usa para determinar validationMode.
.PARAMETER Profile
    Perfil a evaluar ("SystemManager" o "IPC_RIP"). Por defecto "SystemManager".
.PARAMETER SystemInfoPath
    Ruta opcional a un JSON con datos de preflight simulados.
.PARAMETER TestMode
    Si se especifica, el Status general se fuerza a Pass y se agrega
    TestModeApplied=true, dejando visibles los resultados reales por check.
.OUTPUTS
    [pscustomobject] con: Status, RealStatus, ValidationMode, DegradedByMode,
    TestModeApplied, Product, Version, Profile, Checks, Sources, Destination,
    Tools y SimulatedSource.
#>

[CmdletBinding()]
param(
    [string]$Product = "Production Pro",
    [string]$Version = "8.3",
    [string]$ManifestPath,
    [string]$HardwareManifestPath,
    [string]$Profile = "SystemManager",
    [string]$SystemInfoPath,
    [switch]$TestMode
)

function Get-BackupRequirementsManifest {
    param(
        [string]$ManifestPath
    )

    if ($ManifestPath) {
        if (-not (Test-Path -Path $ManifestPath -PathType Leaf)) {
            throw "No se encontro el manifiesto de backup en la ruta indicada: $ManifestPath"
        }
        return Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json
    }

    $projectRoot = $null
    if ($PSScriptRoot) {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }

    if ($projectRoot) {
        $localPath = Join-Path -Path $projectRoot -ChildPath "manifests\backup-manifest.json"
        if (Test-Path -Path $localPath -PathType Leaf) {
            return Get-Content -Path $localPath -Raw | ConvertFrom-Json
        }
    }

    $requirementsUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/manifests/backup-manifest.json?cacheBust=$([DateTime]::UtcNow.Ticks)"
    return Invoke-RestMethod -Uri $requirementsUrl -Headers @{
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

function Get-BackupInventory {
    param(
        [object]$ProfileConfig,
        [string]$SystemInfoPath
    )

    if ($SystemInfoPath) {
        if (-not (Test-Path -Path $SystemInfoPath -PathType Leaf)) {
            throw "No se encontro el JSON de sistema simulado: $SystemInfoPath"
        }
        $simulated = Get-Content -Path $SystemInfoPath -Raw | ConvertFrom-Json

        $sources = @()
        foreach ($src in $profileConfig.sources) {
            $simSrc = $null
            if ($simulated.sources) {
                $simSrc = @($simulated.sources) | Where-Object { $_.path.ToLower() -eq $src.path.ToLower() } | Select-Object -First 1
            }
            $exists = $false
            if ($null -ne $simSrc -and $null -ne $simSrc.exists) {
                $exists = [bool]$simSrc.exists
            }
            $sources += [pscustomobject]@{
                Path = [string]$src.path
                Pattern = [string]$src.pattern
                Type = [string]$src.type
                Description = [string]$src.description
                Blocking = [bool]$src.blocking
                Exists = $exists
            }
        }

        # Destination
        $destExists = $false
        if ($null -ne $simulated.destination -and $null -ne $simulated.destination.exists) {
            $destExists = [bool]$simulated.destination.exists
        }
        $destWritable = $false
        if ($null -ne $simulated.destination -and $null -ne $simulated.destination.writable) {
            $destWritable = [bool]$simulated.destination.writable
        }

        # Tools
        $tools = @()
        foreach ($t in $profileConfig.requiredTools) {
            $simTool = $null
            if ($simulated.tools) {
                $simTool = @($simulated.tools) | Where-Object { $_.name.ToLower() -eq $t.name.ToLower() } | Select-Object -First 1
            }
            $exists = $false
            if ($null -ne $simTool -and $null -ne $simTool.exists) {
                $exists = [bool]$simTool.exists
            }
            $tools += [pscustomobject]@{
                Name = [string]$t.name
                PathEnvVar = [string]$t.pathEnvVar
                RelativePath = [string]$t.relativePath
                Exists = $exists
            }
        }

        $mobiusHomeDefined = $false
        if ($null -ne $simulated.mobiusHomeDefined) {
            $mobiusHomeDefined = [bool]$simulated.mobiusHomeDefined
        }

        return [pscustomobject]@{
            Sources = $sources
            Destination = [pscustomobject]@{
                Path = [string]$profileConfig.destination
                Drive = [string]$profileConfig.destinationDrive
                Exists = $destExists
                Writable = $destWritable
            }
            Tools = $tools
            MobiusHomeDefined = $mobiusHomeDefined
            Simulated = $true
        }
    }

    # Real System Check
    # 1. Sources
    $sources = @()
    foreach ($src in $profileConfig.sources) {
        $pathToCheck = [string]$src.path
        $exists = $false
        if (Test-Path -Path $pathToCheck -PathType Container) {
            $exists = $true
        }
        $sources += [pscustomobject]@{
            Path = $pathToCheck
            Pattern = [string]$src.pattern
            Type = [string]$src.type
            Description = [string]$src.description
            Blocking = [bool]$src.blocking
            Exists = $exists
        }
    }

    # 2. Destination
    $destPath = [string]$profileConfig.destination
    $destDrive = [string]$profileConfig.destinationDrive
    $destExists = $false
    $destWritable = $false

    $drivePath = "${destDrive}:"
    if (Test-Path -Path $drivePath) {
        $destExists = $true
        try {
            if (-not (Test-Path -Path $destPath -PathType Container)) {
                New-Item -ItemType Directory -Path $destPath -Force -ErrorAction Stop | Out-Null
            }
            if (Test-Path -Path $destPath -PathType Container) {
                $tempFile = Join-Path -Path $destPath -ChildPath "preflight_temp_$([Guid]::NewGuid().ToString()).tmp"
                Set-Content -Path $tempFile -Value "Preflight write test" -ErrorAction Stop
                if (Test-Path -Path $tempFile -PathType Leaf) {
                    $destWritable = $true
                    Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch {
            $destWritable = $false
        }
    }

    # 3. Tools (only for SM)
    $tools = @()
    $mobiusHomeDefined = $false
    $mobiusHome = $env:MOBIUS_HOME
    if ($null -ne $mobiusHome -and $mobiusHome.Trim() -ne "") {
        $mobiusHomeDefined = $true
    }

    foreach ($t in $profileConfig.requiredTools) {
        $exists = $false
        if ($mobiusHomeDefined) {
            $toolPath = Join-Path -Path $mobiusHome -ChildPath [string]$t.relativePath
            if (Test-Path -Path $toolPath -PathType Leaf) {
                $exists = $true
            }
        }
        $tools += [pscustomobject]@{
            Name = [string]$t.name
            PathEnvVar = [string]$t.pathEnvVar
            RelativePath = [string]$t.relativePath
            Exists = $exists
        }
    }

    return [pscustomobject]@{
        Sources = $sources
        Destination = [pscustomobject]@{
            Path = $destPath
            Drive = $destDrive
            Exists = $destExists
            Writable = $destWritable
        }
        Tools = $tools
        MobiusHomeDefined = $mobiusHomeDefined
        Simulated = $false
    }
}

# --- Carga de manifiesto y datos de sistema ---
$manifest = Get-BackupRequirementsManifest -ManifestPath $ManifestPath
if (-not $manifest.profiles.$Profile) {
    throw "Perfil '$Profile' no definido en el manifiesto de backup."
}

$profileConfig = $manifest.profiles.$Profile
$inventory = Get-BackupInventory -ProfileConfig $profileConfig -SystemInfoPath $SystemInfoPath

$checks = @()

# --- check-backup-sources ---
$foundSources = @()
$missingBlocking = @()
$missingNonBlocking = @()
foreach ($s in $inventory.Sources) {
    $desc = $s.Description
    if ($s.Exists) {
        $foundSources += "${desc} (existe)"
    }
    else {
        if ($s.Blocking) {
            $missingBlocking += "${desc} (bloqueante)"
        }
        else {
            $missingNonBlocking += "${desc} (opcional)"
        }
    }
}

$sourcesStatus = "Pass"
$sourcesDetail = ""
if ($missingBlocking.Count -gt 0) {
    $sourcesStatus = "Warning"
    $sourcesDetail = "Faltan fuentes obligatorias: $($missingBlocking -join ', '). Encontradas: $($foundSources -join ', ')."
    if ($missingNonBlocking.Count -gt 0) {
        $sourcesDetail += " Faltan fuentes opcionales: $($missingNonBlocking -join ', ')."
    }
}
elseif ($missingNonBlocking.Count -gt 0) {
    $sourcesStatus = "Warning"
    $sourcesDetail = "Todas las fuentes obligatorias encontradas. Faltan fuentes opcionales: $($missingNonBlocking -join ', '). Encontradas: $($foundSources -join ', ')."
}
else {
    $sourcesStatus = "Pass"
    $sourcesDetail = "Todas las fuentes (obligatorias y opcionales) existen: $($foundSources -join ', ')."
}

$checks += [pscustomobject]@{
    Id = "check-backup-sources"
    Name = "Validar fuentes de backup"
    Status = $sourcesStatus
    Detail = $sourcesDetail
    Blocking = $true
}

# --- check-backup-destination ---
$destStatus = "Pass"
$destDetail = ""
$destPath = $inventory.Destination.Path
if ($inventory.Destination.Exists -and $inventory.Destination.Writable) {
    $destStatus = "Pass"
    $destDetail = "La ruta de destino ${destPath} existe y es escribible."
}
elseif (-not $inventory.Destination.Exists) {
    $driveLetter = $inventory.Destination.Drive
    $destStatus = "Warning"
    $destDetail = "La unidad de destino ${driveLetter}: no existe o no esta accesible."
}
else {
    $destStatus = "Warning"
    $destDetail = "La ruta de destino ${destPath} existe pero no es escribible (permiso denegado)."
}

$checks += [pscustomobject]@{
    Id = "check-backup-destination"
    Name = "Validar destino de backup"
    Status = $destStatus
    Detail = $destDetail
    Blocking = $true
}

# --- check-backup-tools ---
$toolsStatus = "Pass"
$toolsDetail = ""
if ($Profile -eq "IPC_RIP") {
    $toolsStatus = "Info"
    $toolsDetail = "El perfil IPC/RIP no requiere herramientas adicionales."
}
else {
    if (-not $inventory.MobiusHomeDefined) {
        $toolsStatus = "Warning"
        $toolsDetail = "La variable de entorno MOBIUS_HOME no esta definida."
    }
    else {
        $missingTools = @()
        $foundTools = @()
        foreach ($t in $inventory.Tools) {
            if ($t.Exists) {
                $foundTools += $t.Name
            }
            else {
                $missingTools += $t.Name
            }
        }

        if ($missingTools.Count -gt 0) {
            $toolsStatus = "Warning"
            $toolsDetail = "Faltan herramientas requeridas en MOBIUS_HOME: $($missingTools -join ', '). Encontradas: $($foundTools -join ', ')."
        }
        else {
            $toolsStatus = "Pass"
            $toolsDetail = "Todas las herramientas requeridas estan presentes en MOBIUS_HOME: $($foundTools -join ', ')."
        }
    }
}

$checks += [pscustomobject]@{
    Id = "check-backup-tools"
    Name = "Validar herramientas de backup"
    Status = $toolsStatus
    Detail = $toolsDetail
    Blocking = $true
}

# --- Estado general ---
$hwRequirements = Get-HardwareRequirementsManifest -HardwareManifestPath $HardwareManifestPath
$validationMode = "enforcing"
if ($hwRequirements.validationMode) {
    $validationMode = [string]$hwRequirements.validationMode
}

$realStatus = "Pass"
$hasWarning = $false
$hasFail = $false

foreach ($check in $checks) {
    if ($check.Status -eq "Fail") {
        $hasFail = $true
    }
    elseif ($check.Status -eq "Warning") {
        $hasWarning = $true
    }
}

if ($hasFail) {
    $realStatus = "Fail"
}
elseif ($hasWarning) {
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

# --- Resúmenes de campos de salida específicos ---
$foundList = @()
$missingList = @()
foreach ($s in $inventory.Sources) {
    if ($s.Exists) {
        $foundList += $s.Path
    }
    else {
        $missingList += $s.Path
    }
}
$sourcesSummary = [pscustomobject]@{
    Total = $inventory.Sources.Count
    FoundCount = $foundList.Count
    MissingCount = $missingList.Count
    Found = $foundList
    Missing = $missingList
}

$destSummary = [pscustomobject]@{
    Path = $inventory.Destination.Path
    Exists = $inventory.Destination.Exists
    Writable = $inventory.Destination.Writable
}

$foundToolsList = @()
$missingToolsList = @()
foreach ($t in $inventory.Tools) {
    if ($t.Exists) {
        $foundToolsList += $t.Name
    }
    else {
        $missingToolsList += $t.Name
    }
}
$toolsSummary = [pscustomobject]@{
    MobiusHomeDefined = $inventory.MobiusHomeDefined
    Found = $foundToolsList
    Missing = $missingToolsList
}

$result = [pscustomobject]@{
    Status = $finalStatus
    RealStatus = $realStatus
    ValidationMode = $validationMode
    DegradedByMode = $degradedByMode
    TestModeApplied = $testModeApplied
    Product = $Product
    Version = $Version
    Profile = $Profile
    Checks = $checks
    Sources = $sourcesSummary
    Destination = $destSummary
    Tools = $toolsSummary
    SimulatedSource = $inventory.Simulated
}

Write-Output $result
