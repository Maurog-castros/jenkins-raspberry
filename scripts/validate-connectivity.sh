#!/usr/bin/env bash
# validate-connectivity.sh – Check connectivity between this host and the
# Jenkins master before starting (or troubleshooting) the agent.
set -euo pipefail

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
ok()   { log "  ✔  $*"; }
fail() { log "  ✖  $*" >&2; ERRORS=$(( ERRORS + 1 )); }

ERRORS=0

# ── Load .env if present ──────────────────────────────────────────────────────
if [ -f .env ]; then
    # shellcheck source=/dev/null
    set -o allexport
    source .env
    set +o allexport
    log "Loaded variables from .env"
fi

# ── Required variables ────────────────────────────────────────────────────────
: "${JENKINS_URL:?JENKINS_URL is not set. Export it or create a .env file.}"
: "${AGENT_NAME:?AGENT_NAME is not set.}"

log "Validating connectivity to Jenkins master"
log "  JENKINS_URL : ${JENKINS_URL}"
log "  AGENT_NAME  : ${AGENT_NAME}"

# ── 1. DNS / TCP reachability ─────────────────────────────────────────────────
JENKINS_HOST=$(echo "${JENKINS_URL}" | sed -E 's|https?://([^/:]+).*|\1|')
# Extract explicit port from URL (e.g. http://host:9090/); empty string if absent
JENKINS_PORT=$(echo "${JENKINS_URL}" | sed -E 's|https?://[^/:]+:([0-9]+).*|\1|; t; s|.*||')
if [ -z "${JENKINS_PORT}" ]; then
    # No explicit port in URL – use scheme default
    if [[ "${JENKINS_URL}" =~ ^https ]]; then
        JENKINS_PORT="443"
    else
        JENKINS_PORT="80"
    fi
fi

log "Checking TCP connection to ${JENKINS_HOST}:${JENKINS_PORT}..."
if timeout 5 bash -c "echo >/dev/tcp/${JENKINS_HOST}/${JENKINS_PORT}" 2>/dev/null; then
    ok "TCP connection to ${JENKINS_HOST}:${JENKINS_PORT} succeeded."
else
    fail "Cannot open TCP connection to ${JENKINS_HOST}:${JENKINS_PORT}. Check firewall / routing."
fi

# ── 2. HTTP reachability ──────────────────────────────────────────────────────
log "Checking HTTP reachability (${JENKINS_URL}/login)..."
HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 10 "${JENKINS_URL}/login" || true)
if [[ "${HTTP_CODE}" =~ ^(200|403)$ ]]; then
    ok "HTTP ${HTTP_CODE} from ${JENKINS_URL}/login – Jenkins is up."
elif [ "${HTTP_CODE}" = "000" ]; then
    fail "No HTTP response from ${JENKINS_URL}/login (code 000). Check URL and network."
else
    fail "Unexpected HTTP ${HTTP_CODE} from ${JENKINS_URL}/login."
fi

# ── 3. Agent JNLP endpoint ────────────────────────────────────────────────────
JNLP_URL="${JENKINS_URL}/computer/${AGENT_NAME}/slave-agent.jnlp"
log "Checking JNLP endpoint (${JNLP_URL})..."
JNLP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 10 "${JNLP_URL}" || true)
if [[ "${JNLP_CODE}" =~ ^(200|401|403)$ ]]; then
    ok "JNLP endpoint reachable (HTTP ${JNLP_CODE})."
elif [ "${JNLP_CODE}" = "404" ]; then
    fail "JNLP endpoint returned 404. Verify that node '${AGENT_NAME}' exists in Jenkins."
else
    fail "Unexpected HTTP ${JNLP_CODE} from JNLP endpoint."
fi

# ── 4. Java availability ──────────────────────────────────────────────────────
log "Checking Java..."
if java -version 2>/dev/null; then
    ok "Java is available."
else
    fail "Java not found in PATH."
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
if [ "${ERRORS}" -eq 0 ]; then
    log "All checks passed. The agent should be able to connect."
    exit 0
else
    log "${ERRORS} check(s) failed. Resolve the issues above before starting the agent."
    exit 1
fi
