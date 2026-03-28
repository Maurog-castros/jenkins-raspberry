#!/bin/bash
# =============================================================================
# evaluate_services.sh
# Evaluador integral de servicios en Raspberry Pi
# Detecta errores, valida estado del sistema y genera plan de corrección
# Autor: Mauro | Fecha: $(date +%Y-%m-%d)
# =============================================================================

# --- Colores para la consola ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # Sin color

# --- Funciones de estilo ---
header()  { echo -e "\n${BLUE}══════════════════════════════════════════════${NC}"; echo -e "${WHITE}  $1${NC}"; echo -e "${BLUE}══════════════════════════════════════════════${NC}"; }
ok()      { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "  ${YELLOW}[⚠]${NC}   $1"; }
error()   { echo -e "  ${RED}[✗]${NC}   $1"; }
info()    { echo -e "  ${CYAN}[i]${NC}   $1"; }
divider() { echo -e "  ${BLUE}----------------------------------------------${NC}"; }
step()    { echo -e "\n  ${WHITE}▶ $1${NC}"; }
label()   { echo -e "  ${MAGENTA}$1${NC}"; }

# --- Variables globales ---
SERVICES_TO_CHECK=("smbd" "nmbd" "ssh" "cron" "systemd-resolved" "systemd-timesyncd")
ERRORS_FOUND=0
WARNINGS_FOUND=0
declare -a CORRECTION_PLAN
PLAN_INDEX=0

# =============================================================================
echo ""
echo -e "${WHITE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${WHITE}║   📊 EVALUADOR INTEGRAL DE SERVICIOS           ║${NC}"
echo -e "${WHITE}║   Raspberry Pi - $(date '+%d/%m/%Y %H:%M:%S')           ║${NC}"
echo -e "${WHITE}╚════════════════════════════════════════════════╝${NC}"
echo ""
info "Validando servicios, logs y estado del sistema..."
echo ""

# =============================================================================
# FUNCIÓN: Registrar acciones en el plan de corrección
# =============================================================================
add_to_plan() {
    local priority=$1
    local action=$2
    local description=$3
    
    CORRECTION_PLAN[$PLAN_INDEX]="[$priority] $action | $description"
    ((PLAN_INDEX++))
}

# =============================================================================
# PASO 1: VALIDACIÓN DE SERVICIOS CRÍTICOS
# =============================================================================
header "1. ESTADO DE SERVICIOS CRÍTICOS"

declare -A SERVICE_STATUS

for service in "${SERVICES_TO_CHECK[@]}"; do
    ACTIVE=$(systemctl is-active "$service" 2>/dev/null)
    ENABLED=$(systemctl is-enabled "$service" 2>/dev/null)
    
    echo ""
    info "Servicio: ${MAGENTA}$service${NC}"
    
    # Validar estado activo
    if [ "$ACTIVE" == "active" ]; then
        ok "Servicio activo"
        SERVICE_STATUS["$service"]="ACTIVE"
    else
        error "Servicio NO activo (estado: $ACTIVE)"
        SERVICE_STATUS["$service"]="INACTIVE"
        ((ERRORS_FOUND++))
        add_to_plan "CRITICAL" "systemctl start $service" "Servicio $service no está corriendo"
    fi
    
    # Validar si está habilitado
    if [ "$ENABLED" == "enabled" ]; then
        info "Habilitado en boot"
    else
        warn "NO habilitado en boot (estado: $ENABLED)"
        ((WARNINGS_FOUND++))
        add_to_plan "MEDIUM" "systemctl enable $service" "Servicio $service no inicia automáticamente"
    fi
done

divider

# =============================================================================
# PASO 2: VALIDACIÓN DE LOGS PARA ERRORES
# =============================================================================
header "2. ANÁLISIS DE LOGS DEL SISTEMA"

echo ""
info "Verificando logs en /var/log/ para errores recientes (últimas 24h)..."
echo ""

# Revisar journal del sistema
error_count=$(journalctl --since "24 hours ago" --priority err | wc -l)
if [ "$error_count" -gt 0 ]; then
    error "Se encontraron ${RED}$error_count${NC} errores en los últimos 24 horas"
    ((ERRORS_FOUND++))
    add_to_plan "HIGH" "journalctl --since '24 hours ago' --priority err" "Revisar log de errores del sistema"
else
    ok "Sin errores críticos en journalctl (últimas 24h)"
fi

# Revisar logs de Samba si existe
if [ -f "/var/log/samba/log.smbd" ]; then
    samba_errors=$(grep -i "error\|failed\|cannot" /var/log/samba/log.smbd 2>/dev/null | tail -5 | wc -l)
    if [ "$samba_errors" -gt 0 ]; then
        warn "Detectados $samba_errors posibles errores en logs de Samba"
        ((WARNINGS_FOUND++))
        add_to_plan "HIGH" "tail -20 /var/log/samba/log.smbd" "Revisar errores de Samba"
    else
        ok "Logs de Samba sin errores aparentes"
    fi
fi

# Revisar SSH
if [ -f "/var/log/auth.log" ]; then
    ssh_fails=$(grep -i "failed password\|invalid user" /var/log/auth.log 2>/dev/null | wc -l)
    if [ "$ssh_fails" -gt 50 ]; then
        warn "Detectados $ssh_fails intentos fallidos de SSH (últimas 24h)"
        ((WARNINGS_FOUND++))
        add_to_plan "MEDIUM" "fail2ban" "Configurar protección contra fuerza bruta SSH"
    fi
fi

divider

# =============================================================================
# PASO 3: VALIDACIÓN DE RECURSOS DEL SISTEMA
# =============================================================================
header "3. RECURSOS DEL SISTEMA"

# Espacio en disco
echo ""
info "Espacio en disco:"
echo ""
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')

echo "  Partición raíz: ${CYAN}$DISK_USED${NC}/$DISK_TOTAL (${CYAN}$DISK_FREE${NC} libre)"

if [ "$DISK_USAGE" -gt 90 ]; then
    error "Disco casi lleno (${RED}$DISK_USAGE%${NC})"
    ((ERRORS_FOUND++))
    add_to_plan "CRITICAL" "df -h && du -sh /*" "Liberar espacio en disco"
elif [ "$DISK_USAGE" -gt 80 ]; then
    warn "Disco con uso alto (${YELLOW}$DISK_USAGE%${NC})"
    ((WARNINGS_FOUND++))
    add_to_plan "HIGH" "du -sh /var /home" "Monitorear espacio en disco"
else
    ok "Espacio en disco adecuado (${GREEN}$DISK_USAGE%${NC} usado)"
fi

# Memoria
echo ""
info "Memoria del sistema:"
echo ""
MEM_TOTAL=$(free -h | awk 'NR==2 {print $2}')
MEM_USED=$(free -h | awk 'NR==2 {print $3}')
MEM_FREE=$(free -h | awk 'NR==2 {print $4}')
MEM_PERCENT=$(free | awk 'NR==2 {printf "%.0f", ($3/$2)*100}')

echo "  Total: ${CYAN}$MEM_TOTAL${NC} | Usado: ${CYAN}$MEM_USED${NC} | Libre: ${CYAN}$MEM_FREE${NC}"

if [ "$MEM_PERCENT" -gt 90 ]; then
    error "Memoria casi agotada (${RED}$MEM_PERCENT%${NC})"
    ((ERRORS_FOUND++))
    add_to_plan "CRITICAL" "ps aux --sort=-%mem | head" "Identificar procesos consumiendo memoria"
elif [ "$MEM_PERCENT" -gt 80 ]; then
    warn "Memoria con uso alto (${YELLOW}$MEM_PERCENT%${NC})"
    ((WARNINGS_FOUND++))
else
    ok "Memoria disponible (${GREEN}$MEM_PERCENT%${NC} usado)"
fi

# Temperatura (si está disponible)
echo ""
info "Temperatura del CPU:"
echo ""
if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
    TEMP=$(cat /sys/class/thermal/thermal_zone0/temp | awk '{printf "%.1f", $1/1000}')
    echo "  ${CYAN}$TEMP°C${NC}"
    
    if (( $(echo "$TEMP > 80" | bc -l) )); then
        error "Temperatura crítica (${RED}$TEMP°C${NC} - riesgo de throttling)"
        ((ERRORS_FOUND++))
        add_to_plan "CRITICAL" "vcgencmd measure_temp && watch -n 1 vcgencmd measure_temp" "Mejorar ventilación/enfriamiento"
    elif (( $(echo "$TEMP > 70" | bc -l) )); then
        warn "Temperatura elevada (${YELLOW}$TEMP°C${NC})"
        ((WARNINGS_FOUND++))
    else
        ok "Temperatura normal (${GREEN}$TEMP°C${NC})"
    fi
else
    info "Sensor de temperatura no disponible"
fi

divider

# =============================================================================
# PASO 4: VALIDACIÓN DE PUNTO DE MONTAJE SSD
# =============================================================================
header "4. VALIDACIÓN DE PUNTOS DE MONTAJE"

echo ""
info "Revisando puntos de montaje /mnt/..."
echo ""

if [ -d "/mnt" ]; then
    MOUNT_COUNT=$(findmnt /mnt -r -l 2>/dev/null | wc -l)
    if [ "$MOUNT_COUNT" -lt 2 ]; then
        warn "Solo se encontró 1 o menos puntos de montaje en /mnt/"
        ((WARNINGS_FOUND++))
        add_to_plan "MEDIUM" "./setup_samba_shares.sh" "Configurar/detectar shares en /mnt/"
    else
        ok "Se encontraron $MOUNT_COUNT puntos de montaje"
    fi
    
    # Verificar si /mnt/ssd existe y está montado
    if mountpoint -q /mnt/ssd 2>/dev/null; then
        ok "/mnt/ssd está montado"
        
        SSD_USAGE=$(df /mnt/ssd | awk 'NR==2 {print $5}' | sed 's/%//')
        SSD_FREE=$(df -h /mnt/ssd | awk 'NR==2 {print $4}')
        
        echo "  Espacio libre: ${CYAN}$SSD_FREE${NC} (${CYAN}$SSD_USAGE%${NC} usado)"
        
        if [ "$SSD_USAGE" -gt 90 ]; then
            error "SSD casi lleno (${RED}$SSD_USAGE%${NC})"
            ((ERRORS_FOUND++))
            add_to_plan "CRITICAL" "du -sh /mnt/ssd/*" "Liberar espacio en SSD"
        elif [ "$SSD_USAGE" -gt 80 ]; then
            warn "SSD con alto uso (${YELLOW}$SSD_USAGE%${NC})"
            ((WARNINGS_FOUND++))
        fi
    else
        error "/mnt/ssd NO está montado"
        ((ERRORS_FOUND++))
        add_to_plan "CRITICAL" "./fix_samba_automount.sh && mount /mnt/ssd" "Montar SSD"
    fi
else
    error "Directorio /mnt no existe"
    ((ERRORS_FOUND++))
    add_to_plan "CRITICAL" "mkdir -p /mnt && ./setup_samba_shares.sh" "Crear y configurar /mnt"
fi

divider

# =============================================================================
# PASO 5: VALIDACIÓN ESPECÍFICA DE SAMBA
# =============================================================================
header "5. VALIDACIÓN DE SAMBA"

echo ""

# Estado de servicios Samba
if [ "${SERVICE_STATUS[smbd]}" == "ACTIVE" ] && [ "${SERVICE_STATUS[nmbd]}" == "ACTIVE" ]; then
    ok "Servicios Samba (smbd + nmbd) están activos"
else
    error "Uno o más servicios Samba inactivos"
    ((ERRORS_FOUND++))
    add_to_plan "CRITICAL" "systemctl start smbd nmbd" "Reiniciar servicios Samba"
fi

# Validar sintaxis de smb.conf
echo ""
info "Validando sintaxis de /etc/samba/smb.conf..."

if testparm -s /etc/samba/smb.conf > /dev/null 2>&1; then
    ok "Sintaxis de smb.conf correcta"
else
    error "ERROR en sintaxis de smb.conf"
    ((ERRORS_FOUND++))
    add_to_plan "CRITICAL" "testparm /etc/samba/smb.conf" "Revisar y corregir smb.conf"
fi

# Verificar usuarios Samba
echo ""
info "Usuarios registrados en Samba:"
SAMBA_USERS=$(pdbedit -L 2>/dev/null | wc -l)
if [ "$SAMBA_USERS" -gt 0 ]; then
    ok "Se encontraron $SAMBA_USERS usuario(s) en Samba"
    pdbedit -L 2>/dev/null | while read line; do
        USER=$(echo "$line" | cut -d: -f1)
        echo "  • ${CYAN}$USER${NC}"
    done
else
    error "Sin usuarios registrados en Samba"
    ((ERRORS_FOUND++))
    add_to_plan "HIGH" "pdbedit -a -u mauro" "Crear usuario Samba"
fi

divider

# =============================================================================
# PASO 6: VALIDACIÓN DE RED Y CONECTIVIDAD
# =============================================================================
header "6. VALIDACIÓN DE RED"

echo ""
info "Conectividad de red:"
echo ""

# Obtener dirección IP
IP_ADDR=$(hostname -I | awk '{print $1}')
if [ -z "$IP_ADDR" ]; then
    error "No se pudo obtener dirección IP"
    ((ERRORS_FOUND++))
    add_to_plan "CRITICAL" "ip link show && systemctl restart networking" "Verificar configuración de red"
else
    ok "IP asignada: ${CYAN}$IP_ADDR${NC}"
fi

# Verificar conectividad a internet
if ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    ok "Conectividad a internet disponible"
else
    warn "No hay conectividad a internet (puede no ser crítico)"
    ((WARNINGS_FOUND++))
fi

# Verificar resolución DNS
if nslookup google.com > /dev/null 2>&1; then
    ok "Resolución DNS funcionando"
else
    warn "Problema con resolución DNS"
    ((WARNINGS_FOUND++))
    add_to_plan "MEDIUM" "systemctl restart systemd-resolved" "Reiniciar resolvedor DNS"
fi

divider

# =============================================================================
# PASO 7: REPORTE FINAL Y PLAN DE CORRECCIÓN
# =============================================================================
header "7. REPORTE FINAL"

echo ""
echo -e "  ${WHITE}Resumen:${NC}"
echo "  • Errores encontrados:    ${RED}$ERRORS_FOUND${NC}"
echo "  • Advertencias encontradas: ${YELLOW}$WARNINGS_FOUND${NC}"
echo ""

# Determinación del estado general
if [ "$ERRORS_FOUND" -eq 0 ] && [ "$WARNINGS_FOUND" -eq 0 ]; then
    echo -e "  ${GREEN}✓ ESTADO: EXCELENTE${NC}"
    echo "  El sistema está funcionando correctamente sin problemas."
    echo ""
elif [ "$ERRORS_FOUND" -eq 0 ]; then
    echo -e "  ${YELLOW}⚠ ESTADO: BUENO CON ADVERTENCIAS${NC}"
    echo "  El sistema funciona pero existen puntos de atención."
    echo ""
else
    echo -e "  ${RED}✗ ESTADO: REQUIERE ATENCIÓN${NC}"
    echo "  Existen problemas que deben ser corregidos."
    echo ""
fi

# Mostrar plan de corrección si hay problemas
if [ "$PLAN_INDEX" -gt 0 ]; then
    header "📋 PLAN DE CORRECCIÓN PRIORIZADO"
    echo ""
    
    # Agrupar por prioridad
    CRITICAL=()
    HIGH=()
    MEDIUM=()
    
    for ((i=0; i<PLAN_INDEX; i++)); do
        item="${CORRECTION_PLAN[$i]}"
        if [[ $item == *"CRITICAL"* ]]; then
            CRITICAL+=("$item")
        elif [[ $item == *"HIGH"* ]]; then
            HIGH+=("$item")
        elif [[ $item == *"MEDIUM"* ]]; then
            MEDIUM+=("$item")
        fi
    done
    
    # Mostrar CRITICAL
    if [ ${#CRITICAL[@]} -gt 0 ]; then
        echo -e "  ${RED}🔴 CRÍTICO (Hacer primero):${NC}"
        for ((i=0; i<${#CRITICAL[@]}; i++)); do
            item="${CRITICAL[$i]}"
            action=$(echo "$item" | cut -d'|' -f1 | sed 's/\[CRITICAL\]//g' | xargs)
            desc=$(echo "$item" | cut -d'|' -f2 | xargs)
            echo -e "    $((i+1)). ${WHITE}$action${NC}"
            echo -e "       └─ ${CYAN}$desc${NC}"
        done
        echo ""
    fi
    
    # Mostrar HIGH
    if [ ${#HIGH[@]} -gt 0 ]; then
        echo -e "  ${YELLOW}🟠 ALTA PRIORIDAD:${NC}"
        for ((i=0; i<${#HIGH[@]}; i++)); do
            item="${HIGH[$i]}"
            action=$(echo "$item" | cut -d'|' -f1 | sed 's/\[HIGH\]//g' | xargs)
            desc=$(echo "$item" | cut -d'|' -f2 | xargs)
            echo -e "    $((i+1)). ${WHITE}$action${NC}"
            echo -e "       └─ ${CYAN}$desc${NC}"
        done
        echo ""
    fi
    
    # Mostrar MEDIUM
    if [ ${#MEDIUM[@]} -gt 0 ]; then
        echo -e "  ${MAGENTA}🟡 MEDIANA PRIORIDAD:${NC}"
        for ((i=0; i<${#MEDIUM[@]}; i++)); do
            item="${MEDIUM[$i]}"
            action=$(echo "$item" | cut -d'|' -f1 | sed 's/\[MEDIUM\]//g' | xargs)
            desc=$(echo "$item" | cut -d'|' -f2 | xargs)
            echo -e "    $((i+1)). ${WHITE}$action${NC}"
            echo -e "       └─ ${CYAN}$desc${NC}"
        done
        echo ""
    fi
    
    divider
fi

echo ""
echo -e "  ${WHITE}Próximos pasos:${NC}"
if [ "$ERRORS_FOUND" -gt 0 ]; then
    echo "  1. Ejecutar las acciones CRÍTICAS en el orden mostrado"
    echo "  2. Re-ejecutar este script para validar correcciones"
    echo "  3. Proceder con acciones de ALTA PRIORIDAD"
else
    echo "  1. Revisar advertencias (si las hay)"
    echo "  2. Realizar backup del sistema (recomendado)"
    echo "  3. Monitorear servicio de Samba regularmente"
fi

echo ""
echo -e "${WHITE}═══════════════════════════════════════════════${NC}"
echo ""
