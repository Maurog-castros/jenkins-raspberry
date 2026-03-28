#!/usr/bin/env bash
# setup-ssh-agent.sh – Prepare the Raspberry Pi host (or container image) for
# SSH-based Jenkins agent connectivity.
#
# Usage:
#   sudo bash scripts/setup-ssh-agent.sh [--key-path PATH]
#
# What this script does:
#   1. Creates the 'jenkins' OS user (if absent).
#   2. Generates an ED25519 SSH key pair (if absent).
#   3. Prints the public key to be added to the Jenkins master node config.
#   4. Optionally adds the Jenkins master host key to known_hosts.
set -euo pipefail

# ── Helpers ───────────────────────────────────────────────────────────────────
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }
die() { log "ERROR: $*" >&2; exit 1; }

# ── Defaults ──────────────────────────────────────────────────────────────────
JENKINS_USER="jenkins"
JENKINS_HOME="/home/jenkins"
KEY_PATH="${JENKINS_HOME}/.ssh/id_ed25519"

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --key-path)
            KEY_PATH="$2"; shift 2 ;;
        *)
            die "Unknown argument: $1" ;;
    esac
done

# ── Must run as root ──────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    die "This script must be run as root (use sudo)."
fi

# ── 1. Create jenkins user ────────────────────────────────────────────────────
if id "${JENKINS_USER}" &>/dev/null; then
    log "User '${JENKINS_USER}' already exists."
else
    log "Creating user '${JENKINS_USER}'..."
    useradd -m -s /bin/bash "${JENKINS_USER}"
    log "User '${JENKINS_USER}' created."
fi

# ── 2. Generate SSH key ───────────────────────────────────────────────────────
SSH_DIR="${JENKINS_HOME}/.ssh"
mkdir -p "${SSH_DIR}"
chown "${JENKINS_USER}:${JENKINS_USER}" "${SSH_DIR}"
chmod 700 "${SSH_DIR}"

if [ -f "${KEY_PATH}" ]; then
    log "SSH key already exists at ${KEY_PATH}. Skipping key generation."
else
    log "Generating ED25519 SSH key at ${KEY_PATH}..."
    sudo -u "${JENKINS_USER}" ssh-keygen -t ed25519 -f "${KEY_PATH}" -N "" -C "jenkins-agent@raspberry"
    log "SSH key generated."
fi

# ── 3. Authorised keys (for master-initiated connections) ─────────────────────
AUTH_KEYS="${SSH_DIR}/authorized_keys"
touch "${AUTH_KEYS}"
chown "${JENKINS_USER}:${JENKINS_USER}" "${AUTH_KEYS}"
chmod 600 "${AUTH_KEYS}"

log "Public key (add this to Jenkins → Manage Nodes → <node> → SSH Credentials):"
echo ""
cat "${KEY_PATH}.pub"
echo ""

# ── 4. Optional: add Jenkins master to known_hosts ────────────────────────────
if [ -n "${JENKINS_URL:-}" ]; then
    JENKINS_HOST=$(echo "${JENKINS_URL}" | sed -E 's|https?://([^/:]+).*|\1|')
    log "Adding ${JENKINS_HOST} to ${JENKINS_USER} known_hosts..."
    sudo -u "${JENKINS_USER}" ssh-keyscan -H "${JENKINS_HOST}" >> "${SSH_DIR}/known_hosts" 2>/dev/null || \
        log "Warning: ssh-keyscan failed. Add the host key manually if needed."
fi

log "SSH agent setup complete."
log "Next steps:"
log "  1. Add the PRIVATE key (${KEY_PATH}) to Jenkins credentials:"
log "     Manage Jenkins → Credentials → System → Global credentials → Add"
log "     Kind: 'SSH Username with private key', Username: jenkins,"
log "     Private Key: paste the contents of ${KEY_PATH} (NOT the .pub file)."
log "  2. Set the 'Launch method' to 'Launch agents via SSH' with host: <raspberry-ip>."
log "  3. Start or restart the agent from the Jenkins UI."
