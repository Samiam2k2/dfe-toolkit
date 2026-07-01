<#
.SYNOPSIS
    Interfaz grafica WPF para DFE-Toolkit.
.DESCRIPTION
    GUI local compatible con Windows PowerShell 5.1+ para gestionar pasos de
    instalacion demo de servidores DFE.
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
    Failed = [char]::ConvertFromUtf32(0x274C)
    Skipped = [char]::ConvertFromUtf32(0x23ED) + [char]0xFE0F
    Running = [char]::ConvertFromUtf32(0x25B6) + [char]0xFE0F
}

function Get-StatusText {
    param([string]$Status)

    switch ($Status) {
        "Completed" { return "$($statusIcons.Completed) Completado" }
        "Failed" { return "$($statusIcons.Failed) Fallido" }
        "Skipped" { return "$($statusIcons.Skipped) Saltado" }
        "Running" { return "$($statusIcons.Running) En ejecucion..." }
        default { return "$($statusIcons.Pending) Pendiente" }
    }
}

$installPlanJson = @'
{
  "plans": [
    {
      "product": "Production Pro",
      "model": "Commercial",
      "version": "8.3",
      "steps": [
        "Validar hardware",
        "Configurar BIOS y red",
        "Verificar almacenamiento",
        "Confirmar version de Windows Server",
        "Instalar prerequisitos",
        "Configurar usuarios de servicio",
        "Preparar carpetas de trabajo",
        "Instalar software principal",
        "Configurar servicios DFE",
        "Activar licencias",
        "Crear backup en blanco",
        "Instalar updates",
        "Ejecutar optimizadores",
        "Configurar colas de impresion",
        "Validar comunicacion con prensa",
        "Procesar jobs demo",
        "Revisar logs principales",
        "Documentar configuracion",
        "Backup final",
        "Validacion final con operador"
      ]
    },
    {
      "product": "Production Pro",
      "model": "Labels & Packaging",
      "version": "8.3",
      "steps": [
        "Validar hardware",
        "Configurar BIOS y red",
        "Verificar almacenamiento",
        "Confirmar version de Windows Server",
        "Instalar prerequisitos",
        "Configurar usuarios de servicio",
        "Preparar carpetas de trabajo",
        "Instalar software principal",
        "Configurar servicios DFE",
        "Activar licencias",
        "Crear backup en blanco",
        "Instalar updates",
        "Ejecutar optimizadores",
        "Configurar colas de etiquetas",
        "Validar comunicacion con prensa",
        "Procesar jobs demo de etiquetas",
        "Revisar logs principales",
        "Documentar configuracion",
        "Backup final",
        "Validacion final con operador"
      ]
    },
    {
      "product": "Composer",
      "model": "Composer Server",
      "version": "10.1",
      "steps": [
        "Validar hardware",
        "Configurar red del servidor",
        "Verificar almacenamiento",
        "Confirmar version de Windows Server",
        "Instalar prerequisitos",
        "Configurar usuarios de servicio",
        "Preparar carpetas de composicion",
        "Instalar Composer Server",
        "Configurar servicios Composer",
        "Activar licencias",
        "Configurar plantillas base",
        "Instalar updates",
        "Ejecutar optimizadores",
        "Configurar rutas de entrada",
        "Validar comunicacion con DFE",
        "Procesar jobs demo",
        "Revisar logs principales",
        "Documentar configuracion",
        "Backup final",
        "Validacion final con operador"
      ]
    }
  ]
}
'@

$installPlans = ($installPlanJson | ConvertFrom-Json).plans
$session = @{
    Product = "Production Pro"
    Model = "Commercial"
    Version = "8.3"
    Steps = @{}
}

if (Test-Path -Path $sessionPath -PathType Leaf) {
    try {
        $loadedSession = Get-Content -Path $sessionPath -Raw | ConvertFrom-Json
        if ($loadedSession.Product) { $session.Product = $loadedSession.Product }
        if ($loadedSession.Model) { $session.Model = $loadedSession.Model }
        if ($loadedSession.Version) { $session.Version = $loadedSession.Version }
        if ($loadedSession.Steps) {
            foreach ($property in $loadedSession.Steps.PSObject.Properties) {
                $stepStates = @{}
                foreach ($stepProperty in $property.Value.PSObject.Properties) {
                    $stepStates[$stepProperty.Name] = $stepProperty.Value
                }
                $session.Steps[$property.Name] = $stepStates
            }
        }
    }
    catch {
        $session.Steps = @{}
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
        <DropShadowEffect x:Key="SoftShadow" Color="#000000" BlurRadius="12" ShadowDepth="1" Opacity="0.16" />
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
                           Text="Modo demo de instalacion"
                           Foreground="#9E9E9E"
                           FontSize="12" />
            </StackPanel>
        </Border>

        <Grid Grid.Column="1" Background="White" Margin="0">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto" />
                <RowDefinition Height="*" />
                <RowDefinition Height="Auto" />
            </Grid.RowDefinitions>

            <Border Grid.Row="0" Background="White" Padding="30,24,30,16" BorderBrush="#E5E7EB" BorderThickness="0,0,0,1">
                <DockPanel>
                    <StackPanel DockPanel.Dock="Left">
                        <TextBlock x:Name="HeaderTitle" Text="Pasos de instalacion" FontSize="26" FontWeight="SemiBold" Foreground="#1F2937" />
                        <TextBlock x:Name="PlanSubtitle" Text="Seleccione una instalacion y cargue los pasos" Foreground="#6B7280" Margin="0,4,0,0" />
                    </StackPanel>
                </DockPanel>
            </Border>

            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Background="#F8FAFC">
                <StackPanel x:Name="StepsPanel" Margin="24" />
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
$stepsPanel = $window.FindName("StepsPanel")
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
$footerModeText.Text = "Modo demo de instalaci$($oAcuteLower)n"
$headerTitle.Text = "Pasos de instalaci$($oAcuteLower)n"
$planSubtitle.Text = "Seleccione una instalaci$($oAcuteLower)n y cargue los pasos"

$script:currentSteps = @()
$script:stepRows = @()

function Get-PlanKey {
    param(
        [string]$Product,
        [string]$Model,
        [string]$Version
    )

    return "$Product|$Model|$Version"
}

function Get-SelectedPlan {
    $product = [string]$productCombo.SelectedItem
    $model = [string]$modelCombo.SelectedItem
    $version = [string]$versionCombo.SelectedItem

    return $installPlans | Where-Object {
        $_.product -eq $product -and $_.model -eq $model -and $_.version -eq $version
    } | Select-Object -First 1
}

function Update-Progress {
    if (-not $script:currentSteps -or $script:currentSteps.Count -eq 0) {
        $progressBar.Value = 0
        $progressLabel.Text = "Progreso general: 0%"
        return
    }

    $completed = @($script:currentSteps | Where-Object { $_.Status -eq "Completed" }).Count
    $percent = [math]::Round(($completed / $script:currentSteps.Count) * 100, 0)
    $progressBar.Value = $percent
    $progressLabel.Text = "Progreso general: $percent% ($completed de $($script:currentSteps.Count) pasos completados)"
}

function Update-StepRow {
    param([int]$Index)

    $row = $script:stepRows[$Index]
    $step = $script:currentSteps[$Index]

    $row.StatusText.Text = Get-StatusText -Status $step.Status
    $row.ExecuteButton.IsEnabled = ($step.Status -eq "Pending")

    switch ($step.Status) {
        "Completed" { $row.StatusText.Foreground = "#15803D" }
        "Failed" { $row.StatusText.Foreground = "#B91C1C" }
        "Skipped" { $row.StatusText.Foreground = "#6B7280" }
        "Running" { $row.StatusText.Foreground = "#1D4ED8" }
        default { $row.StatusText.Foreground = "#92400E" }
    }
}

function Save-Session {
    $planKey = Get-PlanKey -Product ([string]$productCombo.SelectedItem) -Model ([string]$modelCombo.SelectedItem) -Version ([string]$versionCombo.SelectedItem)

    if (-not $session.Steps.ContainsKey($planKey)) {
        $session.Steps[$planKey] = @{}
    }

    foreach ($step in $script:currentSteps) {
        $session.Steps[$planKey][$step.Number] = $step.Status
    }

    $session.Product = [string]$productCombo.SelectedItem
    $session.Model = [string]$modelCombo.SelectedItem
    $session.Version = [string]$versionCombo.SelectedItem

    $sessionObject = [ordered]@{
        Product = $session.Product
        Model = $session.Model
        Version = $session.Version
        Steps = $session.Steps
        SavedAt = (Get-Date).ToString("s")
    }

    $sessionObject | ConvertTo-Json -Depth 8 | Set-Content -Path $sessionPath -Encoding UTF8
}

function Load-Steps {
    $plan = Get-SelectedPlan
    $stepsPanel.Children.Clear()
    $script:currentSteps = @()
    $script:stepRows = @()

    if (-not $plan) {
        $planSubtitle.Text = "No hay pasos configurados para la seleccion actual"
        Update-Progress
        return
    }

    $planSubtitle.Text = "$($plan.product) - $($plan.model) - Version $($plan.version)"
    $planKey = Get-PlanKey -Product $plan.product -Model $plan.model -Version $plan.version
    $savedSteps = @{}
    if ($session.Steps.ContainsKey($planKey)) {
        $savedSteps = $session.Steps[$planKey]
    }

    for ($index = 0; $index -lt $plan.steps.Count; $index++) {
        $number = "{0:D2}" -f ($index + 1)
        $status = "Pending"
        if ($savedSteps.ContainsKey($number)) {
            $status = [string]$savedSteps[$number]
        }

        $step = [pscustomobject]@{
            Number = $number
            Name = [string]$plan.steps[$index]
            Status = $status
        }
        $script:currentSteps += $step

        $border = New-Object Windows.Controls.Border
        $border.Background = "#FFFFFF"
        $border.BorderBrush = "#E5E7EB"
        $border.BorderThickness = "1"
        $border.CornerRadius = "7"
        $border.Padding = "14"
        $border.Margin = "0,0,0,10"

        $shadow = New-Object Windows.Media.Effects.DropShadowEffect
        $shadow.Color = [Windows.Media.Color]::FromRgb(0, 0, 0)
        $shadow.BlurRadius = 12
        $shadow.ShadowDepth = 1
        $shadow.Opacity = 0.16
        $border.Effect = $shadow

        $grid = New-Object Windows.Controls.Grid
        $grid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width = "58" }))
        $grid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width = "*" }))
        $grid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width = "150" }))
        $grid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width = "110" }))

        $numberText = New-Object Windows.Controls.TextBlock
        $numberText.Text = $number
        $numberText.FontSize = 18
        $numberText.FontWeight = "Bold"
        $numberText.Foreground = "#0078D4"
        $numberText.VerticalAlignment = "Center"
        [Windows.Controls.Grid]::SetColumn($numberText, 0)
        $grid.Children.Add($numberText) | Out-Null

        $nameText = New-Object Windows.Controls.TextBlock
        $nameText.Text = $step.Name
        $nameText.FontSize = 14
        $nameText.Foreground = "#111827"
        $nameText.VerticalAlignment = "Center"
        $nameText.TextWrapping = "Wrap"
        [Windows.Controls.Grid]::SetColumn($nameText, 1)
        $grid.Children.Add($nameText) | Out-Null

        $statusText = New-Object Windows.Controls.TextBlock
        $statusText.FontSize = 13
        $statusText.FontWeight = "SemiBold"
        $statusText.VerticalAlignment = "Center"
        [Windows.Controls.Grid]::SetColumn($statusText, 2)
        $grid.Children.Add($statusText) | Out-Null

        $executeButton = New-Object Windows.Controls.Button
        $executeButton.Content = "Ejecutar"
        $executeButton.Tag = $index
        $executeButton.Width = 92
        $executeButton.Height = 32
        $executeButton.HorizontalAlignment = "Right"
        $executeButton.VerticalAlignment = "Center"
        [Windows.Controls.Grid]::SetColumn($executeButton, 3)
        $grid.Children.Add($executeButton) | Out-Null

        $executeButton.Add_Click({
            param($sender, $eventArgs)

            $stepIndex = [int]$sender.Tag
            $script:currentSteps[$stepIndex].Status = "Running"
            Update-StepRow -Index $stepIndex

            $timer = New-Object Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromMilliseconds(850)
            $timer.Tag = $stepIndex
            $timer.Add_Tick({
                param($timerSender, $timerArgs)

                $timerSender.Stop()
                $finishedIndex = [int]$timerSender.Tag

                if ((Get-Random -Minimum 1 -Maximum 101) -le 92) {
                    $script:currentSteps[$finishedIndex].Status = "Completed"
                }
                else {
                    $script:currentSteps[$finishedIndex].Status = "Failed"
                }

                Update-StepRow -Index $finishedIndex
                Update-Progress
                Save-Session
            })
            $timer.Start()
        })

        $border.Child = $grid
        $stepsPanel.Children.Add($border) | Out-Null

        $script:stepRows += [pscustomobject]@{
            StatusText = $statusText
            ExecuteButton = $executeButton
        }
        Update-StepRow -Index $index
    }

    Update-Progress
    Save-Session
}

function Update-ModelCombo {
    $modelCombo.Items.Clear()
    $versionCombo.Items.Clear()

    $product = [string]$productCombo.SelectedItem
    $models = @($installPlans | Where-Object { $_.product -eq $product } | Select-Object -ExpandProperty model -Unique)

    foreach ($model in $models) {
        $modelCombo.Items.Add($model) | Out-Null
    }

    if ($models -contains $session.Model) {
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
    $model = [string]$modelCombo.SelectedItem
    $versions = @($installPlans | Where-Object { $_.product -eq $product -and $_.model -eq $model } | Select-Object -ExpandProperty version -Unique)

    foreach ($version in $versions) {
        $versionCombo.Items.Add($version) | Out-Null
    }

    if ($versions -contains $session.Version) {
        $versionCombo.SelectedItem = $session.Version
    }
    elseif ($versionCombo.Items.Count -gt 0) {
        $versionCombo.SelectedIndex = 0
    }
}

function Show-Report {
    if (-not $script:currentSteps -or $script:currentSteps.Count -eq 0) {
        [Windows.MessageBox]::Show("Primero cargue los pasos de instalacion.", "DFE-Toolkit", "OK", "Information") | Out-Null
        return
    }

    $completed = @($script:currentSteps | Where-Object { $_.Status -eq "Completed" }).Count
    $failed = @($script:currentSteps | Where-Object { $_.Status -eq "Failed" }).Count
    $pending = @($script:currentSteps | Where-Object { $_.Status -eq "Pending" }).Count
    $message = "Resumen de instalacion demo`n`nProducto: $($productCombo.SelectedItem)`nModelo: $($modelCombo.SelectedItem)`nVersion: $($versionCombo.SelectedItem)`n`nCompletados: $completed`nFallidos: $failed`nPendientes: $pending"

    [Windows.MessageBox]::Show($message, "Reporte DFE-Toolkit", "OK", "Information") | Out-Null
}

$products = @($installPlans | Select-Object -ExpandProperty product -Unique)
foreach ($product in $products) {
    $productCombo.Items.Add($product) | Out-Null
}

if ($products -contains $session.Product) {
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

$reportButton.Add_Click({
    Show-Report
})

$window.Add_Closing({
    Save-Session
})

Update-ModelCombo
Load-Steps

$window.ShowDialog() | Out-Null
