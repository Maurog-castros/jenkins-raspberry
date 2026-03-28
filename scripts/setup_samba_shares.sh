#!/bin/bash
# =============================================================================
# setup_samba_shares.sh  v2
# Detecta todas las particiones compartibles, las monta y configura Samba
# para que sean visibles en la red como unidades de red independientes.
# Autor: Mauro | Fecha: $(date +%Y-%m-%d)
# =============================================================================

# --- Colores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# --- Funciones de estilo ---
header()  { echo -e "\n${BLUE}══════════════════════════════════════════════${NC}"; echo -e "${WHITE}  $1${NC}"; echo -e "${BLUE}══════════════════════════════════════════════${NC}"; }
ok()      { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "  ${YELLOW}[AVISO]${NC} $1"; }
error()   { echo -e "  ${RED}[ERROR]${NC} $1"; }
info()    { echo -e "  ${CYAN}[INFO]${NC}  $1"; }
divider() { echo -e "  ${BLUE}----------------------------------------------${NC}"; }
step()    { echo -e "\n  ${WHITE}▶ $1${NC}"; }
label()   { echo -e "  ${MAGENTA}$1${NC}"; }

# --- Config ---
SAMBA_USER="mauro"
BASE_MOUNT="/mnt"
FSTAB="/etc/fstab"
SMBD_CONF="/etc/samba/smb.conf"
USER_ID=$(id -u "$SAMBA_USER" 2>/dev/null)
GROUP_ID=$(id -g "$SAMBA_USER" 2>/dev/null)
DEVICE_TIMEOUT=30

# Particiones a EXCLUIR (sistema operativo y swap)
EXCLUDE_DEVS="mmcblk0p1 mmcblk0p2 zram0"

# =============================================================================
echo ""
echo -e "${WHITE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${WHITE}║   📦 CONFIGURAR UNIDADES DE RED (SAMBA)      ║${NC}"
echo -e "${WHITE}║         Raspberry Pi - $(date '+%d/%m/%Y %H:%M:%S')        ║${NC}"
echo -e "${WHITE}╚══════════════════════════════════════════════╝${NC}"
echo ""
info "Detectando particiones disponibles para compartir en red..."
info "Usuario Samba: $SAMBA_USER (UID=$USER_ID)"
# =============================================================================


# =============================================================================
# PASO 1: Detectar todas las particiones compartibles
# =============================================================================
header "1. INVENTARIO DE PARTICIONES DEL SISTEMA"
echo ""
echo -e "  ${WHITE}Dispositivos detectados:${NC}"
echo ""

declare -a SHAREABLE_PARTS   # lista de /dev/sdXN a procesar

while IFS=" " read -r NAME SIZE TYPE FSTYPE LABEL UUID; do
    # Solo particiones con filesystem conocido
    [ "$TYPE" != "part" ] && continue
    [ -z "$FSTYPE" ] && continue
    [ "$FSTYPE" = "swap" ] && continue
    [ "$FSTYPE" = "" ] && continue

    # Excluir dispositivos del sistema
    SKIP=false
    for EXCL in $EXCLUDE_DEVS; do
        [ "$NAME" = "$EXCL" ] && SKIP=true && break
    done
    $SKIP && continue

    DEV="/dev/$NAME"

    # Obtener mount point real usando findmnt (no lsblk que puede confundir)
    REAL_MOUNT=$(findmnt -n -o TARGET "$DEV" 2>/dev/null)

    # Estado
    if [ -n "$REAL_MOUNT" ]; then
        STATUS_TXT="${GREEN}✓ Montada en $REAL_MOUNT${NC}"
    else
        STATUS_TXT="${YELLOW}⚠  Sin montar${NC}"
    fi

    LABEL_SHOW="${LABEL:-sin etiqueta}"
    echo -e "  ${MAGENTA}📀 $DEV${NC}  ${WHITE}$SIZE${NC}  [$FSTYPE]  ${CYAN}$LABEL_SHOW${NC}  → $STATUS_TXT"

    SHAREABLE_PARTS+=("$DEV|$SIZE|$FSTYPE|$LABEL|$UUID|$REAL_MOUNT")

done < <(lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,UUID -rn 2>/dev/null)

echo ""
info "Se encontraron ${#SHAREABLE_PARTS[@]} partición(es) compartible(s)"

if [ ${#SHAREABLE_PARTS[@]} -eq 0 ]; then
    warn "No se encontraron particiones disponibles."
    exit 0
fi


# =============================================================================
# PASO 2: Montar particiones que no están montadas
# =============================================================================
header "2. MONTAJE DE PARTICIONES"

declare -A FINAL_MOUNT   # DEV → mount point final

for ENTRY in "${SHAREABLE_PARTS[@]}"; do
    IFS='|' read -r DEV SIZE FSTYPE LABEL UUID EXISTING_MOUNT <<< "$ENTRY"

    echo ""
    LABEL_SHOW="${LABEL:-sin etiqueta}"
    label "  ─── $DEV  ($SIZE, $FSTYPE, $LABEL_SHOW) ───"

    if [ -n "$EXISTING_MOUNT" ]; then
        ok "Ya montada en $EXISTING_MOUNT"
        FINAL_MOUNT[$DEV]="$EXISTING_MOUNT"
        continue
    fi

    # Generar nombre de directorio: usar nombre de partición limpio
    PART_NAME=$(basename "$DEV")           # ej: sdb4
    if [ -n "$LABEL" ]; then
        # Sanitizar label: minúsculas, sin espacios ni chars raros
        DIR_NAME=$(echo "$LABEL" | tr '[:upper:]' '[:lower:]' \
                   | tr -cs 'a-z0-9' '_' | sed 's/_*$//;s/^_*//')
    else
        DIR_NAME="$PART_NAME"
    fi

    MOUNT_PATH="$BASE_MOUNT/$DIR_NAME"

    step "Montando $DEV → $MOUNT_PATH"
    mkdir -p "$MOUNT_PATH"

    # Opciones de montaje según filesystem
    if echo "$FSTYPE" | grep -qi "ntfs"; then
        MOUNT_OPTS="uid=${USER_ID},gid=${GROUP_ID},noatime,nodiratime,big_writes,nofail"
    elif echo "$FSTYPE" | grep -qi "vfat\|fat\|exfat"; then
        MOUNT_OPTS="uid=${USER_ID},gid=${GROUP_ID},fmask=0113,dmask=0002,noatime,nofail"
    else
        MOUNT_OPTS="defaults,noatime,nofail"
    fi

    if mount -t "$FSTYPE" -o "$MOUNT_OPTS" "$DEV" "$MOUNT_PATH" 2>/dev/null; then
        ok "Montado correctamente en $MOUNT_PATH"
        FINAL_MOUNT[$DEV]="$MOUNT_PATH"

        # Agregar a fstab si no existe
        if [ -n "$UUID" ] && ! grep -q "$UUID" "$FSTAB"; then
            FSTAB_OPTS="${MOUNT_OPTS},x-systemd.automount,x-systemd.device-timeout=${DEVICE_TIMEOUT},x-systemd.idle-timeout=0"
            echo "UUID=$UUID  $MOUNT_PATH  $FSTYPE  $FSTAB_OPTS  0  0" >> "$FSTAB"
            ok "Agregado a fstab (UUID=$UUID)"
        else
            info "Ya existe en fstab — sin cambios"
        fi
    else
        error "No se pudo montar $DEV — se omitirá del share"
        rmdir "$MOUNT_PATH" 2>/dev/null
    fi
done


# =============================================================================
# PASO 3: Configurar shares en smb.conf
# =============================================================================
header "3. CONFIGURANDO SHARES EN smb.conf"

BACKUP_CONF="${SMBD_CONF}.bak.$(date +%Y%m%d_%H%M%S)"
step "Backup de smb.conf → $BACKUP_CONF"
cp "$SMBD_CONF" "$BACKUP_CONF" && ok "Backup creado" || { error "Error en backup. Abortando."; exit 1; }

for ENTRY in "${SHAREABLE_PARTS[@]}"; do
    IFS='|' read -r DEV SIZE FSTYPE LABEL UUID EXISTING_MOUNT <<< "$ENTRY"

    MOUNT_PATH="${FINAL_MOUNT[$DEV]}"
    [ -z "$MOUNT_PATH" ] && continue
    [ ! -d "$MOUNT_PATH" ] && continue

    # Nombre del share: basado en el directorio de montaje (siempre limpio)
    SHARE_NAME=$(basename "$MOUNT_PATH")
    COMMENT="${LABEL:-$SHARE_NAME} ($FSTYPE, $SIZE)"

    echo ""
    label "  ─── Share [$SHARE_NAME] → $MOUNT_PATH ───"

    if grep -q "^\[$SHARE_NAME\]" "$SMBD_CONF"; then
        # Actualizar el path si el share ya existía con path incorrecto
        CURRENT_PATH=$(grep -A10 "^\[$SHARE_NAME\]" "$SMBD_CONF" | grep "path" | head -1 | awk -F'= ' '{print $2}' | xargs)
        if [ "$CURRENT_PATH" != "$MOUNT_PATH" ]; then
            warn "Share [$SHARE_NAME] existe pero con path incorrecto: $CURRENT_PATH"
            step "Actualizando path a: $MOUNT_PATH"
            sed -i "/^\[$SHARE_NAME\]/,/^\[/{s|path = .*|path = $MOUNT_PATH|}" "$SMBD_CONF"
            ok "Path actualizado"
        else
            ok "Share [$SHARE_NAME] ya está configurado correctamente"
        fi
    else
        step "Creando share [$SHARE_NAME]..."
        cat >> "$SMBD_CONF" << EOF

[$SHARE_NAME]
   comment = $COMMENT
   path = $MOUNT_PATH
   browseable = yes
   read only = no
   valid users = $SAMBA_USER
   force user = $SAMBA_USER
   force group = $SAMBA_USER
   create mask = 0664
   directory mask = 0775
EOF
        ok "Share [$SHARE_NAME] creado"
    fi

    info "  Ruta     : $MOUNT_PATH"
    info "  Tipo FS  : $FSTYPE  |  Tamaño: $SIZE"
    [ -n "$LABEL" ] && info "  Etiqueta : $LABEL"
done


# =============================================================================
# PASO 4: Validar smb.conf y reiniciar Samba
# =============================================================================
header "4. VALIDACIÓN Y REINICIO DE SAMBA"

step "Validando sintaxis de smb.conf..."
if testparm -s &>/dev/null; then
    ok "Sintaxis de smb.conf correcta"
else
    error "Error en smb.conf — restaurando backup..."
    cp "$BACKUP_CONF" "$SMBD_CONF"
    error "Backup restaurado. Revisá el archivo manualmente."
    exit 1
fi

step "Recargando systemd daemon..."
systemctl daemon-reload

step "Reiniciando smbd y nmbd..."
systemctl restart smbd && ok "smbd reiniciado" || error "Error al reiniciar smbd"
systemctl restart nmbd && ok "nmbd reiniciado" || error "Error al reiniciar nmbd"


# =============================================================================
# PASO 5: Resumen final con tabla de shares
# =============================================================================
header "5. UNIDADES DISPONIBLES EN LA RED"

IP_ADDR=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)

echo ""
echo -e "  ${WHITE}╔══════════════════════════════════════════════╗${NC}"
echo -e "  ${WHITE}║  Acceso desde Windows:                       ║${NC}"
echo -e "  ${WHITE}║  \\\\\\\\${HOSTNAME}  o  \\\\\\\\${IP_ADDR}${NC}"
echo -e "  ${WHITE}╚══════════════════════════════════════════════╝${NC}"
echo ""
printf "  ${WHITE}%-20s %-25s %-10s %-8s %-8s${NC}\n" "SHARE" "PATH" "ESTADO" "TOTAL" "LIBRE"
echo -e "  ${BLUE}──────────────────────────────────────────────────────────────────${NC}"

# Leer shares del smb.conf directamente con grep + awk (sin testparm)
CURRENT_SHARE=""
CURRENT_PATH=""

while IFS= read -r line; do
    # Detectar encabezado de sección [share]
    if echo "$line" | grep -q '^\['; then
        # Procesar el share anterior antes de pasar al siguiente
        if [ -n "$CURRENT_SHARE" ] && [ -n "$CURRENT_PATH" ]; then
            # Excluir shares del sistema
            if [[ "$CURRENT_SHARE" != "global" && "$CURRENT_SHARE" != "homes" && \
                  "$CURRENT_SHARE" != "printers" && "$CURRENT_SHARE" != "print\$" ]]; then
                if mountpoint -q "$CURRENT_PATH" 2>/dev/null; then
                    DF_OUT=$(df -h "$CURRENT_PATH" 2>/dev/null | tail -1)
                    D_TOTAL=$(echo "$DF_OUT" | awk '{print $2}')
                    D_FREE=$(echo "$DF_OUT"  | awk '{print $4}')
                    STATUS="${GREEN}✓ activa${NC}"
                elif [ -d "$CURRENT_PATH" ]; then
                    D_TOTAL="—"; D_FREE="—"
                    STATUS="${YELLOW}⚠ sin montar${NC}"
                else
                    D_TOTAL="—"; D_FREE="—"
                    STATUS="${RED}✗ no existe${NC}"
                fi
                printf "  ${MAGENTA}%-20s${NC} %-25s $STATUS  ${CYAN}%-8s${NC} ${GREEN}%-8s${NC}\n" \
                    "\\\\$HOSTNAME\\$CURRENT_SHARE" "$CURRENT_PATH" "$D_TOTAL" "$D_FREE"
            fi
        fi
        CURRENT_SHARE=$(echo "$line" | tr -d '[]' | xargs)
        CURRENT_PATH=""
    fi

    # Capturar path de la sección actual
    if echo "$line" | grep -q '^\s*path\s*='; then
        CURRENT_PATH=$(echo "$line" | awk -F'= ' '{print $2}' | xargs)
    fi
done < "$SMBD_CONF"

# Procesar el último share del archivo
if [ -n "$CURRENT_SHARE" ] && [ -n "$CURRENT_PATH" ]; then
    if [[ "$CURRENT_SHARE" != "global" && "$CURRENT_SHARE" != "homes" && \
          "$CURRENT_SHARE" != "printers" && "$CURRENT_SHARE" != "print\$" ]]; then
        if mountpoint -q "$CURRENT_PATH" 2>/dev/null; then
            DF_OUT=$(df -h "$CURRENT_PATH" 2>/dev/null | tail -1)
            D_TOTAL=$(echo "$DF_OUT" | awk '{print $2}')
            D_FREE=$(echo "$DF_OUT"  | awk '{print $4}')
            STATUS="${GREEN}✓ activa${NC}"
        elif [ -d "$CURRENT_PATH" ]; then
            D_TOTAL="—"; D_FREE="—"
            STATUS="${YELLOW}⚠ sin montar${NC}"
        else
            D_TOTAL="—"; D_FREE="—"
            STATUS="${RED}✗ no existe${NC}"
        fi
        printf "  ${MAGENTA}%-20s${NC} %-25s $STATUS  ${CYAN}%-8s${NC} ${GREEN}%-8s${NC}\n" \
            "\\\\$HOSTNAME\\$CURRENT_SHARE" "$CURRENT_PATH" "$D_TOTAL" "$D_FREE"
    fi
fi

echo -e "  ${BLUE}──────────────────────────────────────────────────────────────────${NC}"
echo ""
echo -e "  ${CYAN}Usuario para conectar:${NC} ${WHITE}$SAMBA_USER${NC}"
echo -e "  ${CYAN}Contraseña:${NC} la de Samba (sudo smbpasswd -a $SAMBA_USER si la olvidaste)"
echo ""
echo -e "  ${YELLOW}PRÓXIMO PASO:${NC} Reiniciá para verificar el automount completo:"
echo -e "    ${WHITE}sudo reboot${NC}"
echo ""
