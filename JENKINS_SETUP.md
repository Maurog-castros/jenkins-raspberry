# 🚀 Jenkins - Instalación en Docker (Raspberry Pi)

## ✅ Estado: COMPLETADO

Jenkins ha sido **instalado y desplegado exitosamente** en Docker en tu Raspberry Pi.

---

## 📋 Acceso Inicial

### URL de Jenkins
```
http://raspi-lab:8080
http://raspi-lab.local:8080
```

O usa la IP local:
```
http://172.18.0.1:8080  (verifica tu IP con: hostname -I)
```

### Credenciales Iniciales

**Usuario:** `admin`

**Token inicial:**
```
8693077cc42840fd8aaa9b35c4dbe816
```

> 📌 **Este token es de una sola vez.** Una vez que ingreses a Jenkins, deberás:
> 1. Pegar este token en "Administrator password"
> 2. Hacer clic en "Continue"
> 3. Seleccionar "Install suggested plugins"
> 4. Crear tu usuario administrador

---

## 🔧 Configuración del Contenedor

### Docker Compose
- **Archivo:** `/home/mauro/docker-compose.yml`
- **Comandos útiles:**
  ```bash
  # Ver estado
  docker ps | grep jenkins
  
  # Ver logs
  docker compose logs -f jenkins
  
  # Reiniciar
  docker compose restart jenkins
  
  # Detener
  docker compose down
  
  # Iniciar
  docker compose up -d jenkins
  ```

### Recursos Asignados
- **RAM:** 256MB reservado / 512MB máximo
- **CPU:** Sin límite (pero optimizado para RPi)
- **Puerto Web:** 8080
- **Puerto Agentes:** 50000
- **Almacenamiento:** `/home/mauro/jenkins_home/`

### Optimizaciones para Raspberry Pi
- JVM configurado con máximo 512MB de heap
- Límite de conexiones simultáneas reducido
- Decay factor para estadísticas de carga aumentado

---

## 🎯 Próximos Pasos

### 1. Acceder a Jenkins
1. Abre tu navegador
2. Ve a `http://raspi-lab:8080`
3. Pega el token de arriba

### 2. Configuración Recomendada
Una vez dentro de Jenkins, ve a **Manage Jenkins → System Configuration** y:

```
Ejecutores: 1-2 (máximo)
  → La RPi solo soporta 1-2 trabajos paralelos
  
Total de ejecutores: 1-2

Configurar disco: Monitorear `/home/mauro/jenkins_home`
  → Máximo 80% de uso de disco
```

### 3. Instalar Plugins Esenciales
En **Manage Jenkins → Manage Plugins**:
- Git plugin (para clonar repos)
- Docker plugin (para ejecutar builds en contenedores)
- Pipeline (para Jenkins Declarative Pipeline)
- Blue Ocean (interfaz moderna)

### 4. Conectar tu Repositorio
1. Ve a **New Item**
2. Crea un "Pipeline" o "Multibranch Pipeline"
3. Apunta a tu repositorio Git

---

## 📊 Monitoreo y Mantenimiento

### Ver Logs en Tiempo Real
```bash
docker compose logs -f jenkins
```

### Limpiar Caché
Si Jenkins necesita espacio:
```bash
docker compose exec jenkins /bin/bash -c "rm -rf /var/jenkins_home/caches/*"
```

### Actualizar Jenkins
```bash
docker compose pull jenkins
docker compose down
docker compose up -d jenkins
```

### Respaldar Configuración
```bash
tar -czf jenkins_backup_$(date +%Y%m%d).tar.gz /home/mauro/jenkins_home/
```

---

## ⚠️ Limitaciones en Raspberry Pi

⚠️ **RAM limitada (904MB total)**
- Si Jenkins consume mucha RAM, reduce el heap
- Evita builds muy pesados simultáneamente
- Monitorea con: `free -h`

⚠️ **Almacenamiento limitado**
- Raíz: 23GB
- USB1: ~4.5GB (41% lleno)
- USB2: ~28GB

⚠️ **CPU ARM64**
- Algunos plugins pueden no tener imágenes optimizadas
- Considera usar agentes de build en otra máquina

---

## 🔐 Seguridad

### Cambiar Contraseña Admin
1. Inicia sesión con el token
2. Ve a **Manage Jenkins → Security**
3. Cambia la contraseña de admin

### Configurar Firewall
```bash
sudo ufw allow 8080/tcp
sudo ufw allow 50000/tcp
sudo ufw enable
```

### Acceso Remoto
- Usa SSH forward si accedes desde fuera:
  ```bash
  ssh -L 8080:localhost:8080 mauro@raspi-lab
  ```

---

## 🆘 Troubleshooting

### Jenkins no responde
```bash
docker compose logs jenkins
docker compose restart jenkins
```

### Limpiar datos y reiniciar
```bash
docker compose down
rm -rf /home/mauro/jenkins_home/
docker compose up -d jenkins
# Espera 1-2 minutos y obtén nuevo token
```

### Ver token si se olvidó
```bash
cat /home/mauro/jenkins_home/secrets/initialAdminPassword
```

---

## 📚 Recursos Útiles

- [Jenkins Documentation](https://www.jenkins.io/doc/)
- [Jenkins Docker Image](https://github.com/jenkinsci/docker/blob/master/README.md)
- [Raspberry Pi + Docker](https://docs.docker.com/engine/install/debian/)

---

**Última actualización:** 2026-03-28  
**Estado:** ✅ Jenkins 2.479+ Ready
