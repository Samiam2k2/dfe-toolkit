# Guía de Manifiestos de DFE-Toolkit

Esta guía describe la arquitectura de configuración, la organización de carpetas y el formato de los manifiestos utilizados por DFE-Toolkit para validar servidores DFE tanto desde la interfaz gráfica (GUI) como desde la consola de comandos (CLI).

---

## 1. Organización de Archivos

Todos los archivos de requisitos se almacenan bajo el directorio `manifests/` con la siguiente estructura jerárquica:

```
manifests/
├── catalog.json                       # Catálogo centralizado de productos y versiones
├── production-pro/
│   └── 8.3/
│       ├── hardware.json              # Requisitos de hardware
│       ├── network.json               # Requisitos de red
│       ├── storage.json               # Requisitos de almacenamiento y estructura
│       ├── security.json              # Requisitos de seguridad (UAC, privilegios, firewall)
│       ├── backup.json                # Configuración preflight para copias de seguridad
│       └── assessment-checks.json     # Definición de checks eIDs evaluados por el toolkit
└── composer/
    └── 10.1/
        └── placeholder.json           # Manifiesto placeholder para productos en desarrollo
```

---

## 2. Estructura de `catalog.json`

El archivo `manifests/catalog.json` es el punto único de verdad para la carga dinámica de opciones en el DFE-Toolkit. Su esquema JSON es el siguiente:

```json
{
  "products": [
    {
      "id": "production-pro",
      "displayName": "Production Pro",
      "models": [
        {
          "id": "commercial",
          "displayName": "Commercial",
          "versions": [
            {
              "id": "8.3",
              "displayName": "8.3",
              "stepsAvailable": true,
              "manifests": {
                "hardware": "manifests/production-pro/8.3/hardware.json",
                "network": "manifests/production-pro/8.3/network.json",
                "storage": "manifests/production-pro/8.3/storage.json",
                "security": "manifests/production-pro/8.3/security.json",
                "backup": "manifests/production-pro/8.3/backup.json",
                "assessment": "manifests/production-pro/8.3/assessment-checks.json"
              }
            }
          ]
        }
      ]
    }
  ]
}
```

### Campos Clave:
- **`displayName`**: Es el nombre textual legible que la interfaz gráfica (GUI) y la CLI muestran en pantalla al usuario.
- **`stepsAvailable`**: Un booleano (`true`/`false`) que determina si el toolkit debe mostrar las tarjetas de pasos e intentar la ejecución.
  - Si es `true`, los pasos de validación se cargan automáticamente.
  - Si es `false`, el toolkit oculta las tarjetas de ejecución y muestra el mensaje indicando que los pasos no están disponibles aún.
- **`manifests`**: Diccionario que contiene las rutas relativas dentro del repositorio para cada uno de los manifiestos JSON.

---

## 3. Instrucciones para Agregar Productos y Versiones

Para agregar compatibilidad con un nuevo producto, modelo o versión:

1. **Crear la estructura de archivos**:
   Cree una subcarpeta bajo `manifests/` siguiendo el patrón `manifests/[id-del-producto]/[id-de-la-version]/`.
2. **Crear los manifiestos**:
   Copie y ajuste los archivos JSON de requisitos (`hardware.json`, `network.json`, etc.) para adaptarlos al nuevo entorno.
3. **Actualizar el Catálogo**:
   Edite `manifests/catalog.json` y añada el nuevo producto, modelo o versión dentro de los arreglos correspondientes. Asegúrese de especificar `stepsAvailable` como `true` o `false` según el estado de desarrollo de la validación.

---

## 4. El Campo Reservado `variants`

> [!IMPORTANT]
> El campo `variants` a nivel de modelo está explícitamente reservado para futuras implementaciones de configuraciones variantes (por ejemplo: básica, estándar, avanzada o simplificada). 
> **No modifique ni implemente lógica alrededor de este campo** hasta que la arquitectura de variantes sea formalmente diseñada y aprobada.

---

## 5. Advertencia sobre URL de Descarga Directa (Raw URLs)

Los validadores de DFE-Toolkit están diseñados para ser totalmente independientes y autónomos. Si se ejecutan directamente desde la terminal sin pasar parámetros de configuración (`-ManifestPath`, etc.), el script intentará descargar la versión por defecto directamente desde GitHub (Raw URLs de la rama `main`).

> [!WARNING]
> Si cambia la estructura de carpetas de los manifiestos en el repositorio o renombra archivos, **debe actualizar los enlaces de fallback URL dentro del código de cada script validador** en `scripts/validation/`.
> Si olvida este paso, la ejecución autónoma (sin parámetros directos) fallará al no poder descargar los recursos de GitHub.
