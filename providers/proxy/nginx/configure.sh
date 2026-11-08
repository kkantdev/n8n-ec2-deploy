#!/usr/bin/env bash
# ==============================================================================
# Nginx Proxy Configuration & Validation Logic
# ==============================================================================

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../config/defaults.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/validation.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../lib/system-checks.sh"

nginx_validate_prerequisites() {
    log_step "Checking port availability for Nginx (ports 80 and 443)..."

    if ! check_port_availability 80 "HTTP / Nginx"; then
        return 1
    fi
    if ! check_port_availability 443 "HTTPS / Nginx"; then
        return 1
    fi

    log_success "Ports 80 and 443 are available for Nginx."
    return 0
}

nginx_prompt_config() {
    print_section "Nginx Domain & SSL Configuration"

    # Domain Prompt
    local domain=""
    while true; do
        domain=$(prompt_input "Enter your fully qualified domain name (e.g., automation.example.com)")

        if ! validate_domain "$domain"; then
            log_error "Invalid domain format. Do not include http://, https://, or slashes."
            continue
        fi

        log_step "Verifying DNS A record for '${domain}'..."
        echo -e "${COLOR_DIM}Checking that '${domain}' resolves to EC2 Public IP (${EC2_PUBLIC_IP})...${COLOR_RESET}"

        local dns_status=0
        validate_dns_resolution "$domain" "$EC2_PUBLIC_IP" || dns_status=$?

        if [[ $dns_status -eq 0 ]]; then
            log_success "DNS verified! '${domain}' resolves correctly to ${EC2_PUBLIC_IP}."
            break
        elif [[ $dns_status -eq 1 ]]; then
            log_warn "No DNS A record found for '${domain}'."
            echo -e "${COLOR_YELLOW}Let's Encrypt will fail to issue an SSL certificate if DNS is not yet pointing to this EC2 instance.${COLOR_RESET}"
            echo -e "Action required: In your DNS provider (e.g., Cloudflare, Route53, GoDaddy), add:"
            echo -e "   ${COLOR_BOLD}Type:${COLOR_RESET} A"
            echo -e "   ${COLOR_BOLD}Name:${COLOR_RESET} ${domain}"
            echo -e "   ${COLOR_BOLD}Value:${COLOR_RESET} ${EC2_PUBLIC_IP}"
            echo -e "   ${COLOR_BOLD}TTL:${COLOR_RESET} Auto or 300 seconds"
            echo ""
            if prompt_yes_no "Do you want to re-check DNS?" "Y"; then
                continue
            fi
            if ! prompt_yes_no "Proceed anyway without verified DNS? (Certbot SSL issuance may fail)" "N"; then
                continue
            fi
            break
        else
            log_warn "DNS mismatch: '${domain}' resolves to [${RESOLVED_DNS_IPS[*]}], not ${EC2_PUBLIC_IP}."
            echo -e "Please update your DNS A record to point to this EC2 instance (${EC2_PUBLIC_IP})."
            if prompt_yes_no "Do you want to re-check DNS?" "Y"; then
                continue
            fi
            if ! prompt_yes_no "Proceed anyway despite DNS mismatch?" "N"; then
                continue
            fi
            break
        fi
    done

    # Email Prompt for Let's Encrypt expiration notifications
    local email=""
    while true; do
        email=$(prompt_input "Enter email for Let's Encrypt SSL notifications")
        if validate_email "$email"; then
            break
        else
            log_error "Invalid email address format. Please enter a valid email."
        fi
    done

    export DEPLOY_DOMAIN="$domain"
    export DEPLOY_HOST="$domain"
    export DEPLOY_PROTOCOL="https"
    export DEPLOY_PORT="443"
    export DEPLOY_SSL_EMAIL="$email"

    return 0
}

nginx_generate_config() {
    local target_dir="${1:-$INSTALL_DIR}"
    local proxy_dir="${target_dir}/proxy"
    local nginx_conf_dir="${proxy_dir}/nginx/conf.d"
    local certbot_conf_dir="${proxy_dir}/certbot/conf"
    local certbot_www_dir="${proxy_dir}/certbot/www"

    log_step "Generating Nginx reverse proxy configuration..."

    mkdir -p "$nginx_conf_dir"
    mkdir -p "$certbot_conf_dir"
    mkdir -p "$certbot_www_dir"

    # Copy docker-compose.yml for proxy
    local compose_src="${SCRIPT_DIR}/docker-compose.yml"
    cp "$compose_src" "${proxy_dir}/docker-compose.yml"

    # Process n8n.conf template
    local template_file="${SCRIPT_DIR}/../../../templates/nginx/n8n.conf"
    local target_conf="${nginx_conf_dir}/n8n.conf"

    sed "s/__DOMAIN_NAME__/${DEPLOY_DOMAIN}/g" "$template_file" > "$target_conf"

    log_success "Nginx configuration files generated in: ${proxy_dir}"
    return 0
}

