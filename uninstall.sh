#!/usr/bin/env bash
# ==============================================================================
# n8n EC2 Deploy - Uninstallation Script
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Path & Directory Resolution
# ------------------------------------------------------------------------------
# Determine operational directory
if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "bash" && "${BASH_SOURCE[0]}" != "-bash" && -e "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
else
    SCRIPT_DIR="$(pwd)"
fi

# Detect whether running from repo or installed /opt/applications/n8n/
if [[ -d "${SCRIPT_DIR}/lib" ]]; then
    PROJECT_ROOT="${SCRIPT_DIR}"
elif [[ -d "${SCRIPT_DIR}/.installer/lib" ]]; then
    PROJECT_ROOT="${SCRIPT_DIR}/.installer"
else
    PROJECT_ROOT="${PROJECT_ROOT:-${SCRIPT_DIR}}"
fi

export PROJECT_ROOT
LIB_DIR="${LIB_DIR:-${PROJECT_ROOT}/lib}"
export LIB_DIR
CONFIG_DIR="${CONFIG_DIR:-${PROJECT_ROOT}/config}"
export CONFIG_DIR
PROVIDERS_DIR="${PROVIDERS_DIR:-${PROJECT_ROOT}/providers}"
export PROVIDERS_DIR
TEMPLATES_DIR="${TEMPLATES_DIR:-${PROJECT_ROOT}/templates}"
export TEMPLATES_DIR

# Determine deployment installation directory
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    INSTALL_DIR="${SCRIPT_DIR}"
else
    INSTALL_DIR="${INSTALL_DIR:-/opt/applications/n8n}"
fi
export INSTALL_DIR

# Robust library loader with existence checking
load_lib() {
    local lib_file="$1"
    if [[ ! -f "$lib_file" ]]; then
        echo -e "\033[31m[✖ ERROR]\033[0m Required library file not found: ${lib_file}" >&2
        echo -e "Please ensure all repository files are present under ${PROJECT_ROOT}." >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$lib_file"
}

# Source libraries
load_lib "${CONFIG_DIR}/defaults.sh"
load_lib "${LIB_DIR}/colors.sh"
load_lib "${LIB_DIR}/common.sh"
load_lib "${LIB_DIR}/environment.sh"

ensure_root

# Load deployed environment if available
load_deployment_env "$INSTALL_DIR" 2>/dev/null || true

print_banner "N8N EC2 DEPLOYMENT UNINSTALLATION"

echo -e "${COLOR_YELLOW}${COLOR_BOLD}WARNING: You are about to uninstall n8n from this server.${COLOR_RESET}"
echo ""
echo -e "This will stop and remove:"
echo -e "  • All n8n and dependency Docker containers"
echo -e "  • Reverse proxy containers (Nginx / Traefik) if installed"
echo -e "  • Docker networks created for this deployment"
echo ""

if ! prompt_yes_no "Are you sure you want to proceed with uninstallation?" "N"; then
    log_info "Uninstallation cancelled by user."
    exit 0
fi

log_step "Stopping and removing Docker containers..."

# 1. Stop and remove proxy containers if present
if [[ -f "${INSTALL_DIR}/proxy/docker-compose.yml" ]]; then
    log_info "Stopping reverse proxy containers..."
    docker compose -f "${INSTALL_DIR}/proxy/docker-compose.yml" down -v --remove-orphans 2>/dev/null || true
fi

# 2. Stop and remove main application containers
if [[ -f "${INSTALL_DIR}/docker-compose.yml" ]]; then
    log_info "Stopping n8n and database containers..."
    docker compose -f "${INSTALL_DIR}/docker-compose.yml" down --remove-orphans 2>/dev/null || true
fi

# 3. Clean up custom docker networks
log_step "Cleaning up Docker networks..."
docker network rm "${DOCKER_PROXY_NETWORK}" 2>/dev/null || true
docker network rm "${DOCKER_INTERNAL_NETWORK}" 2>/dev/null || true

# 4. Safe persistent data retention check
echo ""
echo -e "${COLOR_YELLOW}${COLOR_BOLD}DATA PRESERVATION CHECK:${COLOR_RESET}"
echo -e "By default, your workflow database and credentials are ${COLOR_GREEN}${COLOR_BOLD}PRESERVED${COLOR_RESET} at:"
echo -e "  • ${INSTALL_DIR}/data/n8n"
if [[ -d "${INSTALL_DIR}/postgres" ]]; then
    echo -e "  • ${INSTALL_DIR}/postgres/data"
fi
echo ""
echo -e "Keeping persistent data allows you to reinstall or migrate n8n in the future without losing workflows."
echo ""

local delete_data=""
echo -ne "${COLOR_RED}${COLOR_BOLD}Do you want to PERMANENTLY DELETE all persistent data and workflows? Type uppercase 'YES' to confirm${COLOR_RESET}: "
read -r delete_data

if [[ "$delete_data" == "YES" ]]; then
    log_warn "Permanently removing persistent data directories..."
    rm -rf "${INSTALL_DIR}/data"
    rm -rf "${INSTALL_DIR}/postgres"
    rm -rf "${INSTALL_DIR}/proxy"
    rm -rf "${INSTALL_DIR}/logs"
    rm -rf "${INSTALL_DIR}/.env"*
    rm -rf "${INSTALL_DIR}/docker-compose.yml"
    rm -rf "${INSTALL_DIR}/.installer"
    rm -rf "${INSTALL_DIR}/README.md"
    rm -rf "${INSTALL_DIR}/manage.sh"
    rm -rf "${INSTALL_DIR}/uninstall.sh"
    log_success "All application containers, configuration, and persistent data have been deleted."
else
    log_info "Preserving persistent data directories in ${INSTALL_DIR}/."
    rm -f "${INSTALL_DIR}/docker-compose.yml"
    rm -rf "${INSTALL_DIR}/proxy/docker-compose.yml" 2>/dev/null || true
    log_success "n8n services removed. Persistent data preserved safely."
fi

echo ""
log_success "Uninstallation complete."
