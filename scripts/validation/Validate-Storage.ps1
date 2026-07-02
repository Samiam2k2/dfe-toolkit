<#
.SYNOPSIS
    Valida el almacenamiento del servidor DFE contra los requisitos aprobados.
.DESCRIPTION
    Script independiente compatible con Windows PowerShell 5.1 (sin dependencias
    externas). Ejecuta los 3 checks de categoria "storage" definidos en
    manifests/assessment-checks.json:
        - check-storage-free-space
        - check-storage-drive-layout
        - check-storage-backup-location

    Devuelve al pipeline un objeto estructurado con el estado general y el
    detalle por check. Puede leer los datos del sistema real o de un JSON
    simulado (-SystemInfoPath) para pruebas en laboratorio/VM.

    El nombre y el flag "blocking" de cada check se leen de assessment-checks.json.
.PARAMETER Product
    Nombre del producto a evaluar. Por defecto "Production Pro".
.PARAMETER Version
    Version del producto. Por defecto "8.3".
.PARAMETER ManifestPath
    Ruta local a storage-requirements.json. Si no se provee y no existe la copia
    local, se descarga de raw.githubusercontent con cache-bust.
.PARAMETER AssessmentPath
    Ruta local a assessment-checks.json (de donde se toma name/blocking de cada
    check). Si no se provee y no existe la copia local, se descarga con cache-bust.
.PARAMETER HardwareManifestPath
    Ruta local a hardware-requirements.json. Se usa para determinar validationMode.
.PARAMETER Profile
    Perfil de la maquina: "SystemManager" o "IPC_RIP". Por defecto "SystemManager".
.PARAMETER SystemInfoPath
    Ruta opcional a un JSON con datos de disco simulados.
.PARAMETER TestMode
    Si se especifica, el Status general se fuerza a Pass y se agrega
    TestModeApplied=true, dejando visibles los resultados reales por check.
.OUTPUTS
    [pscustomobject] con: Status, RealStatus, ValidationMode, DegradedByMode,
    TestModeApplied, Product, Version, Profile, Checks (arreglo de objetos
    Id/Name/Status/Detail/Blocking), Drives y SimulatedSource.
#>

[CmdletBinding()]
param(
    [string]$Product = "Production Pro",
    [string]$Version = "8.3",
    [string]$ManifestPath,
    [string]$AssessmentPath,
    [string]$HardwareManifestPath,
    [string]$Profile = "SystemManager",
    [string]$SystemInfoPath,
    [switch]$TestMode
)

function Get-StorageRequirementsManifest {
    param(
        [string]$ManifestPath
    )

    if ($ManifestPath) {
        if (-not (Test-Path -Path $ManifestPath -PathType Leaf)) {
            throw "No se encontro el manifiesto de almacenamiento en la ruta indicada: $ManifestPath"
        }
        return Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json
    }

    $projectRoot = $null
    if ($PSScriptRoot) {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }

    if ($projectRoot) {
        $localPath = Join-Path -Path $projectRoot -ChildPath "manifests\storage-requirements.json"
        if (Test-Path -Path $localPath -PathType Leaf) {
            return Get-Content -Path $localPath -Raw | ConvertFrom-Json
        }
    }

    $requirementsUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/manifests/storage-requirements.json?cacheBust=$([DateTime]::UtcNow.Ticks)"
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

function Get-StorageInventory {
    param(
        [string]$SystemInfoPath,
        [string]$BackupPath
    )

    if ($SystemInfoPath) {
        if (-not (Test-Path -Path $SystemInfoPath -PathType Leaf)) {
            throw "No se encontro el JSON de sistema simulado: $SystemInfoPath"
        }

        $simulated = Get-Content -Path $SystemInfoPath -Raw | ConvertFrom-Json

        $drives = @()
        foreach ($drive in @($simulated.drives)) {
            $freeGb = $null
            if ($null -ne $drive.freeGB) { $freeGb = [double]$drive.freeGB }

            $sizeGb = $null
            if ($null -ne $drive.sizeGB) { $sizeGb = [double]$drive.sizeGB }

            $exists = $true
            if ($null -ne $drive.exists) { $exists = [bool]$drive.exists }

            $drives += [pscustomobject]@{
                Letter = [string]$drive.letter
                FreeGB = $freeGb
                SizeGB = $sizeGb
                Exists = $exists
            }
        }

        $backupPathExists = $false
        if ($null -ne $simulated.backupPathExists) { $backupPathExists = [bool]$simulated.backupPathExists }

        $backupPathWritable = $false
        if ($null -ne $simulated.backupPathWritable) { $backupPathWritable = [bool]$simulated.backupPathWritable }

        return [pscustomobject]@{
            Drives = $drives
            BackupPathExists = $backupPathExists
            BackupPathWritable = $backupPathWritable
            Simulated = $true
        }
    }

    # Query local drives using Win32_LogicalDisk (DeviceID, Size, FreeSpace, DriveType)
    # DriveType 3 is Local Disk.
    $logicalDisks = @(Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 })
    $drives = @()
    foreach ($disk in $logicalDisks) {
        $letter = $disk.DeviceID.Replace(":", "").ToUpper()
        $sizeGb = $null
        if ($disk.Size) { $sizeGb = [math]::Round([double]$disk.Size / 1GB, 2) }
        $freeGb = $null
        if ($disk.FreeSpace) { $freeGb = [math]::Round([double]$disk.FreeSpace / 1GB, 2) }

        $drives += [pscustomobject]@{
            Letter = $letter
            FreeGB = $freeGb
            SizeGB = $sizeGb
            Exists = $true
        }
    }

    $backupPathExists = $false
    $backupPathWritable = $false
    if ($BackupPath) {
        if (Test-Path -Path $BackupPath -PathType Container) {
            $backupPathExists = $true
            try {
                $tempFile = Join-Path -Path $BackupPath -ChildPath "test_write_$([Guid]::NewGuid().Guid).tmp"
                "test" | Out-File -FilePath $tempFile -Encoding utf8 -ErrorAction Stop
                if (Test-Path -Path $tempFile -PathType Leaf) {
                    $backupPathWritable = $true
                    Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue | Out-Null
                }
            }
            catch {
                $backupPathWritable = $false
            }
        }
    }

    return [pscustomobject]@{
        Drives = $drives
        BackupPathExists = $backupPathExists
        BackupPathWritable = $backupPathWritable
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
$requirements = Get-StorageRequirementsManifest -ManifestPath $ManifestPath
$assessment = Get-AssessmentChecksManifest -AssessmentPath $AssessmentPath

# Obtener ruta de backup segun el Profile
$backupLoc = $requirements.backupLocations | Where-Object { $_.profile -eq $Profile } | Select-Object -First 1
if (-not $backupLoc) {
    throw "No se encontro la ruta de backup para el perfil '$Profile' en el manifiesto."
}
$backupPath = $backupLoc.path

$system = Get-StorageInventory -SystemInfoPath $SystemInfoPath -BackupPath $backupPath

# --- Validar unidades y layout ---
$expectedDrives = @($requirements.expectedDrives)
$expectedNames = @($expectedDrives | ForEach-Object { [string]$_.letter.ToUpper() })

$foundExpected = @()
$missingExpected = @()
foreach ($expected in $expectedDrives) {
    $driveLetter = [string]$expected.letter.ToUpper()
    $driveRole = [string]$expected.role
    
    $drive = $system.Drives | Where-Object { $_.Letter.ToUpper() -eq $driveLetter } | Select-Object -First 1
    if ($drive) {
        $foundExpected += [string]$driveLetter
    }
    else {
        $missingExpected += [string]"$driveLetter (rol $driveRole)"
    }
}

$unexpectedDrives = @()
foreach ($d in $system.Drives) {
    $letter = $d.Letter.ToUpper()
    if ($expectedNames -notcontains $letter) {
        $unexpectedDrives += [string]$letter
    }
}

$drivesInventory = [pscustomobject]@{
    Expected = $expectedNames
    FoundExpected = $foundExpected
    MissingExpected = $missingExpected
    Unexpected = $unexpectedDrives
}

$checks = @()

# --- check-storage-drive-layout ---
$layoutMeta = Get-CheckMeta -Assessment $assessment -Id "check-storage-drive-layout"
if ($missingExpected.Count -eq 0) {
    $checks += New-CheckResult -Meta $layoutMeta -Status "Pass" -Detail "Se encontraron todas las unidades esperadas: $($expectedNames -join ', ')."
}
else {
    $missingDetails = @()
    foreach ($m in $missingExpected) {
        $missingDetails += "Falta la unidad $m"
    }
    $checks += New-CheckResult -Meta $layoutMeta -Status "Warning" -Detail ($missingDetails -join "; ")
}

# --- check-storage-free-space ---
$freeSpaceMeta = Get-CheckMeta -Assessment $assessment -Id "check-storage-free-space"
$freeSpaceProblems = @()
$freeSpaceDetails = @()
$hasNullMin = $false
$hasFailedMin = $false

foreach ($expected in $expectedDrives) {
    $driveLetter = [string]$expected.letter.ToUpper()
    $driveRole = [string]$expected.role
    $minFreeGB = $expected.minFreeGB

    $drive = $system.Drives | Where-Object { $_.Letter.ToUpper() -eq $driveLetter } | Select-Object -First 1
    if (-not $drive) {
        $freeSpaceDetails += "unidad ${driveLetter}: no encontrada"
        $freeSpaceProblems += "unidad ${driveLetter}: no existe"
        continue
    }

    $actualFree = $drive.FreeGB
    if ($null -eq $actualFree) {
        $freeSpaceDetails += "unidad ${driveLetter}: libre no determinado"
        $freeSpaceProblems += "unidad ${driveLetter}: no se pudo determinar espacio libre"
        continue
    }

    $freeSpaceDetails += "unidad ${driveLetter}: $actualFree GB libres"

    if ($null -eq $minFreeGB) {
        $hasNullMin = $true
    }
    else {
        if ($actualFree -lt $minFreeGB) {
            $hasFailedMin = $true
            $freeSpaceProblems += "unidad ${driveLetter}: $actualFree GB libres (minimo $minFreeGB GB)"
        }
    }
}

if ($hasFailedMin) {
    $checks += New-CheckResult -Meta $freeSpaceMeta -Status "Fail" -Detail "No cumple minimos de espacio libre: $($freeSpaceProblems -join '; '). Detalles: $($freeSpaceDetails -join ', ')."
}
elseif ($freeSpaceProblems.Count -gt 0) {
    $checks += New-CheckResult -Meta $freeSpaceMeta -Status "Warning" -Detail "Problemas de espacio libre: $($freeSpaceProblems -join '; '). Detalles: $($freeSpaceDetails -join ', ')."
}
elseif ($hasNullMin) {
    $checks += New-CheckResult -Meta $freeSpaceMeta -Status "Warning" -Detail "Espacio libre detectado por unidad: $($freeSpaceDetails -join ', '). El manifiesto no define minimo (minFreeGB) para comparar."
}
else {
    $checks += New-CheckResult -Meta $freeSpaceMeta -Status "Pass" -Detail "Espacio libre suficiente: $($freeSpaceDetails -join ', ')."
}

# --- check-storage-backup-location ---
$backupMeta = Get-CheckMeta -Assessment $assessment -Id "check-storage-backup-location"
if ($system.BackupPathExists) {
    if ($system.BackupPathWritable) {
        $checks += New-CheckResult -Meta $backupMeta -Status "Pass" -Detail "La ruta de backup '$backupPath' existe y es escribible para el perfil '$Profile'."
    }
    else {
        $checks += New-CheckResult -Meta $backupMeta -Status "Warning" -Detail "La ruta de backup '$backupPath' existe pero no tiene permisos de escritura para el perfil '$Profile'."
    }
}
else {
    $checks += New-CheckResult -Meta $backupMeta -Status "Warning" -Detail "la ruta de backup $backupPath no existe (se creara al ejecutar el backup)"
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
    elseif ($check.Status -eq "Warning" -or $check.Status -eq "Fail" -or $check.Status -eq "Info") {
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
    Drives = $drivesInventory
    SimulatedSource = $system.Simulated
}

Write-Output $result
