#!/usr/bin/env bash
# ==============================================================================
# Database Provider: EC2 Local PostgreSQL (Containerized)
# ==============================================================================

# Ensure directory context
if [[ -z "${PROJECT_ROOT:-}" || -z "${LIB_DIR:-}" ]]; then
    _DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${_DIR}/../.." && pwd)}"
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
load_lib "${LIB_DIR}/secrets.sh"

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
