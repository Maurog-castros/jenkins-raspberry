#!/bin/bash
# =============================================================================
# validate_samba_service.sh
# Diagnóstico completo del servicio Samba en Raspberry Pi
# Autor: Mauro | Fecha: $(date +%Y-%m-%d)
# =============================================================================

# --- Colores para la consola ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BLUE='\033[0;34m'
NC='\033[0m' # Sin color

# --- Funciones de estilo ---
header()  { echo -e "\n${BLUE}══════════════════════════════════════════════${NC}"; echo -e "${WHITE}  $1${NC}"; echo -e "${BLUE}══════════════════════════════════════════════${NC}"; }
ok()      { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "  ${YELLOW}[AVISO]${NC} $1"; }
error()   { echo -e "  ${RED}[ERROR]${NC} $1"; }
info()    { echo -e "  ${CYAN}[INFO]${NC}  $1"; }
divider() { echo -e "  ${BLUE}----------------------------------------------${NC}"; }

# =============================================================================
echo ""
echo -e "${WHITE}╔══════════════════════════════════════════════╗${NC}"
echo -e "${WHITE}║     🔍 DIAGNÓSTICO DEL SERVICIO SAMBA        ║${NC}"
echo -e "${WHITE}║         Raspberry Pi - $(date '+%d/%m/%Y %H:%M:%S')        ║${NC}"
echo -e "${WHITE}╚══════════════════════════════════════════════╝${NC}"
# =============================================================================


# --- 1. Verificar si Samba está instalado ---
header "1. INSTALACIÓN DE SAMBA"

if dpkg -l | grep -q "^ii  samba "; then
    SAMBA_VER=$(dpkg -l samba | awk 'NR==4{print $3}')
    ok "Samba está instalado (versión: $SAMBA_VER)"
else
    error "Samba NO está instalado en este sistema"
    warn "Podés instalarlo con: sudo apt install samba samba-common-bin"
    exit 1
fi

if dpkg -l | grep -q "^ii  samba-common"; then
    ok "samba-common está instalado"
else
    warn "samba-common NO está instalado"
fi


# --- 2. Estado de los servicios ---
header "2. ESTADO DE LOS SERVICIOS"

for SERVICE in smbd nmbd; do
    STATUS=$(systemctl is-active $SERVICE 2>/dev/null)
    ENABLED=$(systemctl is-enabled $SERVICE 2>/dev/null)

    if [ "$STATUS" == "active" ]; then
        ok "$SERVICE está ACTIVO y corriendo"
    else
        error "$SERVICE está: $STATUS"
    fi

    if [ "$ENABLED" == "enabled" ]; then
        info "$SERVICE está habilitado para iniciar con el sistema"
    else
        warn "$SERVICE NO está habilitado en el arranque"
    fi
    divider
done


# --- 3. Verificar archivo de configuración ---
header "3. CONFIGURACIÓN: /etc/samba/smb.conf"

CONF="/etc/samba/smb.conf"

if [ -f "$CONF" ]; then
    ok "El archivo smb.conf existe"

    # Validar sintaxis con testparm
    echo ""
    info "Validando sintaxis del archivo de configuración..."
    TESTPARM_OUT=$(testparm -s 2>&1)
    TESTPARM_EXIT=$?

    if [ $TESTPARM_EXIT -eq 0 ]; then
        ok "La sintaxis de smb.conf es correcta"
    else
        error "Se encontraron ERRORES en smb.conf:"
        echo "$TESTPARM_OUT" | grep -i "error\|warning" | while read line; do
            warn "$line"
        done
    fi

    # Mostrar los shares definidos
    echo ""
    info "Carpetas compartidas (shares) definidas:"
    SHARES=$(testparm -s 2>/dev/null | grep '^\[' | grep -v '^\[global\]' | grep -v '^\[homes\]' | grep -v '^\[printers\]')
    if [ -z "$SHARES" ]; then
        warn "No se encontraron shares definidos (además de los predeterminados)"
    else
        echo "$SHARES" | while read share; do
            info "  → $share"
        done
    fi
else
    error "El archivo smb.conf NO existe en $CONF"
fi


# --- 4. Verificar puertos y conectividad ---
header "4. PUERTOS DE RED (137, 138, 139, 445)"

for PORT in 139 445; do
    if ss -tlnp 2>/dev/null | grep -q ":$PORT "; then
        ok "Puerto TCP $PORT está ESCUCHANDO"
    else
        error "Puerto TCP $PORT NO está escuchando"
    fi
done

for PORT in 137 138; do
    if ss -ulnp 2>/dev/null | grep -q ":$PORT "; then
        ok "Puerto UDP $PORT está ESCUCHANDO"
    else
        warn "Puerto UDP $PORT NO está escuchando (puede ser normal si se usa solo smbd)"
    fi
done


# --- 5. Firewall ---
header "5. FIREWALL (UFW)"

if command -v ufw &>/dev/null; then
    UFW_STATUS=$(ufw status 2>/dev/null | head -1)
    info "Estado UFW: $UFW_STATUS"

    if echo "$UFW_STATUS" | grep -q "active"; then
        warn "UFW está activo. Verificando reglas para Samba..."
        if ufw status 2>/dev/null | grep -qi "samba\|445\|139\|137"; then
            ok "Samba tiene reglas permitidas en UFW"
        else
            error "No se encontraron reglas UFW para Samba"
            warn "Podés permitirlo con: sudo ufw allow Samba"
        fi
    else
        ok "UFW está inactivo (firewall no bloquea Samba)"
    fi
else
    info "UFW no está instalado"
fi


# --- 6. Usuarios de Samba ---
header "6. USUARIOS DE SAMBA"

if command -v pdbedit &>/dev/null; then
    USERS=$(pdbedit -L 2>/dev/null)
    if [ -z "$USERS" ]; then
        warn "No hay usuarios de Samba configurados"
        warn "Podés agregar uno con: sudo smbpasswd -a <usuario>"
    else
        ok "Usuarios de Samba registrados:"
        echo "$USERS" | while read user; do
            info "  → $user"
        done
    fi
else
    warn "pdbedit no disponible, no se pueden listar usuarios"
fi


# --- 7. Permisos de carpetas compartidas ---
header "7. PERMISOS DE PATHS COMPARTIDOS"

PATHS=$(testparm -s 2>/dev/null | grep -E '^\s+path\s*=' | awk -F'=' '{print $2}' | tr -d ' ')

if [ -z "$PATHS" ]; then
    warn "No se encontraron paths de shares para validar"
else
    echo "$PATHS" | while read SHARE_PATH; do
        if [ -d "$SHARE_PATH" ]; then
            PERMS=$(stat -c "%a %U:%G" "$SHARE_PATH")
            ok "Directorio existe: $SHARE_PATH ($PERMS)"
        else
            error "El directorio NO existe: $SHARE_PATH"
        fi
    done
fi


# --- 8. Últimas entradas del log de Samba ---
header "8. ÚLTIMOS ERRORES EN LOGS DE SAMBA"

LOG_DIR="/var/log/samba"
if [ -d "$LOG_DIR" ]; then
    LOG_FILES=$(ls -t $LOG_DIR/log.smbd $LOG_DIR/log.nmbd 2>/dev/null)
    if [ -z "$LOG_FILES" ]; then
        info "No se encontraron archivos de log principales"
    else
        for LOG in $LOG_FILES; do
            info "Últimas líneas de $(basename $LOG):"
            tail -10 "$LOG" | while read line; do
                echo -e "    ${YELLOW}$line${NC}"
            done
            divider
        done
    fi
else
    warn "Directorio de logs no encontrado: $LOG_DIR"
fi


# --- Resumen Final ---
header "✅ DIAGNÓSTICO COMPLETADO"
echo ""
echo -e "  Si encontraste ${RED}[ERROR]${NC} en alguna sección, esos son los puntos a corregir."
echo -e "  Si todo aparece ${GREEN}[OK]${NC}, el servicio debería estar funcionando."
echo ""
echo -e "  ${CYAN}Comandos útiles:${NC}"
echo -e "    sudo systemctl restart smbd nmbd     → Reiniciar Samba"
echo -e "    sudo systemctl enable smbd nmbd      → Habilitar en arranque"
echo -e "    sudo smbpasswd -a <usuario>           → Agregar usuario"
echo -e "    sudo ufw allow Samba                  → Permite Samba en firewall"
echo ""
