#!/usr/bin/env bash
# ==============================================================================
# Traefik Proxy Lifecycle Logic
# ==============================================================================

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../config/defaults.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/common.sh"

traefik_install() {
    local target_dir="${1:-$INSTALL_DIR}"
    local proxy_dir="${target_dir}/proxy"
    local acme_file="${proxy_dir}/letsencrypt/acme.json"

    log_step "Initializing Traefik reverse proxy..."

    # Ensure proxy network exists
    docker network create "${DOCKER_PROXY_NETWORK}" >/dev/null 2>&1 || true

    # Traefik will refuse to start if acme.json permissions are not strictly 600
    if [[ ! -f "$acme_file" ]]; then
        mkdir -p "$(dirname "$acme_file")"
        touch "$acme_file"
    fi
    chmod 600 "$acme_file"

    log_step "Starting Traefik container..."
    docker compose -f "${proxy_dir}/docker-compose.yml" up -d

    log_success "Traefik started successfully."
    return 0
}

traefik_start() {
    local target_dir="${1:-$INSTALL_DIR}"
    local proxy_dir="${target_dir}/proxy"
    docker compose -f "${proxy_dir}/docker-compose.yml" up -d
}

traefik_stop() {
    local target_dir="${1:-$INSTALL_DIR}"
    local proxy_dir="${target_dir}/proxy"
    docker compose -f "${proxy_dir}/docker-compose.yml" down
}

traefik_status() {
    local target_dir="${1:-$INSTALL_DIR}"
    local proxy_dir="${target_dir}/proxy"
    docker compose -f "${proxy_dir}/docker-compose.yml" ps
}

traefik_logs() {
    local target_dir="${1:-$INSTALL_DIR}"
    local proxy_dir="${target_dir}/proxy"
    docker compose -f "${proxy_dir}/docker-compose.yml" logs -f --tail=100 "$@"
}

