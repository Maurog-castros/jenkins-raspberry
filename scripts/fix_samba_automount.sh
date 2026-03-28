#!/bin/bash
# =============================================================================
# fix_samba_automount.sh
# Configura el montaje automático confiable del SSD via systemd automount
# Garantiza que /mnt/ssd esté disponible siempre que Samba lo necesite
# Autor: Mauro | Fecha: $(date +%Y-%m-%d)
# =============================================================================

# --- Colores para la consola ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Funciones de estilo ---
header()  { echo -e "\n${BLUE}══════════════════════════════════════════════${NC}"; echo -e "${WHITE}  $1${NC}"; echo -e "${BLUE}══════════════════════════════════════════════${NC}"; }
ok()      { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "  ${YELLOW}[AVISO]${NC} $1"; }
error()   { echo -e "  ${RED}[ERROR]${NC} $1"; }
info()    { echo -e "  ${CYAN}[INFO]${NC}  $1"; }
divider() { echo -e "  ${BLUE}----------------------------------------------${NC}"; }
step()    { echo -e "\n  ${WHITE}▶ $1${NC}"; }

# --- Configuración ---
MOUNT_POINT="/mnt/ssd"
FSTAB="/etc/fstab"
SAMBA_USER="mauro"
DEVICE_TIMEOUT=30   # segundos de espera máxima para el dispositivo

# =============================================================================
echo ""
echo -e "${WHITE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${WHITE}║   🔌 CONFIGURACIÓN DE AUTOMOUNT DEL SSD      ║${NC}"
echo -e "${WHITE}║         Raspberry Pi - $(date '+%d/%m/%Y %H:%M:%S')        ║${NC}"
echo -e "${WHITE}╚══════════════════════════════════════════════╝${NC}"
echo ""
info "Este script configura el SSD para montarse automáticamente"
info "usando systemd, garantizando que Samba siempre lo encuentre."
# =============================================================================


# --- 1. Verificar entrada actual en fstab ---
header "1. ENTRADA ACTUAL EN /etc/fstab"

if grep -q "$MOUNT_POINT" "$FSTAB"; then
    CURRENT_LINE=$(grep "$MOUNT_POINT" "$FSTAB")
    info "Entrada encontrada:"
    echo ""
    echo -e "    ${YELLOW}$CURRENT_LINE${NC}"
    echo ""

    # Extraer componentes
    DEVICE=$(echo "$CURRENT_LINE" | awk '{print $1}')
    FS_TYPE=$(echo "$CURRENT_LINE" | awk '{print $3}')
    info "Dispositivo : $DEVICE"
    info "Filesystem  : $FS_TYPE"
    info "Mount point : $MOUNT_POINT"
else
    error "No se encontró entrada para $MOUNT_POINT en $FSTAB"
    error "Ejecutá primero fix_samba_permissions.sh para configurar el montaje"
    exit 1
fi


# --- 2. Verificar si ntfs-3g está disponible ---
header "2. VERIFICANDO SOPORTE PARA $FS_TYPE"

if echo "$FS_TYPE" | grep -qi "ntfs"; then
    if command -v ntfs-3g &>/dev/null; then
        NTFS_VER=$(ntfs-3g --version 2>&1 | head -1)
        ok "ntfs-3g disponible: $NTFS_VER"
    else
        error "ntfs-3g NO está instalado"
        step "Instalando ntfs-3g..."
        apt-get install -y ntfs-3g &>/dev/null
        if command -v ntfs-3g &>/dev/null; then
            ok "ntfs-3g instalado correctamente"
        else
            error "No se pudo instalar ntfs-3g"
            exit 1
        fi
    fi
fi


# --- 3. Construir nueva línea fstab con automount ---
header "3. PREPARANDO NUEVA CONFIGURACIÓN fstab"

# Obtener UID/GID del usuario Samba
USER_ID=$(id -u "$SAMBA_USER" 2>/dev/null)
GROUP_ID=$(id -g "$SAMBA_USER" 2>/dev/null)

if [ -z "$USER_ID" ]; then
    error "Usuario '$SAMBA_USER' no encontrado"
    exit 1
fi

info "Usuario : $SAMBA_USER (UID=$USER_ID, GID=$GROUP_ID)"
info "Timeout dispositivo: ${DEVICE_TIMEOUT}s"
echo ""

# Opciones para NTFS con automount systemd
#   x-systemd.automount         → monta bajo demanda (automount unit)
#   x-systemd.device-timeout=N  → espera N segundos al dispositivo al arrancar
#   x-systemd.idle-timeout=0    → no desmontar si está inactivo
#   nofail                      → no falla el boot si el disco no está
#   noatime,nodiratime          → mejora de performance (no actualiza atime)
#   big_writes                  → mejor rendimiento en escrituras largas
#   uid=, gid=                  → propietario de los archivos montados

if echo "$FS_TYPE" | grep -qi "ntfs"; then
    NEW_OPTIONS="uid=${USER_ID},gid=${GROUP_ID},noatime,nodiratime,big_writes,nofail,x-systemd.automount,x-systemd.device-timeout=${DEVICE_TIMEOUT},x-systemd.idle-timeout=0"
elif echo "$FS_TYPE" | grep -qi "vfat\|fat\|exfat"; then
    NEW_OPTIONS="uid=${USER_ID},gid=${GROUP_ID},fmask=0113,dmask=0002,noatime,nofail,x-systemd.automount,x-systemd.device-timeout=${DEVICE_TIMEOUT},x-systemd.idle-timeout=0"
else
    # ext4, xfs, btrfs, etc.
    NEW_OPTIONS="defaults,noatime,nofail,x-systemd.automount,x-systemd.device-timeout=${DEVICE_TIMEOUT},x-systemd.idle-timeout=0"
fi

NEW_LINE="$DEVICE  $MOUNT_POINT  $FS_TYPE  $NEW_OPTIONS  0  0"

info "Nueva línea que se escribirá:"
echo ""
echo -e "    ${GREEN}$NEW_LINE${NC}"
echo ""

warn "¿Querés continuar y aplicar este cambio? (s/n)"
read -r CONFIRM
if [[ ! "$CONFIRM" =~ ^[sSyY]$ ]]; then
    warn "Operación cancelada por el usuario"
    exit 0
fi


# --- 4. Backup de fstab ---
header "4. BACKUP DE SEGURIDAD"

BACKUP="${FSTAB}.bak.$(date +%Y%m%d_%H%M%S)"
step "Creando backup en $BACKUP..."
if cp "$FSTAB" "$BACKUP"; then
    ok "Backup guardado: $BACKUP"
else
    error "No se pudo crear el backup. Abortando."
    exit 1
fi


# --- 5. Desmontar si está activo ---
header "5. PREPARANDO EL PUNTO DE MONTAJE"

if mountpoint -q "$MOUNT_POINT"; then
    step "Desmontando $MOUNT_POINT para re-configurar..."
    if umount --lazy "$MOUNT_POINT" 2>/dev/null || umount "$MOUNT_POINT" 2>/dev/null; then
        ok "$MOUNT_POINT desmontado"
    else
        warn "No se pudo desmontar $MOUNT_POINT — se re-montará sobre el existente"
    fi
else
    info "$MOUNT_POINT no estaba montado"
fi


# --- 6. Aplicar nueva línea en fstab ---
header "6. ACTUALIZANDO /etc/fstab"

step "Reemplazando entrada anterior..."
# Usamos | como delimitador en sed para evitar conflicto con / del path
sed -i "\|$MOUNT_POINT|d" "$FSTAB"
echo "$NEW_LINE" >> "$FSTAB"

if grep -qF "$MOUNT_POINT" "$FSTAB"; then
    ok "fstab actualizado correctamente"
    echo ""
    info "Verificación del contenido actualizado:"
    grep "$MOUNT_POINT" "$FSTAB" | while read line; do
        echo -e "    ${GREEN}$line${NC}"
    done
else
    error "No se pudo verificar la escritura en fstab"
    warn "Restaurando backup..."
    cp "$BACKUP" "$FSTAB"
    error "Backup restaurado. Revisá manualmente el fstab."
    exit 1
fi


# --- 7. Recargar systemd y montar ---
header "7. ACTIVANDO EL AUTOMOUNT CON SYSTEMD"

step "Recargando configuración de systemd daemon..."
if systemctl daemon-reload; then
    ok "systemd daemon recargado"
else
    error "Error al recargar systemd"
fi

step "Montando $MOUNT_POINT con la nueva configuración..."
if mount "$MOUNT_POINT"; then
    ok "$MOUNT_POINT montado correctamente"
else
    error "Error al montar $MOUNT_POINT"
    warn "Intentando diagnóstico..."
    dmesg | tail -5 | while read line; do
        warn "$line"
    done
    exit 1
fi

# Verificar que quedó bien montado
if mountpoint -q "$MOUNT_POINT"; then
    MOUNT_DETAIL=$(findmnt -n -o SOURCE,FSTYPE,OPTIONS "$MOUNT_POINT")
    ok "$MOUNT_POINT está activo"
    info "Detalle: $MOUNT_DETAIL"
    NEW_PERMS=$(stat -c "Dueño: %U:%G | Permisos: %a" "$MOUNT_POINT")
    info "Permisos: $NEW_PERMS"
else
    error "$MOUNT_POINT no quedó montado"
    exit 1
fi


# --- 8. Crear unidad systemd para que Samba dependa del SSD ---
header "8. DEPENDENCIA SYSTEMD: SAMBA → SSD"

# Nombre de la unit de mount (systemd convierte / en -)
UNIT_NAME=$(systemd-escape --path "$MOUNT_POINT").mount
AUTOMOUNT_UNIT=$(systemd-escape --path "$MOUNT_POINT").automount
info "Unit de mount   : $UNIT_NAME"
info "Unit de automount: $AUTOMOUNT_UNIT"
divider

step "Configurando smbd para depender del mount del SSD..."

OVERRIDE_DIR="/etc/systemd/system/smbd.service.d"
OVERRIDE_FILE="$OVERRIDE_DIR/wait-for-ssd.conf"

mkdir -p "$OVERRIDE_DIR"

cat > "$OVERRIDE_FILE" << EOF
# Generado por fix_samba_automount.sh - $(date)
# Asegura que smbd espere a que /mnt/ssd esté montado antes de iniciar
[Unit]
After=$UNIT_NAME $AUTOMOUNT_UNIT
Requires=$UNIT_NAME
EOF

if [ -f "$OVERRIDE_FILE" ]; then
    ok "Override de smbd creado: $OVERRIDE_FILE"
    cat "$OVERRIDE_FILE" | while read line; do
        info "  $line"
    done
else
    error "No se pudo crear el override de smbd"
fi

step "Recargando systemd y reiniciando smbd..."
systemctl daemon-reload

if systemctl restart smbd; then
    ok "smbd reiniciado correctamente"
else
    error "Error al reiniciar smbd"
fi

if systemctl restart nmbd; then
    ok "nmbd reiniciado correctamente"
else
    error "Error al reiniciar nmbd"
fi

divider
# Estado final de los servicios
for SERVICE in smbd nmbd; do
    STATUS=$(systemctl is-active $SERVICE)
    ENABLED=$(systemctl is-enabled $SERVICE 2>/dev/null)
    if [ "$STATUS" == "active" ]; then
        ok "$SERVICE → ACTIVO ($ENABLED)"
    else
        error "$SERVICE → $STATUS"
    fi
done


# --- 9. Prueba de escritura final ---
header "9. PRUEBA FINAL DE ACCESO AL SHARE"

TEST_FILE="$MOUNT_POINT/.automount_test_$(date +%s)"
step "Probando escritura en $MOUNT_POINT como '$SAMBA_USER'..."

if sudo -u "$SAMBA_USER" touch "$TEST_FILE" 2>/dev/null; then
    ok "Escritura exitosa en $MOUNT_POINT"
    rm -f "$TEST_FILE"
    ok "Archivo de prueba eliminado"
else
    error "El usuario '$SAMBA_USER' NO puede escribir en $MOUNT_POINT"
    warn "Permisos actuales: $(stat -c '%a %U:%G' $MOUNT_POINT)"
fi


# --- Resumen Final ---
header "✅ AUTOMOUNT CONFIGURADO EXITOSAMENTE"
echo ""
echo -e "  ${GREEN}Qué se configuró:${NC}"
echo -e "    → fstab actualizado con x-systemd.automount"
echo -e "    → systemd esperará ${DEVICE_TIMEOUT}s al SSD en cada arranque"
echo -e "    → smbd configurado para depender del mount del SSD"
echo -e "    → Backup guardado en: $BACKUP"
echo ""
echo -e "  ${CYAN}Para verificar que todo quedó bien, ejecutá:${NC}"
echo -e "    sudo ~/scripts/validate_samba_service.sh"
echo ""
echo -e "  ${CYAN}Para ver el estado del automount:${NC}"
echo -e "    systemctl status $AUTOMOUNT_UNIT"
echo -e "    systemctl status $UNIT_NAME"
echo ""
echo -e "  ${YELLOW}RECOMENDACIÓN:${NC} Reiniciá la Raspberry para probar el arranque completo:"
echo -e "    sudo reboot"
echo ""
