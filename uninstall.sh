#!/usr/bin/env bash
# ==============================================================================
# n8n EC2 Deploy - Uninstallation Script
# ==============================================================================

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve installation root and library directory
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    INSTALL_DIR="${SCRIPT_DIR}"
    if [[ -d "${SCRIPT_DIR}/.installer/lib" ]]; then
        LIB_DIR="${SCRIPT_DIR}/.installer/lib"
        CONFIG_DIR="${SCRIPT_DIR}/.installer/config"
    else
        LIB_DIR="${SCRIPT_DIR}/lib"
        CONFIG_DIR="${SCRIPT_DIR}/config"
    fi
else
    INSTALL_DIR="${INSTALL_DIR:-/opt/applications/n8n}"
    LIB_DIR="${SCRIPT_DIR}/lib"
    CONFIG_DIR="${SCRIPT_DIR}/config"
fi

# Source libraries
# shellcheck source=/dev/null
source "${CONFIG_DIR}/defaults.sh"
# shellcheck source=/dev/null
source "${LIB_DIR}/colors.sh"
# shellcheck source=/dev/null
source "${LIB_DIR}/common.sh"
# shellcheck source=/dev/null
source "${LIB_DIR}/environment.sh"

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
