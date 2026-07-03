# DFE Toolkit

Herramienta local en PowerShell para validaciones básicas orientadas a servidores DFE HP Indigo en Windows.

## Requisitos

- Windows 10/11 o Windows Server.
- PowerShell 5.1 o superior.
- Permisos de lectura sobre las rutas locales que se quieran validar.

## Estructura

```text
dfe-toolkit/
├── bootstrap.ps1                     # Descarga y lanza la interfaz gráfica
├── src/
│   └── Gui.ps1                       # Interfaz gráfica WPF
├── scripts/
│   └── validation/
│       ├── Validate-Specifications.ps1 # Orquestador principal de especificaciones
│       ├── Validate-Hardware.ps1
│       ├── Validate-Network.ps1
│       ├── Validate-OperatingSystem.ps1
│       ├── Validate-Storage.ps1
│       └── Validate-Security.ps1
├── utilities/
│   └── backup/                       # Utilidades externas (Preflight de backup)
│       ├── Preflight-Backup.ps1
│       ├── Test-PreflightBackup.ps1
│       ├── README.md
│       └── fixtures/
├── tests/
│   ├── Test-ValidateSpecifications.ps1 # Pruebas del orquestador consolidado
│   ├── Test-ValidateHardware.ps1
│   ├── Test-ValidateNetwork.ps1
│   ├── Test-ValidateOperatingSystem.ps1
│   ├── Test-ValidateStorage.ps1
│   ├── Test-ValidateSecurity.ps1
│   └── fixtures/                     # Fixtures simuladas por módulo
├── config/
│   └── session.json                  # Sesión de ejecución actual de la GUI
├── manifests/                        # Requisitos definidos por producto/versión
│   ├── catalog.json
│   ├── production-pro/
│   │   └── 8.3/
│   │       ├── hardware.json
│   │       ├── network.json
│   │       ├── storage.json
│   │       ├── security.json
│   │       ├── backup.json
│   │       └── assessment-checks.json
│   └── composer/
│       └── 10.1/
│           └── placeholder.json
└── README.md
```

---

## Uso Remoto (Lanzamiento Directo)

Para descargar y abrir la interfaz gráfica (GUI) WPF directamente desde GitHub:

```powershell
irm https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/bootstrap.ps1 | iex
```

---

## Uso Local

Desde la carpeta del proyecto clonado localmente, puede iniciar la GUI ejecutando:

```powershell
.\bootstrap.ps1
```

O directamente ejecutando el script de la GUI:

```powershell
.\src\Gui.ps1
```

---

## GUI WPF

La interfaz gráfica permite seleccionar dinámicamente el Producto, Modelo y Versión desde un catálogo centralizado (`catalog.json`). La interfaz se compone de los siguientes pasos:

1. **Paso 01 — Validar especificaciones**: Llama al script orquestador consolidado para validar el hardware, la red, el sistema operativo, el almacenamiento y la seguridad en un único paso interactivo, mostrando un checklist detallado en el panel.
2. **Pasos 02 a 07**: Tarjetas placeholder de instalación y pruebas adicionales en desarrollo para futuras versiones ("Próximamente").

Al cerrar, guarda el estado de la sesión en `config/session.json` de forma que los resultados persistan al reabrir la aplicación.

---

## Validación de Especificaciones (`Validate-Specifications.ps1`)

El script `scripts/validation/Validate-Specifications.ps1` coordina secuencialmente la ejecución de los 5 validadores específicos del DFE:

- **Validate-Hardware.ps1**: Modelo de servidor, fabricante, generación, memoria física y procesadores.
- **Validate-Network.ps1**: Nombres de adaptadores (DataLAN, External LAN, Internal LAN), estado de red, IP estática, métricas de red y archivo hosts.
- **Validate-OperatingSystem.ps1**: Validación del sistema operativo y baseline de build.
- **Validate-Storage.ps1**: Espacio libre por unidad de disco, unidades y layout esperado.
- **Validate-Security.ps1**: Privilegios de administrador del toolkit, configuración de UAC y estado del Firewall.

Consolida todos los checks en un único objeto de salida estructurado y genera un checklist en formato de texto plano (disponible en la propiedad `.Text` del resultado).

### Ejecución Manual del Orquestador:

```powershell
$manifests = @{
    hardware = "manifests/production-pro/8.3/hardware.json"
    network = "manifests/production-pro/8.3/network.json"
    storage = "manifests/production-pro/8.3/storage.json"
    security = "manifests/production-pro/8.3/security.json"
    assessment = "manifests/production-pro/8.3/assessment-checks.json"
}

.\scripts\validation\Validate-Specifications.ps1 -Product "Production Pro" -Version "8.3" -Model "commercial" -ManifestPaths $manifests
```

---

## Pruebas de Software

El toolkit contiene suites de pruebas automatizadas que ejecutan los validadores contra fixtures JSON de sistema simulado para comprobar aserciones de código:

```powershell
# Pruebas del orquestador consolidado
.\tests\Test-ValidateSpecifications.ps1

# Pruebas de validadores individuales
.\tests\Test-ValidateHardware.ps1
.\tests\Test-ValidateNetwork.ps1
.\tests\Test-ValidateOperatingSystem.ps1
.\tests\Test-ValidateStorage.ps1
.\tests\Test-ValidateSecurity.ps1

# Pruebas de utilidades externas
.\utilities\backup\Test-PreflightBackup.ps1
```
