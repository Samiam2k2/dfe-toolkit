<#
.SYNOPSIS
    Valida la configuracion de red del servidor DFE contra los requisitos aprobados.
.DESCRIPTION
    Script independiente compatible con Windows PowerShell 5.1 (sin dependencias
    externas). Ejecuta los 5 checks de categoria "network" definidos en
    manifests/assessment-checks.json:
        - check-network-adapter-names
        - check-network-adapter-state
        - check-network-static-ip
        - check-network-metrics
        - check-hosts-file

    Devuelve al pipeline un objeto estructurado con el estado general y el
    detalle por check. Puede leer los datos del sistema real (Get-NetAdapter,
    Get-NetIPInterface, Get-NetIPAddress y el archivo hosts) o de un JSON
    simulado (-SystemInfoPath) para pruebas en laboratorio/VM.

    El nombre y el flag "blocking" de cada check se leen de assessment-checks.json;
    no se queman severidades en el codigo.
.PARAMETER ManifestPath
    Ruta local a network-requirements.json. Si no se provee y no existe la copia
    local, se descarga de raw.githubusercontent con cache-bust.
.PARAMETER AssessmentPath
    Ruta local a assessment-checks.json (de donde se toma name/blocking de cada
    check). Si no se provee y no existe la copia local, se descarga con cache-bust.
.PARAMETER SystemInfoPath
    Ruta opcional a un JSON con datos de red simulados
    (adapters:[{name,status,dhcp,interfaceMetric,ipv4Addresses:[]}] y hostsContent).
    Si se provee, se usan esos datos en vez de los cmdlets Get-Net*.
.PARAMETER TestMode
    Si se especifica, el Status general se fuerza a Pass y se agrega
    TestModeApplied=true, dejando visibles los resultados reales por check.
.OUTPUTS
    [pscustomobject] con: Status, RealStatus, TestModeApplied, Checks
    (arreglo de objetos Id/Name/Status/Detail/Blocking), Adapters (inventario
    detectado) y SimulatedSource.
#>

[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$AssessmentPath,
    [string]$SystemInfoPath,
    [switch]$TestMode
)

function Get-NetworkRequirementsManifest {
    param(
        [string]$ManifestPath
    )

    if ($ManifestPath) {
        if (-not (Test-Path -Path $ManifestPath -PathType Leaf)) {
            throw "No se encontro el manifiesto de red en la ruta indicada: $ManifestPath"
        }
        return Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json
    }

    $projectRoot = $null
    if ($PSScriptRoot) {
        $projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }

    if ($projectRoot) {
        $localPath = Join-Path -Path $projectRoot -ChildPath "manifests\production-pro\8.3\network.json"
        if (Test-Path -Path $localPath -PathType Leaf) {
            return Get-Content -Path $localPath -Raw | ConvertFrom-Json
        }
    }

    $requirementsUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/manifests/production-pro/8.3/network.json?cacheBust=$([DateTime]::UtcNow.Ticks)"
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

function Get-NetworkInventory {
    param(
        [string]$SystemInfoPath
    )

    if ($SystemInfoPath) {
        if (-not (Test-Path -Path $SystemInfoPath -PathType Leaf)) {
            throw "No se encontro el JSON de sistema simulado: $SystemInfoPath"
        }

        $simulated = Get-Content -Path $SystemInfoPath -Raw | ConvertFrom-Json

        $adapters = @()
        foreach ($adapter in @($simulated.adapters)) {
            $ipv4 = @()
            foreach ($ip in @($adapter.ipv4Addresses)) {
                if ($ip -and ([string]$ip -notlike "169.254.*")) {
                    $ipv4 += [string]$ip
                }
            }

            $metric = $null
            if ($null -ne $adapter.interfaceMetric) { $metric = [int]$adapter.interfaceMetric }

            $adapters += [pscustomobject]@{
                Name = [string]$adapter.name
                Status = [string]$adapter.status
                Dhcp = [string]$adapter.dhcp
                InterfaceMetric = $metric
                Ipv4Addresses = $ipv4
            }
        }

        $hostsContent = ""
        if ($null -ne $simulated.hostsContent) { $hostsContent = [string]$simulated.hostsContent }

        return [pscustomobject]@{
            Adapters = $adapters
            HostsContent = $hostsContent
            Simulated = $true
        }
    }

    $physicalAdapters = @(Get-NetAdapter -Physical -ErrorAction Stop)
    $adapters = @()
    foreach ($adapter in $physicalAdapters) {
        $ipInterface = Get-NetIPInterface -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1

        $metric = $null
        $dhcp = ""
        if ($ipInterface) {
            $metric = [int]$ipInterface.InterfaceMetric
            $dhcp = [string]$ipInterface.Dhcp
        }

        $ipv4 = @()
        foreach ($ip in @(Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)) {
            if ($ip.IPAddress -and ($ip.IPAddress -notlike "169.254.*")) {
                $ipv4 += [string]$ip.IPAddress
            }
        }

        $adapters += [pscustomobject]@{
            Name = [string]$adapter.Name
            Status = [string]$adapter.Status
            Dhcp = $dhcp
            InterfaceMetric = $metric
            Ipv4Addresses = $ipv4
        }
    }

    $hostsContent = ""
    $hostsPath = "C:\Windows\System32\drivers\etc\hosts"
    if (Test-Path -Path $hostsPath -PathType Leaf) {
        $hostsContent = Get-Content -Path $hostsPath -Raw -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        Adapters = $adapters
        HostsContent = $hostsContent
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
$requirements = Get-NetworkRequirementsManifest -ManifestPath $ManifestPath
$assessment = Get-AssessmentChecksManifest -AssessmentPath $AssessmentPath
$network = Get-NetworkInventory -SystemInfoPath $SystemInfoPath

$expectedAdapters = @($requirements.expectedAdapters)
$expectedNames = @($expectedAdapters | ForEach-Object { [string]$_.name })

# --- Inventario: esperados encontrados/faltantes y no esperados ---
$foundExpected = @()
$missingExpected = @()
foreach ($expected in $expectedAdapters) {
    $adapter = $network.Adapters | Where-Object { $_.Name -eq $expected.name } | Select-Object -First 1
    if ($adapter) {
        $foundExpected += [string]$expected.name
    }
    else {
        $missingExpected += [string]$expected.name
    }
}

$unexpectedAdapters = @($network.Adapters | Where-Object { $expectedNames -notcontains $_.Name } | ForEach-Object { [string]$_.Name })

$adapterInventory = [pscustomobject]@{
    Expected = $expectedNames
    FoundExpected = $foundExpected
    MissingExpected = $missingExpected
    Unexpected = $unexpectedAdapters
}

$checks = @()

# --- check-network-adapter-names ---
$namesMeta = Get-CheckMeta -Assessment $assessment -Id "check-network-adapter-names"
if ($missingExpected.Count -eq 0) {
    $checks += New-CheckResult -Meta $namesMeta -Status "Pass" -Detail "Se encontraron todos los adaptadores esperados: $($expectedNames -join ', ')."
}
else {
    $checks += New-CheckResult -Meta $namesMeta -Status "Warning" -Detail "Faltan adaptadores esperados: $($missingExpected -join ', '). Encontrados: $(if ($foundExpected.Count -gt 0) { $foundExpected -join ', ' } else { 'ninguno' })."
}

# --- check-network-adapter-state ---
$stateMeta = Get-CheckMeta -Assessment $assessment -Id "check-network-adapter-state"
$stateProblems = @()
foreach ($expected in $expectedAdapters) {
    if (-not $expected.requireUp) { continue }
    $adapter = $network.Adapters | Where-Object { $_.Name -eq $expected.name } | Select-Object -First 1
    if (-not $adapter) {
        $stateProblems += "$($expected.name): no encontrado"
    }
    elseif ($adapter.Status -ne "Up") {
        $stateProblems += "$($expected.name): estado '$($adapter.Status)'"
    }
}

if ($stateProblems.Count -eq 0) {
    $checks += New-CheckResult -Meta $stateMeta -Status "Pass" -Detail "Todos los adaptadores esperados que requieren estar activos estan en estado Up."
}
else {
    $checks += New-CheckResult -Meta $stateMeta -Status "Warning" -Detail "Adaptadores que deberian estar activos con problemas: $($stateProblems -join '; ')."
}

# --- check-network-static-ip ---
$staticMeta = Get-CheckMeta -Assessment $assessment -Id "check-network-static-ip"
$staticProblems = @()
foreach ($expected in $expectedAdapters) {
    if (-not $expected.requireStaticIp) { continue }
    $adapter = $network.Adapters | Where-Object { $_.Name -eq $expected.name } | Select-Object -First 1
    if (-not $adapter) {
        $staticProblems += "$($expected.name): no encontrado"
        continue
    }

    $isStatic = ($adapter.Dhcp -eq "Disabled")
    if (-not $isStatic) {
        $staticProblems += "$($expected.name): DHCP '$($adapter.Dhcp)' (se esperaba IP estatica)"
    }
    elseif ($adapter.Ipv4Addresses.Count -eq 0) {
        $staticProblems += "$($expected.name): sin IPv4 valida asignada"
    }
}

if ($staticProblems.Count -eq 0) {
    $checks += New-CheckResult -Meta $staticMeta -Status "Pass" -Detail "Todos los adaptadores esperados que requieren IP estatica tienen DHCP deshabilitado y una IPv4 asignada."
}
else {
    $checks += New-CheckResult -Meta $staticMeta -Status "Warning" -Detail "Adaptadores con IP no estatica o sin IPv4: $($staticProblems -join '; ')."
}

# --- check-network-metrics ---
$metricsMeta = Get-CheckMeta -Assessment $assessment -Id "check-network-metrics"
$metricProblems = @()
foreach ($expected in $expectedAdapters) {
    if ($null -eq $expected.interfaceMetric) { continue }
    $adapter = $network.Adapters | Where-Object { $_.Name -eq $expected.name } | Select-Object -First 1
    if (-not $adapter) {
        $metricProblems += "$($expected.name): no encontrado"
        continue
    }

    if ($null -eq $adapter.InterfaceMetric) {
        $metricProblems += "$($expected.name): metrica desconocida (se esperaba $($expected.interfaceMetric))"
    }
    elseif ([int]$adapter.InterfaceMetric -ne [int]$expected.interfaceMetric) {
        $metricProblems += "$($expected.name): metrica $($adapter.InterfaceMetric) (se esperaba $($expected.interfaceMetric))"
    }
}

if ($metricProblems.Count -eq 0) {
    $checks += New-CheckResult -Meta $metricsMeta -Status "Pass" -Detail "Las metricas de interfaz de los adaptadores esperados coinciden con el manifiesto."
}
else {
    $checks += New-CheckResult -Meta $metricsMeta -Status "Warning" -Detail "Adaptadores con metrica incorrecta: $($metricProblems -join '; ')."
}

# --- check-hosts-file ---
$hostsMeta = Get-CheckMeta -Assessment $assessment -Id "check-hosts-file"
$requiredEntries = @()
if ($requirements.hostsFile -and $requirements.hostsFile.requiredEntries) {
    $requiredEntries = @($requirements.hostsFile.requiredEntries)
}

if ($requiredEntries.Count -eq 0) {
    $checks += New-CheckResult -Meta $hostsMeta -Status "Warning" -Detail "El manifiesto no define entradas requeridas para el archivo hosts. Check informativo; agregue requiredEntries para validar."
}
else {
    $hostsText = ""
    if ($network.HostsContent) { $hostsText = [string]$network.HostsContent }

    $missingEntries = @()
    foreach ($entry in $requiredEntries) {
        if ($hostsText -notlike "*$entry*") {
            $missingEntries += [string]$entry
        }
    }

    if ($missingEntries.Count -eq 0) {
        $checks += New-CheckResult -Meta $hostsMeta -Status "Pass" -Detail "El archivo hosts contiene todas las entradas requeridas ($($requiredEntries.Count))."
    }
    else {
        $checks += New-CheckResult -Meta $hostsMeta -Status "Warning" -Detail "Faltan entradas requeridas en el archivo hosts: $($missingEntries -join ', ')."
    }
}

# --- Estado general ---
# Fail solo si un check bloqueante da Fail; Warning si sin Fails bloqueantes hay
# al menos un Warning o un Fail no bloqueante; Pass si todo Pass.
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
    Checks = $checks
    Adapters = $adapterInventory
    SimulatedSource = $network.Simulated
}

Write-Output $result
