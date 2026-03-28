#!/bin/bash

# Script para gestionar Jenkins en Raspberry Pi
# Uso: ./jenkins-manager.sh [comando]

JENKINS_HOME="/home/mauro/jenkins_home"
DOCKER_COMPOSE_FILE="/home/mauro/docker-compose.yml"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Función para mostrar menú
show_menu() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}     🚀 GESTOR DE JENKINS - RASPBERRY PI${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Comandos disponibles:"
    echo ""
    echo -e "  ${YELLOW}status${NC}          - Mostrar estado actual de Jenkins"
    echo -e "  ${YELLOW}logs${NC}            - Ver logs en tiempo real"
    echo -e "  ${YELLOW}token${NC}           - Mostrar token inicial"
    echo -e "  ${YELLOW}restart${NC}         - Reiniciar Jenkins"
    echo -e "  ${YELLOW}stop${NC}            - Detener Jenkins"
    echo -e "  ${YELLOW}start${NC}           - Iniciar Jenkins"
    echo -e "  ${YELLOW}url${NC}             - Mostrar URL de acceso"
    echo -e "  ${YELLOW}memory${NC}          - Mostrar uso de memoria"
    echo -e "  ${YELLOW}backup${NC}          - Crear backup de configuración"
    echo -e "  ${YELLOW}clean${NC}           - Limpiar caché y datos temporales"
    echo -e "  ${YELLOW}reset${NC}           - Resetear Jenkins completamente"
    echo -e "  ${YELLOW}help${NC}            - Mostrar esta ayuda"
    echo ""
}

# Función: Estado
status_jenkins() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}STATUS DE JENKINS${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}🐳 Contenedor Docker:${NC}"
    docker ps -a --filter "name=jenkins" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    
    echo -e "${YELLOW}📊 Uso de memoria:${NC}"
    docker stats jenkins --no-stream 2>/dev/null | tail -1 || echo "Jenkins no está corriendo"
    echo ""
    
    echo -e "${YELLOW}📁 Almacenamiento:${NC}"
    du -sh $JENKINS_HOME 2>/dev/null || echo "Directorio no encontrado"
    echo ""
    
    echo -e "${YELLOW}🔌 Puertos:${NC}"
    ss -tulnp 2>/dev/null | grep -E '8080|50000' || netstat -tulnp 2>/dev/null | grep -E '8080|50000'
    echo ""
}

# Función: Logs
logs_jenkins() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}LOGS DE JENKINS (Ctrl+C para salir)${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    docker compose -f $DOCKER_COMPOSE_FILE logs -f jenkins
}

# Función: Token
token_jenkins() {
    TOKEN_FILE="$JENKINS_HOME/secrets/initialAdminPassword"
    
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}TOKEN INICIAL DE JENKINS${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if [ -f "$TOKEN_FILE" ]; then
        TOKEN=$(cat "$TOKEN_FILE")
        echo -e "${YELLOW}Token:${NC}"
        echo -e "${CYAN}$TOKEN${NC}"
        echo ""
        echo "Úsalo en: http://raspi-lab:8080"
    else
        echo -e "${RED}[ERROR]${NC} Token no encontrado"
        echo "Jenkins quizá ya ha sido configurado, o aún no está inicializado"
    fi
    echo ""
}

# Función: URL
url_jenkins() {
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}URLs DE ACCESO${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Opción 1 (Hostname):${NC}"
    echo -e "  ${CYAN}http://raspi-lab:8080${NC}"
    echo ""
    echo -e "${YELLOW}Opción 2 (IP Local):${NC}"
    echo -e "  ${CYAN}http://$LOCAL_IP:8080${NC}"
    echo ""
    echo -e "${YELLOW}Opción 3 (Acceso remoto con SSH tunnel):${NC}"
    echo -e "  ${CYAN}ssh -L 8080:localhost:8080 mauro@raspi-lab${NC}"
    echo -e "  Luego abre: ${CYAN}http://localhost:8080${NC}"
    echo ""
}

# Función: Restart
restart_jenkins() {
    echo -e "${YELLOW}🔄 Reiniciando Jenkins...${NC}"
    docker compose -f $DOCKER_COMPOSE_FILE restart jenkins
    echo -e "${GREEN}[OK]${NC} Jenkins reiniciado"
    sleep 2
    status_jenkins
}

# Función: Stop
stop_jenkins() {
    echo -e "${YELLOW}⛔ Deteniendo Jenkins...${NC}"
    docker compose -f $DOCKER_COMPOSE_FILE stop jenkins
    echo -e "${GREEN}[OK]${NC} Jenkins detenido"
}

# Función: Start
start_jenkins() {
    echo -e "${YELLOW}▶️ Iniciando Jenkins...${NC}"
    docker compose -f $DOCKER_COMPOSE_FILE up -d jenkins
    echo -e "${GREEN}[OK]${NC} Jenkins iniciado"
    sleep 2
    status_jenkins
}

# Función: Memory
memory_jenkins() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}USO DE MEMORIA${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}Sistema general:${NC}"
    free -h
    echo ""
    
    echo -e "${YELLOW}Docker (Jenkins):${NC}"
    docker stats jenkins --no-stream 2>/dev/null || echo "Jenkins no está corriendo"
    echo ""
}

# Función: Backup
backup_jenkins() {
    BACKUP_FILE="/home/mauro/jenkins_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    echo -e "${YELLOW}📦 Creando backup...${NC}"
    tar -czf "$BACKUP_FILE" -C /home/mauro jenkins_home/ 2>/dev/null
    
    if [ -f "$BACKUP_FILE" ]; then
        SIZE=$(du -h "$BACKUP_FILE" | awk '{print $1}')
        echo -e "${GREEN}[OK]${NC} Backup creado: $BACKUP_FILE ($SIZE)"
    else
        echo -e "${RED}[ERROR]${NC} No se pudo crear el backup"
    fi
    echo ""
}

# Función: Clean
clean_jenkins() {
    echo -e "${YELLOW}🧹 Limpiando caché...${NC}"
    docker compose -f $DOCKER_COMPOSE_FILE exec -T jenkins /bin/bash -c "rm -rf /var/jenkins_home/caches/* 2>/dev/null" || echo "No hay caché que limpiar"
    echo -e "${GREEN}[OK]${NC} Limpieza completada"
    echo ""
}

# Función: Reset (peligrosa!)
reset_jenkins() {
    echo -e "${RED}⚠️  ADVERTENCIA: Esto eliminará TODOS los datos de Jenkins${NC}"
    read -p "¿Continuar? (escribir 'SI' para confirmar): " -r
    echo
    
    if [[ $REPLY == "SI" ]]; then
        echo -e "${YELLOW}Deteniendo Jenkins...${NC}"
        docker compose -f $DOCKER_COMPOSE_FILE down
        
        echo -e "${YELLOW}Eliminando datos...${NC}"
        rm -rf $JENKINS_HOME
        
        echo -e "${YELLOW}Iniciando Jenkins...${NC}"
        docker compose -f $DOCKER_COMPOSE_FILE up -d jenkins
        
        echo -e "${GREEN}[OK]${NC} Jenkins reseteado"
        sleep 5
        token_jenkins
    else
        echo -e "${YELLOW}Operación cancelada${NC}"
    fi
    echo ""
}

# Main
case "${1:-help}" in
    status) status_jenkins ;;
    logs) logs_jenkins ;;
    token) token_jenkins ;;
    restart) restart_jenkins ;;
    stop) stop_jenkins ;;
    start) start_jenkins ;;
    url) url_jenkins ;;
    memory) memory_jenkins ;;
    backup) backup_jenkins ;;
    clean) clean_jenkins ;;
    reset) reset_jenkins ;;
    help|"") show_menu ;;
    *)
        echo -e "${RED}Comando no reconocido: $1${NC}"
        show_menu
        exit 1
        ;;
esac
