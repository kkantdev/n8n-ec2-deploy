#!/usr/bin/env bash
# ==============================================================================
# Docker Engine & Docker Compose V2 Verification and Installation
# ==============================================================================

# Ensure directory context
if [[ -z "${PROJECT_ROOT:-}" || -z "${LIB_DIR:-}" ]]; then
    _DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${_DIR}/.." && pwd)}"
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

load_lib "${LIB_DIR}/common.sh"

# Check if Docker is installed and running
check_docker_engine() {
    log_step "Checking Docker Engine..."

    if ! command_exists docker; then
        return 1
    fi

    # Check if docker daemon is reachable
    if ! docker info >/dev/null 2>&1; then
        log_warn "Docker is installed but the Docker daemon is not running or not accessible."
        if command_exists systemctl; then
            log_info "Attempting to start Docker daemon..."
            systemctl start docker >/dev/null 2>&1 || true
            sleep 2
            if docker info >/dev/null 2>&1; then
                log_success "Docker daemon started successfully."
                return 0
            fi
        fi
        return 2 # Docker installed, but daemon not running
    fi

    local docker_ver
    docker_ver="$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"
    log_success "Docker Engine verified: version ${docker_ver}"
    return 0
}

# Check if Docker Compose V2 is available (docker compose)
check_docker_compose_v2() {
    log_step "Checking Docker Compose V2..."

    if ! docker compose version >/dev/null 2>&1; then
        return 1
    fi

    local compose_ver
    compose_ver="$(docker compose version 2>/dev/null | awk '{print $4}' | tr -d 'v,')"
    log_success "Docker Compose V2 verified: version ${compose_ver}"
    return 0
}

# Install Docker Engine on Ubuntu using official Docker repository
install_docker_engine() {
    log_info "Preparing to install official Docker Engine and Compose plugin on Ubuntu..."
    echo -e "${COLOR_YELLOW}This will add Docker's official apt repository and install docker-ce.${COLOR_RESET}"

    if ! prompt_yes_no "Do you want to proceed with Docker installation?" "Y"; then
        log_error "Docker installation cancelled by user. Docker is required to deploy n8n."
        return 1
    fi

    export DEBIAN_FRONTEND=noninteractive

    log_step "Updating package lists and installing prerequisites..."
    apt-get update -y >/dev/null 2>&1 || {
        log_error "Failed to update apt package cache."
        return 1
    }

    apt-get install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1 || {
        log_error "Failed to install prerequisite packages."
        return 1
    }

    log_step "Configuring Docker official GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    if [[ -f /etc/apt/keyrings/docker.gpg ]]; then
        rm -f /etc/apt/keyrings/docker.gpg
    fi
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || {
        log_error "Failed to download and verify Docker GPG key."
        return 1
    }
    chmod a+r /etc/apt/keyrings/docker.gpg

    log_step "Setting up Docker repository..."
    local arch
    arch="$(dpkg --print-architecture)"
    local codename
    codename="$(lsb_release -cs)"
    echo \
      "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    log_step "Installing Docker Engine, CLI, Containerd, and Compose plugin..."
    apt-get update -y >/dev/null 2>&1
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null 2>&1 || {
        log_error "Failed to install Docker packages from apt."
        return 1
    }

    log_step "Enabling and starting Docker service..."
    systemctl enable docker >/dev/null 2>&1 || true
    systemctl start docker >/dev/null 2>&1 || true

    # Add SUDO_USER to docker group if applicable
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        usermod -aG docker "$SUDO_USER" >/dev/null 2>&1 || true
    fi

    if check_docker_engine && check_docker_compose_v2; then
        log_success "Docker Engine and Docker Compose V2 were successfully installed."
        return 0
    else
        log_error "Docker installation finished but health verification failed."
        return 1
    fi
}

# Install missing Compose plugin if Docker Engine exists
install_compose_plugin() {
    log_info "Installing docker-compose-plugin..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null 2>&1
    apt-get install -y docker-compose-plugin >/dev/null 2>&1 || {
        log_error "Failed to install docker-compose-plugin via apt."
        return 1
    }

    if check_docker_compose_v2; then
        log_success "Docker Compose V2 plugin successfully installed."
        return 0
    else
        log_error "Failed to verify Docker Compose V2 after installation."
        return 1
    fi
}

# Verify or setup Docker
ensure_docker_ready() {
    if ! check_docker_engine; then
        install_docker_engine || return 1
    fi

    if ! check_docker_compose_v2; then
        install_compose_plugin || return 1
    fi

    return 0
}
