#!/usr/bin/env bash
# ==============================================================================
# System & Pre-flight Environment Checks
# ==============================================================================

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../config/defaults.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/validation.sh"

# Verify Ubuntu OS distribution & supported release version
check_os() {
    log_step "Checking operating system compatibility..."

    if [[ ! -f /etc/os-release ]]; then
        log_error "Operating system could not be identified (/etc/os-release missing)."
        log_error "This installer targets Ubuntu Server (22.04 LTS or 24.04 LTS)."
        return 1
    fi

    # Read os-release
    local os_id=""
    local version_id=""
    os_id=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    version_id=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')

    if [[ "$os_id" != "ubuntu" ]]; then
        log_error "Unsupported Linux distribution: '${os_id}'."
        log_error "This installer is specifically optimized and tested for Ubuntu Server."
        return 1
    fi

    # Supported Ubuntu versions: 20.04, 22.04, 24.04
    case "$version_id" in
        "22.04"|"24.04"|"20.04")
            log_success "Operating system verified: Ubuntu ${version_id} LTS"
            return 0
            ;;
        *)
            log_warn "Detected Ubuntu ${version_id}. The recommended and tested versions are 22.04 LTS or 24.04 LTS."
            if prompt_yes_no "Do you want to proceed anyway?" "N"; then
                return 0
            else
                return 1
            fi
            ;;
    esac
}

# Verify CPU Architecture
check_architecture() {
    log_step "Checking CPU architecture..."
    local arch
    arch="$(uname -m)"

    case "$arch" in
        x86_64|amd64)
            log_success "Architecture verified: ${arch} (64-bit x86)"
            return 0
            ;;
        aarch64|arm64)
            log_success "Architecture verified: ${arch} (64-bit ARM / AWS Graviton)"
            return 0
            ;;
        *)
            log_error "Unsupported CPU architecture: ${arch}."
            log_error "Official n8n and PostgreSQL Docker images require x86_64 or aarch64."
            return 1
            ;;
    esac
}

# Verify Available Disk Space
check_disk_space() {
    log_step "Checking available disk space..."

    local target_mount="/opt"
    if [[ ! -d "/opt" ]]; then
        target_mount="/"
    fi

    local available_mb
    available_mb=$(df -BM "$target_mount" | awk 'NR==2 {gsub("M","",$4); print $4}')

    if [[ -z "$available_mb" || ! "$available_mb" =~ ^[0-9]+$ ]]; then
        log_warn "Could not reliably determine free disk space on ${target_mount}. Proceeding cautiously."
        return 0
    fi

    if (( available_mb < MIN_DISK_SPACE_MB )); then
        log_error "Insufficient disk space: ${available_mb} MB available, but at least ${MIN_DISK_SPACE_MB} MB is required."
        log_error "Please resize your EC2 EBS root volume or free up space before continuing."
        return 1
    fi

    log_success "Available disk space: ${available_mb} MB (Minimum required: ${MIN_DISK_SPACE_MB} MB)"
    return 0
}

# Verify Memory (RAM)
check_memory() {
    log_step "Checking available system memory (RAM)..."

    local total_ram_mb
    total_ram_mb=$(free -m | awk '/^Mem:/{print $2}')

    if [[ -n "$total_ram_mb" && "$total_ram_mb" =~ ^[0-9]+$ ]]; then
        if (( total_ram_mb < MIN_RAM_MB )); then
            log_warn "System memory is ${total_ram_mb} MB (less than recommended ${MIN_RAM_MB} MB)."
            log_warn "n8n and PostgreSQL work best on t3.small, t4g.small (2GB RAM) or larger instances."
            log_warn "If running on t2.micro / t3.micro (1GB RAM), ensure swap is enabled to prevent OOM kills."
        else
            log_success "System memory verified: ${total_ram_mb} MB RAM"
        fi
    fi
    return 0
}

# Check if a specific network port is in use
is_port_in_use() {
    local port="$1"

    if command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -qE "(:|^)${port}[[:space:]]"; then
            return 0
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -qE "(:|^)${port}[[:space:]]"; then
            return 0
        fi
    elif command -v lsof >/dev/null 2>&1; then
        if lsof -iTCP:"${port}" -sTCP:LISTEN -P -n >/dev/null 2>&1; then
            return 0
        fi
    fi

    return 1 # Port appears free
}

# Verify required ports are available
check_port_availability() {
    local port="$1"
    local service_desc="$2"

    if is_port_in_use "$port"; then
        log_error "Port ${port} (${service_desc}) is already in use by another process on this server."
        echo -e "Use ${COLOR_YELLOW}sudo ss -tulnp | grep :${port}${COLOR_RESET} to inspect the conflicting process."
        return 1
    fi

    return 0
}

# Check Internet Connectivity
check_internet_connectivity() {
    log_step "Checking outbound internet connectivity..."

    local test_urls=("https://registry-1.docker.io" "https://archive.ubuntu.com" "https://1.1.1.1")
    local connected=0

    for url in "${test_urls[@]}"; do
        if curl -s -f -m 5 --head "$url" >/dev/null 2>&1; then
            connected=1
            break
        fi
    done

    if [[ $connected -eq 1 ]]; then
        log_success "Internet connectivity verified."
        return 0
    else
        log_error "Internet connectivity check failed."
        log_error "Your EC2 instance cannot connect to external services."
        log_error "Ensure your EC2 instance is in a public subnet with an Internet Gateway, or has a working NAT Gateway."
        return 1
    fi
}

# Detect AWS EC2 Public IPv4 Address
detect_ec2_public_ip() {
    local detected_ip=""

    # 1. Try AWS IMDSv2 (Session token)
    local token
    token=$(curl -s -f -m 2 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)
    if [[ -n "$token" ]]; then
        detected_ip=$(curl -s -f -m 2 -H "X-aws-ec2-metadata-token: $token" "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || true)
    fi

    # 2. Try AWS IMDSv1
    if [[ -z "$detected_ip" ]] || ! validate_ipv4 "$detected_ip"; then
        detected_ip=$(curl -s -f -m 2 "http://169.254.169.254/latest/meta-data/public-ipv4" 2>/dev/null || true)
    fi

    # 3. Fallback to external IP discovery services
    if [[ -z "$detected_ip" ]] || ! validate_ipv4 "$detected_ip"; then
        detected_ip=$(curl -s -f -4 -m 3 "https://api.ipify.org" 2>/dev/null || true)
    fi
    if [[ -z "$detected_ip" ]] || ! validate_ipv4 "$detected_ip"; then
        detected_ip=$(curl -s -f -4 -m 3 "https://ifconfig.me" 2>/dev/null || true)
    fi
    if [[ -z "$detected_ip" ]] || ! validate_ipv4 "$detected_ip"; then
        detected_ip=$(curl -s -f -4 -m 3 "https://icanhazip.com" | tr -d '[:space:]' 2>/dev/null || true)
    fi

    if validate_ipv4 "$detected_ip"; then
        EC2_PUBLIC_IP="$detected_ip"
        log_success "Detected EC2 Public IPv4: ${detected_ip}"
        return 0
    else
        log_warn "Could not automatically detect the EC2 Public IPv4 address."
        return 1
    fi
}

# Run all core system requirement checks
run_system_checks() {
    print_section "Step 2: System Requirements Verification"

    check_os || return 1
    check_architecture || return 1
    check_disk_space || return 1
    check_memory || return 1
    check_internet_connectivity || return 1

    # Detect public IP
    if ! detect_ec2_public_ip; then
        while true; do
            local user_ip
            user_ip=$(prompt_input "Please enter this EC2 instance's Public IPv4 address")
            if validate_ipv4 "$user_ip"; then
                EC2_PUBLIC_IP="$user_ip"
                break
            else
                log_error "Invalid IPv4 address format. Please try again."
            fi
        done
    fi

    return 0
}

