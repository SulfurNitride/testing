#!/bin/bash
# -------------------------------------------------------------------
# utils.sh
# Utility functions for MO2 Helper
# -------------------------------------------------------------------

read_with_tab_completion() {
    local prompt="$1"
    local default_value="${2:-}"
    local var_name="$3"

    # Validate var_name to prevent injection
    if [[ ! "$var_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        log_error "Invalid variable name: $var_name"
        return 1
    fi

    # If there's a default value, show it in the prompt
    if [ -n "$default_value" ]; then
        prompt="$prompt [default: $default_value]: "
    else
        prompt="$prompt: "
    fi

    # Use Bash's readline capabilities for tab completion
    local input_value
    read -e -p "$prompt" input_value

    # If input is empty and default exists, use default
    if [ -z "$input_value" ] && [ -n "$default_value" ]; then
        input_value="$default_value"
    fi

    # Expand tilde if present
    input_value="${input_value/#\~/$HOME}"

    # Use declare instead of eval for safety
    declare -g "$var_name=$input_value"
}

# Improved game directory finder with validation
find_game_directory() {
    local game_name="$1"
    local steam_root="$2"

    # Validate inputs
    if [ -z "$game_name" ] || [ -z "$steam_root" ]; then
        log_error "Invalid parameters for find_game_directory"
        return 1
    fi

    log_info "Looking for game directory: $game_name"

    # Get steam library paths
    local steam_paths=()
    steam_paths+=("$steam_root")

    # Parse library folders more safely
    local libraryfolders="$steam_root/steamapps/libraryfolders.vdf"
    if [ -f "$libraryfolders" ]; then
        # Use a more robust VDF parsing approach
        while IFS= read -r line; do
            if [[ "$line" =~ \"path\"[[:space:]]*\"([^\"]+)\" ]]; then
                local path="${BASH_REMATCH[1]}"
                if [ -d "$path" ]; then
                    steam_paths+=("$path")
                fi
            fi
        done < "$libraryfolders"
    fi

    # Search through all steam libraries
    for path in "${steam_paths[@]}"; do
        local candidate="$path/steamapps/common/$game_name"
        if [ -d "$candidate" ]; then
            # Validate it's actually a game directory
            if [ -n "$(ls -A "$candidate" 2>/dev/null)" ]; then
                log_info "Found game directory: $candidate"
                echo "$candidate"
                return 0
            fi
        fi
    done

    log_warning "Could not find game directory: $game_name"
    return 1
}

# Validate and sanitize file paths
sanitize_path() {
    local path="$1"

    # Remove any potentially dangerous characters
    path="${path//[$'\n\r']/}"  # Remove newlines
    path="${path//[[:cntrl:]]/}" # Remove control characters

    # Resolve relative paths
    if [[ "$path" == /* ]]; then
        # Absolute path
        echo "$path"
    else
        # Relative path - make it absolute
        echo "$(pwd)/$path"
    fi
}

# Improved command exists check with type validation
command_exists() {
    local cmd="$1"

    # Validate command name
    if [[ ! "$cmd" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        return 1
    fi

    # Use type instead of command for better reliability
    type "$cmd" &> /dev/null
}

# Safe temporary file creation
create_temp_file() {
    local prefix="${1:-nak}"
    local suffix="${2:-}"

    local temp_file
    if [ -n "$suffix" ]; then
        temp_file=$(mktemp --suffix="$suffix" "${TMPDIR:-/tmp}/${prefix}.XXXXXXXX")
    else
        temp_file=$(mktemp "${TMPDIR:-/tmp}/${prefix}.XXXXXXXX")
    fi

    if [ -z "$temp_file" ] || [ ! -f "$temp_file" ]; then
        log_error "Failed to create temporary file"
        return 1
    fi

    # Add to cleanup list
    TEMP_FILES+=("$temp_file")

    # Set secure permissions
    chmod 600 "$temp_file"

    echo "$temp_file"
    return 0
}

# Validate user input
validate_input() {
    local input="$1"
    local pattern="$2"
    local error_msg="${3:-Invalid input}"

    if [[ ! "$input" =~ $pattern ]]; then
        log_warning "Input validation failed: $input"
        echo -e "${color_red}$error_msg${color_reset}"
        return 1
    fi

    return 0
}

# Enhanced disk space check with better formatting
check_disk_space() {
    local required_mb=$1
    local path=${2:-$HOME}

    log_info "Checking for $required_mb MB of free space in $path"

    # Get the mount point for the path
    local mount_point=$(df -P "$path" | tail -1 | awk '{print $6}')

    # Get available space in MB
    local available_kb=$(df -P "$path" | tail -1 | awk '{print $4}')
    local available_mb=$((available_kb / 1024))

    if [ $available_mb -lt $required_mb ]; then
        handle_error "Insufficient disk space on $mount_point. Need ${required_mb}MB but only ${available_mb}MB available" false

        # Provide helpful suggestions
        echo -e "\n${color_header}Suggestions to free up space:${color_reset}"
        echo -e "1. Clear package manager cache: ${color_blue}sudo apt clean${color_reset}"
        echo -e "2. Remove old kernels: ${color_blue}sudo apt autoremove${color_reset}"
        echo -e "3. Check large files: ${color_blue}du -sh ~/* | sort -h${color_reset}"

        return 1
    fi

    log_info "Sufficient disk space available: $available_mb MB on $mount_point"
    return 0
}

# Find a specific game directory in Steam libraries
find_game_directory() {
    local game_name="$1"
    local steam_root="$2"
    local steam_paths=("$steam_root")

    log_info "Looking for game directory: $game_name"

    # Get additional library paths from libraryfolders.vdf
    local libraryfolders="$steam_root/steamapps/libraryfolders.vdf"
    if [ -f "$libraryfolders" ]; then
        while read -r line; do
            [[ "$line" == *\"path\"* ]] && steam_paths+=("$(echo "$line" | awk -F'"' '{print $4}')")
        done < "$libraryfolders"
    fi

    # Search through all steam libraries
    for path in "${steam_paths[@]}"; do
        local candidate="$path/steamapps/common/$game_name"
        if [ -d "$candidate" ]; then
            log_info "Found game directory: $candidate"
            echo "$candidate"
            return 0
        fi
    done

    log_warning "Could not find game directory: $game_name"
    return 1
}

# Function to find game compatdata for a specific game
find_game_compatdata() {
    local appid="$1"
    local steam_root="$2"
    local steam_paths=("$steam_root")

    # Check libraryfolders.vdf for additional Steam library paths
    libraryfolders="$steam_root/steamapps/libraryfolders.vdf"
    if [ -f "$libraryfolders" ]; then
        while read -r line; do
            [[ "$line" == *\"path\"* ]] && steam_paths+=("$(echo "$line" | awk -F'"' '{print $4}')")
        done < "$libraryfolders"
    fi

    # Search for compatdata in all Steam libraries
    for path in "${steam_paths[@]}"; do
        compatdata_path="$path/steamapps/compatdata/$appid"
        if [ -d "$compatdata_path" ]; then
            echo "$compatdata_path"
            return 0
        fi
    done

    # Return empty if not found
    echo ""
    return 1
}

# Consolidated functions for finding game-specific compatdata
find_enderal_compatdata() {
    find_game_compatdata "976620" "$(get_steam_root)"
}

find_fnv_compatdata() {
    find_game_compatdata "22380" "$(get_steam_root)"
}

find_bg3_compatdata() {
    find_game_compatdata "1086940" "$(get_steam_root)"
}

find_skyrim_se_compatdata() {
    find_game_compatdata "489830" "$(get_steam_root)"
}

find_fallout4_compatdata() {
    find_game_compatdata "377160" "$(get_steam_root)"
}

find_starfield_compatdata() {
    find_game_compatdata "1716740" "$(get_steam_root)"
}

find_oblivion_compatdata() {
    find_game_compatdata "22330" "$(get_steam_root)"
}

# Check for dependencies needed for downloading
check_download_dependencies() {
    log_info "Checking download dependencies"

    local missing_deps=()

    if ! command_exists curl; then
        missing_deps+=("curl")
    fi

    if ! command_exists jq; then
        missing_deps+=("jq")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${color_yellow}Missing required dependencies: ${missing_deps[*]}${color_reset}"
        echo -e "Please install them with:"
        echo -e "${color_blue}sudo apt install ${missing_deps[*]}${color_reset}"
        log_warning "Missing dependencies: ${missing_deps[*]}"
        return 1
    fi

    log_info "All download dependencies are installed"
    return 0
}

# Get non-Steam games
get_non_steam_games() {
    print_section "Fetching Non-Steam Games"
    log_info "Scanning for non-Steam games (always fresh scan)"

    # Start progress tracking
    local tracker=$(start_progress_tracking "Scanning for non-Steam games" 30)

    echo "Scanning for non-Steam games..."
    local protontricks_output
    if ! protontricks_output=$($protontricks_cmd --list 2>&1); then
        end_progress_tracking "$tracker" false
        error_exit "Failed to run protontricks. Check log for details."
    fi

    local games=""
    local count=0
    while IFS= read -r line; do
        if [[ "$line" =~ "Non-Steam shortcut:" ]]; then
            if [[ "$line" =~ \(([0-9]+)\)$ ]]; then
                appid="${BASH_REMATCH[1]}"
                name=$(echo "$line" | sed -E 's/.*Non-Steam shortcut: (.*) \([0-9]+\)$/\1/')
                games+="$appid:$name"$'\n'
                ((count++))
                update_progress "$tracker" "$count" "20"  # Estimate about 20 games
            fi
        fi
    done <<< "$protontricks_output"

    IFS=$'\n' read -d '' -ra game_array <<< "$games"
    end_progress_tracking "$tracker" true

    if [ ${#game_array[@]} -eq 0 ]; then
        error_exit "No non-Steam games found! Make sure you've added non-Steam games to Steam and launched them at least once."
    fi

    # Still cache the results for potential use by other functions
    if [ "$(get_config "auto_detect_games" "true")" == "true" ]; then
        local game_list=""
        for game in "${game_array[@]}"; do
            game_list+="$game;"
        done

        set_config "detected_games" "$game_list"
        log_info "Updated cached game list with ${#game_array[@]} detected games"
    fi

    echo "Found ${#game_array[@]} non-Steam games."
    return 0
}

# Modified select_game function to allow choosing different games
select_game() {
    log_info "Showing game selection menu"

    # If there's only one game, select it automatically
    if [ ${#game_array[@]} -eq 1 ]; then
        selected_game="${game_array[0]}"
        IFS=':' read -r selected_appid selected_name <<< "$selected_game"
        get_game_components "$selected_appid"
        log_info "Auto-selected only game: $selected_name (AppID: $selected_appid)"
        notify "Selected game: $selected_name" 2
        return 0
    fi

    # Build an array of just the game names for display
    local display_games=()

    for game in "${game_array[@]}"; do
        IFS=':' read -r appid name <<< "$game"
        display_games+=("$name (AppID: $appid)")
    done

    # Show selection menu with the full game list immediately
    print_section "Game Selection"
    echo "Please select a game:"

    select_from_list "Available Non-Steam Games" "${display_games[@]}"
    local choice=$SELECTION_RESULT

    if [ $choice -eq 0 ]; then
        log_info "User canceled game selection"
        return 1
    fi

    selected_game="${game_array[$((choice-1))]}"
    IFS=':' read -r selected_appid selected_name <<< "$selected_game"
    get_game_components "$selected_appid"
    log_info "Selected game: $selected_name (AppID: $selected_appid)"

    # Save as preferred game (for future use in other functions)
    set_config "preferred_game_appid" "$selected_appid"

    notify "Selected game: $selected_name" 2
    return 0
}

# Get components to install for a specific game
get_game_components() {
    local appid="$1"
    case "$appid" in
        22380)
            components=(
                fontsmooth=rgb
                xact
                xact_x64
                d3dx9_43
                d3dx9
                vcrun2022
            )
            ;;
        976620)  # Enderal Special Edition
            components=(
                fontsmooth=rgb
                xact
                xact_x64
                d3dx11_43
                d3dcompiler_43
                d3dcompiler_47
                vcrun2022
                dotnet6
                dotnet7
                dotnet8
            )
            ;;
        *)
            components=(
                fontsmooth=rgb
                xact
                xact_x64
                vcrun2022
                dotnet6
                dotnet7
                dotnet8
                d3dcompiler_47
                d3dx11_43
                d3dcompiler_43
                d3dx9_43
                d3dx9
                vkd3d
            )
            ;;
    esac
}
