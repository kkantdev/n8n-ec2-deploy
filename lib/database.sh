#!/usr/bin/env bash
# ==============================================================================
# Database Provider Dispatcher & Configuration
# ==============================================================================

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../config/defaults.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../providers/database/ec2-postgres.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../providers/database/supabase.sh"

prompt_database_selection() {
    print_section "Step 3: Database Selection"

    echo -e "Choose the database for your n8n workflows and credential storage:\n"
    echo -e "  ${COLOR_CYAN}[1]${COLOR_RESET} ${COLOR_BOLD}PostgreSQL on this EC2 server${COLOR_RESET} (Recommended / Default)"
    echo -e "      ${COLOR_DIM}• Self-contained official PostgreSQL Docker container${COLOR_RESET}"
    echo -e "      ${COLOR_DIM}• High performance, zero extra monthly cloud database costs${COLOR_RESET}"
    echo -e "      ${COLOR_DIM}• Automated credentials, isolated on internal Docker network${COLOR_RESET}"
    echo ""
    echo -e "  ${COLOR_CYAN}[2]${COLOR_RESET} ${COLOR_BOLD}Existing Supabase PostgreSQL database${COLOR_RESET}"
    echo -e "      ${COLOR_DIM}• Connect to managed Supabase cloud database instance${COLOR_RESET}"
    echo -e "      ${COLOR_DIM}• Uses SSL connection string; verifies credentials before install${COLOR_RESET}"
    echo ""

    local choice
    while true; do
        choice=$(prompt_input "Enter database choice [1 or 2]" "1")
        case "$choice" in
            1)
                export SELECTED_DB_PROVIDER="ec2-postgres"
                db_ec2_postgres_configure || return 1
                break
                ;;
            2)
                export SELECTED_DB_PROVIDER="supabase"
                db_supabase_configure || return 1
                break
                ;;
            *)
                log_error "Invalid selection. Please choose 1 or 2."
                ;;
        esac
    done

    return 0
}

