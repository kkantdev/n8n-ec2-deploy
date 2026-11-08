#!/usr/bin/env bash
# ==============================================================================
# Cryptographic Secret Generation & Management
# ==============================================================================

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"

# Generate a strong 32-byte hex encryption key for n8n
# Matches n8n N8N_ENCRYPTION_KEY standard
generate_n8n_encryption_key() {
    local key=""
    if command_exists openssl; then
        key=$(openssl rand -hex 32 2>/dev/null)
    fi

    if [[ -z "$key" || ${#key} -lt 64 ]]; then
        # Fallback to /dev/urandom
        key=$(od -vN 32 -An -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
    fi

    if [[ ${#key} -lt 64 ]]; then
        log_error "Failed to generate cryptographically secure n8n encryption key."
        return 1
    fi

    echo "$key"
}

# Generate a strong random alphanumeric database password
generate_random_password() {
    local length="${1:-32}"
    local password=""

    if command_exists openssl; then
        password=$(openssl rand -base64 48 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c "$length")
    fi

    if [[ -z "$password" || ${#password} -lt "$length" ]]; then
        # Fallback using /dev/urandom
        password=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length")
    fi

    if [[ ${#password} -lt "$length" ]]; then
        log_error "Failed to generate cryptographically secure database password."
        return 1
    fi

    echo "$password"
}

# Extract an existing key from an existing .env file to prevent key rotation
get_existing_secret() {
    local env_file="$1"
    local key_name="$2"

    if [[ -f "$env_file" ]]; then
        local value
        value=$(grep -E "^${key_name}=" "$env_file" | head -n 1 | cut -d= -f2- | tr -d '"\r\n')
        if [[ -n "$value" ]]; then
            echo "$value"
            return 0
        fi
    fi
    return 1
}

