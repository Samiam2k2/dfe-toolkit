<#
.SYNOPSIS
    Valida el sistema operativo del servidor DFE contra los requisitos aprobados.
.DESCRIPTION
    Script independiente compatible con Windows PowerShell 5.1 (sin dependencias
    externas). Ejecuta 2 de los 4 checks de categoria "operating-system" definidos
    en manifests/assessment-checks.json, mas un tercer check informativo:
        - check-operating-system-version (blocking segun assessment)
        - check-os-architecture (blocking segun assessment)
        - check-os-build (informativo por ahora; blocking segun assessment)

    NO incluye check-pending-reboot (se hara en un paso posterior de
    pre-instalacion).

    El SO valido depende del hardware: NO existe un manifiesto de SO propio. Se
    reutiliza la matriz de compatibilidad de manifests/hardware-requirements.json,
    donde cada regla (newInstallation/upgrade) ya trae requiredOperatingSystemPatterns.
    El Paso 3 valida el SO detectado contra los patrones de SO de las reglas cuyo
    modelo coincide con el servidor.

    Devuelve al pipeline un objeto estructurado con el estado general y el detalle
    por check. Puede leer los datos del sistema real (Get-CimInstance) o de un JSON
    simulado (-SystemInfoPath) para pruebas en laboratorio/VM.
.PARAMETER Product
    Nombre del producto a evaluar. Por defecto "Production Pro".
.PARAMETER Version
    Version del producto. Por defecto "8.3".
.PARAMETER ManifestPath
    Ruta local a hardware-requirements.json. Si no se provee y no existe la copia
    local, se descarga de raw.githubusercontent con cache-bust.
.PARAMETER AssessmentPath
    Ruta local a assessment-checks.json (de donde se toma name/blocking de cada
    check). Si no se provee y no existe la copia local, se descarga con cache-bust.
.PARAMETER SystemInfoPath
    Ruta opcional a un JSON con datos de sistema simulados
    (manufacturer, model, osCaption, osArchitecture, osVersion).
    Si se provee, se usan esos datos en vez de Get-CimInstance.
.PARAMETER TestMode
    Si se especifica, el Status general se fuerza a Pass y se agrega
    TestModeApplied=true, dejando visibles los resultados reales por check.
.OUTPUTS
    [pscustomobject] con: Status, RealStatus, ValidationMode, DegradedByMode,
    TestModeApplied, Product, Version, Manufacturer, Model, OperatingSystem,
    OSArchitecture, Checks (arreglo de objetos Id/Name/Status/Detail/Blocking).
#>

[CmdletBinding()]
param(
    [string]$Product = "Production Pro",
    [string]$Version = "8.3",
    [string]$ManifestPath,
    [string]$AssessmentPath,
    [string]$SystemInfoPath,
    [switch]$TestMode
)

# Nota: Test-PatternList replica la funcion homonima de Validate-Hardware.ps1.
# Se duplica a proposito para no depender de un dot-source, que complicaria el
# patron de ejecucion via irm|iex (descarga de un unico script).
function Test-PatternList {
    param(
        [string]$Value,
        [object[]]$Patterns
    )

    foreach ($pattern in @($Patterns)) {
        if ($Value -like "*$pattern*") {
            return $true
        }
    }

    return $false
}

function Get-HardwareRequirementsManifest {
    param(
        [string]$ManifestPath
    )

    if ($ManifestPath) {
        if (-not (Test-Path -Path $ManifestPath -PathType Leaf)) {
            throw "No se encontro el manifiesto de hardware en la ruta indicada: $ManifestPath"
        }
        return Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json
    }

    $projectRoot = $null
    if ($PSScriptRoot) {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }

    if ($projectRoot) {
        $localPath = Join-Path -Path $projectRoot -ChildPath "manifests\production-pro\8.3\hardware.json"
        if (Test-Path -Path $localPath -PathType Leaf) {
            return Get-Content -Path $localPath -Raw | ConvertFrom-Json
        }
    }

    $requirementsUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/manifests/production-pro/8.3/hardware.json?cacheBust=$([DateTime]::UtcNow.Ticks)"
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
        $localPath = Join-Path -Path $projectRoot -ChildPath "manifests\production-pro\8.3\assessment-checks.json"
        if (Test-Path -Path $localPath -PathType Leaf) {
            return Get-Content -Path $localPath -Raw | ConvertFrom-Json
        }
    }

    $assessmentUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/manifests/production-pro/8.3/assessment-checks.json?cacheBust=$([DateTime]::UtcNow.Ticks)"
    return Invoke-RestMethod -Uri $assessmentUrl -Headers @{
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
    } -ErrorAction Stop
}

function Get-OperatingSystemInventory {
    param(
        [string]$SystemInfoPath
    )

    if ($SystemInfoPath) {
        if (-not (Test-Path -Path $SystemInfoPath -PathType Leaf)) {
            throw "No se encontro el JSON de sistema simulado: $SystemInfoPath"
        }

        $simulated = Get-Content -Path $SystemInfoPath -Raw | ConvertFrom-Json

        $osArch = ""
        if ($simulated.osArchitecture) { $osArch = [string]$simulated.osArchitecture }

        $osVersion = ""
        if ($simulated.osVersion) { $osVersion = [string]$simulated.osVersion }

        return [pscustomobject]@{
            Manufacturer = [string]$simulated.manufacturer
            Model = [string]$simulated.model
            OperatingSystem = [string]$simulated.osCaption
            OSArchitecture = $osArch
            OSVersion = $osVersion
            Simulated = $true
        }
    }

    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop

    $osArch = ""
    if ($operatingSystem.OSArchitecture) { $osArch = [string]$operatingSystem.OSArchitecture }

    $osVersion = ""
    if ($operatingSystem.Version) { $osVersion = [string]$operatingSystem.Version }

    return [pscustomobject]@{
        Manufacturer = [string]$computerSystem.Manufacturer
        Model = [string]$computerSystem.Model
        OperatingSystem = [string]$operatingSystem.Caption
        OSArchitecture = $osArch
        OSVersion = $osVersion
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
$requirements = Get-HardwareRequirementsManifest -ManifestPath $ManifestPath
$assessment = Get-AssessmentChecksManifest -AssessmentPath $AssessmentPath

$productRules = $requirements.products | Where-Object {
    $_.productName -eq $Product -and $_.version -eq $Version
} | Select-Object -First 1

if (-not $productRules) {
    throw "No se encontraron reglas de hardware para $Product $Version."
}

$system = Get-OperatingSystemInventory -SystemInfoPath $SystemInfoPath

$manufacturer = $system.Manufacturer
$model = $system.Model
$osCaption = $system.OperatingSystem
$osArchitecture = $system.OSArchitecture

# --- Resolver que reglas de hardware coinciden con el MODELO detectado ---
# El SO esperado depende del hardware: se toma el conjunto de reglas
# (newInstallation + upgrade) cuyo modelPatterns coincide con el modelo.
# (Mismo criterio de match de modelo que Validate-Hardware.ps1.)
$modelMatchedRules = @()
foreach ($rule in @($productRules.rules.newInstallation.allowedHardware) + @($productRules.rules.upgrade.allowedHardware)) {
    if (Test-PatternList -Value $model -Patterns $rule.modelPatterns) {
        $modelMatchedRules += $rule
    }
}

$checks = @()

# --- check-operating-system-version ---
$osVersionMeta = Get-CheckMeta -Assessment $assessment -Id "check-operating-system-version"

if ($modelMatchedRules.Count -eq 0) {
    # El modelo no corresponde a ninguna configuracion conocida. NO se marca Fail:
    # la incompatibilidad de hardware ya la reporta el Paso 1; aqui solo se avisa.
    $checks += New-CheckResult -Meta $osVersionMeta -Status "Warning" -Detail "No se pudo determinar el SO esperado porque el modelo '$model' no corresponde a una configuracion de hardware conocida. Valide primero el hardware (Paso 1)."
}
else {
    $approvedOsPatterns = @()
    foreach ($rule in $modelMatchedRules) {
        foreach ($pattern in @($rule.requiredOperatingSystemPatterns)) {
            if ($approvedOsPatterns -notcontains $pattern) {
                $approvedOsPatterns += $pattern
            }
        }
    }

    if (Test-PatternList -Value $osCaption -Patterns $approvedOsPatterns) {
        $checks += New-CheckResult -Meta $osVersionMeta -Status "Pass" -Detail "SO detectado: '$osCaption'. Aprobado para el modelo '$model' (esperado: $($approvedOsPatterns -join ', '))."
    }
    else {
        $checks += New-CheckResult -Meta $osVersionMeta -Status "Fail" -Detail "SO detectado: '$osCaption'. No esta entre los SO aprobados para el modelo '$model' (esperado: $($approvedOsPatterns -join ', '))."
    }
}

# --- check-os-architecture ---
$osArchMeta = Get-CheckMeta -Assessment $assessment -Id "check-os-architecture"

# Variantes de string para 64 bits: "64-bit", "64 bits", "x64".
$is64Bit = ($osArchitecture -like "*64*")

if (-not $osArchitecture) {
    $checks += New-CheckResult -Meta $osArchMeta -Status "Warning" -Detail "No se pudo determinar la arquitectura del sistema operativo."
}
elseif ($is64Bit) {
    $checks += New-CheckResult -Meta $osArchMeta -Status "Pass" -Detail "Arquitectura detectada: '$osArchitecture'. Sistema operativo de 64 bits."
}
else {
    $checks += New-CheckResult -Meta $osArchMeta -Status "Fail" -Detail "Arquitectura detectada: '$osArchitecture'. Se requiere un sistema operativo de 64 bits."
}

# --- check-os-build (informativo por ahora) ---
$osBuildMeta = Get-CheckMeta -Assessment $assessment -Id "check-os-build"

$approvedBuilds = @()
if ($requirements.osBuildBaseline -and $requirements.osBuildBaseline.approvedBuilds) {
    $approvedBuilds = @($requirements.osBuildBaseline.approvedBuilds)
}

$buildDetected = $osArchitecture
if ($system.OSVersion) { $buildDetected = $system.OSVersion }

if ($approvedBuilds.Count -eq 0) {
    # Sin baseline definido el check es puramente informativo: se registra con
    # Status "Info" (se muestra con icono de advertencia en la UI) y es NEUTRO
    # para el estado general, para no arrastrar todo el paso a Warning solo por
    # falta de baseline. En cuanto se agregue osBuildBaseline pasa a Pass/Fail.
    $checks += New-CheckResult -Meta $osBuildMeta -Status "Info" -Detail "Build detectado: '$($system.OSVersion)'. El manifiesto no define un baseline de build aprobado. Check informativo; agregue osBuildBaseline para validar."
}
else {
    if (Test-PatternList -Value $system.OSVersion -Patterns $approvedBuilds) {
        $checks += New-CheckResult -Meta $osBuildMeta -Status "Pass" -Detail "Build detectado: '$($system.OSVersion)'. Coincide con el baseline aprobado ($($approvedBuilds -join ', '))."
    }
    else {
        $checks += New-CheckResult -Meta $osBuildMeta -Status "Fail" -Detail "Build detectado: '$($system.OSVersion)'. No coincide con el baseline aprobado ($($approvedBuilds -join ', '))."
    }
}

# --- Estado general ---
# Orden: RealStatus (enforcing) -> degradacion por validationMode -> TestMode.
# Misma logica de dos fases + TestMode que Validate-Hardware.ps1.

# validationMode del manifiesto. Default "enforcing" si el campo no existe.
$validationMode = "enforcing"
if ($requirements.validationMode) {
    $validationMode = [string]$requirements.validationMode
}

# Fase a) RealStatus con logica enforcing (alineada con Validate-Hardware.ps1):
# Fail si algun check bloqueante da Fail; Warning si sin Fails bloqueantes hay al
# menos un Warning o un Fail no bloqueante; Pass si todo Pass.
$realStatus = "Pass"
$hasBlockingFail = $false
$hasWarningOrNonBlockingFail = $false
foreach ($check in $checks) {
    if ($check.Status -eq "Fail" -and $check.Blocking) {
        $hasBlockingFail = $true
    }
    elseif ($check.Status -eq "Warning" -or $check.Status -eq "Fail") {
        $hasWarningOrNonBlockingFail = $true
    }
}

if ($hasBlockingFail) {
    $realStatus = "Fail"
}
elseif ($hasWarningOrNonBlockingFail) {
    $realStatus = "Warning"
}

# Fase b) En modo informational, un Fail real se degrada a Warning. RealStatus
# SIEMPRE conserva el valor sin degradar para dejar el rastro honesto.
$finalStatus = $realStatus
$degradedByMode = $false
if ($validationMode -eq "informational" -and $realStatus -eq "Fail") {
    $finalStatus = "Warning"
    $degradedByMode = $true
}

# Fase c) -TestMode se aplica encima al final: fuerza Status a Pass.
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
    Manufacturer = $manufacturer
    Model = $model
    OperatingSystem = $osCaption
    OSArchitecture = $osArchitecture
    SimulatedSource = $system.Simulated
    Checks = $checks
}

Write-Output $result
