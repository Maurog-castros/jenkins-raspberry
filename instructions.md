# 📦 Proyecto Raspberry Pi - Sistema de Compartición Samba

## 🎯 Evaluación del Proyecto

### Objetivo Principal
Configurar una **Raspberry Pi como servidor de archivos en la red** utilizando **Samba**, permitiendo acceder y compartir discos (SSD) desde cualquier dispositivo en la red (Windows, Mac, Linux) sin necesidad de transporte físico.

### Estado Actual
Tu proyecto está bien estructurado y es **robusto**:

✅ **Fortalezas:**
- Scripts bash modulares y bien documentados
- Output legible con colores y estilos claros
- Separación de responsabilidades (diagnosticar, configurar, corregir, validar)
- Sistema de mensajería intuitivo (OK, ERROR, AVISO, INFO)
- Enfoque en automatización completa

⚠️ **Análisis de componentes:**
- `evaluate_services.sh` → Evaluación integral del sistema (nuevo - REFERENCIA CENTRAL)
- `validate_samba_service.sh` → Diagnóstico del estado de Samba
- `setup_samba_shares.sh` → Detecta particiones y configura shares
- `fix_samba_permissions.sh` → Corrige permisos de acceso
- `fix_samba_automount.sh` → Configura montaje automático del SSD

---

## 🚀 Flujo de Uso del Proyecto

### Fase 0: Evaluación Integral del Sistema (NUEVA)
**Comando:** `./evaluate_services.sh`

**Purpose:** Diagnóstico completo de TODOS los servicios y recursos del sistema
- Valida estado de servicios críticos (smbd, nmbd, ssh, cron, etc.)
- Analiza logs para detectar errores recientes (últimas 24h)
- Verifica recursos (disco, memoria, temperatura)
- Chequea puntos de montaje y SSD
- Valida configuración específica de Samba
- Verifica conectividad de red y DNS
- **Genera plan de corrección priorizado** (CRÍTICO → ALTO → MEDIO)

**Salida esperada:** 
- Tabla de estado del sistema completo
- Indicador visual de estado general (EXCELENTE / BUENO / REQUIERE ATENCIÓN)
- Lista priorizada de problemas encontrados
- Plan de acción numerado con instrucciones específicas

**Cuándo ejecutar:**
- ✅ PRIMERO, antes de hacer cualquier otra cosa
- ✅ Después de cada cambio importante
- ✅ Semanalmente como monitoreo rutinario
- ✅ Cuando hay problemas y necesitas diagnóstico rápido

**Ejemplo de salida:**
```
[OK] Servicio smbd activo
[⚠] Servicio nginx NO habilitado en boot
[i] Memoria disponible (45% usado)
[✗] Disco de /mnt/ssd al 91% (crítico)

Plan de corrección:
[CRÍTICO] systemctl start nginx | Servicio nginx no está corriendo
[HIGH] du -sh /mnt/ssd/* | Liberar espacio en SSD
[MEDIUM] systemctl enable nginx | Servicio no inicia automáticamente
```

---

### Fase 1: Validación Inicial
**Comando:** `./validate_samba_service.sh`

**Purpose:** Diagnosticar si Samba está correctamente instalado y configurado
- Verifica instalación de Samba
- Chequea estado de servicios (smbd, nmbd)
- Valida sintaxis de `/etc/samba/smb.conf`
- Verifica puertos escuchando (137, 138, 139, 445)
- Checkea firewall y usuarios registrados

**Salida esperada:** Tabla con estado de cada validación ✅

---

### Fase 2: Configuración de Shares
**Comando:** `./setup_samba_shares.sh`

**Purpose:** Detectar automáticamente discos/particiones compartibles y configurarlos en Samba
- Escanea particiones del sistema
- Excluye particiones del SO (no toca mmcblk0)
- Monta dispositivos en `/mnt/`
- Crea entries en `/etc/fstab` para persistencia
- Configura shares en `/etc/samba/smb.conf`
- Reinicia servicios Samba

**Casos de uso:**
- Conectar nuevo SSD USB
- Agregar disco duro externo
- Re-configurar shares existentes

---

### Fase 3: Corrección de Permisos
**Comando:** `./fix_samba_permissions.sh`

**Purpose:** Garantizar que el usuario `mauro` tiene acceso de lectura/escritura al share

**Problema que resuelve:**
- Share visible en la red pero sin permisos de escritura
- Directorios propiedad de `root` que no permiten cambios
- Sincronización de permisos entre Samba y el SO

**Lo que hace:**
- Verifica que `/mnt/ssd` esté montado
- Cambia propietario a `mauro:mauro`
- Ajusta permisos (775 - lectura/escritura completa)
- Recarga configuración de Samba

---

### Fase 4: Montaje Automático
**Comando:** `./fix_samba_automount.sh`

**Purpose:** Configurar que el SSD se monte automáticamente al encender la Raspberry

**Por qué es importante:**
- Si el SSD no está montado, Samba no puede compartirlo
- Evita tener que montar manualmente después de reinicios
- Garantiza disponibilidad del servidor

**Configuración:**
- Detecta UUID del dispositivo SSD
- Crea entrada en `/etc/fstab` con opciones confiables
- (Opcional) Configura systemd automount para arranque remoto

---

## 💾 Cómo Usar Cada Script

### Preparación Inicial (Una sola vez)

```bash
# 1. Conectarse a la Raspberry via SSH
ssh raspi

# 2. Crear directorio de scripts
mkdir -p ~/scripts

# 3. Desde tu PC (en Visual Studio Code o terminal local):
# Copiar todos los scripts a la Raspberry
scp *.sh raspi:~/scripts/

# 4. Dar permisos de ejecución a todos
ssh raspi 'chmod +x ~/scripts/*.sh'
```

### Protocolo de Uso: "Evaluación y Mantenimiento del Sistema"

```bash
# Paso 1: EVALUACIÓN INTEGRAL (siempre primero)
~/scripts/evaluate_services.sh

# Paso 2: Seguir el plan de corrección generado
# Ejecutar las acciones según la prioridad mostrada
# (CRÍTICO → ALTO → MEDIO)

# Paso 3: Re-evaluar para confirmar correcciones
~/scripts/evaluate_services.sh
```

### Uso Típico: "Quiero compartir un nuevo disco"

```bash
# Paso 1: Evaluación integral
~/scripts/evaluate_services.sh

# Paso 2: Validar que Samba funciona (debe pasar todas las pruebas)
~/scripts/validate_samba_service.sh

# Paso 3: Detectar y montar el nuevo disco
~/scripts/setup_samba_shares.sh

# Paso 4: Corregir permisos si es necesario
~/scripts/fix_samba_permissions.sh

# Paso 5: Configurar montaje automático
~/scripts/fix_samba_automount.sh

# Paso 6: Validar nuevamente
~/scripts/validate_samba_service.sh

# Paso 7: Evaluación final
~/scripts/evaluate_services.sh
```

### Uso Típico: "El share no funciona o hay problemas"

```bash
# Paso 1: Evaluación integral (detecta TODOS los problemas)
~/scripts/evaluate_services.sh

# Paso 2: Ejecutar las correcciones sugeridas en ORDEN
# El script genera un plan priorizado - seguirlo tal cual

# Paso 3: Diagnóstico específico de Samba
~/scripts/validate_samba_service.sh

# Paso 4: Correcciones específicas
# (elegir según el problema)
~/scripts/fix_samba_permissions.sh   # Si hay problemas de acceso
~/scripts/fix_samba_automount.sh     # Si el SSD no está montado

# Paso 5: Validar nuevamente
~/scripts/validate_samba_service.sh
~/scripts/evaluate_services.sh
```

---

## 🔧 Configuración Actual

### Usuario Samba
- **Usuario:** `mauro`
- **Ubicación de shares:** `/mnt/ssd` (y otras particiones en `/mnt/`)
- **Archivo de config:** `/etc/samba/smb.conf`

### Servicios Críticos
- `smbd` - Servidor de archivos Samba (puerto 445 TCP)
- `nmbd` - Protocolo NetBIOS (puertos 137-138 UDP)

### Puntos de Montaje
- `/mnt/ssd` - Share principal (SSD externo)
- `/mnt/*` - Otras particiones detectadas automáticamente

---

## 📋 Próximos Pasos / Mejoras Futuras

### Fase Siguiente: Acceso desde Windows/Mac/Linux
Una vez que Samba esté configurado, podrás:

**Windows:**
```
✔️ Abrir "Este equipo" → "Agregar ubicación de red"
✔️ Escribir: \\raspi\ssd
✔️ Ingresar usuario: mauro / contraseña
```

**Mac/Linux:**
```bash
# Montar vía Finder (Mac) o terminal (Linux)
mount_smbfs //mauro@raspi/ssd /Volumes/ssd
```

### Mejoras Técnicas a Considerar
1. **Backup automático** - Script de sync periódico
2. **Monitoreo** - Alertas si disco se llena
3. **Logs** - Registrar accesos al share
4. **Seguridad** - Configurar autenticación más fuerte
5. **Performance** - Monitoreo de velocidad de transferencia

---

## 🆘 Troubleshooting Rápido

**Primera línea de acción en TODO problema:**
```bash
~/scripts/evaluate_services.sh
```

Este script detectará automáticamente qué está mal y generará un plan de corrección.

---

| Problema | Comando diagnóstico | Solución |
|----------|---------------------------|----------|
| Problemas generales | `./evaluate_services.sh` | Seguir plan de corrección |
| Share no visible en red | `./validate_samba_service.sh` | Verificar si smbd está activo |
| No poder escribir en share | `./fix_samba_permissions.sh` | Cambiar propietario a mauro |
| Errores de montaje | `mount \| grep /mnt` | Ejecutar `./fix_samba_automount.sh` |
| Samba no arranca | `systemctl status smbd` | Ver logs, luego reconfigurar smb.conf |
| Share desaparece tras reboot | `cat /etc/fstab` | Ejecutar `./fix_samba_automount.sh` |
| CPU/Memoria alta | `./evaluate_services.sh` | Revisa sección de recursos |
| Disco lleno | `./evaluate_services.sh` | Liberar espacio según plan |

---

## 📝 Logging & Auditoría

Todos los scripts generan **output legible** en consola:
- 🟦 `[INFO]` - Información general (cyan)
- 🟩 `[OK]` - Operación exitosa (verde)
- 🟨 `[AVISO]` - Advertencia (amarillo)
- 🟥 `[ERROR]` - Fallo crítico (rojo)

**Recomendación:** Ejecuta los scripts y captura la salida en archivos de log:
```bash
./validate_samba_service.sh > validation_$(date +%Y%m%d_%H%M%S).log 2>&1
```

---

## 🎓 Conceptos Clave

### Samba
Protocolo SMB/CIFS que permite compartir archivos entre sistemas operativos diferentes como si fuera un pendrive en la red.

### Mount Point (`/mnt/ssd`)
Ubicación en el árbol de directorios del Linux donde se "monta" (conecta) un dispositivo para acceder a sus archivos.

### `/etc/fstab`
Archivo que define qué dispositivos montar automáticamente al iniciar el SO.

### UUID del dispositivo
Identificador único del disco (más confiable que `/dev/sdaX` que puede cambiar).

### Permisos (755, 775)
- `7` = propietario tiene lectura/escritura/ejecución
- `5` = otros usuarios solo lectura/ejecución
- `7` = grupo tiene lectura/escritura/ejecución

---

## ✅ Checklist de Implementación

- [ ] Copiar todos los scripts a `~/scripts/` en la Raspberry
  - [ ] evaluate_services.sh (nuevo)
  - [ ] validate_samba_service.sh
  - [ ] setup_samba_shares.sh
  - [ ] fix_samba_permissions.sh
  - [ ] fix_samba_automount.sh
- [ ] Ejecutar `evaluate_services.sh` y revisar el reporte completo
- [ ] Ejecutar recomendaciones del plan de corrección (CRÍTICO primero)
- [ ] Ejecutar `evaluate_services.sh` nuevamente para validar correcciones
- [ ] Ejecutar `validate_samba_service.sh` y verificar que pase todas las pruebas
- [ ] Conectar SSD y ejecutar `setup_samba_shares.sh`
- [ ] Ejecutar `fix_samba_permissions.sh` si hay problemas de acceso
- [ ] Ejecutar `fix_samba_automount.sh` para montaje automático
- [ ] Validar nuevamente con `validate_samba_service.sh`
- [ ] Volver a ejecutar `evaluate_services.sh` como evaluación final
- [ ] Probar acceso desde Windows/Mac/Linux
- [ ] Documentar shares finales en un archivo de referencia

---

## 📞 Soporte & Continuación

Este proyecto está listo para **expanderse** hacia:
- ✅ Automatización completa de backups
- ✅ Monitoreo y alertas del estado del servidor
- ✅ Interfaz web para gestión
- ✅ Replicación de datos entre múltiples Raspberry Pi

Contáctame cuando necesites ayuda con los próximos pasos.

---

**Última actualización:** Marzo 2026  
**Estado:** Proyecto lisisto para despliegue inicial  
**Versión de scripts:** v2 (con validación y corrección)
