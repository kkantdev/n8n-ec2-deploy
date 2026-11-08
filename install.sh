#!/usr/bin/env bash
# ==============================================================================
# n8n EC2 Deploy - Interactive Installation Wizard
# ==============================================================================

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all configuration and core libraries
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/config/defaults.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/colors.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/validation.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/system-checks.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/docker.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/secrets.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/environment.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/database.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/compose-generator.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/deployment.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/health-check.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/providers/proxy/provider-interface.sh"

# Trap interruptions gracefully
setup_interrupt_trap

# ------------------------------------------------------------------------------
# Step 1: Welcome Screen & Existing Deployment Check
# ------------------------------------------------------------------------------
show_welcome_screen() {
    clear 2>/dev/null || true
    echo ""
    echo -e "${COLOR_CYAN}${COLOR_BOLD}================================================================${COLOR_RESET}"
    echo -e "${COLOR_WHITE}${COLOR_BOLD}                   n8n EC2 DEPLOYMENT WIZARD                   ${COLOR_RESET}"
    echo -e "${COLOR_CYAN}${COLOR_BOLD}================================================================${COLOR_RESET}"
    echo ""
    echo -e "  Deploy your own n8n automation server on AWS EC2 using Docker."
    echo -e "  Production-conscious, secure, and beginner-friendly."
    echo ""
    echo -e "${COLOR_CYAN}================================================================${COLOR_RESET}"
    echo ""
}

check_existing_deployment() {
    local target_dir="${INSTALL_DIR}"

    if [[ -f "${target_dir}/.env" || -f "${target_dir}/docker-compose.yml" ]]; then
        echo -e "${COLOR_YELLOW}${COLOR_BOLD}[!] An existing n8n deployment was detected in ${target_dir}.${COLOR_RESET}"
        echo ""
        echo -e "  ${COLOR_CYAN}[1]${COLOR_RESET} Manage existing deployment (Status, Start, Stop, Logs, Update)"
        echo -e "  ${COLOR_CYAN}[2]${COLOR_RESET} Reconfigure / Reinstall (Existing data and secrets will be preserved)"
        echo -e "  ${COLOR_CYAN}[0]${COLOR_RESET} Exit"
        echo ""

        local action
        action=$(prompt_input "Select an option [1, 2, or 0]" "1")
        case "$action" in
            1)
                if [[ -x "${target_dir}/manage.sh" ]]; then
                    exec "${target_dir}/manage.sh"
                elif [[ -x "${SCRIPT_DIR}/manage.sh" ]]; then
                    exec "${SCRIPT_DIR}/manage.sh"
                else
                    log_error "Management script not found. Exiting."
                    exit 1
                fi
                ;;
            2)
                log_info "Proceeding with reinstallation. A backup of .env will be created."
                ;;
            0|*)
                log_info "Installation aborted by user."
                exit 0
                ;;
        esac
    fi
}

# ------------------------------------------------------------------------------
# Access Method Selection
# ------------------------------------------------------------------------------
prompt_access_method_selection() {
    print_section "Step 3: Access Method Selection"

    echo -e "Choose how you would like to access your n8n instance:\n"
    echo -e "  ${COLOR_CYAN}[1]${COLOR_RESET} ${COLOR_BOLD}AWS Public IP + Port 5678${COLOR_RESET} (Default)"
    echo -e "      ${COLOR_DIM}• Direct HTTP access via: http://${EC2_PUBLIC_IP}:5678${COLOR_RESET}"
    echo -e "      ${COLOR_DIM}• Quickest setup, no domain name required${COLOR_RESET}"
    echo -e "      ${COLOR_DIM}• Requires opening TCP port 5678 in your AWS EC2 Security Group${COLOR_RESET}"
    echo ""
    echo -e "  ${COLOR_CYAN}[2]${COLOR_RESET} ${COLOR_BOLD}Custom Domain + HTTPS${COLOR_RESET}"
    echo -e "      ${COLOR_DIM}• Secure production access via: https://automation.example.com${COLOR_RESET}"
    echo -e "      ${COLOR_DIM}• Automated Let's Encrypt SSL certificate issuance & renewal${COLOR_RESET}"
    echo -e "      ${COLOR_DIM}• Choose between Nginx or Traefik reverse proxies${COLOR_RESET}"
    echo ""

    local choice
    while true; do
        choice=$(prompt_input "Enter access method [1 or 2]" "1")
        case "$choice" in
            1)
                export SELECTED_ACCESS_METHOD="public-ip"
                export SELECTED_PROXY_PROVIDER="none"
                export DEPLOY_PROTOCOL="http"
                export DEPLOY_HOST="$EC2_PUBLIC_IP"
                export DEPLOY_PORT="${DEFAULT_N8N_PORT}"
                export N8N_HOST_PORT="${DEFAULT_N8N_PORT}"

                # Verify port 5678 is free
                if ! check_port_availability "${DEFAULT_N8N_PORT}" "n8n Web UI"; then
                    log_error "Port ${DEFAULT_N8N_PORT} is already occupied on this host."
                    return 1
                fi

                log_warn "Security Notice: Plain HTTP is unencrypted over the public internet."
                log_info "n8n will be accessible at: http://${EC2_PUBLIC_IP}:${DEFAULT_N8N_PORT}"
                break
                ;;
            2)
                export SELECTED_ACCESS_METHOD="custom-domain"
                prompt_proxy_selection || return 1
                break
                ;;
            *)
                log_error "Invalid selection. Please choose 1 or 2."
                ;;
        esac
    done

    return 0
}

prompt_proxy_selection() {
    echo ""
    echo -e "Choose a reverse proxy to handle HTTPS and WebSockets:\n"
    echo -e "  ${COLOR_CYAN}[1]${COLOR_RESET} ${COLOR_BOLD}Nginx${COLOR_RESET} (Industry standard, lightweight, Certbot SSL renewal)"
    echo -e "  ${COLOR_CYAN}[2]${COLOR_RESET} ${COLOR_BOLD}Traefik${COLOR_RESET} (Cloud-native edge router, built-in Let's Encrypt ACME)"
    echo ""

    local proxy_choice
    while true; do
        proxy_choice=$(prompt_input "Select reverse proxy provider [1 or 2]" "1")
        case "$proxy_choice" in
            1)
                export SELECTED_PROXY_PROVIDER="nginx"
                load_proxy_provider "nginx" || return 1
                nginx_validate_prerequisites || return 1
                nginx_prompt_config || return 1
                break
                ;;
            2)
                export SELECTED_PROXY_PROVIDER="traefik"
                load_proxy_provider "traefik" || return 1
                traefik_validate_prerequisites || return 1
                traefik_prompt_config || return 1
                break
                ;;
            *)
                log_error "Invalid selection. Please choose 1 or 2."
                ;;
        esac
    done

    return 0
}

# ------------------------------------------------------------------------------
# Main Wizard Execution Flow
# ------------------------------------------------------------------------------
main() {
    # Privilege check
    ensure_root

    # Welcome banner
    show_welcome_screen

    # Existing installation detection
    check_existing_deployment

    # System requirements verification
    run_system_checks || {
        log_error "System requirements check failed. Aborting installation."
        exit 1
    }

    # Verify or install Docker and Docker Compose V2
    ensure_docker_ready || {
        log_error "Docker Engine or Docker Compose V2 is not ready. Aborting installation."
        exit 1
    }

    # Database Selection
    prompt_database_selection || {
        log_error "Database configuration failed. Aborting installation."
        exit 1
    }

    # Access Method Selection
    prompt_access_method_selection || {
        log_error "Access method configuration failed. Aborting installation."
        exit 1
    }

    # Deployment summary confirmation
    echo ""
    print_banner "DEPLOYMENT CONFIGURATION SUMMARY"
    echo -e "  ${COLOR_BOLD}Deployment Directory:${COLOR_RESET} ${INSTALL_DIR}"
    echo -e "  ${COLOR_BOLD}Database Provider:${COLOR_RESET}    ${SELECTED_DB_PROVIDER}"
    echo -e "  ${COLOR_BOLD}Access Method:${COLOR_RESET}        ${SELECTED_ACCESS_METHOD}"
    if [[ "$SELECTED_ACCESS_METHOD" == "custom-domain" ]]; then
        echo -e "  ${COLOR_BOLD}Domain Name:${COLOR_RESET}          ${DEPLOY_DOMAIN}"
        echo -e "  ${COLOR_BOLD}Reverse Proxy:${COLOR_RESET}        ${SELECTED_PROXY_PROVIDER}"
        echo -e "  ${COLOR_BOLD}SSL Certificate:${COLOR_RESET}      Let's Encrypt (${DEPLOY_SSL_EMAIL})"
    else
        echo -e "  ${COLOR_BOLD}Access URL:${COLOR_RESET}           http://${EC2_PUBLIC_IP}:${DEFAULT_N8N_PORT}"
    fi
    echo ""

    if ! prompt_yes_no "Do you want to proceed with this deployment?" "Y"; then
        log_warn "Installation cancelled by user."
        exit 0
    fi

    # Prepare directories and file permissions
    prepare_deployment_directories "$INSTALL_DIR"

    # Write .env configuration with chmod 600
    write_deployment_env "$INSTALL_DIR"

    # Generate docker-compose.yml
    generate_docker_compose "$INSTALL_DIR"

    # Generate Proxy configuration if selected
    if [[ "$SELECTED_ACCESS_METHOD" == "custom-domain" ]]; then
        case "$SELECTED_PROXY_PROVIDER" in
            nginx)
                nginx_generate_config "$INSTALL_DIR"
                ;;
            traefik)
                traefik_generate_config "$INSTALL_DIR"
                ;;
        esac
    fi

    # Install management utilities into installation directory
    install_management_utilities "$INSTALL_DIR"

    # Setup Docker networks
    setup_docker_networks

    # Start services
    start_deployment "$INSTALL_DIR"

    # Run health verification
    run_deployment_verification "$INSTALL_DIR" || {
        log_warn "Deployment started, but some health checks could not be fully verified."
        echo -e "Check container logs with: ${COLOR_YELLOW}sudo ${INSTALL_DIR}/manage.sh${COLOR_RESET}"
        exit 1
    }
}

main "$@"

