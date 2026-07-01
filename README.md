# DFE Toolkit

Herramienta local en PowerShell para validaciones basicas orientadas a servidores DFE HP Indigo en Windows.

## Requisitos

- Windows 10/11 o Windows Server.
- PowerShell 5.1 o superior.
- Permisos de lectura sobre las rutas locales que se quieran validar.

## Estructura

```text
/Users/samiam/dfe-toolkit/
├── bootstrap.ps1
├── src/
│   ├── Main.ps1
│   └── Gui.ps1
├── config/
│   └── settings.json
├── manifests/
│   └── hardware-requirements.json
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

La GUI permite seleccionar producto, modelo y version, cargar el paso `01. Validar hardware`, validar fabricante/modelo/SO contra `manifests/hardware-requirements.json`, ver el resultado en pantalla, consultar el progreso general y generar un resumen. En modo pruebas, el paso se marca como completado aunque el servidor no coincida. Al cerrar, guarda el estado de la sesion en `config/session.json`.

## Notas

- El proyecto trabaja solo en local.
- Las claves y rutas DFE usadas por la validacion son ejemplos tipicos para Windows.
- No se incluyen credenciales, tokens ni rutas de clientes.
