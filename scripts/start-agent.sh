#!/usr/bin/env bash
# start-agent.sh – Entry-point for the Jenkins agent container.
# Supports both JNLP (WebSocket/TCP) and SSH connection modes.
set -euo pipefail

# ── Helpers ───────────────────────────────────────────────────────────────────
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

# ── Validate required variables ───────────────────────────────────────────────
: "${JENKINS_URL:?JENKINS_URL is required}"
: "${AGENT_NAME:?AGENT_NAME is required}"
: "${AGENT_MODE:=jnlp}"

log "Starting Jenkins agent '${AGENT_NAME}' in ${AGENT_MODE} mode"
log "Jenkins master: ${JENKINS_URL}"

# ── Wait until Jenkins master is reachable ────────────────────────────────────
MAX_RETRIES=30
RETRY_INTERVAL=10
attempt=0

log "Waiting for Jenkins master to be reachable..."
until curl -fsSL --max-time 5 --output /dev/null "${JENKINS_URL}/login" 2>/dev/null; do
    attempt=$(( attempt + 1 ))
    if [ "${attempt}" -ge "${MAX_RETRIES}" ]; then
        die "Jenkins master at ${JENKINS_URL} did not become available after $((MAX_RETRIES * RETRY_INTERVAL)) seconds."
    fi
    log "Attempt ${attempt}/${MAX_RETRIES}: Jenkins not ready yet, retrying in ${RETRY_INTERVAL}s..."
    sleep "${RETRY_INTERVAL}"
done
log "Jenkins master is reachable."

# ── Launch agent ──────────────────────────────────────────────────────────────
case "${AGENT_MODE}" in
    jnlp)
        : "${AGENT_SECRET:?AGENT_SECRET is required for JNLP mode}"

        log "Launching JNLP agent..."
        exec java \
            ${JAVA_OPTS:--Xms64m -Xmx256m -XX:+UseSerialGC -Djava.awt.headless=true} \
            -jar /usr/share/jenkins/agent.jar \
            -url "${JENKINS_URL}" \
            -name "${AGENT_NAME}" \
            -secret "${AGENT_SECRET}" \
            -workDir "/home/jenkins/agent"
        ;;

    ssh)
        # In SSH mode the master initiates the connection; the container only
        # needs an SSH server.  This mode is intended for use with a sidecar
        # ssh-server container or an external host.  The script here simply
        # validates the environment and keeps the process alive so that the
        # base image is ready for connections.
        log "Agent configured for SSH mode."
        log "Ensure an SSH server is reachable and the master has the public key configured."
        log "Sleeping indefinitely – SSH connections are managed externally."
        exec tail -f /dev/null
        ;;

    *)
        die "Unknown AGENT_MODE '${AGENT_MODE}'. Use 'jnlp' or 'ssh'."
        ;;
esac
