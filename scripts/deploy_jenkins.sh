#!/bin/bash

# Script para desplegar Jenkins en Raspberry Pi con Docker
# Uso: ./deploy_jenkins.sh

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    🚀 DESPLEGANDO JENKINS EN DOCKER - RASPBERRY PI${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# Variables
JENKINS_HOME="/home/mauro/jenkins_home"
JENKINS_PORT=8080
DOCKER_COMPOSE_FILE="/home/mauro/docker-compose.yml"

# Paso 1: Verificar Docker
echo -e "${YELLOW}[1/5]${NC} Verificando Docker..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[ERROR]${NC} Docker no está instalado"
    exit 1
fi
echo -e "${GREEN}[OK]${NC} Docker está instalado: $(docker --version)"
echo ""

# Paso 2: Verificar si Jenkins ya está corriendo
echo -e "${YELLOW}[2/5]${NC} Verificando Jenkins existente..."
if docker ps -a --format '{{.Names}}' | grep -q "^jenkins$"; then
    echo -e "${YELLOW}[AVISO]${NC} Jenkins ya existe"
    read -p "¿Detener y remover contenedor existente? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        echo -e "${YELLOW}Deteniendo jenkins...${NC}"
        docker stop jenkins 2>/dev/null || true
        sleep 2
        echo -e "${YELLOW}Removiendo jenkins...${NC}"
        docker rm jenkins 2>/dev/null || true
    else
        echo -e "${YELLOW}Usando contenedor existente${NC}"
        echo ""
    fi
fi
echo ""

# Paso 3: Preparar directorio jenkins_home
echo -e "${YELLOW}[3/5]${NC} Preparando directorio jenkins_home..."
if [ ! -d "$JENKINS_HOME" ]; then
    mkdir -p "$JENKINS_HOME"
    echo -e "${GREEN}[OK]${NC} Directorio creado: $JENKINS_HOME"
else
    echo -e "${GREEN}[OK]${NC} Directorio existente: $JENKINS_HOME"
fi

# Establecer permisos correctos
sudo chown -R 1000:1000 "$JENKINS_HOME" 2>/dev/null || echo -e "${YELLOW}[NOTA]${NC} Configurar permisos manualmente si es necesario"
echo ""

# Paso 4: Lanzar contenedor de Jenkins
echo -e "${YELLOW}[4/5]${NC} Iniciando contenedor Jenkins..."

if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
    echo -e "${RED}[ERROR]${NC} docker-compose.yml no encontrado en $DOCKER_COMPOSE_FILE"
    echo "Asegúrate de haber copiado el archivo docker-compose.yml"
    exit 1
fi

cd "$(dirname "$DOCKER_COMPOSE_FILE")"
docker compose up -d jenkins

echo -e "${GREEN}[OK]${NC} Contenedor iniciado"
echo ""

# Paso 5: Esperar a que Jenkins esté listo y obtener token
echo -e "${YELLOW}[5/5]${NC} Esperando a que Jenkins esté listo..."
echo -e "${YELLOW}Esto puede tomar 1-2 minutos (primera ejecución instala plugins)...${NC}"

TIMEOUT=120
ELAPSED=0
READY=false

while [ $ELAPSED -lt $TIMEOUT ]; do
    if docker exec jenkins curl -s http://localhost:8080/login > /dev/null 2>&1; then
        READY=true
        break
    fi
    
    ELAPSED=$((ELAPSED + 5))
    echo -ne "\r⏳ Esperando... ${ELAPSED}s"
    sleep 5
done

echo ""
echo ""

if [ "$READY" = true ]; then
    echo -e "${GREEN}[OK]${NC} Jenkins está listo ✅"
    echo ""
    
    # Obtener token inicial (si existe)
    TOKEN_FILE="$JENKINS_HOME/secrets/initialAdminPassword"
    if [ -f "$TOKEN_FILE" ]; then
        echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}CONFIGURACIÓN INICIAL${NC}"
        echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "🌐 URL de Jenkins:"
        echo -e "   ${YELLOW}http://raspi-lab:$JENKINS_PORT${NC}"
        echo -e "   o"
        echo -e "   ${YELLOW}http://$(hostname -I | awk '{print $1}'):$JENKINS_PORT${NC}"
        echo ""
        echo -e "🔑 Token inicial (pegalo en Jenkins):"
        echo -e "   ${YELLOW}$(cat $TOKEN_FILE)${NC}"
        echo ""
        echo -e "⏒ Usuario: ${YELLOW}admin${NC}"
        echo ""
    else
        echo -e "${YELLOW}[NOTA]${NC} Token inicial aún no disponible, revisa en Jenkins"
    fi
else
    echo -e "${RED}[ERROR]${NC} Jenkins no está listo después de 2 minutos ❌"
    echo ""
    echo "Revisa los logs:"
    echo -e "  ${YELLOW}docker compose logs jenkins${NC}"
    exit 1
fi

# Información final
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}PRÓXIMOS PASOS${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "1. Abre el navegador y ve a: http://raspi-lab:$JENKINS_PORT"
echo "2. Pega el token inicial (Unlock Jenkins)"
echo "3. Selecciona 'Install suggested plugins'"
echo "4. Crea el usuario administrador"
echo "5. Recomendaciones para Raspberry Pi:"
echo "   - Limita ejecuciones paralelas a 1-2 (Manage Jenkins > Configure System)"
echo "   - Aumenta el memory pool si es necesario"
echo ""
echo "Ver logs:"
echo "  ${YELLOW}docker compose logs -f jenkins${NC}"
echo ""
echo "Detener Jenkins:"
echo "  ${YELLOW}docker compose down${NC}"
echo ""
