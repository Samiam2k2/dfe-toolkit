<#
.SYNOPSIS
    Valida el hardware del servidor DFE contra los requisitos aprobados.
.DESCRIPTION
    Script independiente compatible con Windows PowerShell 5.1 (sin dependencias
    externas). Ejecuta los 5 checks de categoria "hardware" definidos en
    manifests/assessment-checks.json:
        - check-hardware-model
        - check-hardware-manufacturer
        - check-hardware-generation
        - check-memory-capacity
        - check-cpu-inventory

    Devuelve al pipeline un objeto estructurado con el estado general y el
    detalle por check. Puede leer los datos del sistema real (Get-CimInstance)
    o de un JSON simulado (-SystemInfoPath) para pruebas en laboratorio/VM.
.PARAMETER Product
    Nombre del producto a evaluar. Por defecto "Production Pro".
.PARAMETER Version
    Version del producto. Por defecto "8.3".
.PARAMETER ManifestPath
    Ruta local a hardware-requirements.json. Si no se provee y no existe la copia
    local, se descarga de raw.githubusercontent con cache-bust.
.PARAMETER SystemInfoPath
    Ruta opcional a un JSON con datos de sistema simulados
    (manufacturer, model, osCaption, memoryGB, cpuSockets, cpuCores).
    Si se provee, se usan esos datos en vez de Get-CimInstance.
.PARAMETER TestMode
    Si se especifica, el Status general se fuerza a Pass y se agrega
    TestModeApplied=true, dejando visibles los resultados reales por check.
.OUTPUTS
    [pscustomobject] con: Status, TestModeApplied, Product, Version,
    Manufacturer, Model, OperatingSystem, MemoryGB, CpuSockets, CpuCores,
    Checks (arreglo de objetos Id/Name/Status/Detail/Blocking).
#>

[CmdletBinding()]
param(
    [string]$Product = "Production Pro",
    [string]$Version = "8.3",
    [string]$ManifestPath,
    [string]$SystemInfoPath,
    [switch]$TestMode
)

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

function Convert-RuleIdToLabel {
    param([string]$RuleId)

    $textInfo = (Get-Culture).TextInfo
    $parts = $RuleId -split "-"
    $hardwareParts = @()
    $osParts = @()
    $osStarted = $false

    foreach ($part in $parts) {
        if ($part -eq "windows") {
            $osStarted = $true
        }

        if ($osStarted) {
            $osParts += $part
        }
        else {
            $hardwareParts += $part
        }
    }

    $hardware = ($hardwareParts | ForEach-Object {
        switch -Regex ($_) {
            "^hp$" { "HP"; break }
            "^hpe$" { "HPE"; break }
            "^z\d+" { $_.ToUpper(); break }
            "^g\d+" { $_.ToUpper(); break }
            "^gen\d+" { "Gen" + $_.Substring(3); break }
            "^dl\d+" { $_.ToUpper(); break }
            default { $textInfo.ToTitleCase($_) }
        }
    }) -join " "

    $os = ($osParts | ForEach-Object {
        switch -Regex ($_) {
            "^windows$" { "Windows"; break }
            "^server$" { "Server"; break }
            default { $_ }
        }
    }) -join " "

    return "$hardware + $os"
}

function Test-HardwareRule {
    param(
        [object]$Rule,
        [string]$Manufacturer,
        [string]$Model,
        [string]$OperatingSystem
    )

    $manufacturerMatch = Test-PatternList -Value $Manufacturer -Patterns $Rule.manufacturerPatterns
    $modelMatch = Test-PatternList -Value $Model -Patterns $Rule.modelPatterns
    $osMatch = Test-PatternList -Value $OperatingSystem -Patterns $Rule.requiredOperatingSystemPatterns

    return ($manufacturerMatch -and $modelMatch -and $osMatch)
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

function Get-SystemInventory {
    param(
        [string]$SystemInfoPath
    )

    if ($SystemInfoPath) {
        if (-not (Test-Path -Path $SystemInfoPath -PathType Leaf)) {
            throw "No se encontro el JSON de sistema simulado: $SystemInfoPath"
        }

        $simulated = Get-Content -Path $SystemInfoPath -Raw | ConvertFrom-Json

        $memoryGb = $null
        if ($null -ne $simulated.memoryGB) { $memoryGb = [double]$simulated.memoryGB }

        $cpuSockets = $null
        if ($null -ne $simulated.cpuSockets) { $cpuSockets = [int]$simulated.cpuSockets }

        $cpuCores = $null
        if ($null -ne $simulated.cpuCores) { $cpuCores = [int]$simulated.cpuCores }

        $cpuName = ""
        if ($simulated.cpuName) { $cpuName = [string]$simulated.cpuName }

        return [pscustomobject]@{
            Manufacturer = [string]$simulated.manufacturer
            Model = [string]$simulated.model
            OperatingSystem = [string]$simulated.osCaption
            MemoryGB = $memoryGb
            CpuSockets = $cpuSockets
            CpuCores = $cpuCores
            CpuName = $cpuName
            Simulated = $true
        }
    }

    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)

    $memoryGb = $null
    if ($computerSystem.TotalPhysicalMemory) {
        $memoryGb = [math]::Round([double]$computerSystem.TotalPhysicalMemory / 1GB, 2)
    }

    $cpuSockets = $processors.Count
    $cpuCores = 0
    foreach ($processor in $processors) {
        if ($processor.NumberOfCores) {
            $cpuCores += [int]$processor.NumberOfCores
        }
    }

    $cpuName = ""
    if ($processors.Count -gt 0 -and $processors[0].Name) {
        $cpuName = [string]$processors[0].Name
    }

    return [pscustomobject]@{
        Manufacturer = [string]$computerSystem.Manufacturer
        Model = [string]$computerSystem.Model
        OperatingSystem = [string]$operatingSystem.Caption
        MemoryGB = $memoryGb
        CpuSockets = $cpuSockets
        CpuCores = $cpuCores
        CpuName = $cpuName
        Simulated = $false
    }
}

function New-CheckResult {
    param(
        [string]$Id,
        [string]$Name,
        [string]$Status,
        [string]$Detail,
        [bool]$Blocking
    )

    return [pscustomobject]@{
        Id = $Id
        Name = $Name
        Status = $Status
        Detail = $Detail
        Blocking = $Blocking
    }
}

# --- Carga de manifiesto y datos de sistema ---
$requirements = Get-HardwareRequirementsManifest -ManifestPath $ManifestPath

$productRules = $requirements.products | Where-Object {
    $_.productName -eq $Product -and $_.version -eq $Version
} | Select-Object -First 1

if (-not $productRules) {
    throw "No se encontraron reglas de hardware para $Product $Version."
}

$system = Get-SystemInventory -SystemInfoPath $SystemInfoPath

$manufacturer = $system.Manufacturer
$model = $system.Model
$osCaption = $system.OperatingSystem

# --- Coincidencia de reglas de hardware (modelo + fabricante + SO) ---
$newInstallMatches = @()
foreach ($rule in @($productRules.rules.newInstallation.allowedHardware)) {
    if (Test-HardwareRule -Rule $rule -Manufacturer $manufacturer -Model $model -OperatingSystem $osCaption) {
        $newInstallMatches += [pscustomobject]@{
            Mode = "Instalacion nueva"
            Label = Convert-RuleIdToLabel -RuleId $rule.id
            Rule = $rule
        }
    }
}

$upgradeMatches = @()
foreach ($rule in @($productRules.rules.upgrade.allowedHardware)) {
    if (Test-HardwareRule -Rule $rule -Manufacturer $manufacturer -Model $model -OperatingSystem $osCaption) {
        $upgradeMatches += [pscustomobject]@{
            Mode = "Upgrade"
            Label = Convert-RuleIdToLabel -RuleId $rule.id
            Rule = $rule
        }
    }
}

$allMatches = @($newInstallMatches) + @($upgradeMatches)

$checks = @()

# --- check-hardware-manufacturer ---
$allowedManufacturers = @()
foreach ($rule in @($productRules.rules.newInstallation.allowedHardware) + @($productRules.rules.upgrade.allowedHardware)) {
    foreach ($pattern in @($rule.manufacturerPatterns)) {
        if ($allowedManufacturers -notcontains $pattern) {
            $allowedManufacturers += $pattern
        }
    }
}

$manufacturerMatch = Test-PatternList -Value $manufacturer -Patterns $allowedManufacturers
if ($manufacturerMatch) {
    $checks += New-CheckResult -Id "check-hardware-manufacturer" -Name "Validar fabricante del servidor" -Status "Pass" -Detail "Fabricante detectado: '$manufacturer'. Coincide con un fabricante aprobado (HP/HPE)." -Blocking $true
}
else {
    $checks += New-CheckResult -Id "check-hardware-manufacturer" -Name "Validar fabricante del servidor" -Status "Fail" -Detail "Fabricante detectado: '$manufacturer'. No coincide con ningun fabricante aprobado ($($allowedManufacturers -join ', '))." -Blocking $true
}

# --- check-hardware-model ---
if ($allMatches.Count -gt 0) {
    $labels = @($allMatches | ForEach-Object { "$($_.Label) ($($_.Mode))" })
    $checks += New-CheckResult -Id "check-hardware-model" -Name "Validar modelo de servidor" -Status "Pass" -Detail "Modelo detectado: '$model'. Coincide con: $($labels -join '; ')." -Blocking $true
}
else {
    $checks += New-CheckResult -Id "check-hardware-model" -Name "Validar modelo de servidor" -Status "Fail" -Detail "Modelo detectado: '$model' con SO '$osCaption'. No coincide con ninguna configuracion soportada para instalacion nueva ni upgrade." -Blocking $true
}

# --- check-hardware-generation ---
$generationMatch = $false
$generationLabel = ""
foreach ($match in $allMatches) {
    if ($match.Rule.hardwareGenerationPatterns) {
        foreach ($pattern in @($match.Rule.hardwareGenerationPatterns)) {
            if (($model -like "*$pattern*") -or ($match.Label -like "*$pattern*")) {
                $generationMatch = $true
                $generationLabel = $pattern
                break
            }
        }
    }
    if ($generationMatch) { break }
}

if ($generationMatch) {
    $checks += New-CheckResult -Id "check-hardware-generation" -Name "Validar generacion de hardware" -Status "Pass" -Detail "Generacion de hardware confirmada contra el patron aprobado: '$generationLabel'." -Blocking $true
}
elseif ($allMatches.Count -gt 0) {
    $checks += New-CheckResult -Id "check-hardware-generation" -Name "Validar generacion de hardware" -Status "Warning" -Detail "El modelo '$model' coincide con una configuracion soportada, pero no se pudo confirmar la generacion exacta por patron. Revise manualmente." -Blocking $true
}
else {
    $checks += New-CheckResult -Id "check-hardware-generation" -Name "Validar generacion de hardware" -Status "Fail" -Detail "No se pudo validar la generacion: el modelo '$model' no coincide con ninguna configuracion aprobada." -Blocking $true
}

# --- check-memory-capacity ---
$minimumResources = $productRules.minimumResources
$memoryDetailSuffix = ""
if ($minimumResources -and $minimumResources.notes) {
    $memoryDetailSuffix = " (Nota manifiesto: $($minimumResources.notes))"
}

if ($null -eq $system.MemoryGB) {
    $checks += New-CheckResult -Id "check-memory-capacity" -Name "Validar memoria instalada" -Status "Warning" -Detail "No se pudo determinar la memoria fisica instalada." -Blocking $true
}
elseif (-not $minimumResources -or $null -eq $minimumResources.memoryGBMin) {
    $checks += New-CheckResult -Id "check-memory-capacity" -Name "Validar memoria instalada" -Status "Warning" -Detail "Memoria instalada: $($system.MemoryGB) GB. El manifiesto no define un minimo (memoryGBMin) para comparar.$memoryDetailSuffix" -Blocking $true
}
else {
    $memoryMin = [double]$minimumResources.memoryGBMin
    if ([double]$system.MemoryGB -ge $memoryMin) {
        $checks += New-CheckResult -Id "check-memory-capacity" -Name "Validar memoria instalada" -Status "Pass" -Detail "Memoria instalada: $($system.MemoryGB) GB. Cumple el minimo requerido de $memoryMin GB.$memoryDetailSuffix" -Blocking $true
    }
    else {
        $checks += New-CheckResult -Id "check-memory-capacity" -Name "Validar memoria instalada" -Status "Fail" -Detail "Memoria instalada: $($system.MemoryGB) GB. Por debajo del minimo requerido de $memoryMin GB.$memoryDetailSuffix" -Blocking $true
    }
}

# --- check-cpu-inventory (blocking:false -> Warning si falla) ---
$cpuDescription = "Sockets: $($system.CpuSockets); Nucleos: $($system.CpuCores)"
if ($system.CpuName) {
    $cpuDescription = "CPU: $($system.CpuName); " + $cpuDescription
}

$cpuSocketsMin = $null
$cpuCoresMin = $null
if ($minimumResources) {
    if ($null -ne $minimumResources.cpuSocketsMin) { $cpuSocketsMin = [int]$minimumResources.cpuSocketsMin }
    if ($null -ne $minimumResources.cpuCoresMin) { $cpuCoresMin = [int]$minimumResources.cpuCoresMin }
}

if ($null -eq $system.CpuSockets -or $null -eq $system.CpuCores) {
    $checks += New-CheckResult -Id "check-cpu-inventory" -Name "Validar procesadores" -Status "Warning" -Detail "No se pudo inventariar completamente el CPU. $cpuDescription" -Blocking $false
}
elseif ($null -eq $cpuSocketsMin -and $null -eq $cpuCoresMin) {
    $checks += New-CheckResult -Id "check-cpu-inventory" -Name "Validar procesadores" -Status "Warning" -Detail "$cpuDescription. El manifiesto no define minimos de CPU para comparar." -Blocking $false
}
else {
    $socketsOk = ($null -eq $cpuSocketsMin) -or ([int]$system.CpuSockets -ge $cpuSocketsMin)
    $coresOk = ($null -eq $cpuCoresMin) -or ([int]$system.CpuCores -ge $cpuCoresMin)

    if ($socketsOk -and $coresOk) {
        $checks += New-CheckResult -Id "check-cpu-inventory" -Name "Validar procesadores" -Status "Pass" -Detail "$cpuDescription. Cumple minimos (sockets>=$cpuSocketsMin, nucleos>=$cpuCoresMin)." -Blocking $false
    }
    else {
        $checks += New-CheckResult -Id "check-cpu-inventory" -Name "Validar procesadores" -Status "Warning" -Detail "$cpuDescription. No cumple minimos (sockets>=$cpuSocketsMin, nucleos>=$cpuCoresMin). No bloquea el paso." -Blocking $false
    }
}

# --- Estado general ---
$realStatus = "Pass"
foreach ($check in $checks) {
    if ($check.Blocking -and $check.Status -eq "Fail") {
        $realStatus = "Fail"
        break
    }
}

$finalStatus = $realStatus
$testModeApplied = $false
if ($TestMode) {
    $testModeApplied = $true
    $finalStatus = "Pass"
}

$result = [pscustomobject]@{
    Status = $finalStatus
    RealStatus = $realStatus
    TestModeApplied = $testModeApplied
    Product = $Product
    Version = $Version
    Manufacturer = $manufacturer
    Model = $model
    OperatingSystem = $osCaption
    MemoryGB = $system.MemoryGB
    CpuSockets = $system.CpuSockets
    CpuCores = $system.CpuCores
    CpuName = $system.CpuName
    SimulatedSource = $system.Simulated
    Checks = $checks
}

Write-Output $result
