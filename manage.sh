#!/usr/bin/env bash
# ==============================================================================
# n8n EC2 Deploy - Management Interface
# ==============================================================================

set -euo pipefail

# Determine operational directory
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
# shellcheck source=/dev/null
source "${LIB_DIR}/health-check.sh"

ensure_root

# Load deployed environment
if ! load_deployment_env "$INSTALL_DIR"; then
    log_error "Deployment configuration not found in ${INSTALL_DIR}."
    log_error "Please run install.sh first to deploy n8n."
    exit 1
fi

# ------------------------------------------------------------------------------
# Action 1: Check Status
# ------------------------------------------------------------------------------
status_action() {
    print_banner "N8N SYSTEM STATUS"

    local access_url=""
    if [[ "${DEPLOYMENT_ACCESS_TYPE:-public-ip}" == "custom-domain" ]]; then
        access_url="https://${DOMAIN_NAME:-localhost}"
    else
        access_url="http://${PUBLIC_IPV4:-localhost}:${N8N_PORT:-5678}"
    fi

    echo -e "  ${COLOR_BOLD}Access URL:${COLOR_RESET}           ${COLOR_CYAN}${access_url}${COLOR_RESET}"
    echo -e "  ${COLOR_BOLD}Deployment Directory:${COLOR_RESET} ${INSTALL_DIR}"
    echo -e "  ${COLOR_BOLD}Database Provider:${COLOR_RESET}    ${DEPLOYMENT_DATABASE_TYPE:-ec2-postgres}"
    echo -e "  ${COLOR_BOLD}Access Method:${COLOR_RESET}        ${DEPLOYMENT_ACCESS_TYPE:-public-ip}"
    echo -e "  ${COLOR_BOLD}Reverse Proxy:${COLOR_RESET}        ${PROXY_PROVIDER:-none}"
    echo ""

    echo -e "${COLOR_BOLD}Core Application Containers:${COLOR_RESET}"
    if [[ -f "${INSTALL_DIR}/docker-compose.yml" ]]; then
        docker compose -f "${INSTALL_DIR}/docker-compose.yml" ps
    else
        log_warn "Main docker-compose.yml missing."
    fi

    if [[ "${PROXY_PROVIDER:-none}" != "none" && -f "${INSTALL_DIR}/proxy/docker-compose.yml" ]]; then
        echo ""
        echo -e "${COLOR_BOLD}Reverse Proxy Containers:${COLOR_RESET}"
        docker compose -f "${INSTALL_DIR}/proxy/docker-compose.yml" ps
    fi

    echo ""
    log_step "Testing live health endpoint..."
    if docker exec n8n wget -qO- http://127.0.0.1:5678/healthz >/dev/null 2>&1; then
        log_success "n8n application is healthy and responsive."
    else
        log_warn "n8n application did not respond to healthz endpoint."
    fi
}

# ------------------------------------------------------------------------------
# Action 2: Start Services
# ------------------------------------------------------------------------------
start_action() {
    log_step "Starting n8n deployment services..."

    # Start proxy first if configured
    if [[ "${PROXY_PROVIDER:-none}" != "none" && -f "${INSTALL_DIR}/proxy/docker-compose.yml" ]]; then
        log_info "Starting reverse proxy (${PROXY_PROVIDER})..."
        docker compose -f "${INSTALL_DIR}/proxy/docker-compose.yml" up -d
    fi

    # Start main application
    log_info "Starting n8n and database..."
    docker compose -f "${INSTALL_DIR}/docker-compose.yml" up -d

    log_success "Services started."
}

# ------------------------------------------------------------------------------
# Action 3: Stop Services
# ------------------------------------------------------------------------------
stop_action() {
    log_step "Stopping n8n deployment services..."

    # Stop main application safely
    docker compose -f "${INSTALL_DIR}/docker-compose.yml" down

    # Stop proxy if configured
    if [[ "${PROXY_PROVIDER:-none}" != "none" && -f "${INSTALL_DIR}/proxy/docker-compose.yml" ]]; then
        docker compose -f "${INSTALL_DIR}/proxy/docker-compose.yml" down
    fi

    log_success "All services stopped safely without data loss."
}

# ------------------------------------------------------------------------------
# Action 4: Restart Services
# ------------------------------------------------------------------------------
restart_action() {
    log_step "Restarting n8n deployment services..."
    stop_action
    sleep 2
    start_action
    log_success "Restart complete."
}

# ------------------------------------------------------------------------------
# Action 5: View Logs
# ------------------------------------------------------------------------------
logs_action() {
    echo ""
    echo -e "${COLOR_BOLD}Select logs to view:${COLOR_RESET}"
    echo -e "  ${COLOR_CYAN}[1]${COLOR_RESET} n8n application logs"
    if [[ "${DEPLOYMENT_DATABASE_TYPE:-ec2-postgres}" == "ec2-postgres" ]]; then
        echo -e "  ${COLOR_CYAN}[2]${COLOR_RESET} PostgreSQL database logs"
    fi
    if [[ "${PROXY_PROVIDER:-none}" != "none" ]]; then
        echo -e "  ${COLOR_CYAN}[3]${COLOR_RESET} Reverse proxy (${PROXY_PROVIDER}) logs"
    fi
    echo -e "  ${COLOR_CYAN}[4]${COLOR_RESET} All containers combined"
    echo -e "  ${COLOR_CYAN}[0]${COLOR_RESET} Back to main menu"
    echo ""

    local choice
    choice=$(prompt_input "Enter log selection" "1")

    case "$choice" in
        1)
            docker compose -f "${INSTALL_DIR}/docker-compose.yml" logs -f --tail=100 n8n
            ;;
        2)
            docker compose -f "${INSTALL_DIR}/docker-compose.yml" logs -f --tail=100 postgres
            ;;
        3)
            if [[ "${PROXY_PROVIDER:-none}" != "none" && -f "${INSTALL_DIR}/proxy/docker-compose.yml" ]]; then
                docker compose -f "${INSTALL_DIR}/proxy/docker-compose.yml" logs -f --tail=100
            fi
            ;;
        4)
            docker compose -f "${INSTALL_DIR}/docker-compose.yml" logs -f --tail=50
            ;;
        0|*)
            return 0
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Action 6: Update n8n
# ------------------------------------------------------------------------------
update_action() {
    print_banner "UPDATE N8N VERSION"

    # Detect current image tag
    local current_image
    current_image=$(docker inspect --format='{{.Config.Image}}' n8n 2>/dev/null || echo "Unknown")

    echo -e "  ${COLOR_BOLD}Current n8n Image:${COLOR_RESET} ${current_image}"
    echo ""
    echo -e "  ${COLOR_DIM}This workflow will pull the latest or specified n8n image.${COLOR_RESET}"
    echo -e "  ${COLOR_GREEN}• Your database data and workflows are preserved.${COLOR_RESET}"
    echo -e "  ${COLOR_GREEN}• Your N8N_ENCRYPTION_KEY will NOT be changed.${COLOR_RESET}"
    echo -e "  ${COLOR_GREEN}• Your .env configuration will be backed up automatically.${COLOR_RESET}"
    echo ""

    local target_tag
    target_tag=$(prompt_input "Enter target n8n version tag (e.g., 1.76.0 or latest)" "${N8N_IMAGE_TAG}")

    if [[ -z "$target_tag" ]]; then
        log_error "Version tag cannot be empty."
        return 1
    fi

    if ! prompt_yes_no "Proceed with updating n8n to '${target_tag}'?" "Y"; then
        log_info "Update cancelled by user."
        return 0
    fi

    log_step "Pulling target n8n Docker image: ${N8N_IMAGE_NAME}:${target_tag}..."
    if ! docker pull "${N8N_IMAGE_NAME}:${target_tag}"; then
        log_error "Failed to pull image ${N8N_IMAGE_NAME}:${target_tag}. Verify that the tag exists on Docker Hub."
        return 1
    fi

    log_step "Backing up configuration before update..."
    backup_env_file "$INSTALL_DIR"

    # Update compose file image tag safely
    local compose_file="${INSTALL_DIR}/docker-compose.yml"
    sed -i "s|image: ${N8N_IMAGE_NAME}:.*|image: ${N8N_IMAGE_NAME}:${target_tag}|g" "$compose_file"

    log_step "Recreating n8n container with updated image..."
    docker compose -f "$compose_file" up -d --no-deps n8n

    log_step "Verifying application health post-update..."
    if verify_n8n_health "$INSTALL_DIR"; then
        log_success "n8n was successfully updated to version ${target_tag}!"
    else
        log_error "Post-update health check failed! Check logs using option [5]."
        echo -e "If necessary, you can roll back to ${current_image}."
    fi
}

# ------------------------------------------------------------------------------
# Action 7: Uninstall
# ------------------------------------------------------------------------------
uninstall_action() {
    local uninstall_script="${INSTALL_DIR}/uninstall.sh"
    if [[ ! -x "$uninstall_script" ]]; then
        uninstall_script="${SCRIPT_DIR}/uninstall.sh"
    fi

    if [[ -x "$uninstall_script" ]]; then
        exec "$uninstall_script"
    else
        log_error "Uninstall script not found at ${uninstall_script}."
    fi
}

# ------------------------------------------------------------------------------
# Interactive Management Menu Loop
# ------------------------------------------------------------------------------
show_menu() {
    while true; do
        echo ""
        echo -e "${COLOR_CYAN}${COLOR_BOLD}========================================${COLOR_RESET}"
        echo -e "${COLOR_WHITE}${COLOR_BOLD}             N8N MANAGEMENT             ${COLOR_RESET}"
        echo -e "${COLOR_CYAN}${COLOR_BOLD}========================================${COLOR_RESET}"
        echo ""
        echo -e "  ${COLOR_CYAN}[1]${COLOR_RESET} Check Status"
        echo -e "  ${COLOR_CYAN}[2]${COLOR_RESET} Start n8n"
        echo -e "  ${COLOR_CYAN}[3]${COLOR_RESET} Stop n8n"
        echo -e "  ${COLOR_CYAN}[4]${COLOR_RESET} Restart n8n"
        echo -e "  ${COLOR_CYAN}[5]${COLOR_RESET} View Logs"
        echo -e "  ${COLOR_CYAN}[6]${COLOR_RESET} Update n8n"
        echo -e "  ${COLOR_CYAN}[7]${COLOR_RESET} Uninstall"
        echo -e "  ${COLOR_CYAN}[0]${COLOR_RESET} Exit"
        echo ""

        local selection
        selection=$(prompt_input "Select an option [0-7]" "1")

        case "$selection" in
            1) status_action ;;
            2) start_action ;;
            3) stop_action ;;
            4) restart_action ;;
            5) logs_action ;;
            6) update_action ;;
            7) uninstall_action; break ;;
            0) log_info "Goodbye!"; exit 0 ;;
            *) log_error "Invalid selection. Please choose a number from 0 to 7." ;;
        esac

        echo ""
        prompt_input "Press [Enter] to return to menu" "" >/dev/null || true
    done
}

# Support non-interactive CLI flags as well as interactive menu
if [[ $# -gt 0 ]]; then
    case "$1" in
        status) status_action ;;
        start) start_action ;;
        stop) stop_action ;;
        restart) restart_action ;;
        logs) logs_action ;;
        update) update_action ;;
        uninstall) uninstall_action ;;
        *) echo "Usage: $0 [status|start|stop|restart|logs|update|uninstall]" ;;
    esac
else
    show_menu
fi

