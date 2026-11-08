#!/usr/bin/env bash
# ==============================================================================
# Reverse Proxy Provider Interface Definition
# ==============================================================================

# Every proxy provider (Nginx, Traefik, etc.) must implement the following functions:
# - <provider>_validate_prerequisites
# - <provider>_prompt_config
# - <provider>_generate_config
# - <provider>_install
# - <provider>_start
# - <provider>_stop
# - <provider>_status
# - <provider>_logs

# Load a reverse proxy provider dynamically
load_proxy_provider() {
    local provider="$1"
    local provider_dir="${SCRIPT_DIR}/../providers/proxy/${provider}"

    if [[ ! -d "$provider_dir" ]]; then
        log_error "Reverse proxy provider '${provider}' does not exist."
        return 1
    fi

    local install_script="${provider_dir}/install.sh"
    local configure_script="${provider_dir}/configure.sh"

    if [[ ! -f "$install_script" || ! -f "$configure_script" ]]; then
        log_error "Proxy provider '${provider}' is missing required scripts."
        return 1
    fi

    # shellcheck source=/dev/null
    source "$configure_script"
    # shellcheck source=/dev/null
    source "$install_script"

    export CURRENT_PROXY_PROVIDER="$provider"
    log_info "Loaded reverse proxy provider: ${provider}"
    return 0
}

