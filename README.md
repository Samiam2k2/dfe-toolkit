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
├── logs/
└── README.md
```

## Uso

Desde la carpeta del proyecto:

```powershell
.\bootstrap.ps1
```

El script muestra un menu con estas opciones:

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

La GUI permite seleccionar producto, modelo y version, cargar pasos de instalacion, ejecutar pasos en modo demo, ver progreso general y generar un resumen. Al cerrar, guarda el estado de la sesion en `config/session.json`.

## Notas

- El proyecto trabaja solo en local.
- Las claves y rutas DFE usadas por la validacion son ejemplos tipicos para Windows.
- No se incluyen credenciales, tokens ni rutas de clientes.
