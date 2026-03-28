#!/bin/bash
# =============================================================================
# fix_samba_permissions.sh
# Corrige los permisos del share Samba [ssd] en /mnt/ssd
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

# Variables del share
SHARE_PATH="/mnt/ssd"
SHARE_USER="mauro"
SHARE_GROUP="mauro"

# =============================================================================
echo ""
echo -e "${WHITE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${WHITE}║   🔧 CORRECCIÓN DE PERMISOS - SAMBA [ssd]    ║${NC}"
echo -e "${WHITE}║         Raspberry Pi - $(date '+%d/%m/%Y %H:%M:%S')        ║${NC}"
echo -e "${WHITE}╚══════════════════════════════════════════════╝${NC}"
# =============================================================================


# --- 1. Verificar si /mnt/ssd está montado ---
header "1. ESTADO DEL PUNTO DE MONTAJE: $SHARE_PATH"

if mountpoint -q "$SHARE_PATH"; then
    ok "$SHARE_PATH está montado correctamente"

    # Mostrar info del dispositivo montado
    MOUNT_INFO=$(findmnt -n -o SOURCE,FSTYPE,OPTIONS "$SHARE_PATH")
    SOURCE=$(echo "$MOUNT_INFO" | awk '{print $1}')
    FSTYPE=$(echo "$MOUNT_INFO" | awk '{print $2}')
    OPTIONS=$(echo "$MOUNT_INFO" | awk '{print $3}')

    info "Dispositivo : $SOURCE"
    info "Filesystem  : $FSTYPE"
    info "Opciones    : $OPTIONS"
    divider

    # Advertir si es FAT32/NTFS (no soportan permisos UNIX reales)
    if echo "$FSTYPE" | grep -qiE "vfat|fat|ntfs|exfat"; then
        warn "El filesystem es $FSTYPE — NO soporta permisos UNIX reales (chown/chmod)"
        warn "Los permisos deben configurarse en las opciones de montaje (fstab)"
        echo ""
        NEEDS_FSTAB_FIX=true
    else
        info "Filesystem $FSTYPE soporta permisos UNIX → podemos usar chown/chmod"
        NEEDS_FSTAB_FIX=false
    fi
else
    error "$SHARE_PATH NO está montado"
    warn "El SSD puede no estar conectado o el montaje falló"
    echo ""

    step "Buscando dispositivos disponibles..."
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | grep -v "loop"
    echo ""

    step "Revisando /etc/fstab para entradas del SSD..."
    if grep -q "$SHARE_PATH" /etc/fstab; then
        info "Entrada encontrada en /etc/fstab:"
        grep "$SHARE_PATH" /etc/fstab | while read line; do
            info "  $line"
        done
        echo ""
        step "Intentando montar $SHARE_PATH..."
        if mount "$SHARE_PATH" 2>/dev/null; then
            ok "$SHARE_PATH montado exitosamente"
            NEEDS_FSTAB_FIX=false
        else
            error "No se pudo montar $SHARE_PATH"
            error "Verificá que el dispositivo esté conectado y configurado en /etc/fstab"
            exit 1
        fi
    else
        error "No hay entrada en /etc/fstab para $SHARE_PATH"
        warn "Deberás configurar el montaje automático del SSD"
        echo ""
        info "Dispositivos disponibles:"
        lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL
        exit 1
    fi
fi


# --- 2. Permisos actuales ---
header "2. PERMISOS ACTUALES DE $SHARE_PATH"

CURRENT_PERMS=$(stat -c "Dueño: %U:%G | Permisos: %a (%A)" "$SHARE_PATH")
info "$CURRENT_PERMS"


# --- 3. Aplicar correcciones ---
header "3. APLICANDO CORRECCIONES"

if [ "$NEEDS_FSTAB_FIX" = true ]; then
    # --- Caso FAT32/NTFS: hay que re-montar con uid/gid correctos ---
    warn "Este filesystem no soporta chown/chmod directo"
    warn "Hay que configurar las opciones de montaje en /etc/fstab"
    echo ""

    USER_ID=$(id -u "$SHARE_USER")
    GROUP_ID=$(id -g "$SHARE_GROUP")

    info "UID de $SHARE_USER: $USER_ID"
    info "GID de $SHARE_GROUP: $GROUP_ID"
    divider

    # Detectar dispositivo del share
    DEVICE=$(findmnt -n -o SOURCE "$SHARE_PATH")
    FS_TYPE=$(findmnt -n -o FSTYPE "$SHARE_PATH")

    echo ""
    info "Entrada actual en /etc/fstab para $SHARE_PATH:"
    if grep -q "$SHARE_PATH" /etc/fstab; then
        grep "$SHARE_PATH" /etc/fstab | while read line; do
            warn "  ACTUAL  → $line"
        done
    else
        warn "No hay entrada en /etc/fstab — se montó manualmente o en otro lugar"
    fi

    echo ""
    # Construir nueva línea según filesystem
    if echo "$FS_TYPE" | grep -qi "ntfs"; then
        NEW_FSTAB="$DEVICE  $SHARE_PATH  $FS_TYPE  defaults,uid=$USER_ID,gid=$GROUP_ID,umask=002,nofail  0  0"
    else
        NEW_FSTAB="$DEVICE  $SHARE_PATH  $FS_TYPE  defaults,uid=$USER_ID,gid=$GROUP_ID,fmask=0113,dmask=0002,nofail  0  0"
    fi

    info "Línea CORRECTA para /etc/fstab:"
    echo ""
    echo -e "    ${GREEN}$NEW_FSTAB${NC}"
    echo ""

    step "Creando backup de /etc/fstab..."
    BACKUP="/etc/fstab.bak.$(date +%Y%m%d_%H%M%S)"
    cp /etc/fstab "$BACKUP"
    ok "Backup guardado en: $BACKUP"

    step "Actualizando /etc/fstab..."
    if grep -q "$SHARE_PATH" /etc/fstab; then
        # Reemplazar línea existente
        sed -i "s|.*$SHARE_PATH.*|$NEW_FSTAB|" /etc/fstab
        ok "Línea de fstab actualizada"
    else
        # Agregar nueva línea
        echo "$NEW_FSTAB" >> /etc/fstab
        ok "Línea de fstab agregada"
    fi

    step "Re-montando $SHARE_PATH con nuevas opciones..."
    umount "$SHARE_PATH" 2>/dev/null
    if mount "$SHARE_PATH"; then
        ok "$SHARE_PATH re-montado correctamente"
        NEW_PERMS=$(stat -c "Dueño: %U:%G | Permisos: %a (%A)" "$SHARE_PATH")
        ok "Nuevos permisos → $NEW_PERMS"
    else
        error "Error al re-montar $SHARE_PATH"
        error "Revisá la línea en /etc/fstab manualmente"
    fi

else
    # --- Caso ext4/btrfs/etc: chown y chmod directo ---
    step "Verificando que el usuario '$SHARE_USER' existe..."
    if id "$SHARE_USER" &>/dev/null; then
        ok "Usuario '$SHARE_USER' encontrado (UID=$(id -u $SHARE_USER))"
    else
        error "El usuario '$SHARE_USER' NO existe en el sistema"
        exit 1
    fi

    step "Asignando propietario $SHARE_USER:$SHARE_GROUP a $SHARE_PATH..."
    if chown "$SHARE_USER":"$SHARE_GROUP" "$SHARE_PATH"; then
        ok "chown aplicado correctamente"
    else
        error "Error al aplicar chown en $SHARE_PATH"
        exit 1
    fi

    step "Aplicando permisos 775 a $SHARE_PATH..."
    if chmod 775 "$SHARE_PATH"; then
        ok "chmod 775 aplicado"
    else
        error "Error al aplicar chmod en $SHARE_PATH"
        exit 1
    fi

    NEW_PERMS=$(stat -c "Dueño: %U:%G | Permisos: %a (%A)" "$SHARE_PATH")
    ok "Nuevos permisos → $NEW_PERMS"
fi


# --- 4. Reiniciar Samba ---
header "4. REINICIANDO SERVICIOS SAMBA"

step "Reiniciando smbd..."
if systemctl restart smbd; then
    ok "smbd reiniciado correctamente"
else
    error "Error al reiniciar smbd"
fi

step "Reiniciando nmbd..."
if systemctl restart nmbd; then
    ok "nmbd reiniciado correctamente"
else
    error "Error al reiniciar nmbd"
fi

sleep 1

# Verificar que quedaron activos
for SERVICE in smbd nmbd; do
    STATUS=$(systemctl is-active $SERVICE)
    if [ "$STATUS" == "active" ]; then
        ok "$SERVICE está ACTIVO"
    else
        error "$SERVICE quedó en estado: $STATUS"
    fi
done


# --- 5. Prueba de acceso al share ---
header "5. PRUEBA DE ACCESO AL SHARE"

step "Probando lectura/escritura en $SHARE_PATH como usuario $SHARE_USER..."

TEST_FILE="$SHARE_PATH/.samba_test_$(date +%s)"
if sudo -u "$SHARE_USER" touch "$TEST_FILE" 2>/dev/null; then
    ok "Escritura exitosa en $SHARE_PATH"
    rm -f "$TEST_FILE"
    ok "Archivo de prueba eliminado"
else
    error "El usuario '$SHARE_USER' NO puede escribir en $SHARE_PATH"
    warn "Puede haber permisos adicionales que corregir"
fi

step "Verificando share con smbclient..."
if command -v smbclient &>/dev/null; then
    SHARE_LIST=$(smbclient -L localhost -U "$SHARE_USER"%"" -N 2>/dev/null | grep -i "ssd\|Disk")
    if [ -n "$SHARE_LIST" ]; then
        ok "Share [ssd] visible en la red local:"
        echo "$SHARE_LIST" | while read line; do
            info "  $line"
        done
    else
        warn "No se pudo listar el share via smbclient (puede requerir password)"
    fi
fi


# --- Resumen Final ---
header "✅ CORRECCIÓN COMPLETADA"
echo ""
echo -e "  ${GREEN}Qué se hizo:${NC}"
echo -e "    → Se verificó el montaje de $SHARE_PATH"
echo -e "    → Se corrigieron los permisos para el usuario $SHARE_USER"
echo -e "    → Se reiniciaron smbd y nmbd"
echo -e "    → Se probó el acceso al share"
echo ""
echo -e "  ${CYAN}Próximos pasos si sigue fallando:${NC}"
echo -e "    1. Verificá que conectás desde Windows con usuario: $SHARE_USER"
echo -e "    2. Revisá la contraseña Samba: sudo smbpasswd -a $SHARE_USER"
echo -e "    3. Revisá los logs: sudo tail -50 /var/log/samba/log.smbd"
echo -e "    4. Corré nuevamente: sudo ~/scripts/validate_samba_service.sh"
echo ""
