#!/bin/bash
# -------------------------------------------------------------------
# nak.sh - Enhanced Version
# Linux Modding Helper with improved security, error handling, and UX
# -------------------------------------------------------------------

# Script metadata
SCRIPT_VERSION="1.6.0"
SCRIPT_DATE="$(date +%Y-%m-%d)"

# Strict mode for better error handling
set -euo pipefail
IFS=$'\n\t'

# Define script directory to find modules
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LIB_DIR="$SCRIPT_DIR/lib"

# Source only essential modules at startup
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/error.sh"
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/proton.sh"
source "$LIB_DIR/portablepython.sh"
source "$LIB_DIR/vdf.sh"
source "$LIB_DIR/mo2download.sh"
source "$LIB_DIR/sky-tex-opti.sh"
source "$LIB_DIR/vortex.sh"

# Source game modules
source "$LIB_DIR/games/games.sh"
source "$LIB_DIR/games/fallout.sh"
source "$LIB_DIR/games/enderal.sh"
source "$LIB_DIR/games/bg3.sh"

# Source TTW modules
source "$LIB_DIR/ttw/hoolamike.sh"
source "$LIB_DIR/ttw/installation.sh"

source "$LIB_DIR/core.sh"

# Enhanced initialization
initialize_script() {
    push_error_context "Script Initialization"

    # Setup logging first
    setup_logging
    log_info "Starting NaK version $SCRIPT_VERSION"

    # Create default config
    create_default_config
    load_cached_values

    # Check bash version
    if [ "${BASH_VERSION%%.*}" -lt 4 ]; then
        error_exit "This script requires Bash 4.0 or higher. Current version: $BASH_VERSION"
    fi

    # Check critical dependencies early
    if ! check_critical_dependencies; then
        error_exit "Critical dependencies are missing. Cannot continue."
    fi

    # Log system information
    log_system_info

    # Set up signal handlers
    trap 'handle_interrupt' INT TERM
    trap 'cleanup' EXIT

    # Initialize operation cache
    OPERATION_CACHE=()

    pop_error_context
}

# Check only critical dependencies at startup
check_critical_dependencies() {
    local missing=()

    # Only check for absolutely essential commands
    for cmd in bash mktemp; do
        if ! command_exists "$cmd"; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${color_red}Missing critical dependencies: ${missing[*]}${color_reset}"
        return 1
    fi

    return 0
}

# Handle interrupts gracefully
handle_interrupt() {
    echo -e "\n\n${color_yellow}Interrupted by user${color_reset}"

    # Check if transaction is active
    if $TRANSACTION_ACTIVE; then
        echo -e "${color_yellow}Rolling back active transaction...${color_reset}"
        rollback_transaction
    fi

    # Perform cleanup
    cleanup

    exit 130  # Standard exit code for SIGINT
}

# Enhanced main menu with lazy loading
main_menu() {
    while true; do
        print_header

        # Show system status
        show_system_status

        display_menu "Main Menu" \
            "Mod Organizer Setup" "Set up MO2 with Proton, NXM handler, and dependencies" \
            "Vortex Setup" "Set up Vortex with Proton, NXM handler, and dependencies" \
            "Limo Setup" "Set up game prefixes for Limo (Linux native mod manager)" \
            "Tale of Two Wastelands" "TTW-specific installation and tools" \
            "Hoolamike Tools" "Wabbajack and other modlist installations" \
            "Sky Texture Optimizer" "Run the Skyrim modlist texture optimizer tool" \
            "Game-Specific Info" "Game-specific fixes and information" \
            "System Utilities" "Logs, configuration, and system tools" \
            "Exit" "Quit the application"

        local choice=$?

        case $choice in
            1)
                push_navigation "Mod Organizer Setup"
                load_module "mo2download.sh" && \
                load_module "proton.sh" && \
                load_module "vdf.sh" && \
                mo2_setup_menu
                pop_navigation
                ;;
            2)
                push_navigation "Vortex Setup"
                load_module "vortex.sh" && \
                load_module "proton.sh" && \
                load_module "vdf.sh" && \
                vortex_setup_menu
                pop_navigation
                ;;
            3)
                push_navigation "Limo Setup"
                load_module "utils.sh" && \
                load_module "proton.sh" && \
                limo_setup_menu
                pop_navigation
                ;;
            4)
                push_navigation "Tale of Two Wastelands"
                load_module "ttw/hoolamike.sh" && \
                load_module "ttw/installation.sh" && \
                load_module "games/fallout.sh" && \
                ttw_installation_menu
                pop_navigation
                ;;
            5)
                push_navigation "Hoolamike Tools"
                load_module "ttw/hoolamike.sh" && \
                hoolamike_tools_menu
                pop_navigation
                ;;
            6)
                push_navigation "Sky Texture Optimizer"
                load_module "sky-tex-opti.sh" && \
                sky_tex_opti_main
                pop_navigation
                ;;
            7)
                push_navigation "Game-Specific Info"
                load_module "games/games.sh" && \
                game_specific_menu
                pop_navigation
                ;;
            8)
                push_navigation "System Utilities"
                system_utilities_menu
                pop_navigation
                ;;
            9)
                if confirm_action "Are you sure you want to exit?" "y"; then
                    log_info "User exited application"
                    echo -e "\n${color_green}Thank you for using NaK!${color_reset}"
                    exit 0
                fi
                ;;
        esac
    done
}

# Show system status on main menu
show_system_status() {
    echo -e "${color_header}System Status:${color_reset}"

    # Check if key tools are available
    local status_items=()

    # Check Protontricks
    if get_cached_or_execute "protontricks_check" 60 command_exists protontricks; then
        status_items+=("${color_green}✓${color_reset} Protontricks")
    else
        status_items+=("${color_red}✗${color_reset} Protontricks")
    fi

    # Check 7zip
    if get_cached_or_execute "7z_check" 60 command_exists 7z; then
        status_items+=("${color_green}✓${color_reset} 7-Zip")
    else
        status_items+=("${color_yellow}○${color_reset} 7-Zip")
    fi

    # Check disk space
    local home_free_mb=$(df -m "$HOME" | awk 'NR==2 {print $4}')
    if [ $home_free_mb -gt 10240 ]; then  # More than 10GB
        status_items+=("${color_green}✓${color_reset} Disk Space")
    else
        status_items+=("${color_yellow}!${color_reset} Low Disk")
    fi

    # Display status in a single line
    echo -e "${status_items[*]}"
    echo
}

# Enhanced system utilities menu
system_utilities_menu() {
    while true; do
        print_header

        display_menu "System Utilities" \
            "View Logs" "Display recent log entries and log file location" \
            "System Check" "Comprehensive system compatibility check" \
            "Configuration" "Adjust script settings and preferences" \
            "Clear Cache" "Clear cached data and temporary files" \
            "Export Diagnostics" "Export system diagnostics for troubleshooting" \
            "Check for Updates" "Check for script updates" \
            "About" "View information about this script" \
            "Back to Main Menu" "Return to the main menu"

        local choice=$?

        case $choice in
            1) view_logs_interactive ;;
            2) comprehensive_system_check ;;
            3) configuration_menu ;;
            4) clear_cache_interactive ;;
            5) export_diagnostics ;;
            6) check_for_updates_interactive ;;
            7) show_about ;;
            8) return ;;
        esac
    done
}

# ===== MAIN SCRIPT EXECUTION =====

# Initialize the script
initialize_script

# Welcome message with system check
print_header
echo -e "${color_green}Welcome to NaK - The Linux Modding Helper!${color_reset}"
echo -e "Enhanced version with improved security and user experience.\n"

# Quick system check
echo -n "Performing quick system check... "
if check_critical_dependencies; then
    echo -e "${color_green}OK${color_reset}"
else
    echo -e "${color_red}FAILED${color_reset}"
    echo -e "\nPlease install missing dependencies before continuing."
    exit 1
fi

echo -e "\nPress any key to start..."
read -n 1 -s

# Load UI module after welcome
load_module "ui.sh"

# Check for updates if enabled
if [ "$(get_config "check_updates" "true")" == "true" ]; then
    echo -n "Checking for updates... "
    if get_cached_or_execute "update_check" 3600 check_for_updates; then
        echo -e "${color_green}Done${color_reset}"
    else
        echo -e "${color_yellow}Skipped${color_reset}"
    fi
fi

# Start main menu
main_menu

# This point should never be reached
exit 0
