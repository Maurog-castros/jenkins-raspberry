#!/bin/bash
# =============================================================================
# setup_auto_samba.sh
# Instala y configura un demonio que corre cada 2 minutos
# automatizando la conexión/desconexión de discos y shares Samba.
# Autor: Mauro | Fecha: $(date +%Y-%m-%d)
# =============================================================================

# --- Colores ---
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
step()    { echo -e "\n  ${WHITE}▶ $1${NC}"; }

echo ""
echo -e "${WHITE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${WHITE}║  🔄 INSTALANDO DAEMON HOTPLUG PARA SAMBA     ║${NC}"
echo -e "${WHITE}╚══════════════════════════════════════════════╝${NC}"

# =============================================================================
header "1. LIMPIANDO CONFIGURACIONES ANTERIORES"

# Remover la dependencia estricta que impedía iniciar Samba
if [ -f "/etc/systemd/system/smbd.service.d/wait-for-ssd.conf" ]; then
    rm -f /etc/systemd/system/smbd.service.d/wait-for-ssd.conf
    systemctl daemon-reload
    ok "Dependencia estricta de arranque removida"
fi

# Eliminar líneas generadas en fstab por los scripts anteriores
sed -i 's/^UUID=.*\/mnt\/ssd.*//g' /etc/fstab
sed -i 's/^UUID=.*\/mnt\/boot.*//g' /etc/fstab
sed -i 's/^UUID=.*\/mnt\/sdb4.*//g' /etc/fstab
sed -i '/^\s*$/d' /etc/fstab
ok "Archivo /etc/fstab limpiado de montajes duros"

# Limpiar shares viejos del smb.conf y agregar 'include'
sed -i '/\[ssd\]/,$d' /etc/samba/smb.conf
sed -i '/\[boot\]/,$d' /etc/samba/smb.conf
sed -i '/\[sdb4_recovery\]/,$d' /etc/samba/smb.conf
sed -i '/include = \/etc\/samba\/dynamic_shares.conf/d' /etc/samba/smb.conf

echo "include = /etc/samba/dynamic_shares.conf" >> /etc/samba/smb.conf
touch /etc/samba/dynamic_shares.conf
ok "Archivo smb.conf preparado para recibir shares dinámicos"


# =============================================================================
header "2. CREANDO SCRIPT DEL DEMONIO (samba_hotplug_daemon.sh)"

DAEMON_PATH="/usr/local/bin/samba_hotplug_daemon.sh"

cat << 'EOF' > "$DAEMON_PATH"
#!/bin/bash
# Demonio de Auto-Mount y Auto-Share para Samba
# Ejecutado por systemd timer cada 2 mins

SAMBA_USER="mauro"
BASE_DIR="/mnt/usb_shares"
DYNAMIC_CONF="/etc/samba/dynamic_shares.conf"

USER_ID=$(id -u "$SAMBA_USER" 2>/dev/null || echo 1000)
GROUP_ID=$(id -g "$SAMBA_USER" 2>/dev/null || echo 1000)

mkdir -p "$BASE_DIR"

# 1. LIMPIAR DESCONECTADOS (Stale mounts)
for mp in "$BASE_DIR"/*; do
    [ -e "$mp" ] || continue
    if mountpoint -q "$mp"; then
        # Check si el dispositivo físico sigue existiendo
        DEV=$(findmnt -n -o SOURCE "$mp" 2>/dev/null)
        if [ -n "$DEV" ] && [ ! -b "$DEV" ]; then
            umount -l "$mp" 2>/dev/null
            rmdir "$mp" 2>/dev/null
        fi
    else
        # Es un directorio vacío (se desconectó o falló)
        rmdir "$mp" 2>/dev/null
    fi
done

# 2. ESCANEAR E INTENTAR MONTAR
TEMP_CONF=$(mktemp)

lsblk -o NAME,TYPE,FSTYPE,LABEL,UUID,MOUNTPOINT -rn 2>/dev/null | while read -r NAME TYPE FSTYPE LABEL UUID MOUNTPOINT; do
    # Omitir tarjetas SD internas y memoria
    if [[ "$NAME" == mmcblk* ]] || [[ "$NAME" == loop* ]] || [[ "$NAME" == zram* ]]; then
        continue
    fi
    # Solo discos particionados o discos enteros si no tienen tabla
    if [[ "$TYPE" != "part" && "$TYPE" != "disk" ]]; then
        continue
    fi
    # Solo si tienen un filesystem reconocido que no sea swap
    if [ -z "$FSTYPE" ] || [ "$FSTYPE" == "swap" ]; then
        continue
    fi
    
    DEV="/dev/$NAME"
    
    # Nombre seguro para el share
    SAFE_LABEL=$(echo "$LABEL" | tr -C 'a-zA-Z0-9' '_')
    if [ -n "$SAFE_LABEL" ] && [ "$SAFE_LABEL" != "_" ]; then
        SAFE_LABEL=$(echo "$SAFE_LABEL" | sed 's/_*$//')
        SHARE_NAME="usb_${SAFE_LABEL}_${UUID:0:4}"
    else
        SHARE_NAME="usb_${UUID:0:8}"
    fi
    
    MOUNT_TARGET="$BASE_DIR/$SHARE_NAME"
    
    if [ -n "$MOUNTPOINT" ]; then
        if [[ "$MOUNTPOINT" != "$BASE_DIR"* ]]; then
            MOUNT_TARGET="$MOUNTPOINT"
        fi
    else
        mkdir -p "$MOUNT_TARGET"
        if echo "$FSTYPE" | grep -qi "ntfs"; then
            OPTS="uid=$USER_ID,gid=$GROUP_ID,noatime,nodiratime,big_writes,nofail"
        elif echo "$FSTYPE" | grep -qi "vfat\|fat\|exfat"; then
            OPTS="uid=$USER_ID,gid=$GROUP_ID,fmask=0113,dmask=0002,noatime,nofail"
        else
            OPTS="defaults,noatime,nofail"
        fi
        
        # Intentar montar directo
        if ! mount -t "$FSTYPE" -o "$OPTS" "$DEV" "$MOUNT_TARGET" 2>/dev/null; then
            if ! mount -o "uid=$USER_ID,gid=$GROUP_ID" "$DEV" "$MOUNT_TARGET" 2>/dev/null; then
                rmdir "$MOUNT_TARGET" 2>/dev/null
                continue
            fi
        fi
    fi
    
    # Escribir la configuración si está montado
    if mountpoint -q "$MOUNT_TARGET"; then
        echo "" >> "$TEMP_CONF"
        echo "[$SHARE_NAME]" >> "$TEMP_CONF"
        echo "   comment = USB Auto-Share ($FSTYPE)" >> "$TEMP_CONF"
        echo "   path = $MOUNT_TARGET" >> "$TEMP_CONF"
        echo "   browseable = yes" >> "$TEMP_CONF"
        echo "   read only = no" >> "$TEMP_CONF"
        echo "   valid users = $SAMBA_USER" >> "$TEMP_CONF"
        echo "   force user = $SAMBA_USER" >> "$TEMP_CONF"
        echo "   force group = $SAMBA_USER" >> "$TEMP_CONF"
        echo "   create mask = 0664" >> "$TEMP_CONF"
        echo "   directory mask = 0775" >> "$TEMP_CONF"
        
        if ! echo "$FSTYPE" | grep -qi "vfat\|fat\|exfat\|ntfs"; then
            chown "$SAMBA_USER:$SAMBA_USER" "$MOUNT_TARGET" 2>/dev/null
            chmod 775 "$MOUNT_TARGET" 2>/dev/null
        fi
    fi
done

# 3. ACTUALIZAR SAMBA SOLAMENTE SI HAY CAMBIOS
if ! cmp -s "$TEMP_CONF" "$DYNAMIC_CONF"; then
    cat "$TEMP_CONF" > "$DYNAMIC_CONF"
    systemctl reload smbd nmbd 2>/dev/null || smbcontrol all reload-config
fi

rm -f "$TEMP_CONF"
EOF

chmod +x "$DAEMON_PATH"
ok "Script del demonio creado en $DAEMON_PATH"


# =============================================================================
header "3. PROGRAMANDO TIMER DE SYSTEMD (2 MINS)"

cat << 'EOF' > /etc/systemd/system/samba-hotplug.service
[Unit]
Description=Samba USB Hotplug Daemon
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/samba_hotplug_daemon.sh
EOF

cat << 'EOF' > /etc/systemd/system/samba-hotplug.timer
[Unit]
Description=Run Samba USB Hotplug Daemon every 2 minutes

[Timer]
OnBootSec=30sec
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now samba-hotplug.timer
ok "Timer configurado y activado."


# =============================================================================
header "4. INICIANDO Y PROBANDO"

step "Reiniciando servicios Samba limpios..."
systemctl restart smbd nmbd
ok "smbd y nmbd iniciados"

step "Ejecutando la primera pasada del demonio manualmente..."
"$DAEMON_PATH"
ok "Escaneo completado."

echo ""
echo -e "${GREEN}✅ DEMONIO ACTIVADO Y CORRIENDO !${NC}"
echo ""
echo -e "  Para ver qué shares creó dinámicamente, ejecutá:"
echo -e "  ${CYAN}cat /etc/samba/dynamic_shares.conf${NC}"
echo ""
echo -e "  El sistema ahora va a montar y compartir cualquier USB conectado"
echo -e "  y los retirará automáticamente si los desconectás."
echo ""
