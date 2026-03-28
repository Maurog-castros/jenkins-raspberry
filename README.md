# Jenkins Agent for Raspberry Pi 3

A lightweight, production-ready Jenkins **remote agent** optimised for
Raspberry Pi 3 (ARM64, 1 GB RAM) running Docker.

> **Note** – This repository provides the *agent* side only.  
> You need an existing Jenkins *master/controller* reachable over the network.

---

## Architecture

```
┌─────────────────────────────────┐          ┌───────────────────────────┐
│       Jenkins Master            │          │    Raspberry Pi 3 (ARM64) │
│  (remote host / cloud)          │          │                           │
│                                 │  JNLP /  │  ┌─────────────────────┐  │
│  ┌──────────────────────────┐   │◄─────────┤  │  Docker Container   │  │
│  │  Manage Nodes            │   │  SSH     │  │  jenkins-agent:latest│  │
│  │  └─ raspberry-agent      │   │          │  │                     │  │
│  │     ├─ Secret / key      │   │          │  │  • OpenJDK 17 JRE   │  │
│  │     └─ Workspace         │   │          │  │  • agent.jar (JNLP) │  │
│  └──────────────────────────┘   │          │  │  • git, curl, ssh   │  │
│                                 │          │  │  • user: jenkins    │  │
└─────────────────────────────────┘          │  └─────────────────────┘  │
                                             │  Volume: agent-workspace   │
                                             └───────────────────────────┘
```

---

## Project Layout

```
.
├── Dockerfile                  # Multi-stage build (downloader + final)
├── docker-compose.yml          # Service definition
├── .env.example                # Template for environment variables
├── scripts/
│   ├── start-agent.sh          # Container entry-point (JNLP or SSH mode)
│   ├── validate-connectivity.sh# Pre-flight connectivity checks
│   └── setup-ssh-agent.sh      # One-time SSH key setup (host-level)
├── examples/
│   └── example-pipeline.groovy # Sample Jenkins pipeline
└── README.md
```

---

## Prerequisites

| Requirement | Minimum Version |
|---|---|
| Raspberry Pi OS (64-bit) | Bookworm or later |
| Docker Engine | 24.x |
| Docker Compose plugin | 2.x |
| Jenkins Master | 2.426 LTS or later |

---

## Quick Start (JNLP mode)

### 1. Configure the Jenkins node

1. In Jenkins: **Manage Jenkins → Nodes → New Node**.
2. Choose **Permanent Agent**.
3. Set a **Name** (e.g. `raspberry-agent`) and **Label** (e.g. `raspberry`).
4. Set **Remote root directory** to `/home/jenkins/agent`.
5. Set **Launch method** to **Launch agent by connecting it to the master**.
6. Save and copy the **Agent secret** shown on the node detail page.

### 2. Clone and configure

```bash
git clone https://github.com/Maurog-castros/jenkins-raspberry.git
cd jenkins-raspberry
cp .env.example .env
```

Edit `.env`:

```env
JENKINS_URL=http://your-jenkins-master:8080
AGENT_NAME=raspberry-agent
AGENT_SECRET=<paste secret here>
AGENT_MODE=jnlp
```

### 3. Validate connectivity (optional but recommended)

```bash
bash scripts/validate-connectivity.sh
```

### 4. Build and start the agent

```bash
docker compose up --build -d
docker compose logs -f
```

The agent will wait until Jenkins is reachable, then connect automatically.

---

## SSH Mode Setup

SSH mode is useful when the Jenkins master initiates the connection (e.g.
behind a NAT or when using the *SSH Build Agents* plugin).

### 1. Prepare SSH credentials on the Raspberry Pi

```bash
sudo bash scripts/setup-ssh-agent.sh
```

The script creates the `jenkins` OS user, generates an ED25519 key pair,
and prints the **public key**.

### 2. Add the key to Jenkins

1. **Manage Jenkins → Credentials → System → Global credentials → Add**.
2. Kind: **SSH Username with private key**.
3. Username: `jenkins`.
4. Private Key: paste the content of `/home/jenkins/.ssh/id_ed25519`
   (or use *Enter directly*).
5. Save.

### 3. Configure the Jenkins node for SSH

1. **Manage Jenkins → Nodes → New Node → Permanent Agent**.
2. **Remote root directory**: `/home/jenkins/agent`.
3. **Launch method**: *Launch agents via SSH*.
4. **Host**: `<raspberry-pi-ip>`.
5. **Credentials**: the credential created above.
6. **Host Key Verification Strategy**: *Known hosts file*.

### 4. Update `.env` and start

```env
AGENT_MODE=ssh
```

```bash
docker compose up --build -d
```

---

## Environment Variables Reference

| Variable | Required | Default | Description |
|---|---|---|---|
| `JENKINS_URL` | Yes | – | Full URL of the Jenkins master |
| `AGENT_NAME` | Yes | – | Node name as configured in Jenkins |
| `AGENT_SECRET` | JNLP only | – | Agent secret from Jenkins node page |
| `AGENT_MODE` | No | `jnlp` | Connection mode: `jnlp` or `ssh` |
| `JAVA_OPTS` | No | `-Xms64m -Xmx256m ...` | JVM tuning flags |

---

## Security

- The container runs as **non-root user** `jenkins` (UID 1000).
- Credentials are supplied via **environment variables** (`.env` file) –
  never hardcoded in source code.
- The `.env` file is listed in `.gitignore` and must never be committed.
- SSH private keys should be stored as **Docker secrets** or in a secrets
  manager (Vault, AWS SSM, etc.) in production.
- Use **least privilege**: the `jenkins` user has no `sudo` rights inside
  the container.

### Using Docker Secrets (optional)

```yaml
# docker-compose.yml fragment
secrets:
  agent_secret:
    file: ./secrets/agent_secret.txt

services:
  jenkins-agent:
    secrets:
      - agent_secret
    environment:
      AGENT_SECRET_FILE: /run/secrets/agent_secret
```

Then read the secret in `start-agent.sh`:

```bash
AGENT_SECRET=$(cat "${AGENT_SECRET_FILE}")
```

---

## Resource Tuning

The default JVM flags target a Raspberry Pi 3 with ~1 GB RAM:

```
-Xms64m        # initial heap (keep small at start)
-Xmx256m       # max heap (leaves room for OS + Docker)
-XX:+UseSerialGC  # serial GC has lower overhead on single/dual-core
-Djava.awt.headless=true
```

Adjust `JAVA_OPTS` in `.env` if you have more/less RAM available.

---

## Observability

Container logs are written to **stdout/stderr** and captured by Docker's
`json-file` driver (10 MB × 3 files, configurable in `docker-compose.yml`).

```bash
# Follow live logs
docker compose logs -f jenkins-agent

# Last 100 lines
docker compose logs --tail=100 jenkins-agent
```

For basic system metrics on the Raspberry Pi host, add a `node-exporter`
service to the Compose file:

```yaml
services:
  node-exporter:
    image: prom/node-exporter:latest
    restart: unless-stopped
    network_mode: host
    pid: host
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
    networks:
      - jenkins-net
```

---

## Example Pipeline

See [`examples/example-pipeline.groovy`](examples/example-pipeline.groovy)
for a minimal pipeline that targets the `raspberry` label.

---

## Troubleshooting

### Low voltage warning (Raspberry Pi)

Symptoms: random reboots, SD card corruption, slow performance.

- Use a **5V / 3A** power supply (official RPi PSU recommended).
- Check `/proc/device-tree/chosen/bootargs` or `dmesg | grep voltage`.
- Avoid powering via a hub or laptop USB port.

### Out of memory

Symptoms: agent process killed by OOM killer, `exit code 137`.

```bash
dmesg | grep -i "oom\|killed"
```

Fixes:

- Reduce `JAVA_OPTS` heap: `-Xmx192m` or even `-Xmx128m`.
- Ensure swap is enabled: `sudo dphys-swapfile setup && sudo dphys-swapfile swapon`.
- Limit other services running on the Pi.

### Docker issues

```bash
# Check daemon status
sudo systemctl status docker

# Rebuild image cleanly
docker compose build --no-cache

# Prune dangling images / stopped containers
docker system prune -f
```

### Agent not connecting

1. Run the connectivity validator:
   ```bash
   bash scripts/validate-connectivity.sh
   ```
2. Ensure the Jenkins node is in **waiting** state (not *offline* or *disabled*).
3. Check that `AGENT_NAME` and `AGENT_SECRET` match exactly what Jenkins shows.
4. Verify the firewall allows outbound TCP to port `8080` (JNLP) or `22` (SSH).
5. Check for clock skew (`timedatectl`) – SSL errors can result from time drift.

### SSH key rejected

```bash
# Regenerate known_hosts entry
ssh-keyscan -H <jenkins-master-host> >> ~/.ssh/known_hosts
```

---

## Minimal Plugin Recommendations

| Plugin | Purpose |
|---|---|
| [SSH Build Agents](https://plugins.jenkins.io/ssh-slaves/) | SSH-based agent launch |
| [Docker](https://plugins.jenkins.io/docker-plugin/) | Docker build/run steps |
| [Git](https://plugins.jenkins.io/git/) | Source checkout |
| [Pipeline](https://plugins.jenkins.io/workflow-aggregator/) | Declarative pipelines |
| [Timestamper](https://plugins.jenkins.io/timestamper/) | Timestamps in logs |
| [Build Discarder](https://plugins.jenkins.io/build-discarder/) | Automatic log rotation |

---

## License

[MIT](LICENSE)
