# Utilidad de Preflight de Backup (Magic Backup Preflight)

Esta carpeta contiene el script y los recursos para realizar el **Preflight de Backup** en servidores DFE.

## Descripción

El script `Preflight-Backup.ps1` realiza comprobaciones estáticas y de accesibilidad para asegurar que el entorno está listo para llevar a cabo una copia de seguridad completa (Magic Backup), sin llegar a realizar la copia en sí.

### Checks Realizados:
1. **`check-backup-sources`**: Verifica la existencia y accesibilidad de los directorios de origen críticos definidos en la configuración de la versión.
2. **`check-backup-destination`**: Valida que la unidad de destino exista y sea escribible realizando una prueba de creación de archivo temporal.
3. **`check-backup-tools`**: (Solo en perfil `SystemManager`) Valida que la variable de entorno `MOBIUS_HOME` y las herramientas ejecutables requeridas existan.

---

## ¿Por qué está en `utilities/`?

Este script **no forma parte del flujo de validación de especificaciones inicial del servidor DFE** (Paso 1). Se ubica en utilidades porque:
1. Su propósito es de pre-ejecución operativa y no de validación de hardware/arquitectura base.
2. Se espera que sea reutilizado más adelante por el **Paso 07: Assessment final** o integraciones operativas del instalador.
3. Permite su uso aislado y manual por los ingenieros de soporte técnico en campo sin necesidad de cargar toda la suite DFE-Toolkit.

---

## Cómo Ejecutarlo Manualmente

### 1. Ejecutar para System Manager:
```powershell
.\utilities\backup\Preflight-Backup.ps1 -Profile "SystemManager"
```

### 2. Ejecutar para IPC / RIP:
```powershell
.\utilities\backup\Preflight-Backup.ps1 -Profile "IPC_RIP"
```

### 3. Ejecutar en modo pruebas con fixture simulado:
```powershell
.\utilities\backup\Preflight-Backup.ps1 -Profile "SystemManager" -SystemInfoPath .\utilities\backup\fixtures\backup-sm-ok.json
```
