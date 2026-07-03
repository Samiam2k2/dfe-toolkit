<#
.SYNOPSIS
    Interfaz grafica WPF para DFE-Toolkit.
.DESCRIPTION
    GUI compatible con Windows PowerShell 5.1+ para ejecutar la validacion
    consolidada de especificaciones del servidor DFE.
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
    SpecsStatus = "Pending"
    LastResult = ""
}

if (Test-Path -Path $sessionPath -PathType Leaf) {
    try {
        $loadedSession = Get-Content -Path $sessionPath -Raw | ConvertFrom-Json
        if ($loadedSession.Product) { $session.Product = $loadedSession.Product }
        if ($loadedSession.Model) { $session.Model = $loadedSession.Model }
        if ($loadedSession.Version) { $session.Version = $loadedSession.Version }
        if ($loadedSession.SpecsStatus) { $session.SpecsStatus = $loadedSession.SpecsStatus }
        if ($loadedSession.LastResult) { $session.LastResult = $loadedSession.LastResult }
    }
    catch {
        $session.LastResult = ""
    }
}

function Get-CatalogManifest {
    [CmdletBinding()]
    param()

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

$script:catalog = Get-CatalogManifest

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
                     <TextBlock x:Name="StepsNotAvailableText"
                                Text=""
                                Foreground="#E11D48"
                                FontSize="16"
                                FontWeight="SemiBold"
                                TextAlignment="Center"
                                TextWrapping="Wrap"
                                Margin="0,40,0,40"
                                Visibility="Collapsed" />

                     <Border x:Name="SpecsStepCard"
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
                             <TextBlock Grid.Column="1" Text="Validar especificaciones" FontSize="14" Foreground="#111827" VerticalAlignment="Center" />
                             <TextBlock x:Name="SpecsStatusText" Grid.Column="2" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center" />
                             <Button x:Name="ExecuteSpecsButton" Grid.Column="3" Content="Ejecutar" Width="92" Height="32" HorizontalAlignment="Right" />
                         </Grid>
                     </Border>

                     <Border x:Name="Step2Card"
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
                                 <ColumnDefinition Width="110" />
                             </Grid.ColumnDefinitions>
                             <TextBlock Text="02" FontSize="18" FontWeight="Bold" Foreground="#888888" VerticalAlignment="Center" />
                             <TextBlock Grid.Column="1" Text="Instalar prerrequisitos" FontSize="14" Foreground="#777777" VerticalAlignment="Center" />
                             <TextBlock Grid.Column="2" Text="Proximamente" FontSize="13" FontWeight="SemiBold" Foreground="#888888" HorizontalAlignment="Right" VerticalAlignment="Center" />
                         </Grid>
                     </Border>

                     <Border x:Name="Step3Card"
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
                                 <ColumnDefinition Width="110" />
                             </Grid.ColumnDefinitions>
                             <TextBlock Text="03" FontSize="18" FontWeight="Bold" Foreground="#888888" VerticalAlignment="Center" />
                             <TextBlock Grid.Column="1" Text="Instalar software" FontSize="14" Foreground="#777777" VerticalAlignment="Center" />
                             <TextBlock Grid.Column="2" Text="Proximamente" FontSize="13" FontWeight="SemiBold" Foreground="#888888" HorizontalAlignment="Right" VerticalAlignment="Center" />
                         </Grid>
                     </Border>

                     <Border x:Name="Step4Card"
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
                                 <ColumnDefinition Width="110" />
                             </Grid.ColumnDefinitions>
                             <TextBlock Text="04" FontSize="18" FontWeight="Bold" Foreground="#888888" VerticalAlignment="Center" />
                             <TextBlock Grid.Column="1" Text="Backup en blanco" FontSize="14" Foreground="#777777" VerticalAlignment="Center" />
                             <TextBlock Grid.Column="2" Text="Proximamente" FontSize="13" FontWeight="SemiBold" Foreground="#888888" HorizontalAlignment="Right" VerticalAlignment="Center" />
                         </Grid>
                     </Border>

                     <Border x:Name="Step5Card"
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
                                 <ColumnDefinition Width="110" />
                             </Grid.ColumnDefinitions>
                             <TextBlock Text="05" FontSize="18" FontWeight="Bold" Foreground="#888888" VerticalAlignment="Center" />
                             <TextBlock Grid.Column="1" Text="Cargar licencia" FontSize="14" Foreground="#777777" VerticalAlignment="Center" />
                             <TextBlock Grid.Column="2" Text="Proximamente" FontSize="13" FontWeight="SemiBold" Foreground="#888888" HorizontalAlignment="Right" VerticalAlignment="Center" />
                         </Grid>
                     </Border>

                     <Border x:Name="Step6Card"
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
                                 <ColumnDefinition Width="110" />
                             </Grid.ColumnDefinitions>
                             <TextBlock Text="06" FontSize="18" FontWeight="Bold" Foreground="#888888" VerticalAlignment="Center" />
                             <TextBlock Grid.Column="1" Text="Pruebas" FontSize="14" Foreground="#777777" VerticalAlignment="Center" />
                             <TextBlock Grid.Column="2" Text="Proximamente" FontSize="13" FontWeight="SemiBold" Foreground="#888888" HorizontalAlignment="Right" VerticalAlignment="Center" />
                         </Grid>
                     </Border>

                     <Border x:Name="Step7Card"
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
                                 <ColumnDefinition Width="110" />
                             </Grid.ColumnDefinitions>
                             <TextBlock Text="07" FontSize="18" FontWeight="Bold" Foreground="#888888" VerticalAlignment="Center" />
                             <TextBlock Grid.Column="1" Text="Assessment final" FontSize="14" Foreground="#777777" VerticalAlignment="Center" />
                             <TextBlock Grid.Column="2" Text="Proximamente" FontSize="13" FontWeight="SemiBold" Foreground="#888888" HorizontalAlignment="Right" VerticalAlignment="Center" />
                         </Grid>
                     </Border>

                     <TextBlock x:Name="ResultLabel" Text="Resultado" FontSize="14" FontWeight="SemiBold" Foreground="#374151" Margin="0,6,0,8" />
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
$stepsNotAvailableText = $window.FindName("StepsNotAvailableText")
$resultLabel = $window.FindName("ResultLabel")

$specsStepCard = $window.FindName("SpecsStepCard")
$step2Card = $window.FindName("Step2Card")
$step3Card = $window.FindName("Step3Card")
$step4Card = $window.FindName("Step4Card")
$step5Card = $window.FindName("Step5Card")
$step6Card = $window.FindName("Step6Card")
$step7Card = $window.FindName("Step7Card")

$specsStatusText = $window.FindName("SpecsStatusText")
$executeSpecsButton = $window.FindName("ExecuteSpecsButton")
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

$specsStepCard.Effect = $shadow
$step2Card.Effect = $shadow
$step3Card.Effect = $shadow
$step4Card.Effect = $shadow
$step5Card.Effect = $shadow
$step6Card.Effect = $shadow
$step7Card.Effect = $shadow

$script:stepStatuses = @{
    Specs = $session.SpecsStatus
}

function Save-Session {
    $sessionObject = [ordered]@{
        Product = [string]$productCombo.SelectedItem
        Model = [string]$modelCombo.SelectedItem
        Version = [string]$versionCombo.SelectedItem
        SpecsStatus = $script:stepStatuses.Specs
        LastResult = $resultTextBox.Text
        SavedAt = (Get-Date).ToString("s")
    }

    $sessionObject | ConvertTo-Json -Depth 4 | Set-Content -Path $sessionPath -Encoding UTF8
}

function Update-Progress {
    $completed = 0
    if ($script:stepStatuses.Specs -eq "Completed" -or $script:stepStatuses.Specs -eq "Warning") {
        $completed = 1
    }
    
    $percent = [math]::Round(($completed / 7) * 100, 0)
    $progressBar.Value = $percent
    $progressLabel.Text = "Progreso general: $percent% ($completed de 7 pasos completados)"
}

function Update-StepState {
    param(
        [string]$Step,
        [string]$Status
    )

    $script:stepStatuses[$Step] = $Status
    $statusText = $specsStatusText
    $button = $executeSpecsButton

    $statusText.Text = Get-StatusText -Status $Status

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

function Update-VersionSteps {
    $selectedVersionName = [string]$versionCombo.SelectedItem
    $script:selectedVersion = $null
    if ($null -ne $script:selectedModel) {
        $script:selectedVersion = $script:selectedModel.versions | Where-Object { $_.displayName -eq $selectedVersionName }
    }

    if ($null -ne $script:selectedVersion) {
        $prodName = $script:selectedProduct.displayName
        $modelName = $script:selectedModel.displayName
        $verName = $script:selectedVersion.displayName

        if ($script:selectedVersion.stepsAvailable) {
            $stepsNotAvailableText.Visibility = "Collapsed"

            $specsStepCard.Visibility = "Visible"
            $step2Card.Visibility = "Visible"
            $step3Card.Visibility = "Visible"
            $step4Card.Visibility = "Visible"
            $step5Card.Visibility = "Visible"
            $step6Card.Visibility = "Visible"
            $step7Card.Visibility = "Visible"
            $resultLabel.Visibility = "Visible"
            $resultTextBox.Visibility = "Visible"

            $planSubtitle.Text = "$prodName - $modelName - Version $verName"

            if (-not $script:loadingSession) {
                $script:stepStatuses.Specs = "Pending"
                $resultTextBox.Text = ""
            } else {
                # Cargar el resultado almacenado si se esta restaurando
                $resultTextBox.Text = $session.LastResult
            }

            Update-StepState -Step "Specs" -Status $script:stepStatuses.Specs
        }
        else {
            $stepsNotAvailableText.Text = "Pasos no disponibles para $prodName $modelName $verName. Proximamente."
            $stepsNotAvailableText.Visibility = "Visible"

            $specsStepCard.Visibility = "Collapsed"
            $step2Card.Visibility = "Collapsed"
            $step3Card.Visibility = "Collapsed"
            $step4Card.Visibility = "Collapsed"
            $step5Card.Visibility = "Collapsed"
            $step6Card.Visibility = "Collapsed"
            $step7Card.Visibility = "Collapsed"
            $resultLabel.Visibility = "Collapsed"
            $resultTextBox.Visibility = "Collapsed"

            $planSubtitle.Text = "$prodName - $modelName - Version $verName"
            $progressBar.Value = 0
            $progressLabel.Text = "Progreso general: 0%"
        }
        Save-Session
    }
}

function Update-ModelCombo {
    $modelCombo.Items.Clear()
    $versionCombo.Items.Clear()

    $selectedProductName = [string]$productCombo.SelectedItem
    $script:selectedProduct = $script:catalog.products | Where-Object { $_.displayName -eq $selectedProductName }

    if ($null -ne $script:selectedProduct) {
        foreach ($model in $script:selectedProduct.models) {
            $modelCombo.Items.Add($model.displayName) | Out-Null
        }
    }

    $hasModel = $false
    if ($null -ne $script:selectedProduct) {
        $hasModel = ($script:selectedProduct.models | Where-Object { $_.displayName -eq $session.Model }) -ne $null
    }

    if ($hasModel) {
        $modelCombo.SelectedItem = $session.Model
    }
    elseif ($modelCombo.Items.Count -gt 0) {
        $modelCombo.SelectedIndex = 0
    }

    Update-VersionCombo
}

function Update-VersionCombo {
    $versionCombo.Items.Clear()

    $selectedModelName = [string]$modelCombo.SelectedItem
    $script:selectedModel = $null
    if ($null -ne $script:selectedProduct) {
        $script:selectedModel = $script:selectedProduct.models | Where-Object { $_.displayName -eq $selectedModelName }
    }

    if ($null -ne $script:selectedModel) {
        foreach ($version in $script:selectedModel.versions) {
            $versionCombo.Items.Add($version.displayName) | Out-Null
        }
    }

    $hasVersion = $false
    if ($null -ne $script:selectedModel) {
        $hasVersion = ($script:selectedModel.versions | Where-Object { $_.displayName -eq $session.Version }) -ne $null
    }

    if ($hasVersion) {
        $versionCombo.SelectedItem = $session.Version
    }
    elseif ($versionCombo.Items.Count -gt 0) {
        $versionCombo.SelectedIndex = 0
    }
}

function Get-ValidateSpecificationsScriptBlock {
    [CmdletBinding()]
    param()

    $localScript = Join-Path -Path $projectRoot -ChildPath "scripts\validation\Validate-Specifications.ps1"
    if (Test-Path -Path $localScript -PathType Leaf) {
        return @{
            Command = $localScript
            IsFile = $true
        }
    }

    $scriptUrl = "https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/scripts/validation/Validate-Specifications.ps1?cacheBust=$([DateTime]::UtcNow.Ticks)"
    $scriptContent = Invoke-RestMethod -Uri $scriptUrl -Headers @{
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
    } -ErrorAction Stop

    return @{
        Command = [scriptblock]::Create($scriptContent)
        IsFile = $false
    }
}

function Invoke-SpecsValidation {
    Update-StepState -Step "Specs" -Status "Running"
    $resultTextBox.Text = "Ejecutando validacion de especificaciones..."

    $script:specsProduct = [string]$productCombo.SelectedItem
    $script:specsVersion = [string]$versionCombo.SelectedItem
    $script:specsModel = [string]$modelCombo.SelectedItem

    $manifestsObj = $script:selectedVersion.manifests
    $script:specsManifestPaths = @{}
    if ($null -ne $manifestsObj) {
        foreach ($prop in $manifestsObj.PSObject.Properties) {
            if ($prop.Value) {
                $script:specsManifestPaths[$prop.Name] = Join-Path -Path $projectRoot -ChildPath $prop.Value
            }
        }
    }

    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timer.Add_Tick({
        param($timerSender, $timerArgs)

        $timerSender.Stop()

        try {
            $validator = Get-ValidateSpecificationsScriptBlock
            $res = & $validator.Command -Product $script:specsProduct -Version $script:specsVersion -Model $script:specsModel -ManifestPaths $script:specsManifestPaths
            $resultTextBox.Text = $res.Text

            switch ($res.Status) {
                "Pass" { Update-StepState -Step "Specs" -Status "Completed" }
                "Warning" { Update-StepState -Step "Specs" -Status "Warning" }
                default { Update-StepState -Step "Specs" -Status "Failed" }
            }
        }
        catch {
            $resultTextBox.Text = "Error al ejecutar la validacion de especificaciones:`r`n$($_.Exception.Message)"
            Update-StepState -Step "Specs" -Status "Failed"
        }

        Save-Session
    })
    $timer.Start()
}

function Show-Report {
    $message = "Reporte DFE-Toolkit`n`nProducto: $($productCombo.SelectedItem)`nModelo: $($modelCombo.SelectedItem)`nVersion: $($versionCombo.SelectedItem)`nPaso 01 - Validar especificaciones: $(Get-StatusText -Status $script:stepStatuses.Specs)"
    [Windows.MessageBox]::Show($message, "Reporte DFE-Toolkit", "OK", "Information") | Out-Null
}

foreach ($product in $script:catalog.products) {
    $productCombo.Items.Add($product.displayName) | Out-Null
}

$hasProduct = $false
if ($null -ne $script:catalog) {
    $hasProduct = ($script:catalog.products | Where-Object { $_.displayName -eq $session.Product }) -ne $null
}

if ($hasProduct) {
    $productCombo.SelectedItem = $session.Product
}
else {
    if ($productCombo.Items.Count -gt 0) {
        $productCombo.SelectedIndex = 0
    }
}

$productCombo.Add_SelectionChanged({
    Update-ModelCombo
})

$modelCombo.Add_SelectionChanged({
    Update-VersionCombo
})

$versionCombo.Add_SelectionChanged({
    Update-VersionSteps
})

$executeSpecsButton.Add_Click({
    Invoke-SpecsValidation
})

$reportButton.Add_Click({
    Show-Report
})

$window.Add_Closing({
    Save-Session
})

$script:loadingSession = $true
Update-ModelCombo
$script:loadingSession = $false

$window.ShowDialog() | Out-Null
