# DFE Toolkit

Herramienta local en PowerShell para validaciones basicas orientadas a servidores DFE HP Indigo en Windows.

## Requisitos

- Windows 10/11 o Windows Server.
- PowerShell 5.1 o superior.
- Permisos de lectura sobre las rutas locales que se quieran validar.

## Estructura

```text
dfe-toolkit/
├── bootstrap.ps1
├── src/
│   ├── Main.ps1
│   └── Gui.ps1
├── scripts/
│   └── validation/
│       ├── Validate-Hardware.ps1
│       └── Validate-Network.ps1
├── tests/
│   ├── Test-ValidateHardware.ps1
│   ├── Test-ValidateNetwork.ps1
│   └── fixtures/
│       ├── z8-g5-win10.json
│       ├── proliant-gen10-ws2019.json
│       ├── z840-win10.json
│       ├── dell-incompatible.json
│       └── network/
│           ├── net-completa.json
│           ├── net-mala-config.json
│           └── net-sin-adaptadores.json
├── config/
│   └── settings.json
├── manifests/
│   ├── assessment-checks.json
│   ├── hardware-requirements.json
│   └── network-requirements.json
├── logs/
└── README.md
```

## Uso remoto

Comando principal, abre la GUI WPF por defecto:

```powershell
irm https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/bootstrap.ps1 | iex
```

Comando alternativo para abrir el menu de texto:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Samiam2k2/dfe-toolkit/main/bootstrap.ps1))) -NoGUI
```

> Nota: PowerShell no permite pasar `-NoGUI` directamente a `iex` con `irm ... | iex -NoGUI`; ese switch se interpreta como parametro de `Invoke-Expression`, no del script descargado.

## Uso local

Desde la carpeta del proyecto, GUI por defecto:

```powershell
.\bootstrap.ps1
```

Menu de texto:

```powershell
.\bootstrap.ps1 -NoGUI
```

El menu de texto incluye estas opciones:

1. Validar Hardware
2. Validar Red
3. Salir
4. Ver resumen de instalacion
5. Abrir interfaz grafica

## GUI WPF

La interfaz grafica esta disponible en `src/Gui.ps1` y requiere Windows PowerShell con WPF.

Ejecutar directamente:

```powershell
.\src\Gui.ps1
```

Tambien se puede abrir desde el menu principal con la opcion `5. Abrir interfaz grafica`.

La GUI permite seleccionar producto, modelo y version, cargar los pasos `01. Validar hardware` y `02. Validar red` y ver los resultados en pantalla. Al cerrar, guarda el estado de la sesion en `config/session.json`.

Los pasos `01. Validar hardware` y `02. Validar red` delegan en `scripts/validation/Validate-Hardware.ps1` y `scripts/validation/Validate-Network.ps1` respectivamente (local si existe, si no se descarga de GitHub con cache-bust). El estado del paso refleja el `Status` real devuelto por el validador: `Pass` -> `Completado`, `Warning` -> `Completado con advertencias` (cuenta como completado en la barra de progreso), `Fail` -> `Fallido`. El modo pruebas ya no es el comportamiento por defecto y solo se aplica si la GUI pasa `-TestMode`.

El archivo `manifests/assessment-checks.json` contiene el manifiesto inicial de verificaciones DFE Assessment para Production Pro Commercial 8.3, organizado por categoria.

## Validacion de hardware

`scripts/validation/Validate-Hardware.ps1` es un script independiente (Windows PowerShell 5.1, sin dependencias) que ejecuta los 5 checks de categoria `hardware` de `manifests/assessment-checks.json`: `check-hardware-model`, `check-hardware-manufacturer`, `check-hardware-generation`, `check-memory-capacity` y `check-cpu-inventory`. Devuelve al pipeline un objeto con el `Status` general y el detalle por check (`Id`, `Name`, `Status`, `Detail`, `Blocking`).

Contra el sistema real:

```powershell
.\scripts\validation\Validate-Hardware.ps1 -Product "Production Pro" -Version "8.3"
```

Contra un JSON de sistema simulado (pruebas en laboratorio/VM):

```powershell
.\scripts\validation\Validate-Hardware.ps1 -SystemInfoPath .\tests\fixtures\z8-g5-win10.json
```

Los minimos de memoria y CPU se leen del bloque `minimumResources` de `manifests/hardware-requirements.json`. Esos valores son placeholder (marcados con `TODO: confirmar contra guia TS1ES-00016`) y deben ajustarse con las cifras oficiales del System Guide antes de promoverse a stable.

### Modo de validacion (`validationMode`)

El campo `validationMode` en la raiz de `manifests/hardware-requirements.json` controla como se calcula el `Status` GENERAL del paso (no cambia la severidad real de cada check, que siempre se muestra tal cual):

- `informational` (valor actual): si algun check bloqueante da `Fail`, el `Status` general se degrada a `Warning` en vez de `Fail`. Pensado para laboratorio/VM sin un servidor DFE real. El objeto de salida incluye `DegradedByMode = $true` y `RealStatus` conserva el `Fail` sin degradar para dejar el rastro honesto.
- `enforcing`: respeta el `blocking` real de cada check y bloquea con `Fail`. Pensado para validar contra un servidor de produccion.

Es una palanca distinta de `-TestMode`, que fuerza el `Status` a `Pass` (`TestModeApplied = $true`). El orden de aplicacion es: `RealStatus` (enforcing) -> degradacion por `validationMode` -> `-TestMode`. Si el campo no existe en el manifiesto, el default es `enforcing` (no cambia el comportamiento de manifiestos viejos).

## Validacion de red

`scripts/validation/Validate-Network.ps1` es un script independiente (Windows PowerShell 5.1, sin dependencias) que ejecuta los 5 checks de categoria `network` de `manifests/assessment-checks.json`: `check-network-adapter-names`, `check-network-adapter-state`, `check-network-static-ip`, `check-network-metrics` y `check-hosts-file`. Devuelve al pipeline un objeto con la misma forma que el validador de hardware (`Status`, `RealStatus`, `TestModeApplied`, `Checks`), mas un inventario de adaptadores (`Adapters`) y `SimulatedSource`.

Los adaptadores esperados y sus metricas se leen de `manifests/network-requirements.json`; el `name` y el flag `blocking` de cada check se leen de `manifests/assessment-checks.json` (hoy los 5 son `blocking:false`, por lo que el paso es informativo y nunca da `Fail`). El check `check-hosts-file` da `Warning` mientras `requiredEntries` este vacio.

Contra el sistema real:

```powershell
.\scripts\validation\Validate-Network.ps1
```

Contra un JSON de red simulada (pruebas en laboratorio/VM):

```powershell
.\scripts\validation\Validate-Network.ps1 -SystemInfoPath .\tests\fixtures\network\net-completa.json
```

## Pruebas

`tests/Test-ValidateHardware.ps1` y `tests/Test-ValidateNetwork.ps1` corren cada validador contra sus fixtures (`tests/fixtures/` y `tests/fixtures/network/`), comparan el `Status` esperado vs obtenido y muestran un resumen PASS/FAIL por caso. Salen con codigo distinto de 0 si algun caso falla.

```powershell
.\tests\Test-ValidateHardware.ps1
.\tests\Test-ValidateNetwork.ps1
```

## Notas

- El proyecto trabaja solo en local.
- Las claves y rutas DFE usadas por la validacion son ejemplos tipicos para Windows.
- No se incluyen credenciales, tokens ni rutas de clientes.
