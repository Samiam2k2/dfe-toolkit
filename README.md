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
│   └── Main.ps1
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

## Notas

- El proyecto trabaja solo en local.
- Las claves y rutas DFE usadas por la validacion son ejemplos tipicos para Windows.
- No se incluyen credenciales, tokens ni rutas de clientes.
