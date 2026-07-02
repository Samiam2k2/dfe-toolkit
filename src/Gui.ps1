<#
.SYNOPSIS
    Interfaz grafica WPF para DFE-Toolkit.
.DESCRIPTION
    GUI compatible con Windows PowerShell 5.1+ para ejecutar la validacion
    real de servidor DFE desde un unico paso.
#>

if ([Threading.Thread]::CurrentThread.ApartmentState -ne "STA") {
    if ($PSCommandPath) {
        Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-File", "`"$PSCommandPath`"")
        return
    }
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

if ($PSScriptRoot) {
    $projectRoot = Split-Path -Parent $PSScriptRoot
}
else {
    $projectRoot = (Get-Location).Path
}

$configRoot = Join-Path -Path $projectRoot -ChildPath "config"
$sessionPath = Join-Path -Path $configRoot -ChildPath "session.json"

if (-not (Test-Path -Path $configRoot -PathType Container)) {
    New-Item -Path $configRoot -ItemType Directory -Force | Out-Null
}

$statusIcons = @{
    Pending = [char]::ConvertFromUtf32(0x23F3)
    Completed = [char]::ConvertFromUtf32(0x2705)
    Warning = [char]::ConvertFromUtf32(0x26A0) + [char]0xFE0F
    Failed = [char]::ConvertFromUtf32(0x274C)
    Running = [char]::ConvertFromUtf32(0x25B6) + [char]0xFE0F
}

$session = @{
    Product = "Production Pro"
    Model = "Commercial"
    Version = "8.3"
    HardwareStatus = "Pending"
    NetworkStatus = "Pending"
    OperatingSystemStatus = "Pending"
    StorageStatus = "Pending"
    SecurityStatus = "Pending"
    LastResult = ""
}

if (Test-Path -Path $sessionPath -PathType Leaf) {
    try {
        $loadedSession = Get-Content -Path $sessionPath -Raw | ConvertFrom-Json
        if ($loadedSession.Product) { $session.Product = $loadedSession.Product }
        if ($loadedSession.Model) { $session.Model = $loadedSession.Model }
        if ($loadedSession.Version) { $session.Version = $loadedSession.Version }
        if ($loadedSession.HardwareStatus) { $session.HardwareStatus = $loadedSession.HardwareStatus }
        if ($loadedSession.NetworkStatus) { $session.NetworkStatus = $loadedSession.NetworkStatus }
        if ($loadedSession.OperatingSystemStatus) { $session.OperatingSystemStatus = $loadedSession.OperatingSystemStatus }
        if ($loadedSession.StorageStatus) { $session.StorageStatus = $loadedSession.StorageStatus }
        if ($loadedSession.SecurityStatus) { $session.SecurityStatus = $loadedSession.SecurityStatus }
        if ($loadedSession.LastResult) { $session.LastResult = $loadedSession.LastResult }
    }
    catch {
        $session.LastResult = ""
    }
}

$installOptions = @{
    "Production Pro" = @{
        Models = @("Commercial", "Labels & Packaging")
        Versions = @("8.3")
    }
    "Composer" = @{
        Models = @("Composer Server")
        Versions = @("10.1")
    }
}

function Get-StatusText {
    param([string]$Status)

    switch ($Status) {
        "Completed" { return "$($statusIcons.Completed) Completado" }
        "Warning" { return "$($statusIcons.Warning) Completado con advertencias" }
        "Failed" { return "$($statusIcons.Failed) Fallido" }
        "Running" { return "$($statusIcons.Running) En ejecucion..." }
        default { return "$($statusIcons.Pending) Pendiente" }
    }
}

function Get-ValidateHardwareScriptBlock {
    [CmdletBinding()]
    param()

    $localScript = Join-Path -Path $projectRoot -ChildPath "scripts\validation\Validate-Hardware.ps1"
    if (Test-Path -Path $localScript -PathType Leaf) {
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

function Invoke-HardwareRequirementsValidation {
    [CmdletBinding()]
    param(
        [string]$Product,
        [string]$Version,
        [switch]$TestMode
    )

    $warningIcon = [char]::ConvertFromUtf32(0x26A0) + [char]0xFE0F
    $checkIcon = [char]::ConvertFromUtf32(0x2705)
    $failIcon = [char]::ConvertFromUtf32(0x274C)
    $infoIcon = [char]::ConvertFromUtf32(0x2139) + [char]0xFE0F

    $validator = Get-ValidateHardwareScriptBlock

    $arguments = @{
        Product = $Product
        Version = $Version
    }
    if ($TestMode) {
        $arguments["TestMode"] = $true
    }

    $result = & $validator.Command @arguments

    $lines = @()
    $lines += "Validacion de hardware"
    $lines += "======================"
    $lines += "Producto evaluado: $($result.Product) $($result.Version)"
    $lines += ""
    $lines += "Servidor detectado:"
    $lines += "  Fabricante: $($result.Manufacturer)"
    $lines += "  Modelo: $($result.Model)"
    $lines += "  Sistema operativo: $($result.OperatingSystem)"
    $lines += "  Memoria: $($result.MemoryGB) GB"
    $lines += "  CPU: sockets $($result.CpuSockets), nucleos $($result.CpuCores)"
    if ($result.SimulatedSource) {
        $lines += "  (Origen: datos simulados de laboratorio)"
    }
    $lines += ""
    $lines += "Checks:"

    foreach ($check in @($result.Checks)) {
        switch ($check.Status) {
            "Pass" { $icon = $checkIcon }
            "Fail" { $icon = $failIcon }
            "Info" { $icon = $infoIcon }
            default { $icon = $warningIcon }
        }
        $lines += "  $icon [$($check.Status)] $($check.Name)"
        $lines += "      $($check.Detail)"
    }

    $lines += ""
    switch ($result.Status) {
        "Pass" { $lines += "$checkIcon Estado general: Pass." }
        "Warning" { $lines += "$warningIcon Estado general: Completado con advertencias." }
        default { $lines += "$failIcon Estado general: Fail." }
    }

    if ($result.DegradedByMode) {
        $lines += ""
        $lines += "Modo informativo (laboratorio): este paso muestra advertencias en vez de bloquear. Cambie validationMode a 'enforcing' en el manifiesto para validar contra un servidor real."
    }

    if ($result.TestModeApplied) {
        $lines += ""
        $lines += "Modo pruebas activo: estado general forzado a Pass; los resultados por check reflejan la realidad."
    }

    # Se adjunta el objeto de resultado como ultimo elemento para que el llamador
    # pueda leer el Status real sin re-parsear el texto.
    return [pscustomobject]@{
        Text = ($lines -join [Environment]::NewLine)
        Result = $result
    }
}

function Get-ValidateNetworkScriptBlock {
    [CmdletBinding()]
    param()

    $localScript = Join-Path -Path $projectRoot -ChildPath "scripts\validation\Validate-Network.ps1"
    if (Test-Path -Path $localScript -PathType Leaf) {
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

function Invoke-NetworkRequirementsValidation {
    [CmdletBinding()]
    param(
        [switch]$TestMode
    )

    $warningIcon = [char]::ConvertFromUtf32(0x26A0) + [char]0xFE0F
    $checkIcon = [char]::ConvertFromUtf32(0x2705)
    $failIcon = [char]::ConvertFromUtf32(0x274C)
    $infoIcon = [char]::ConvertFromUtf32(0x2139) + [char]0xFE0F

    $validator = Get-ValidateNetworkScriptBlock

    $arguments = @{}
    if ($TestMode) {
        $arguments["TestMode"] = $true
    }

    $result = & $validator.Command @arguments

    $lines = @()
    $lines += "Validacion de red"
    $lines += "================="
    if ($result.SimulatedSource) {
        $lines += "(Origen: datos simulados de laboratorio)"
        $lines += ""
    }

    $lines += "Adaptadores:"
    $lines += "  Esperados: $($result.Adapters.Expected -join ', ')"
    if ($result.Adapters.MissingExpected.Count -gt 0) {
        $lines += "  Faltantes: $($result.Adapters.MissingExpected -join ', ')"
    }
    else {
        $lines += "  Faltantes: ninguno"
    }
    if ($result.Adapters.Unexpected.Count -gt 0) {
        $lines += "  No esperados: $($result.Adapters.Unexpected -join ', ')"
    }
    else {
        $lines += "  No esperados: ninguno"
    }
    $lines += ""
    $lines += "Checks:"

    foreach ($check in @($result.Checks)) {
        switch ($check.Status) {
            "Pass" { $icon = $checkIcon }
            "Fail" { $icon = $failIcon }
            "Info" { $icon = $infoIcon }
            default { $icon = $warningIcon }
        }
        $lines += "  $icon [$($check.Status)] $($check.Name)"
        $lines += "      $($check.Detail)"
    }

    $lines += ""
    switch ($result.Status) {
        "Pass" { $lines += "$checkIcon Estado general: Pass." }
        "Warning" { $lines += "$warningIcon Estado general: Completado con advertencias." }
        default { $lines += "$failIcon Estado general: Fail." }
    }

    if ($result.TestModeApplied) {
        $lines += ""
        $lines += "Modo pruebas activo: estado general forzado a Pass; los resultados por check reflejan la realidad."
    }

    # Se adjunta el objeto de resultado como ultimo elemento para que el llamador
    # pueda leer el Status real sin re-parsear el texto.
    return [pscustomobject]@{
        Text = ($lines -join [Environment]::NewLine)
        Result = $result
    }
}

function Get-ValidateOperatingSystemScriptBlock {
    [CmdletBinding()]
    param()

    $localScript = Join-Path -Path $projectRoot -ChildPath "scripts\validation\Validate-OperatingSystem.ps1"
    if (Test-Path -Path $localScript -PathType Leaf) {
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

function Invoke-OSRequirementsValidation {
    [CmdletBinding()]
    param(
        [string]$Product,
        [string]$Version,
        [switch]$TestMode
    )

    $warningIcon = [char]::ConvertFromUtf32(0x26A0) + [char]0xFE0F
    $checkIcon = [char]::ConvertFromUtf32(0x2705)
    $failIcon = [char]::ConvertFromUtf32(0x274C)
    $infoIcon = [char]::ConvertFromUtf32(0x2139) + [char]0xFE0F

    $validator = Get-ValidateOperatingSystemScriptBlock

    $arguments = @{
        Product = $Product
        Version = $Version
    }
    if ($TestMode) {
        $arguments["TestMode"] = $true
    }

    $result = & $validator.Command @arguments

    $lines = @()
    $lines += "Validacion de sistema operativo"
    $lines += "==============================="
    $lines += "Producto evaluado: $($result.Product) $($result.Version)"
    $lines += ""
    $lines += "Servidor detectado:"
    $lines += "  Fabricante: $($result.Manufacturer)"
    $lines += "  Modelo: $($result.Model)"
    $lines += "  Sistema operativo: $($result.OperatingSystem)"
    $lines += "  Arquitectura: $($result.OSArchitecture)"
    if ($result.SimulatedSource) {
        $lines += "  (Origen: datos simulados de laboratorio)"
    }
    $lines += ""
    $lines += "Checks:"

    foreach ($check in @($result.Checks)) {
        switch ($check.Status) {
            "Pass" { $icon = $checkIcon }
            "Fail" { $icon = $failIcon }
            "Info" { $icon = $infoIcon }
            default { $icon = $warningIcon }
        }
        $lines += "  $icon [$($check.Status)] $($check.Name)"
        $lines += "      $($check.Detail)"
    }

    $lines += ""
    switch ($result.Status) {
        "Pass" { $lines += "$checkIcon Estado general: Pass." }
        "Warning" { $lines += "$warningIcon Estado general: Completado con advertencias." }
        default { $lines += "$failIcon Estado general: Fail." }
    }

    if ($result.DegradedByMode) {
        $lines += ""
        $lines += "Modo informativo (laboratorio): este paso muestra advertencias en vez de bloquear. Cambie validationMode a 'enforcing' en el manifiesto para validar contra un servidor real."
    }

    if ($result.TestModeApplied) {
        $lines += ""
        $lines += "Modo pruebas activo: estado general forzado a Pass; los resultados por check reflejan la realidad."
    }

    # Se adjunta el objeto de resultado como ultimo elemento para que el llamador
    # pueda leer el Status real sin re-parsear el texto.
    return [pscustomobject]@{
        Text = ($lines -join [Environment]::NewLine)
        Result = $result
    }
}

function Get-ValidateStorageScriptBlock {
    [CmdletBinding()]
    param()

    $localScript = Join-Path -Path $projectRoot -ChildPath "scripts\validation\Validate-Storage.ps1"
    if (Test-Path -Path $localScript -PathType Leaf) {
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

function Invoke-StorageRequirementsValidation {
    [CmdletBinding()]
    param(
        [string]$Product,
        [string]$Version,
        [string]$Profile = "SystemManager",
        [switch]$TestMode
    )

    $warningIcon = [char]::ConvertFromUtf32(0x26A0) + [char]0xFE0F
    $checkIcon = [char]::ConvertFromUtf32(0x2705)
    $failIcon = [char]::ConvertFromUtf32(0x274C)
    $infoIcon = [char]::ConvertFromUtf32(0x2139) + [char]0xFE0F

    $validator = Get-ValidateStorageScriptBlock

    $arguments = @{
        Product = $Product
        Version = $Version
        Profile = $Profile
    }
    if ($TestMode) {
        $arguments["TestMode"] = $true
    }

    $result = & $validator.Command @arguments

    $lines = @()
    $lines += "Validacion de almacenamiento"
    $lines += "============================"
    $lines += "Producto evaluado: $($result.Product) $($result.Version)"
    $lines += "Perfil: $($result.Profile)"
    $lines += ""
    $lines += "Unidades detectadas:"
    $lines += "  Esperadas: $($result.Drives.Expected -join ', ')"
    if ($result.Drives.MissingExpected.Count -gt 0) {
        $lines += "  Faltantes: $($result.Drives.MissingExpected -join ', ')"
    }
    else {
        $lines += "  Faltantes: ninguna"
    }
    if ($result.Drives.Unexpected.Count -gt 0) {
        $lines += "  No esperadas: $($result.Drives.Unexpected -join ', ')"
    }
    else {
        $lines += "  No esperadas: ninguna"
    }
    if ($result.SimulatedSource) {
        $lines += "  (Origen: datos simulados de laboratorio)"
    }
    $lines += ""
    $lines += "Checks:"

    foreach ($check in @($result.Checks)) {
        switch ($check.Status) {
            "Pass" { $icon = $checkIcon }
            "Fail" { $icon = $failIcon }
            "Info" { $icon = $infoIcon }
            default { $icon = $warningIcon }
        }
        $lines += "  $icon [$($check.Status)] $($check.Name)"
        $lines += "      $($check.Detail)"
    }

    $lines += ""
    switch ($result.Status) {
        "Pass" { $lines += "$checkIcon Estado general: Pass." }
        "Warning" { $lines += "$warningIcon Estado general: Completado con advertencias." }
        default { $lines += "$failIcon Estado general: Fail." }
    }

    if ($result.DegradedByMode) {
        $lines += ""
        $lines += "Modo informativo (laboratorio): este paso muestra advertencias en vez de bloquear. Cambie validationMode a 'enforcing' en el manifiesto de hardware para validar contra un servidor real."
    }

    if ($result.TestModeApplied) {
        $lines += ""
        $lines += "Modo pruebas activo: estado general forzado a Pass; los resultados por check reflejan la realidad."
    }

    # Se adjunta el objeto de resultado como ultimo elemento para que el llamador
    # pueda leer el Status real sin re-parsear el texto.
    return [pscustomobject]@{
        Text = ($lines -join [Environment]::NewLine)
        Result = $result
    }
}

function Get-ValidateSecurityScriptBlock {
    [CmdletBinding()]
    param()

    $localScript = Join-Path -Path $projectRoot -ChildPath "scripts\validation\Validate-Security.ps1"
    if (Test-Path -Path $localScript -PathType Leaf) {
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

function Invoke-SecurityRequirementsValidation {
    [CmdletBinding()]
    param(
        [string]$Product,
        [string]$Version,
        [switch]$TestMode
    )

    $warningIcon = [char]::ConvertFromUtf32(0x26A0) + [char]0xFE0F
    $checkIcon = [char]::ConvertFromUtf32(0x2705)
    $failIcon = [char]::ConvertFromUtf32(0x274C)
    $infoIcon = [char]::ConvertFromUtf32(0x2139) + [char]0xFE0F

    $validator = Get-ValidateSecurityScriptBlock

    $arguments = @{
        Product = $Product
        Version = $Version
    }
    if ($TestMode) {
        $arguments["TestMode"] = $true
    }

    $result = & $validator.Command @arguments

    $lines = @()
    $lines += "Validacion de seguridad"
    $lines += "======================="
    $lines += "Producto evaluado: $($result.Product) $($result.Version)"
    
    $isAdminStr = if ($result.Security.isAdmin) { "si" } else { "no" }
    $lines += "Administrador: ${isAdminStr}"
    
    $uacStr = "desconocido"
    if ($null -ne $result.Security.uacEnabled) {
        $uacStr = if ($result.Security.uacEnabled) { "activo" } else { "desactivado" }
    }
    $lines += "UAC: ${uacStr}"

    $firewallDetails = @()
    foreach ($p in @($result.Security.firewallProfiles)) {
        $nameStr = $p.Name
        $stateStr = if ($p.Enabled) { "activo" } else { "desactivado" }
        $firewallDetails += "${nameStr}: ${stateStr}"
    }
    if ($firewallDetails.Count -gt 0) {
        $lines += "Firewall: $($firewallDetails -join '; ')"
    }
    else {
        $lines += "Firewall: sin perfiles detectados"
    }
    
    if ($result.SimulatedSource) {
        $lines += "  (Origen: datos simulados de laboratorio)"
    }
    $lines += ""
    $lines += "Checks:"

    foreach ($check in @($result.Checks)) {
        switch ($check.Status) {
            "Pass" { $icon = $checkIcon }
            "Fail" { $icon = $failIcon }
            "Info" { $icon = $infoIcon }
            default { $icon = $warningIcon }
        }
        $lines += "  $icon [$($check.Status)] $($check.Name)"
        $lines += "      $($check.Detail)"
    }

    $lines += ""
    switch ($result.Status) {
        "Pass" { $lines += "$checkIcon Estado general: Pass." }
        "Warning" { $lines += "$warningIcon Estado general: Completado con advertencias." }
        default { $lines += "$failIcon Estado general: Fail." }
    }

    if ($result.DegradedByMode) {
        $lines += ""
        $lines += "Modo informativo (laboratorio): este paso muestra advertencias en vez de bloquear. Cambie validationMode a 'enforcing' en el manifiesto de hardware para validar contra un servidor real."
    }

    if ($result.TestModeApplied) {
        $lines += ""
        $lines += "Modo pruebas activo: estado general forzado a Pass; los resultados por check reflejan la realidad."
    }

    return [pscustomobject]@{
        Text = ($lines -join [Environment]::NewLine)
        Result = $result
    }
}

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DFE-Toolkit - Instalacion de Servidores DFE"
        Width="1024"
        Height="768"
        MinWidth="900"
        MinHeight="620"
        ResizeMode="CanResize"
        WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI"
        Background="#F4F6F8">
    <Window.Resources>
        <Style TargetType="ComboBox">
            <Setter Property="Margin" Value="0,6,0,16" />
            <Setter Property="Height" Value="34" />
            <Setter Property="FontSize" Value="13" />
        </Style>
        <Style TargetType="Button">
            <Setter Property="Height" Value="34" />
            <Setter Property="Padding" Value="16,0" />
            <Setter Property="FontWeight" Value="SemiBold" />
            <Setter Property="Foreground" Value="White" />
            <Setter Property="Background" Value="#0078D4" />
            <Setter Property="BorderBrush" Value="#0078D4" />
            <Setter Property="Cursor" Value="Hand" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="1"
                                CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"
                                              Margin="{TemplateBinding Padding}" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#106EBE" />
                                <Setter Property="BorderBrush" Value="#106EBE" />
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Background" Value="#C8C8C8" />
                                <Setter Property="BorderBrush" Value="#C8C8C8" />
                                <Setter Property="Foreground" Value="#666666" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="250" />
            <ColumnDefinition Width="*" />
        </Grid.ColumnDefinitions>

        <Border Grid.Column="0" Background="#2D2D30">
            <StackPanel Margin="22">
                <TextBlock x:Name="SidebarTitle"
                           Text="Seleccion de instalacion"
                           Foreground="White"
                           FontSize="18"
                           FontWeight="Bold"
                           Margin="0,8,0,28" />

                <TextBlock Text="Producto" Foreground="#DADADA" FontWeight="SemiBold" />
                <ComboBox x:Name="ProductCombo" />

                <TextBlock Text="Modelo" Foreground="#DADADA" FontWeight="SemiBold" />
                <ComboBox x:Name="ModelCombo" />

                <TextBlock x:Name="VersionLabel" Text="Version" Foreground="#DADADA" FontWeight="SemiBold" />
                <ComboBox x:Name="VersionCombo" />

                <Button x:Name="LoadStepsButton"
                        Content="Cargar pasos"
                        Margin="0,10,0,0"
                        Background="#0078D4" />

                <TextBlock Text="DFE-Toolkit"
                           Foreground="#9E9E9E"
                           FontSize="12"
                           Margin="0,42,0,0" />
                <TextBlock x:Name="FooterModeText"
                           Text="Validacion real de hardware"
                           Foreground="#9E9E9E"
                           FontSize="12" />
            </StackPanel>
        </Border>

        <Grid Grid.Column="1" Background="White">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto" />
                <RowDefinition Height="*" />
                <RowDefinition Height="Auto" />
            </Grid.RowDefinitions>

            <Border Grid.Row="0" Background="White" Padding="30,24,30,16" BorderBrush="#E5E7EB" BorderThickness="0,0,0,1">
                <StackPanel>
                    <TextBlock x:Name="HeaderTitle" Text="Pasos de instalacion" FontSize="26" FontWeight="SemiBold" Foreground="#1F2937" />
                    <TextBlock x:Name="PlanSubtitle" Text="Seleccione una instalacion y cargue los pasos" Foreground="#6B7280" Margin="0,4,0,0" />
                </StackPanel>
            </Border>

            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Background="#F8FAFC">
                <StackPanel Margin="24">
                    <Border x:Name="HardwareStepCard"
                            Background="#FFFFFF"
                            BorderBrush="#E5E7EB"
                            BorderThickness="1"
                            CornerRadius="7"
                            Padding="14"
                            Margin="0,0,0,14">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="58" />
                                <ColumnDefinition Width="*" />
                                <ColumnDefinition Width="160" />
                                <ColumnDefinition Width="110" />
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="01" FontSize="18" FontWeight="Bold" Foreground="#0078D4" VerticalAlignment="Center" />
                            <TextBlock Grid.Column="1" Text="Validar hardware" FontSize="14" Foreground="#111827" VerticalAlignment="Center" />
                            <TextBlock x:Name="HardwareStatusText" Grid.Column="2" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center" />
                            <Button x:Name="ExecuteHardwareButton" Grid.Column="3" Content="Ejecutar" Width="92" Height="32" HorizontalAlignment="Right" />
                        </Grid>
                    </Border>

                    <Border x:Name="NetworkStepCard"
                            Background="#FFFFFF"
                            BorderBrush="#E5E7EB"
                            BorderThickness="1"
                            CornerRadius="7"
                            Padding="14"
                            Margin="0,0,0,14">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="58" />
                                <ColumnDefinition Width="*" />
                                <ColumnDefinition Width="160" />
                                <ColumnDefinition Width="110" />
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="02" FontSize="18" FontWeight="Bold" Foreground="#0078D4" VerticalAlignment="Center" />
                            <TextBlock Grid.Column="1" Text="Validar red" FontSize="14" Foreground="#111827" VerticalAlignment="Center" />
                            <TextBlock x:Name="NetworkStatusText" Grid.Column="2" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center" />
                            <Button x:Name="ExecuteNetworkButton" Grid.Column="3" Content="Ejecutar" Width="92" Height="32" HorizontalAlignment="Right" />
                        </Grid>
                    </Border>

                    <Border x:Name="OperatingSystemStepCard"
                             Background="#FFFFFF"
                             BorderBrush="#E5E7EB"
                             BorderThickness="1"
                             CornerRadius="7"
                             Padding="14"
                             Margin="0,0,0,14">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="58" />
                                <ColumnDefinition Width="*" />
                                <ColumnDefinition Width="160" />
                                <ColumnDefinition Width="110" />
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="03" FontSize="18" FontWeight="Bold" Foreground="#0078D4" VerticalAlignment="Center" />
                            <TextBlock Grid.Column="1" Text="Validar sistema operativo" FontSize="14" Foreground="#111827" VerticalAlignment="Center" />
                            <TextBlock x:Name="OperatingSystemStatusText" Grid.Column="2" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center" />
                            <Button x:Name="ExecuteOperatingSystemButton" Grid.Column="3" Content="Ejecutar" Width="92" Height="32" HorizontalAlignment="Right" />
                        </Grid>
                    </Border>

                    <Border x:Name="StorageStepCard"
                             Background="#FFFFFF"
                             BorderBrush="#E5E7EB"
                             BorderThickness="1"
                             CornerRadius="7"
                             Padding="14"
                             Margin="0,0,0,14">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="58" />
                                <ColumnDefinition Width="*" />
                                <ColumnDefinition Width="160" />
                                <ColumnDefinition Width="110" />
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="04" FontSize="18" FontWeight="Bold" Foreground="#0078D4" VerticalAlignment="Center" />
                            <TextBlock Grid.Column="1" Text="Validar almacenamiento" FontSize="14" Foreground="#111827" VerticalAlignment="Center" />
                            <TextBlock x:Name="StorageStatusText" Grid.Column="2" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center" />
                            <Button x:Name="ExecuteStorageButton" Grid.Column="3" Content="Ejecutar" Width="92" Height="32" HorizontalAlignment="Right" />
                        </Grid>
                    </Border>

                    <Border x:Name="SecurityStepCard"
                             Background="#FFFFFF"
                             BorderBrush="#E5E7EB"
                             BorderThickness="1"
                             CornerRadius="7"
                             Padding="14"
                             Margin="0,0,0,14">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="58" />
                                <ColumnDefinition Width="*" />
                                <ColumnDefinition Width="160" />
                                <ColumnDefinition Width="110" />
                            </Grid.ColumnDefinitions>
                            <TextBlock Text="05" FontSize="18" FontWeight="Bold" Foreground="#0078D4" VerticalAlignment="Center" />
                            <TextBlock Grid.Column="1" Text="Validar seguridad" FontSize="14" Foreground="#111827" VerticalAlignment="Center" />
                            <TextBlock x:Name="SecurityStatusText" Grid.Column="2" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center" />
                            <Button x:Name="ExecuteSecurityButton" Grid.Column="3" Content="Ejecutar" Width="92" Height="32" HorizontalAlignment="Right" />
                        </Grid>
                    </Border>

                    <TextBlock Text="Resultado" FontSize="14" FontWeight="SemiBold" Foreground="#374151" Margin="0,6,0,8" />
                    <TextBox x:Name="ResultTextBox"
                             MinHeight="320"
                             FontFamily="Consolas"
                             FontSize="13"
                             Foreground="#111827"
                             Background="#FFFFFF"
                             BorderBrush="#CBD5E1"
                             BorderThickness="1"
                             Padding="12"
                             TextWrapping="Wrap"
                             AcceptsReturn="True"
                             VerticalScrollBarVisibility="Auto"
                             IsReadOnly="True" />
                </StackPanel>
            </ScrollViewer>

            <Border Grid.Row="2" Background="White" Padding="24,16" BorderBrush="#E5E7EB" BorderThickness="0,1,0,0">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*" />
                        <ColumnDefinition Width="Auto" />
                    </Grid.ColumnDefinitions>
                    <StackPanel Grid.Column="0" Margin="0,0,24,0">
                        <TextBlock x:Name="ProgressLabel" Text="Progreso general: 0%" Foreground="#374151" FontWeight="SemiBold" Margin="0,0,0,6" />
                        <ProgressBar x:Name="MainProgressBar" Height="16" Minimum="0" Maximum="100" Value="0" />
                    </StackPanel>
                    <Button x:Name="ReportButton" Grid.Column="1" Content="Generar Reporte" Width="160" Height="38" VerticalAlignment="Bottom" />
                </Grid>
            </Border>
        </Grid>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$productCombo = $window.FindName("ProductCombo")
$modelCombo = $window.FindName("ModelCombo")
$versionCombo = $window.FindName("VersionCombo")
$loadStepsButton = $window.FindName("LoadStepsButton")
$hardwareStepCard = $window.FindName("HardwareStepCard")
$networkStepCard = $window.FindName("NetworkStepCard")
$operatingSystemStepCard = $window.FindName("OperatingSystemStepCard")
$storageStepCard = $window.FindName("StorageStepCard")
$securityStepCard = $window.FindName("SecurityStepCard")
$hardwareStatusText = $window.FindName("HardwareStatusText")
$networkStatusText = $window.FindName("NetworkStatusText")
$operatingSystemStatusText = $window.FindName("OperatingSystemStatusText")
$storageStatusText = $window.FindName("StorageStatusText")
$securityStatusText = $window.FindName("SecurityStatusText")
$executeHardwareButton = $window.FindName("ExecuteHardwareButton")
$executeNetworkButton = $window.FindName("ExecuteNetworkButton")
$executeOperatingSystemButton = $window.FindName("ExecuteOperatingSystemButton")
$executeStorageButton = $window.FindName("ExecuteStorageButton")
$executeSecurityButton = $window.FindName("ExecuteSecurityButton")
$resultTextBox = $window.FindName("ResultTextBox")
$progressBar = $window.FindName("MainProgressBar")
$progressLabel = $window.FindName("ProgressLabel")
$reportButton = $window.FindName("ReportButton")
$planSubtitle = $window.FindName("PlanSubtitle")
$sidebarTitle = $window.FindName("SidebarTitle")
$versionLabel = $window.FindName("VersionLabel")
$footerModeText = $window.FindName("FooterModeText")
$headerTitle = $window.FindName("HeaderTitle")

$oAcuteLower = [char]0x00F3
$window.Title = "DFE-Toolkit - Instalaci$($oAcuteLower)n de Servidores DFE"
$sidebarTitle.Text = "Selecci$($oAcuteLower)n de instalaci$($oAcuteLower)n"
$versionLabel.Text = "Versi$($oAcuteLower)n"
$headerTitle.Text = "Pasos de instalaci$($oAcuteLower)n"
$planSubtitle.Text = "Seleccione una instalaci$($oAcuteLower)n y cargue los pasos"
$footerModeText.Text = "Validaci$($oAcuteLower)n real de hardware"

$shadow = New-Object Windows.Media.Effects.DropShadowEffect
$shadow.Color = [Windows.Media.Color]::FromRgb(0, 0, 0)
$shadow.BlurRadius = 12
$shadow.ShadowDepth = 1
$shadow.Opacity = 0.16
$hardwareStepCard.Effect = $shadow

$networkShadow = New-Object Windows.Media.Effects.DropShadowEffect
$networkShadow.Color = [Windows.Media.Color]::FromRgb(0, 0, 0)
$networkShadow.BlurRadius = 12
$networkShadow.ShadowDepth = 1
$networkShadow.Opacity = 0.16
$networkStepCard.Effect = $networkShadow

$operatingSystemShadow = New-Object Windows.Media.Effects.DropShadowEffect
$operatingSystemShadow.Color = [Windows.Media.Color]::FromRgb(0, 0, 0)
$operatingSystemShadow.BlurRadius = 12
$operatingSystemShadow.ShadowDepth = 1
$operatingSystemShadow.Opacity = 0.16
$operatingSystemStepCard.Effect = $operatingSystemShadow

$storageShadow = New-Object Windows.Media.Effects.DropShadowEffect
$storageShadow.Color = [Windows.Media.Color]::FromRgb(0, 0, 0)
$storageShadow.BlurRadius = 12
$storageShadow.ShadowDepth = 1
$storageShadow.Opacity = 0.16
$storageStepCard.Effect = $storageShadow

$securityShadow = New-Object Windows.Media.Effects.DropShadowEffect
$securityShadow.Color = [Windows.Media.Color]::FromRgb(0, 0, 0)
$securityShadow.BlurRadius = 12
$securityShadow.ShadowDepth = 1
$securityShadow.Opacity = 0.16
$securityStepCard.Effect = $securityShadow

$script:stepStatuses = @{
    Hardware = $session.HardwareStatus
    Network = $session.NetworkStatus
    OperatingSystem = $session.OperatingSystemStatus
    Storage = $session.StorageStatus
    Security = $session.SecurityStatus
}

function Save-Session {
    $sessionObject = [ordered]@{
        Product = [string]$productCombo.SelectedItem
        Model = [string]$modelCombo.SelectedItem
        Version = [string]$versionCombo.SelectedItem
        HardwareStatus = $script:stepStatuses.Hardware
        NetworkStatus = $script:stepStatuses.Network
        OperatingSystemStatus = $script:stepStatuses.OperatingSystem
        StorageStatus = $script:stepStatuses.Storage
        SecurityStatus = $script:stepStatuses.Security
        LastResult = $resultTextBox.Text
        SavedAt = (Get-Date).ToString("s")
    }

    $sessionObject | ConvertTo-Json -Depth 4 | Set-Content -Path $sessionPath -Encoding UTF8
}

function Update-Progress {
    # Warning cuenta como paso completado (completado con advertencias).
    $completed = @($script:stepStatuses.Values | Where-Object { $_ -eq "Completed" -or $_ -eq "Warning" }).Count
    $totalSteps = $script:stepStatuses.Count
    $percent = [math]::Round(($completed / $totalSteps) * 100, 0)
    $progressBar.Value = $percent
    $progressLabel.Text = "Progreso general: $percent% ($completed de $totalSteps pasos completados)"
}

function Update-StepState {
    param(
        [string]$Step,
        [string]$Status
    )

    $script:stepStatuses[$Step] = $Status

    if ($Step -eq "Hardware") {
        $statusText = $hardwareStatusText
        $button = $executeHardwareButton
    }
    elseif ($Step -eq "OperatingSystem") {
        $statusText = $operatingSystemStatusText
        $button = $executeOperatingSystemButton
    }
    elseif ($Step -eq "Storage") {
        $statusText = $storageStatusText
        $button = $executeStorageButton
    }
    elseif ($Step -eq "Security") {
        $statusText = $securityStatusText
        $button = $executeSecurityButton
    }
    else {
        $statusText = $networkStatusText
        $button = $executeNetworkButton
    }

    $statusText.Text = Get-StatusText -Status $Status

    # El boton permanece visible tras completar el paso para poder RE-EJECUTAR y
    # volver a mostrar su resultado (los pasos comparten un unico panel de
    # resultado; sin esto no se podia revisar el Paso 1 tras correr el Paso 2).
    # Solo se oculta/deshabilita mientras el paso esta en ejecucion.
    if ($Status -eq "Running") {
        $button.IsEnabled = $false
        $button.Content = "Ejecutar"
    }
    elseif ($Status -eq "Pending") {
        $button.IsEnabled = $true
        $button.Content = "Ejecutar"
    }
    else {
        $button.IsEnabled = $true
        $button.Content = "Ver / Repetir"
    }
    $button.Visibility = "Visible"

    switch ($Status) {
        "Completed" {
            $statusText.Foreground = "#15803D"
        }
        "Warning" {
            $statusText.Foreground = "#B45309"
        }
        "Failed" {
            $statusText.Foreground = "#B91C1C"
        }
        "Running" {
            $statusText.Foreground = "#1D4ED8"
        }
        default {
            $statusText.Foreground = "#92400E"
        }
    }

    Update-Progress
}

function Load-Steps {
    $script:stepStatuses.Hardware = "Pending"
    $script:stepStatuses.Network = "Pending"
    $script:stepStatuses.OperatingSystem = "Pending"
    $script:stepStatuses.Storage = "Pending"
    $script:stepStatuses.Security = "Pending"
    $resultTextBox.Text = ""
    $planSubtitle.Text = "$($productCombo.SelectedItem) - $($modelCombo.SelectedItem) - Version $($versionCombo.SelectedItem)"
    Update-StepState -Step "Hardware" -Status "Pending"
    Update-StepState -Step "Network" -Status "Pending"
    Update-StepState -Step "OperatingSystem" -Status "Pending"
    Update-StepState -Step "Storage" -Status "Pending"
    Update-StepState -Step "Security" -Status "Pending"
    Save-Session
}

function Update-ModelCombo {
    $modelCombo.Items.Clear()
    $versionCombo.Items.Clear()

    $product = [string]$productCombo.SelectedItem
    foreach ($model in $installOptions[$product].Models) {
        $modelCombo.Items.Add($model) | Out-Null
    }

    if ($installOptions[$product].Models -contains $session.Model) {
        $modelCombo.SelectedItem = $session.Model
    }
    elseif ($modelCombo.Items.Count -gt 0) {
        $modelCombo.SelectedIndex = 0
    }

    Update-VersionCombo
}

function Update-VersionCombo {
    $versionCombo.Items.Clear()

    $product = [string]$productCombo.SelectedItem
    foreach ($version in $installOptions[$product].Versions) {
        $versionCombo.Items.Add($version) | Out-Null
    }

    if ($installOptions[$product].Versions -contains $session.Version) {
        $versionCombo.SelectedItem = $session.Version
    }
    elseif ($versionCombo.Items.Count -gt 0) {
        $versionCombo.SelectedIndex = 0
    }
}

function Invoke-HardwareValidation {
    Update-StepState -Step "Hardware" -Status "Running"
    $resultTextBox.Text = "Ejecutando validacion de hardware..."

    $script:hardwareProduct = [string]$productCombo.SelectedItem
    $script:hardwareVersion = [string]$versionCombo.SelectedItem

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timer.Add_Tick({
        param($timerSender, $timerArgs)

        $timerSender.Stop()

        try {
            # El comportamiento por defecto ya no es modo pruebas: se refleja el
            # estado real. Para forzar Pass, agregar -TestMode a esta llamada.
            $validation = Invoke-HardwareRequirementsValidation -Product $script:hardwareProduct -Version $script:hardwareVersion
            $resultTextBox.Text = $validation.Text

            switch ($validation.Result.Status) {
                "Pass" { Update-StepState -Step "Hardware" -Status "Completed" }
                "Warning" { Update-StepState -Step "Hardware" -Status "Warning" }
                default { Update-StepState -Step "Hardware" -Status "Failed" }
            }
        }
        catch {
            $resultTextBox.Text = "Error al ejecutar la validacion de hardware:`r`n$($_.Exception.Message)"
            Update-StepState -Step "Hardware" -Status "Failed"
        }

        Save-Session
    })
    $timer.Start()
}

function Invoke-NetworkValidation {
    Update-StepState -Step "Network" -Status "Running"
    $resultTextBox.Text = "Ejecutando validacion de red..."

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timer.Add_Tick({
        param($timerSender, $timerArgs)

        $timerSender.Stop()

        try {
            # El comportamiento por defecto ya no es modo pruebas: se refleja el
            # estado real. Para forzar Pass, agregar -TestMode a esta llamada.
            $validation = Invoke-NetworkRequirementsValidation
            $resultTextBox.Text = $validation.Text

            switch ($validation.Result.Status) {
                "Pass" { Update-StepState -Step "Network" -Status "Completed" }
                "Warning" { Update-StepState -Step "Network" -Status "Warning" }
                default { Update-StepState -Step "Network" -Status "Failed" }
            }
        }
        catch {
            $resultTextBox.Text = "Error al ejecutar la validacion de red:`r`n$($_.Exception.Message)"
            Update-StepState -Step "Network" -Status "Failed"
        }

        Save-Session
    })
    $timer.Start()
}

function Invoke-OSValidation {
    Update-StepState -Step "OperatingSystem" -Status "Running"
    $resultTextBox.Text = "Ejecutando validacion de sistema operativo..."

    $script:osProduct = [string]$productCombo.SelectedItem
    $script:osVersion = [string]$versionCombo.SelectedItem

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timer.Add_Tick({
        param($timerSender, $timerArgs)

        $timerSender.Stop()

        try {
            # El comportamiento por defecto ya no es modo pruebas: se refleja el
            # estado real. Para forzar Pass, agregar -TestMode a esta llamada.
            $validation = Invoke-OSRequirementsValidation -Product $script:osProduct -Version $script:osVersion
            $resultTextBox.Text = $validation.Text

            switch ($validation.Result.Status) {
                "Pass" { Update-StepState -Step "OperatingSystem" -Status "Completed" }
                "Warning" { Update-StepState -Step "OperatingSystem" -Status "Warning" }
                default { Update-StepState -Step "OperatingSystem" -Status "Failed" }
            }
        }
        catch {
            $resultTextBox.Text = "Error al ejecutar la validacion de sistema operativo:`r`n$($_.Exception.Message)"
            Update-StepState -Step "OperatingSystem" -Status "Failed"
        }

        Save-Session
    })
    $timer.Start()
}

function Invoke-StorageValidation {
    Update-StepState -Step "Storage" -Status "Running"
    $resultTextBox.Text = "Ejecutando validacion de almacenamiento..."

    $script:storageProduct = [string]$productCombo.SelectedItem
    $script:storageVersion = [string]$versionCombo.SelectedItem

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timer.Add_Tick({
        param($timerSender, $timerArgs)

        $timerSender.Stop()

        try {
            $validation = Invoke-StorageRequirementsValidation -Product $script:storageProduct -Version $script:storageVersion -Profile "SystemManager"
            $resultTextBox.Text = $validation.Text

            switch ($validation.Result.Status) {
                "Pass" { Update-StepState -Step "Storage" -Status "Completed" }
                "Warning" { Update-StepState -Step "Storage" -Status "Warning" }
                default { Update-StepState -Step "Storage" -Status "Failed" }
            }
        }
        catch {
            $resultTextBox.Text = "Error al ejecutar la validacion de almacenamiento:`r`n$($_.Exception.Message)"
            Update-StepState -Step "Storage" -Status "Failed"
        }

        Save-Session
    })
    $timer.Start()
}

function Invoke-SecurityValidation {
    Update-StepState -Step "Security" -Status "Running"
    $resultTextBox.Text = "Ejecutando validacion de seguridad..."

    $script:securityProduct = [string]$productCombo.SelectedItem
    $script:securityVersion = [string]$versionCombo.SelectedItem

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timer.Add_Tick({
        param($timerSender, $timerArgs)

        $timerSender.Stop()

        try {
            $validation = Invoke-SecurityRequirementsValidation -Product $script:securityProduct -Version $script:securityVersion
            $resultTextBox.Text = $validation.Text

            switch ($validation.Result.Status) {
                "Pass" { Update-StepState -Step "Security" -Status "Completed" }
                "Warning" { Update-StepState -Step "Security" -Status "Warning" }
                default { Update-StepState -Step "Security" -Status "Failed" }
            }
        }
        catch {
            $resultTextBox.Text = "Error al ejecutar la validacion de seguridad:`r`n$($_.Exception.Message)"
            Update-StepState -Step "Security" -Status "Failed"
        }

        Save-Session
    })
    $timer.Start()
}


function Show-Report {
    $message = "Reporte DFE-Toolkit`n`nProducto: $($productCombo.SelectedItem)`nModelo: $($modelCombo.SelectedItem)`nVersion: $($versionCombo.SelectedItem)`nPaso 01 - Validar hardware: $(Get-StatusText -Status $script:stepStatuses.Hardware)`nPaso 02 - Validar red: $(Get-StatusText -Status $script:stepStatuses.Network)`nPaso 03 - Validar sistema operativo: $(Get-StatusText -Status $script:stepStatuses.OperatingSystem)`nPaso 04 - Validar almacenamiento: $(Get-StatusText -Status $script:stepStatuses.Storage)`nPaso 05 - Validar seguridad: $(Get-StatusText -Status $script:stepStatuses.Security)"
    [Windows.MessageBox]::Show($message, "Reporte DFE-Toolkit", "OK", "Information") | Out-Null
}

foreach ($product in $installOptions.Keys) {
    $productCombo.Items.Add($product) | Out-Null
}

if ($installOptions.ContainsKey($session.Product)) {
    $productCombo.SelectedItem = $session.Product
}
else {
    $productCombo.SelectedIndex = 0
}

$productCombo.Add_SelectionChanged({
    Update-ModelCombo
})

$modelCombo.Add_SelectionChanged({
    Update-VersionCombo
})

$loadStepsButton.Add_Click({
    Load-Steps
})

$executeHardwareButton.Add_Click({
    Invoke-HardwareValidation
})

$executeNetworkButton.Add_Click({
    Invoke-NetworkValidation
})

$executeOperatingSystemButton.Add_Click({
    Invoke-OSValidation
})

$executeStorageButton.Add_Click({
    Invoke-StorageValidation
})

$executeSecurityButton.Add_Click({
    Invoke-SecurityValidation
})

$reportButton.Add_Click({
    Show-Report
})

$window.Add_Closing({
    Save-Session
})

Update-ModelCombo
Update-StepState -Step "Hardware" -Status $script:stepStatuses.Hardware
Update-StepState -Step "Network" -Status $script:stepStatuses.Network
Update-StepState -Step "OperatingSystem" -Status $script:stepStatuses.OperatingSystem
Update-StepState -Step "Storage" -Status $script:stepStatuses.Storage
Update-StepState -Step "Security" -Status $script:stepStatuses.Security
$planSubtitle.Text = "$($productCombo.SelectedItem) - $($modelCombo.SelectedItem) - Version $($versionCombo.SelectedItem)"

$window.ShowDialog() | Out-Null
