#!/usr/bin/env bash
# ==============================================================================
# Health Checks & Post-Deployment Verification
# ==============================================================================

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../config/defaults.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"

verify_postgres_health() {
    local target_dir="${1:-$INSTALL_DIR}"
    log_step "Verifying PostgreSQL container health..."

    local elapsed=0
    local timeout=60

    while (( elapsed < timeout )); do
        local status
        status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' n8n-postgres 2>/dev/null || true)

        if [[ "$status" == "healthy" ]]; then
            log_success "PostgreSQL is healthy and accepting connections."
            return 0
        fi

        sleep 3
        (( elapsed += 3 ))
    done

    log_error "PostgreSQL container failed to become healthy within ${timeout}s."
    docker logs --tail=50 n8n-postgres 2>&1 | tail -n 20 >&2
    return 1
}

verify_n8n_health() {
    local target_dir="${1:-$INSTALL_DIR}"
    log_step "Verifying n8n application initialization and migrations..."

    local elapsed=0
    local timeout="${HEALTH_CHECK_TIMEOUT:-180}"

    while (( elapsed < timeout )); do
        # Check container state
        local container_state
        container_state=$(docker inspect --format='{{.State.Status}}' n8n 2>/dev/null || true)

        if [[ "$container_state" == "exited" || "$container_state" == "dead" ]]; then
            log_error "n8n container unexpectedly terminated!"
            docker logs --tail=50 n8n 2>&1 | tail -n 20 >&2
            return 1
        fi

        # Test n8n health endpoint via docker exec wget
        if docker exec n8n wget -qO- http://127.0.0.1:5678/healthz >/dev/null 2>&1; then
            log_success "n8n health endpoint responded OK! Application is fully initialized."
            return 0
        fi

        echo -ne "${COLOR_DIM}Waiting for n8n to complete database migrations... (${elapsed}s/${timeout}s)\r${COLOR_RESET}"
        sleep 5
        (( elapsed += 5 ))
    done

    echo ""
    log_error "n8n application failed to respond to health checks within ${timeout}s."
    log_error "Recent n8n container logs:"
    docker logs --tail=50 n8n 2>&1 | tail -n 25 >&2
    return 1
}

verify_proxy_health() {
    local target_dir="${1:-$INSTALL_DIR}"
    local provider="${SELECTED_PROXY_PROVIDER:-none}"

    if [[ "$provider" == "none" ]]; then
        return 0
    fi

    log_step "Verifying reverse proxy (${provider}) status..."
    local container_name="n8n-proxy-${provider}"

    local status
    status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null || true)

    if [[ "$status" == "running" ]]; then
        log_success "Reverse proxy container (${container_name}) is running."
        return 0
    else
        log_error "Reverse proxy container (${container_name}) is not running (status: ${status})."
        docker logs --tail=30 "$container_name" 2>&1 || true
        return 1
    fi
}

verify_public_endpoint() {
    local target_dir="${1:-$INSTALL_DIR}"
    local access_method="${SELECTED_ACCESS_METHOD:-public-ip}"
    local url=""

    if [[ "$access_method" == "custom-domain" ]]; then
        url="https://${DEPLOY_DOMAIN}"
    else
        url="http://${EC2_PUBLIC_IP}:${N8N_HOST_PORT:-5678}"
    fi

    log_step "Testing public access endpoint: ${url}..."

    # Give services a few seconds to stabilize
    sleep 3

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 10 -k "$url" 2>/dev/null || true)

    if [[ "$http_code" =~ ^(200|301|302|401)$ ]]; then
        log_success "Access endpoint responded successfully (HTTP ${http_code})."
        return 0
    else
        log_warn "Endpoint responded with HTTP ${http_code} or timed out."
        if [[ "$access_method" == "public-ip" ]]; then
            log_warn "If you cannot open ${url} in your browser, ensure that Inbound Port 5678 is allowed in your AWS EC2 Security Group."
        else
            log_warn "Ensure Ports 80 and 443 are allowed in your AWS EC2 Security Group and DNS has propagated."
        fi
        return 0 # Do not fail whole installer since AWS Security Groups are external to host
    fi
}

run_deployment_verification() {
    print_section "Step 4: Installation Verification"

    if [[ "${SELECTED_DB_PROVIDER:-ec2-postgres}" == "ec2-postgres" ]]; then
        if ! verify_postgres_health "$INSTALL_DIR"; then
            return 1
        fi
    fi

    if ! verify_n8n_health "$INSTALL_DIR"; then
        return 1
    fi

    if [[ "${SELECTED_ACCESS_METHOD:-public-ip}" == "custom-domain" ]]; then
        verify_proxy_health "$INSTALL_DIR"
    fi

    verify_public_endpoint "$INSTALL_DIR"

    # Display Final Success Screen
    local display_url=""
    if [[ "${SELECTED_ACCESS_METHOD:-public-ip}" == "custom-domain" ]]; then
        display_url="https://${DEPLOY_DOMAIN}"
    else
        display_url="http://${EC2_PUBLIC_IP}:${N8N_HOST_PORT:-5678}"
    fi

    echo ""
    echo -e "${COLOR_GREEN}${COLOR_BOLD}================================================================${COLOR_RESET}"
    echo -e "${COLOR_WHITE}${COLOR_BOLD}                   DEPLOYMENT SUCCESSFUL!                       ${COLOR_RESET}"
    echo -e "${COLOR_GREEN}${COLOR_BOLD}================================================================${COLOR_RESET}"
    echo ""
    echo -e "  ${COLOR_BOLD}n8n Access URL:${COLOR_RESET}        ${COLOR_CYAN}${COLOR_BOLD}${display_url}${COLOR_RESET}"
    echo -e "  ${COLOR_BOLD}Deployment Directory:${COLOR_RESET}  ${COLOR_WHITE}${INSTALL_DIR}/${COLOR_RESET}"
    echo -e "  ${COLOR_BOLD}Management Command:${COLOR_RESET}    ${COLOR_YELLOW}sudo ${INSTALL_DIR}/manage.sh${COLOR_RESET}"
    echo ""
    if [[ "${SELECTED_ACCESS_METHOD:-public-ip}" == "public-ip" ]]; then
        echo -e "  ${COLOR_YELLOW}AWS Security Group Reminder:${COLOR_RESET}"
        echo -e "  Ensure ${COLOR_BOLD}TCP port 5678${COLOR_RESET} is allowed inbound from your IP in your EC2 Security Group."
        echo ""
    else
        echo -e "  ${COLOR_YELLOW}AWS Security Group Reminder:${COLOR_RESET}"
        echo -e "  Ensure ${COLOR_BOLD}TCP ports 80 and 443${COLOR_RESET} are allowed inbound in your EC2 Security Group."
        echo ""
    fi
    echo -e "${COLOR_GREEN}================================================================${COLOR_RESET}"
    echo ""

    return 0
}

