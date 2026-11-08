#!/usr/bin/env bash
# ==============================================================================
# Environment Configuration Manager (.env)
# ==============================================================================

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../config/defaults.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/secrets.sh"

# Backup existing environment file with timestamp
backup_env_file() {
    local target_dir="${1:-$INSTALL_DIR}"
    local env_path="${target_dir}/.env"

    if [[ -f "$env_path" ]]; then
        local timestamp
        timestamp="$(date +%Y%m%d_%H%M%S)"
        local backup_path="${env_path}.backup.${timestamp}"
        cp "$env_path" "$backup_path"
        chmod 600 "$backup_path"
        log_info "Existing environment file backed up to: ${backup_path}"
    fi
}

# Write environment file with restrictive permissions (chmod 600)
write_deployment_env() {
    local target_dir="${1:-$INSTALL_DIR}"
    local env_path="${target_dir}/.env"

    mkdir -p "$target_dir"

    # Backup existing if present
    backup_env_file "$target_dir"

    # Retain existing encryption key if present to prevent data invalidation
    local existing_key
    existing_key=$(get_existing_secret "$env_path" "N8N_ENCRYPTION_KEY" || true)
    if [[ -n "$existing_key" ]]; then
        N8N_ENCRYPTION_KEY="$existing_key"
        log_info "Preserved existing N8N_ENCRYPTION_KEY from previous configuration."
    elif [[ -z "${N8N_ENCRYPTION_KEY:-}" ]]; then
        N8N_ENCRYPTION_KEY=$(generate_n8n_encryption_key)
    fi

    # Set default timezone if not set
    GENERIC_TIMEZONE="${GENERIC_TIMEZONE:-$DEFAULT_TIMEZONE}"
    EXECUTIONS_DATA_PRUNE="${EXECUTIONS_DATA_PRUNE:-$DEFAULT_EXECUTIONS_DATA_PRUNE}"
    EXECUTIONS_DATA_MAX_AGE="${EXECUTIONS_DATA_MAX_AGE:-$DEFAULT_EXECUTIONS_DATA_MAX_AGE}"

    # Determine base URLs and proxy hops
    local protocol="${DEPLOY_PROTOCOL:-http}"
    local host="${DEPLOY_HOST:-$EC2_PUBLIC_IP}"
    local port="${DEPLOY_PORT:-5678}"
    local proxy_hops=0
    local webhook_url=""
    local editor_base_url=""

    if [[ "$protocol" == "https" ]]; then
        proxy_hops=1
        webhook_url="https://${host}/"
        editor_base_url="https://${host}/"
    else
        webhook_url="http://${host}:${port}/"
        editor_base_url="http://${host}:${port}/"
    fi

    # Create temporary file to assemble environment safely
    local tmp_env
    tmp_env="$(mktemp)"
    chmod 600 "$tmp_env"

    cat <<EOF > "$tmp_env"
# ==============================================================================
# n8n EC2 Deploy - Generated Environment Configuration
# Generated on: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# ==============================================================================

# Application & Domain Settings
N8N_HOST=${host}
N8N_PORT=5678
N8N_PROTOCOL=${protocol}
WEBHOOK_URL=${webhook_url}
N8N_EDITOR_BASE_URL=${editor_base_url}
N8N_PROXY_HOPS=${proxy_hops}

# Core Security
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}

# Execution & Runtime Settings
GENERIC_TIMEZONE=${GENERIC_TIMEZONE}
EXECUTIONS_DATA_PRUNE=${EXECUTIONS_DATA_PRUNE}
EXECUTIONS_DATA_MAX_AGE=${EXECUTIONS_DATA_MAX_AGE}

# Database Configuration
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=${DB_POSTGRESDB_HOST:-postgres}
DB_POSTGRESDB_PORT=${DB_POSTGRESDB_PORT:-5432}
DB_POSTGRESDB_DATABASE=${DB_POSTGRESDB_DATABASE:-n8n}
DB_POSTGRESDB_USER=${DB_POSTGRESDB_USER:-n8n}
DB_POSTGRESDB_PASSWORD=${DB_POSTGRESDB_PASSWORD}
DB_POSTGRESDB_SCHEMA=${DB_POSTGRESDB_SCHEMA:-public}
DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=${DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED:-true}

# Deployment Metadata
DEPLOYMENT_DATABASE_TYPE=${SELECTED_DB_PROVIDER:-ec2-postgres}
DEPLOYMENT_ACCESS_TYPE=${SELECTED_ACCESS_METHOD:-public-ip}
PROXY_PROVIDER=${SELECTED_PROXY_PROVIDER:-none}
DOMAIN_NAME=${DEPLOY_DOMAIN:-}
SSL_EMAIL=${DEPLOY_SSL_EMAIL:-}
PUBLIC_IPV4=${EC2_PUBLIC_IP:-}
EOF

    # Move into place and enforce 600 permissions
    mv "$tmp_env" "$env_path"
    chmod 600 "$env_path"

    log_success "Environment file created: ${env_path} (permissions: 600)"
}

# Load environment configuration from target directory
load_deployment_env() {
    local target_dir="${1:-$INSTALL_DIR}"
    local env_path="${target_dir}/.env"

    if [[ ! -f "$env_path" ]]; then
        return 1
    fi

    # Read variables safely without shell code execution
    while IFS='=' read -r key val || [[ -n "$key" ]]; do
        # Ignore comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key=$(echo "$key" | tr -d '[:space:]')
        val=$(echo "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')
        if [[ -n "$key" && "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            export "$key"="$val"
        fi
    done < "$env_path"

    return 0
}

