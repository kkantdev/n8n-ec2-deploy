#!/usr/bin/env bash
# ==============================================================================
# Common Helper Functions & Logging Utilities
# ==============================================================================

# Source colors if not already defined
if [[ -z "${COLOR_RESET:-}" ]]; then
    _LIB_DIR="${LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    if [[ -f "${_LIB_DIR}/colors.sh" ]]; then
        # shellcheck source=/dev/null
        source "${_LIB_DIR}/colors.sh"
    fi
    unset _LIB_DIR
fi

# Loggers
log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"
}

log_success() {
    echo -e "${COLOR_GREEN}[✓ SUCCESS]${COLOR_RESET} $*"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[⚠ WARNING]${COLOR_RESET} $*"
}

log_error() {
    echo -e "${COLOR_RED}[✖ ERROR]${COLOR_RESET} $*" >&2
}

log_step() {
    echo -e "${COLOR_CYAN}[→]${COLOR_RESET} ${COLOR_BOLD}$*${COLOR_RESET}"
}

# Command existence check
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Root/Sudo privilege verification
ensure_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be executed with root privileges."
        echo -e "Please run with sudo: ${COLOR_YELLOW}sudo $0${COLOR_RESET}"
        exit 1
    fi
}

# Prompt user for text input with default value
# Prompts are emitted to stderr so command substitution captures only the entered value.
prompt_input() {
    local prompt_msg="$1"
    local default_val="${2:-}"
    local user_val=""

    if [[ -n "$default_val" ]]; then
        echo -ne "${COLOR_BOLD}${prompt_msg}${COLOR_RESET} [${COLOR_CYAN}${default_val}${COLOR_RESET}]: " >&2
    else
        echo -ne "${COLOR_BOLD}${prompt_msg}${COLOR_RESET}: " >&2
    fi

    # Read user input safely without terminating under set -e on EOF
    if ! IFS= read -r user_val; then
        user_val="$default_val"
    fi

    # Strip carriage return (\r) and trim leading/trailing whitespace
    user_val=$(echo "$user_val" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    if [[ -z "$user_val" ]]; then
        echo "$default_val"
    else
        echo "$user_val"
    fi
}

# Prompt user for sensitive input without echoing to terminal
prompt_secret() {
    local prompt_msg="$1"
    local secret_val=""

    echo -ne "${COLOR_BOLD}${prompt_msg}${COLOR_RESET} (input hidden): " >&2
    if ! IFS= read -r -s secret_val; then
        secret_val=""
    fi
    echo "" >&2

    # Strip carriage return (\r)
    secret_val=$(echo "$secret_val" | tr -d '\r')
    echo "$secret_val"
}

# Prompt Yes/No confirmation (default choice: Y or N)
prompt_yes_no() {
    local question="$1"
    local default_choice="${2:-Y}" # Y or N
    local prompt_str="[Y/n]"
    [[ "$default_choice" =~ ^[Nn]$ ]] && prompt_str="[y/N]"
    local choice=""

    while true; do
        echo -ne "${COLOR_BOLD}${question}${COLOR_RESET} ${COLOR_CYAN}${prompt_str}${COLOR_RESET}: " >&2
        if ! IFS= read -r choice; then
            choice="$default_choice"
        fi

        choice=$(echo "$choice" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        choice="${choice:-$default_choice}"

        case "$choice" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo -e "${COLOR_YELLOW}Please answer yes (y) or no (n).${COLOR_RESET}" >&2 ;;
        esac
    done
}

# Clean exit handling
cleanup_temp_files() {
    local tmp_dir="${TEMP_WORK_DIR:-}"
    if [[ -n "$tmp_dir" && -d "$tmp_dir" ]]; then
        rm -rf "$tmp_dir"
    fi
}

setup_interrupt_trap() {
    trap 'echo ""; log_warn "Operation interrupted by user. Exiting..."; cleanup_temp_files; exit 130' INT TERM
}
