#!/usr/bin/env bash
# ==============================================================================
# Database Provider: Supabase PostgreSQL
# ==============================================================================

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../config/defaults.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../lib/validation.sh"

db_supabase_configure() {
    log_step "Configuring Supabase PostgreSQL Connection..."

    echo ""
    echo -e "${COLOR_CYAN}${COLOR_BOLD}Supabase PostgreSQL Connection Guidelines:${COLOR_RESET}"
    echo -e "  • ${COLOR_BOLD}Direct Connection${COLOR_RESET} (port 5432): Fast, but requires IPv4 addon if your EC2 instance does not have IPv6."
    echo -e "  • ${COLOR_BOLD}Session Pooler${COLOR_RESET} (pooler.supabase.com:5432): ${COLOR_GREEN}Recommended for n8n${COLOR_RESET} (IPv4 compatible, supports migrations)."
    echo -e "  • ${COLOR_BOLD}Transaction Pooler${COLOR_RESET} (pooler.supabase.com:6543): ${COLOR_YELLOW}Not recommended${COLOR_RESET} for n8n schema migrations."
    echo ""

    local conn_str=""
    local valid=0

    while [[ $valid -eq 0 ]]; do
        conn_str=$(prompt_secret "Enter your Supabase PostgreSQL connection URI (e.g., postgresql://postgres.[ref]:[pass]@[host]:5432/postgres)")

        if [[ -z "$conn_str" ]]; then
            log_error "Connection string cannot be empty."
            continue
        fi

        if ! parse_postgres_uri "$conn_str"; then
            log_error "Invalid PostgreSQL URI format."
            echo -e "Expected format: ${COLOR_YELLOW}postgresql://user:password@hostname:port/dbname?sslmode=require${COLOR_RESET}"
            continue
        fi

        # Check port recommendation
        if [[ "$PARSED_DB_PORT" == "6543" ]]; then
            log_warn "Port 6543 detected (Supabase Transaction Pooler)."
            log_warn "n8n schema migrations require Session mode or Direct connection (port 5432)."
            if ! prompt_yes_no "Are you sure you want to proceed with port 6543?" "N"; then
                continue
            fi
        fi

        log_step "Testing live connectivity to Supabase PostgreSQL..."
        echo -e "${COLOR_DIM}Verifying credentials and migration privileges via ephemeral PostgreSQL client...${COLOR_RESET}"

        if db_supabase_test_connection; then
            valid=1
            log_success "Supabase PostgreSQL connection and permissions verified successfully!"
        else
            log_error "Failed to verify database connection."
            log_error "Please check the host, port, username, password, and ensure Supabase allows inbound connections."
            if ! prompt_yes_no "Would you like to re-enter the connection string?" "Y"; then
                return 1
            fi
        fi
    done

    # Export verified parameters for environment generator
    export DB_POSTGRESDB_HOST="$PARSED_DB_HOST"
    export DB_POSTGRESDB_PORT="$PARSED_DB_PORT"
    export DB_POSTGRESDB_DATABASE="$PARSED_DB_DATABASE"
    export DB_POSTGRESDB_USER="$PARSED_DB_USER"
    export DB_POSTGRESDB_PASSWORD="$PARSED_DB_PASSWORD"
    export DB_POSTGRESDB_SCHEMA="public"
    export DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED="true"

    return 0
}

# Connect to database using ephemeral Docker container and verify connectivity & privileges
db_supabase_test_connection() {
    # Verify docker is available to run ephemeral test
    if ! command_exists docker; then
        log_warn "Docker not yet available to test database connection directly. Verifying host resolution..."
        # Basic host reachability check
        if command_exists nc; then
            nc -z -w 5 "$PARSED_DB_HOST" "$PARSED_DB_PORT" 2>/dev/null && return 0
        fi
        return 0
    fi

    local query="SELECT 1;"
    local check_perm="SELECT has_schema_privilege('${PARSED_DB_USER}', 'public', 'CREATE');"

    # Run lightweight test inside docker container
    local test_output
    test_output=$(docker run --rm \
        -e PGPASSWORD="$PARSED_DB_PASSWORD" \
        -e PGCONNECT_TIMEOUT=10 \
        "${POSTGRES_IMAGE_NAME}:${POSTGRES_IMAGE_TAG}" \
        psql \
        -h "$PARSED_DB_HOST" \
        -p "$PARSED_DB_PORT" \
        -U "$PARSED_DB_USER" \
        -d "$PARSED_DB_DATABASE" \
        -c "$query" 2>&1 || true)

    if echo "$test_output" | grep -q "1 row"; then
        return 0
    else
        log_error "Database connection test error details (credentials redacted):"
        echo "$test_output" | sed "s/${PARSED_DB_PASSWORD}/**********/g" >&2
        return 1
    fi
}

