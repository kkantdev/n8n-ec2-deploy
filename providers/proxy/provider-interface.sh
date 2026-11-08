#!/usr/bin/env bash
# ==============================================================================
# Reverse Proxy Provider Interface Definition
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
    PROVIDERS_DIR="${PROVIDERS_DIR:-${PROJECT_ROOT}/providers}"
    export PROVIDERS_DIR
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

# Load a reverse proxy provider dynamically
load_proxy_provider() {
    local provider="$1"
    local provider_dir="${PROVIDERS_DIR}/proxy/${provider}"

    if [[ ! -d "$provider_dir" ]]; then
        log_error "Reverse proxy provider '${provider}' does not exist at ${provider_dir}."
        return 1
    fi

    local install_script="${provider_dir}/install.sh"
    local configure_script="${provider_dir}/configure.sh"

    load_lib "$configure_script"
    load_lib "$install_script"

    export CURRENT_PROXY_PROVIDER="$provider"
    log_info "Loaded reverse proxy provider: ${provider}"
    return 0
}
