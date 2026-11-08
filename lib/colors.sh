#!/usr/bin/env bash
# ==============================================================================
# Terminal Colors & UI Styling
# ==============================================================================

# Check if stdout is a terminal supporting colors
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    COLOR_RESET="$(tput sgr0)"
    COLOR_BOLD="$(tput bold)"
    COLOR_DIM="$(tput dim 2>/dev/null || echo '')"
    COLOR_RED="$(tput setaf 1)"
    COLOR_GREEN="$(tput setaf 2)"
    COLOR_YELLOW="$(tput setaf 3)"
    COLOR_BLUE="$(tput setaf 4)"
    COLOR_MAGENTA="$(tput setaf 5)"
    COLOR_CYAN="$(tput setaf 6)"
    COLOR_WHITE="$(tput setaf 7)"
else
    # Fallback ANSI escape sequences
    COLOR_RESET="\033[0m"
    COLOR_BOLD="\033[1m"
    COLOR_DIM="\033[2m"
    COLOR_RED="\033[31m"
    COLOR_GREEN="\033[32m"
    COLOR_YELLOW="\033[33m"
    COLOR_BLUE="\033[34m"
    COLOR_MAGENTA="\033[35m"
    COLOR_CYAN="\033[36m"
    COLOR_WHITE="\033[37m"
fi

print_banner() {
    local title="$1"
    echo -e "${COLOR_CYAN}${COLOR_BOLD}================================================================${COLOR_RESET}"
    echo -e "${COLOR_WHITE}${COLOR_BOLD}   ${title}${COLOR_RESET}"
    echo -e "${COLOR_CYAN}${COLOR_BOLD}================================================================${COLOR_RESET}"
}

print_section() {
    local title="$1"
    echo ""
    echo -e "${COLOR_BLUE}${COLOR_BOLD}───▶ ${title} ${COLOR_RESET}"
}

