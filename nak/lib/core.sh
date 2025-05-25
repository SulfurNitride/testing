#!/bin/bash
# -------------------------------------------------------------------
# core.sh
# Core functionality and variables for MO2 Helper
# -------------------------------------------------------------------

# Global variables
declare -a game_array
declare -a TEMP_FILES
declare -A LOADED_MODULES=()
declare -A OPERATION_CACHE=()
declare -a ERROR_CONTEXT_STACK=()
CACHE_TTL=600
LAST_ERROR=""
CURRENT_OPERATION=""
protontricks_cmd=""
selected_appid=""
selected_name=""
selected_scaling="96"  # Default scaling value
show_advice=true
SELECTION_RESULT=0

# Terminal colors and formatting
color_title="\033[1;36m"    # Cyan, bold
color_green="\033[38;2;0;255;0m"   # Green for success messages
color_yellow="\033[38;2;255;255;0m" # Yellow for warnings
color_red="\033[38;2;255;0;0m"      # Red for errors
color_blue="\033[38;2;0;185;255m"   # Blue for commands
color_header="\033[1;33m"  # Yellow bold for headers
color_option="\033[1;37m"  # White bold for menu options
color_desc="\033[0;37m"    # White for descriptions
color_reset="\033[0m"

# Config settings
CONFIG_DIR="$HOME/.config/nak"
CONFIG_FILE="$CONFIG_DIR/config.ini"
DEFAULT_CONFIG=(
    "logging_level=0"                   # 0=INFO, 1=WARNING, 2=ERROR
    "show_advanced_options=false"       # Hide advanced options by default
    "hoolamike_version="                # Last installed Hoolamike version
    "check_updates=true"                # Check for updates on startup
    "enable_telemetry=false"            # Send anonymous usage data
    "preferred_game_appid="             # Last used game AppID
    "default_scaling=96"                # Default DPI scaling value
    "enable_detailed_progress=true"     # Show detailed progress for long operations
    "auto_detect_games=true"            # Automatically detect installed games
    "cache_steam_path=true"             # Cache Steam path between runs
)

# Log file settings
log_dir="$HOME"
log_file="$log_dir/nak.log"
max_log_size=5242880  # 5MB
max_log_files=5

# Function to check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Cleanup function
cleanup() {
    log_info "Running cleanup procedures"

    # Remove temporary files
    if [ ${#TEMP_FILES[@]} -gt 0 ]; then
        log_info "Removing ${#TEMP_FILES[@]} temporary files"
        for file in "${TEMP_FILES[@]}"; do
            if [ -f "$file" ]; then
                rm -f "$file"
                log_info "Removed temporary file: $file"
            fi
        done
    fi

    # Report any errors that caused termination
    if [ -n "$LAST_ERROR" ]; then
        log_error "Script terminated with error: $LAST_ERROR"
    else
        log_info "Script completed normally"
    fi
}

# Dependency checks
check_dependencies() {
    log_info "Checking dependencies"
    if ! command_exists protontricks && \
       ! flatpak list --app --columns=application 2>/dev/null | grep -q com.github.Matoking.protontricks; then
        error_exit "Protontricks is not installed. Install it with:\n- Native: sudo apt install protontricks\n- Flatpak: flatpak install com.github.Matoking.protontricks"
    fi
    
    if command_exists protontricks; then
        protontricks_cmd="protontricks"
        log_info "Using native protontricks"
    else
        protontricks_cmd="flatpak run com.github.Matoking.protontricks"
        log_info "Using flatpak protontricks"
    fi
}

check_flatpak_steam() {
    log_info "Checking for Flatpak Steam"
    if flatpak list --app --columns=application 2>/dev/null | grep -q '^com\.valvesoftware\.Steam$'; then
        error_exit "Detected Steam installed via Flatpak. This script doesn't support Flatpak Steam installations."
    fi
}

get_steam_root() {
    log_info "Finding Steam root directory"

    # Check if we have cached value
    if [ "$(get_config "cache_steam_path" "true")" == "true" ]; then
        local cached_path=$(get_config "steam_path" "")
        if [ -n "$cached_path" ] && [ -d "$cached_path/steamapps" ]; then
            log_info "Using cached Steam path: $cached_path"
            echo "$cached_path"
            return
        fi
    fi

    local candidates=(
        "$HOME/.local/share/Steam"
        "$HOME/.steam/steam"
        "$HOME/.steam/debian-installation"
        "/usr/local/steam"
        "/usr/share/steam"
    )
    for candidate in "${candidates[@]}"; do
        if [ -d "$candidate/steamapps" ]; then
            log_info "Found Steam root: $candidate"

            # Cache the path if enabled
            if [ "$(get_config "cache_steam_path" "true")" == "true" ]; then
                set_config "steam_path" "$candidate"
            fi

            echo "$candidate"
            return
        fi
    done
    error_exit "Could not find Steam installation in standard locations:\n${candidates[*]}"
}

# Function to check for script updates
check_for_updates() {
    # This is a placeholder for the update checking functionality
    # You can implement this later if needed
    log_info "Checking for updates (placeholder)"
    return 0
}

main_menu() {
    while true; do
        print_header

        display_menu "Main Menu" \
            "Mod Organizer Setup" "Set up MO2 with Proton, NXM handler, and dependencies" \
            "Vortex Setup" "Set up Vortex with Proton, NXM handler, and dependencies" \
            "Limo Setup" "Set up game prefixes for Limo (Linux native mod manager)" \
            "Tale of Two Wastelands" "TTW-specific installation and tools" \
            "Hoolamike Tools" "Wabbajack and other modlist installations" \
            "Sky Texture Optimizer (Linux VRAMr)" "Run the Skyrim modlist texture optimizer tool" \
            "Game-Specific Info" "Fallout NV, Enderal, BG3 Info Here! (PLEASE REVIEW!)" \
            "Remove NXM Handlers" "Remove previously configured NXM handlers" \
            "Exit" "Quit the application"

        local choice=$?

        case $choice in
            1) mo2_setup_menu ;;
            2) vortex_setup_menu ;;
            3) limo_setup_menu ;;
            4) ttw_installation_menu ;;
            5) hoolamike_tools_menu ;;
            6) sky_tex_opti_main ;;
            7) game_specific_menu ;;
            8) remove_nxm_handlers ;;
            9)
                log_info "User exited application"
                echo -e "\n${color_green}Thank you for using NaK!${color_reset}"
                exit 0
                ;;
        esac
    done
}

# Limo setup submenu
limo_setup_menu() {
    while true; do
        print_header

        print_section "Limo Setup (Linux Native Mod Manager)"
        echo -e "Limo is a Linux-native mod manager that uses game prefixes directly."
        echo -e "This tool will help you prepare your game prefixes with the necessary dependencies."
        echo -e ""

        display_menu "Limo Setup" \
            "Configure Games for Limo" "Install dependencies for game prefixes" \
            "Back to Main Menu" "Return to the main menu"

        local choice=$?

        case $choice in
            1)
                configure_games_for_limo
                ;;
            2)
                return
                ;;
        esac
    done
}

# Function to configure games for Limo
configure_games_for_limo() {
    check_dependencies

    # List Steam games using protontricks
    print_section "Fetching Steam Games"
    log_info "Scanning for Steam games via protontricks"

    echo "Scanning for Steam games..."
    local protontricks_output
    if ! protontricks_output=$($protontricks_cmd -l 2>&1); then
        handle_error "Failed to run protontricks. Check log for details." false
        return 1
    fi

    local games=""
    local count=0
    local collecting=false

    while IFS= read -r line; do
        # Start collecting games after this line
        if [[ "$line" == "Found the following games:"* ]]; then
            collecting=true
            continue
        fi

        # Stop collecting at the note line
        if [[ "$line" == "To run Protontricks"* ]]; then
            break
        fi

        # Process game lines
        if [ "$collecting" = true ] && [[ "$line" =~ (.*)\(([0-9]+)\) ]]; then
            local name="${BASH_REMATCH[1]}"
            local appid="${BASH_REMATCH[2]}"

            # Trim whitespace from name
            name=$(echo "$name" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

            # Skip non-Steam shortcuts, SteamVR, Proton, etc.
            if [[ "$name" != "Non-Steam shortcut:"* ]] &&
               [[ "$name" != *"SteamVR"* ]] &&
               [[ "$name" != *"Proton"* ]] &&
               [[ "$name" != *"Steam Linux Runtime"* ]]; then
                games+="$appid:$name"$'\n'
                ((count++))
            fi
        fi
    done <<< "$protontricks_output"

    IFS=$'\n' read -d '' -ra game_array <<< "$games"

    if [ ${#game_array[@]} -eq 0 ]; then
        handle_error "No Steam games found! Make sure you've launched your games at least once." false
        return 1
    fi

    echo "Found ${#game_array[@]} Steam games."

    # Select a game
    # Build an array of just the game names for display
    local display_games=()

    for game in "${game_array[@]}"; do
        IFS=':' read -r appid name <<< "$game"
        display_games+=("$name (AppID: $appid)")
    done

    # Show selection menu with the full game list
    print_section "Game Selection"
    echo "Please select a game to configure for Limo:"

    select_from_list "Available Steam Games" "${display_games[@]}"
    local choice=$SELECTION_RESULT

    if [ $choice -eq 0 ]; then
        log_info "User canceled game selection"
        return 1
    fi

    selected_game="${game_array[$((choice-1))]}"
    IFS=':' read -r selected_appid selected_name <<< "$selected_game"
    get_game_components "$selected_appid"
    log_info "Selected game: $selected_name (AppID: $selected_appid)"

    # Install dependencies for the selected game
    print_section "Installing Dependencies for $selected_name"
    echo -e "Installing dependencies for ${color_blue}$selected_name${color_reset}"
    echo -e "This will prepare the game prefix for use with Limo."

    # Install dependencies using existing function
    install_proton_dependencies

    # Find the prefix path for the selected game (for informational purposes)
    local steam_root=$(get_steam_root)
    local compatdata_path=$(find_game_compatdata "$selected_appid" "$steam_root")
    local prefix_path="$compatdata_path/pfx"

    echo -e "\n${color_green}Successfully configured $selected_name for Limo!${color_reset}"
    echo -e "Proton prefix path: ${color_blue}$prefix_path${color_reset}"

    # Ask if user is modding any other games
    echo -e "\nAre you planning to mod any other games with Limo?"
    if confirm_action "Configure another game?"; then
        configure_games_for_limo
    fi

    pause "Press any key to continue..."
    return 0
}

# Hoolamike general tools menu
hoolamike_tools_menu() {
    while true; do
        print_header

        # Check if Hoolamike is installed
        local hoolamike_installed=false
        if [ -f "$HOME/Hoolamike/hoolamike" ]; then
            hoolamike_installed=true
        fi

        # Status indicator
        local hoolamike_status="${color_red}Not Installed${color_reset}"
        if $hoolamike_installed; then
            hoolamike_status="${color_green}Installed${color_reset}"
        fi

        echo -e "Hoolamike: $hoolamike_status"

        display_menu "Hoolamike Mod Tools" \
            "Download/Update Hoolamike" "Download or update the Hoolamike tool" \
            "Install Wabbajack Modlist (Premium)" "Install a Wabbajack modlist using Nexus Premium account" \
            "Install Wabbajack Modlist (Non-Premium)" "Install with browser downloads (no Premium required)" \
            "Edit Configuration" "Edit the Hoolamike configuration file" \
            "Back to Main Menu" "Return to the main menu"

        local choice=$?

        case $choice in
            1)
                if $hoolamike_installed; then
                    echo -e "\n${color_yellow}Hoolamike is already installed.${color_reset}"
                    if confirm_action "Re-download and reinstall?"; then
                        download_hoolamike
                    fi
                else
                    download_hoolamike
                fi
                ;;
            2)
                if ! $hoolamike_installed; then
                    handle_error "Hoolamike is not installed. Please install it first." false
                else
                    install_wabbajack_modlist
                fi
                pause "Press any key to continue..."
                ;;
            3)
                if ! $hoolamike_installed; then
                    handle_error "Hoolamike is not installed. Please install it first." false
                else
                    install_wabbajack_modlist_nonpremium
                fi
                pause "Press any key to continue..."
                ;;
            4)
                if ! $hoolamike_installed; then
                    handle_error "Hoolamike is not installed. Please install it first." false
                else
                    edit_hoolamike_config
                fi
                ;;
            5) return ;;
        esac
    done
}


# MO2 setup submenu
mo2_setup_menu() {
    while true; do
        print_header

        display_menu "Mod Organizer 2 Setup" \
            "Download Mod Organizer 2" "Download and install the latest version" \
            "Set Up Existing Installation" "Configure an existing MO2 installation" \
            "Install Basic Dependencies" "Install common Proton components for MO2" \
            "Configure NXM Handler" "Set up Nexus Mod Manager link handling" \
            "DPI Scaling" "Configure DPI scaling for HiDPI displays" \
            "Back to Main Menu" "Return to the main menu"

        local choice=$?

        case $choice in
            1)
                download_mo2
                pause "Press any key to continue..."
                ;;
            2)
                setup_existing_mo2
                pause "Press any key to continue..."
                ;;
            3)
                check_dependencies
                get_non_steam_games
                if select_game; then
                    install_proton_dependencies
                    pause "Basic dependencies installation complete!"
                fi
                ;;
            4)
                check_dependencies
                get_non_steam_games
                if select_game; then
                    if setup_nxm_handler; then
                        pause "NXM handler configured successfully!"
                    fi
                fi
                ;;
            5)
                check_dependencies
                get_non_steam_games
                if select_game; then
                    select_dpi_scaling
                    apply_dpi_scaling
                    pause "DPI scaling applied successfully!"
                fi
                ;;
            6) return ;;
        esac
    done
}

# Game-specific tools submenu
game_specific_menu() {
    while true; do
        print_header

        display_menu "Game-Specific Fixes" \
            "Fallout New Vegas" "Launch options and fixes for Fallout New Vegas. Along with MO2 NXM and DPI Scaling Fixes" \
            "Enderal Special Edition" "Launch options and fixes for Enderal. Along with MO2 NXM and DPI Scaling Fixes" \
            "Baldur's Gate 3" "Launch options and fixes for Baldur's Gate 3" \
            "All Games Advice" "View advice for all detected games" \
            "Back to Main Menu" "Return to the main menu"

        local choice=$?

        case $choice in
            1) fnv_menu ;;
            2) enderal_menu ;;
            3) bg3_menu ;;
            4) generate_advice ;;
            5) return ;;
        esac
    done
}

# Fallout New Vegas menu
fnv_menu() {
    # Set up for Fallout New Vegas (AppID 22380)
    selected_appid="22380"
    selected_name="Fallout New Vegas"

    while true; do
        # Show launch advice specific to FNV
        print_section "Fallout New Vegas Options"
        local steam_root=$(get_steam_root)
        local fnv_compatdata=$(find_game_compatdata "22380" "$steam_root")

        if [ -n "$fnv_compatdata" ]; then
            echo -e "Recommended launch options for Fallout New Vegas:"
            echo -e "${color_blue}STEAM_COMPAT_DATA_PATH=\"$fnv_compatdata\" %command%${color_reset}"
            log_info "Displayed FNV launch options"

            # Display menu options
            display_menu "Fallout New Vegas Fixes" \
                "Install Dependencies" "Install Fallout New Vegas specific dependencies for modding" \
                "Configure NXM Handler" "Set up Nexus Mod Manager link handling for FNV based modlists. " \
                "Configure DPI Scaling" "Adjust DPI scaling for FNV based modlists" \
                "Back" "Return to the game menu"

            local choice=$?

            case $choice in
                1)
                    install_fnv_dependencies
                    pause "Press any key to continue..."
                    ;;
                2)
                    check_dependencies
                    if setup_nxm_handler; then
                        pause "NXM handler configured successfully for Fallout New Vegas!"
                    fi
                    ;;
                3)
                    check_dependencies
                    select_dpi_scaling
                    apply_dpi_scaling
                    pause "DPI scaling applied successfully for Fallout New Vegas!"
                    ;;
                4)
                    return
                    ;;
            esac
        else
            echo -e "${color_yellow}Fallout New Vegas has not been run yet or is not installed.${color_reset}"
            echo -e "Please run the game at least once through Steam before using these options."
            log_warning "FNV compatdata not found"
            pause "Press any key to continue..."
            return
        fi
    done
}

# Vortex setup submenu
vortex_setup_menu() {
    while true; do
        print_header

        display_menu "Vortex Setup" \
            "Download Vortex" "Download and install the latest version" \
            "Set Up Existing Installation" "Configure an existing Vortex installation" \
            "Install Basic Dependencies" "Install common Proton components for Vortex" \
            "Configure NXM Handler" "Set up Nexus Mod Manager link handling" \
            "DPI Scaling" "Configure DPI scaling for HiDPI displays" \
            "Back to Main Menu" "Return to the main menu"

        local choice=$?

        case $choice in
            1)
                download_vortex
                pause "Press any key to continue..."
                ;;
            2)
                setup_existing_vortex
                pause "Press any key to continue..."
                ;;
            3)
                check_dependencies
                get_non_steam_games
                if select_game; then
                    install_proton_dependencies
                    pause "Basic dependencies installation complete!"
                fi
                ;;
            4)
                check_dependencies
                get_non_steam_games
                if select_game; then
                    if setup_vortex_nxm_handler; then
                        pause "Vortex NXM handler configured successfully!"
                    fi
                fi
                ;;
            5)
                check_dependencies
                get_non_steam_games
                if select_game; then
                    select_dpi_scaling
                    apply_dpi_scaling
                    pause "DPI scaling applied successfully!"
                fi
                ;;
            6) return ;;
        esac
    done
}

# Enderal Special Edition menu
enderal_menu() {
    # Set up for Enderal SE (AppID 976620)
    selected_appid="976620"
    selected_name="Enderal Special Edition"

    while true; do
        # Show launch advice specific to Enderal
        print_section "Enderal Special Edition Options"
        local steam_root=$(get_steam_root)
        local enderal_compatdata=$(find_game_compatdata "976620" "$steam_root")

        if [ -n "$enderal_compatdata" ]; then
            echo -e "Recommended launch options for Enderal Special Edition:"
            echo -e "${color_blue}STEAM_COMPAT_DATA_PATH=\"$enderal_compatdata\" %command%${color_reset}"
            log_info "Displayed Enderal launch options"

            # Display menu options
            display_menu "Enderal Special Edition Fixes" \
                "Install Dependencies" "Install Enderal specific dependencies for modding" \
                "Configure NXM Handler" "Set up Nexus Mod Manager link handling for Enderal based modlists." \
                "Configure DPI Scaling" "Adjust DPI scaling Enderal based modlists." \
                "Back" "Return to the game menu"

            local choice=$?

            case $choice in
                1)
                    # Set components for Enderal before installing
                    components=(
                        fontsmooth=rgb
                        xact
                        xact_x64
                        d3dx11_43
                        d3dcompiler_43
                        d3dcompiler_46
                        d3dcompiler_47
                        vcrun2022
                        dotnet6
                        dotnet7
                        dotnet8
                        winhttp
                    )
                    check_dependencies
                    install_proton_dependencies
                    pause "Press any key to continue..."
                    ;;
                2)
                    check_dependencies
                    if setup_nxm_handler; then
                        pause "NXM handler configured successfully for Enderal Special Edition!"
                    fi
                    ;;
                3)
                    check_dependencies
                    select_dpi_scaling
                    apply_dpi_scaling
                    pause "DPI scaling applied successfully for Enderal Special Edition!"
                    ;;
                4)
                    return
                    ;;
            esac
        else
            echo -e "${color_yellow}Enderal has not been run yet or is not installed.${color_reset}"
            echo -e "Please run the game at least once through Steam before using these options."
            log_warning "Enderal compatdata not found"
            pause "Press any key to continue..."
            return
        fi
    done
}

# System utilities submenu
system_utilities_menu() {
    while true; do
        print_header

        display_menu "System Utilities" \
            "View Logs" "Display recent log entries and log file location" \
            "Check System Compatibility" "Verify system compatibility for gaming" \
            "Configuration" "Adjust script settings and preferences" \
            "About" "View information about this script" \
            "Back to Main Menu" "Return to the main menu"

        local choice=$?

        case $choice in
            1)
                view_logs
                echo -e "\nPress any key to continue..."
                read -n 1
                ;;
            2)
                check_system_compatibility
                echo -e "\nPress any key to continue..."
                read -n 1
                ;;
            3) show_config_menu ;;
            4)
                show_about
                echo -e "\nPress any key to continue..."
                read -n 1
                ;;
            5) return ;;
        esac
    done
}

# Placeholder for the check_system_compatibility function
check_system_compatibility() {
    print_section "System Compatibility Check"
    echo "Checking system compatibility..."
    log_system_info
    
    # You can implement detailed compatibility checks here
    
    echo -e "\n${color_green}Basic system compatibility check passed.${color_reset}"
}

# About function
show_about() {
    print_section "About NaK"
    echo -e "NaK (Na-K) - The Linux Modding Helper"
    echo -e "Version: $SCRIPT_VERSION"
    echo -e "Date: $SCRIPT_DATE"
    echo -e "\nNaK is a powerful tool for managing modding tools on linux, like MO2, or Hoolamike."
    echo -e "Project repository: https://github.com/SulfurNitride/NaK"
}

# Placeholder for the show_config_menu function
show_config_menu() {
    print_section "Configuration Menu"
    echo "Configuration options will be implemented here."
    pause "Press any key to continue..."
}
