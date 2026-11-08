#!/usr/bin/env bash
# ==============================================================================
# Deployment Orchestrator & Directory Setup
# ==============================================================================

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../config/defaults.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/environment.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/compose-generator.sh"

prepare_deployment_directories() {
    local target_dir="${1:-$INSTALL_DIR}"
    log_step "Setting up deployment directory structure in ${target_dir}..."

    mkdir -p "${target_dir}"
    mkdir -p "${target_dir}/data/n8n"
    mkdir -p "${target_dir}/logs"

    # Set ownership for n8n data directory to UID 1000:1000 (node user in n8n container)
    chown -R 1000:1000 "${target_dir}/data/n8n" 2>/dev/null || true
    chmod 750 "${target_dir}/data/n8n"

    # If EC2 PostgreSQL is used, prepare postgres storage
    if [[ "${SELECTED_DB_PROVIDER:-ec2-postgres}" == "ec2-postgres" ]]; then
        mkdir -p "${target_dir}/postgres/data"
        chmod 700 "${target_dir}/postgres/data"
    fi

    log_success "Deployment directories created with secure permissions."
    return 0
}

setup_docker_networks() {
    log_step "Configuring Docker networks..."

    # If reverse proxy is selected, create shared external network
    if [[ "${SELECTED_ACCESS_METHOD:-public-ip}" == "custom-domain" ]]; then
        if ! docker network inspect "${DOCKER_PROXY_NETWORK}" >/dev/null 2>&1; then
            docker network create "${DOCKER_PROXY_NETWORK}" >/dev/null 2>&1 || {
                log_error "Failed to create Docker network '${DOCKER_PROXY_NETWORK}'."
                return 1
            }
            log_success "Created Docker network: ${DOCKER_PROXY_NETWORK}"
        fi
    fi

    return 0
}

start_deployment() {
    local target_dir="${1:-$INSTALL_DIR}"
    log_step "Launching Docker containers..."

    cd "$target_dir" || return 1

    # Pull latest specified images
    log_info "Pulling Docker images (this may take 1-2 minutes)..."
    docker compose -f "${target_dir}/docker-compose.yml" pull --quiet

    # Start database and n8n services
    log_info "Starting n8n and dependencies..."
    docker compose -f "${target_dir}/docker-compose.yml" up -d

    # If proxy provider is selected, install and launch proxy
    if [[ "${SELECTED_ACCESS_METHOD:-public-ip}" == "custom-domain" ]]; then
        case "${SELECTED_PROXY_PROVIDER:-none}" in
            nginx)
                nginx_install "$target_dir"
                ;;
            traefik)
                traefik_install "$target_dir"
                ;;
        esac
    fi

    return 0
}

generate_deployment_readme() {
    local target_dir="${1:-$INSTALL_DIR}"
    local readme_path="${target_dir}/README.md"

    local access_url=""
    if [[ "${SELECTED_ACCESS_METHOD:-public-ip}" == "custom-domain" ]]; then
        access_url="https://${DEPLOY_DOMAIN}"
    else
        access_url="http://${EC2_PUBLIC_IP}:${N8N_HOST_PORT:-5678}"
    fi

    cat <<EOF > "$readme_path"
# n8n EC2 Deployment

Deployed on: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Overview
- **Application URL:** ${access_url}
- **Deployment Directory:** ${target_dir}
- **Access Method:** ${SELECTED_ACCESS_METHOD}
- **Database Provider:** ${SELECTED_DB_PROVIDER}
- **Reverse Proxy:** ${SELECTED_PROXY_PROVIDER}

## Management Commands
Manage this n8n instance easily using the management script:
\`\`\`bash
sudo ${target_dir}/manage.sh
\`\`\`

Available management actions:
- Check container status and health
- Start, stop, and restart services
- Stream real-time logs
- Update n8n safely to newer versions
- Perform safe uninstallation

## Persistent Data Locations
- **n8n Workflow Data:** \`${target_dir}/data/n8n\`
EOF

    if [[ "${SELECTED_DB_PROVIDER}" == "ec2-postgres" ]]; then
        cat <<EOF >> "$readme_path"
- **PostgreSQL Database Files:** \`${target_dir}/postgres/data\`
EOF
    fi

    if [[ "${SELECTED_ACCESS_METHOD}" == "custom-domain" ]]; then
        cat <<EOF >> "$readme_path"
- **Reverse Proxy Configuration:** \`${target_dir}/proxy/\`
EOF
    fi

    cat <<EOF >> "$readme_path"

## Security & Secrets
All secrets and credentials are stored securely in \`${target_dir}/.env\` with restrictive \`0600\` file permissions.
Never delete the \`N8N_ENCRYPTION_KEY\` in \`.env\`, as it is required to decrypt saved credentials in your n8n workflows.
EOF

    chmod 644 "$readme_path"
    log_success "Generated deployment documentation in: ${readme_path}"
}

install_management_utilities() {
    local target_dir="${1:-$INSTALL_DIR}"
    local project_root="${SCRIPT_DIR}/.."

    log_step "Installing operational management utilities..."

    # Copy manage.sh and uninstall.sh to installation directory
    cp "${project_root}/manage.sh" "${target_dir}/manage.sh"
    cp "${project_root}/uninstall.sh" "${target_dir}/uninstall.sh"

    chmod +x "${target_dir}/manage.sh"
    chmod +x "${target_dir}/uninstall.sh"

    # Also copy lib, config, providers, and templates directories so manage.sh is fully standalone!
    mkdir -p "${target_dir}/.installer"
    cp -r "${project_root}/lib" "${target_dir}/.installer/"
    cp -r "${project_root}/config" "${target_dir}/.installer/"
    cp -r "${project_root}/providers" "${target_dir}/.installer/"
    cp -r "${project_root}/templates" "${target_dir}/.installer/"

    generate_deployment_readme "$target_dir"
}

