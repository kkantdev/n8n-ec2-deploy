#!/usr/bin/env bash
# ==============================================================================
# Nginx Proxy Lifecycle & SSL Issuance Logic
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

nginx_install() {
    local target_dir="${1:-$INSTALL_DIR}"
    local proxy_dir="${target_dir}/proxy"
    local cert_dir="${proxy_dir}/certbot/conf/live/${DEPLOY_DOMAIN}"

    log_step "Initializing Nginx and Let's Encrypt SSL certificates..."

    # Ensure proxy network exists
    docker network create "${DOCKER_PROXY_NETWORK}" >/dev/null 2>&1 || true

    # Check if a valid certificate already exists
    if [[ -f "${cert_dir}/fullchain.pem" && -f "${cert_dir}/privkey.pem" ]]; then
        log_success "Existing SSL certificate found for ${DEPLOY_DOMAIN}."
        nginx_start "$target_dir"
        return 0
    fi

    log_step "Generating temporary bootstrap certificate to initialize Nginx..."
    mkdir -p "${cert_dir}"
    if command_exists openssl; then
        openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
            -keyout "${cert_dir}/privkey.pem" \
            -out "${cert_dir}/fullchain.pem" \
            -subj "/CN=localhost" >/dev/null 2>&1 || true
    fi

    log_step "Starting Nginx in bootstrap mode for ACME HTTP challenge..."
    docker compose -f "${proxy_dir}/docker-compose.yml" up -d nginx

    sleep 3

    log_step "Requesting official Let's Encrypt certificate for ${DEPLOY_DOMAIN}..."
    local certbot_status=0
    docker compose -f "${proxy_dir}/docker-compose.yml" run --rm certbot certonly \
        --webroot -w /var/www/certbot \
        -d "${DEPLOY_DOMAIN}" \
        --email "${DEPLOY_SSL_EMAIL}" \
        --rsa-key-size 4096 \
        --agree-tos \
        --non-interactive \
        --no-eff-email || certbot_status=$?

    if [[ $certbot_status -eq 0 && -f "${cert_dir}/fullchain.pem" ]]; then
        log_success "Let's Encrypt certificate successfully acquired for ${DEPLOY_DOMAIN}!"
        log_step "Reloading Nginx with production TLS certificate..."
        docker compose -f "${proxy_dir}/docker-compose.yml" exec nginx nginx -s reload >/dev/null 2>&1 || true
        # Start certbot renewal daemon
        docker compose -f "${proxy_dir}/docker-compose.yml" up -d certbot
        return 0
    else
        log_warn "Certbot could not obtain a Let's Encrypt certificate at this moment."
        log_warn "Possible reasons:"
        log_warn " 1. DNS A record for ${DEPLOY_DOMAIN} has not yet propagated."
        log_warn " 2. AWS Security Group does not allow inbound TCP port 80."
        log_warn "Nginx will continue running with a temporary self-signed certificate."
        log_info "To re-run SSL acquisition later, run:"
        echo -e "${COLOR_YELLOW}sudo ${INSTALL_DIR}/manage.sh${COLOR_RESET} (or certbot retry command)"
        return 0
    fi
}

nginx_start() {
    local target_dir="${1:-$INSTALL_DIR}"
    local proxy_dir="${target_dir}/proxy"
    docker compose -f "${proxy_dir}/docker-compose.yml" up -d
}

nginx_stop() {
    local target_dir="${1:-$INSTALL_DIR}"
    local proxy_dir="${target_dir}/proxy"
    docker compose -f "${proxy_dir}/docker-compose.yml" down
}

nginx_status() {
    local target_dir="${1:-$INSTALL_DIR}"
    local proxy_dir="${target_dir}/proxy"
    docker compose -f "${proxy_dir}/docker-compose.yml" ps
}

nginx_logs() {
    local target_dir="${1:-$INSTALL_DIR}"
    local proxy_dir="${target_dir}/proxy"
    docker compose -f "${proxy_dir}/docker-compose.yml" logs -f --tail=100 "$@"
}
