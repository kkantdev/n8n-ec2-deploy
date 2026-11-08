#!/usr/bin/env bash
# ==============================================================================
# Database Provider: EC2 Local PostgreSQL (Containerized)
# ==============================================================================

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../config/defaults.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../lib/secrets.sh"

db_ec2_postgres_configure() {
    log_step "Configuring local PostgreSQL on EC2..."

    export DB_POSTGRESDB_HOST="postgres"
    export DB_POSTGRESDB_PORT="5432"
    export DB_POSTGRESDB_DATABASE="n8n"
    export DB_POSTGRESDB_USER="n8n"
    export DB_POSTGRESDB_SCHEMA="public"
    export DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED="false"

    # Retain existing password if present in existing .env
    local existing_pass
    existing_pass=$(get_existing_secret "${INSTALL_DIR}/.env" "DB_POSTGRESDB_PASSWORD" || true)

    if [[ -n "$existing_pass" ]]; then
        export DB_POSTGRESDB_PASSWORD="$existing_pass"
        log_info "Retained existing PostgreSQL password from previous configuration."
    else
        export DB_POSTGRESDB_PASSWORD="$(generate_random_password 32)"
        log_success "Generated strong random PostgreSQL password."
    fi

    # Create local directory for persistent postgres storage with secure permissions
    mkdir -p "${INSTALL_DIR}/postgres/data"
    chmod 700 "${INSTALL_DIR}/postgres/data"

    log_success "Local EC2 PostgreSQL configuration completed."
    return 0
}

