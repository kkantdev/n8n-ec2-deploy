#!/usr/bin/env bash
# ==============================================================================
# Traefik Proxy Lifecycle Logic
# ==============================================================================

# Ensure directory context
if [[ -z "${PROJECT_ROOT:-}" || -z "${LIB_DIR:-}" ]]; then
    _DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${_DIR}/../../.." && pwd)}"
    export PROJECT_ROOT
    LIB_DIR="${LIB_DIR:-${PROJECT_ROOT}/lib}"
    export LIB_DIR
    CONFIG_DIR="${CONFIG_DIR:-${PROJECT_ROOT}/config}"
    export CONFIG_DIR
    unset _DIR
fi

if ! declare -f load_lib >/dev/null 2>&1; then
    load_lib() {
        local file_path="$1"
        if [[ ! -f "$file_path" ]]; then
            echo -e "\033[31m[✖ ERROR]\033[0m Required library file not found: ${file_path}" >&2
            exit 1
        fi
        # shellcheck source=/dev/null
        source "$file_path"
    }
fi

load_lib "${CONFIG_DIR}/defaults.sh"
load_lib "${LIB_DIR}/common.sh"

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
