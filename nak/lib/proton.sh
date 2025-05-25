#!/bin/bash
# -------------------------------------------------------------------
# proton.sh
# Proton-specific functionality for MO2 Helper
# -------------------------------------------------------------------

# Find Proton path in Steam libraries
find_proton_path() {
    local steam_root="$1"
    log_info "Finding Proton path (Steam root: $steam_root)"

    local steam_paths=("$steam_root")

    libraryfolders="$steam_root/steamapps/libraryfolders.vdf"
    if [ -f "$libraryfolders" ]; then
        while read -r line; do
            [[ "$line" == *\"path\"* ]] && steam_paths+=("$(echo "$line" | awk -F'"' '{print $4}')")
        done < "$libraryfolders"
    fi

    for path in "${steam_paths[@]}"; do
        proton_candidate="$path/steamapps/common/Proton - Experimental/proton"
        if [ -f "$proton_candidate" ]; then
            log_info "Found Proton path: $proton_candidate"
            echo "$proton_candidate"
            return
        fi
    done

    log_error "Proton - Experimental not found"
    handle_error "Proton - Experimental not found in Steam libraries. Make sure it's installed." false
    return 1
}

# Helper function to run commands through Proton Wine instead of system Wine
run_with_proton_wine() {
    local prefix_path="$1"
    local command="$2"
    local args="${@:3}"  # All remaining arguments

    # Get necessary paths
    local steam_root=$(get_steam_root)
    local proton_path=$(find_proton_path "$steam_root")

    if [ -z "$proton_path" ]; then
        log_error "Could not find Proton installation"
        return 1
    fi

    # Run the command with Proton's Wine
    env STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam_root" \
        STEAM_COMPAT_DATA_PATH="$(dirname "$prefix_path")" \
        "$proton_path" run "$command" $args

    return $?
}

# Register MIME handler for nxm:// protocol
register_mime_handler() {
    log_info "Registering NXM MIME handler"
    echo -n "Registering nxm:// handler... "

    if xdg-mime default modorganizer2-nxm-handler.desktop x-scheme-handler/nxm 2>/dev/null ; then
        echo -e "${color_green}Success (via xdg-mime)${color_reset}"
        log_info "Success (via xdg-mime)"
    else
        local mimeapps="$HOME/.config/mimeapps.list"
        [ -f "$mimeapps" ] || touch "$mimeapps"
        sed -i '/x-scheme-handler\/nxm/d' "$mimeapps"
        echo "x-scheme-handler/nxm=modorganizer2-nxm-handler.desktop" >> "$mimeapps"
        update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
        echo -e "${color_green}Manual registration complete!${color_reset}"
        log_info "Manual registration complete"
    fi
}

# Setup NXM handler for Mod Organizer 2
setup_nxm_handler() {
    if [ -z "$selected_appid" ] || [ -z "$selected_name" ]; then
        handle_error "No game selected. Please select a game first." false
        return 1
    fi

    log_info "Setting up NXM handler for $selected_name (AppID: $selected_appid)"

    print_section "NXM Link Handler Setup"
    check_flatpak_steam
    local steam_root=$(get_steam_root)

    local proton_path=$(find_proton_path "$steam_root")
    if [ -z "$proton_path" ]; then
        handle_error "Could not find Proton Experimental. Make sure it's installed in Steam." false
        return 1
    fi

   while true; do
    read_with_tab_completion "Enter FULL path to nxmhandler.exe (or 'b' to go back)" "" "nxmhandler_path"

    # Check if user wants to go back
    if [[ "$nxmhandler_path" == "b" || "$nxmhandler_path" == "B" ]]; then
        log_info "User cancelled NXM handler setup"
        return 1
    fi

    if [ -f "$nxmhandler_path" ]; then
        log_info "Selected nxmhandler.exe: $nxmhandler_path"
        break
    fi

    echo -e "${color_red}File not found!${color_reset} Try again or enter 'b' to go back."
    log_warning "Invalid path: $nxmhandler_path"
done

    steam_compat_data_path="$steam_root/steamapps/compatdata/$selected_appid"
    desktop_file="$HOME/.local/share/applications/modorganizer2-nxm-handler.desktop"

    log_info "Creating desktop file: $desktop_file"
    mkdir -p "$HOME/.local/share/applications"
    cat << EOF > "$desktop_file"
[Desktop Entry]
Type=Application
Categories=Game;
Exec=bash -c 'env "STEAM_COMPAT_CLIENT_INSTALL_PATH=$steam_root" "STEAM_COMPAT_DATA_PATH=$steam_compat_data_path" "$proton_path" run "$nxmhandler_path" "%u"'
Name=Mod Organizer 2 NXM Handler
MimeType=x-scheme-handler/nxm;
NoDisplay=true
EOF

    chmod +x "$desktop_file"

    register_mime_handler

    echo -e "\n${color_green}NXM Handler setup complete!${color_reset}"
    log_info "NXM Handler setup complete"

    return 0
}

# Function to enable visibility of dotfiles in Wine/Proton
enable_show_dotfiles() {
    local prefix_path="$1"

    if [ -z "$prefix_path" ] || [ ! -d "$prefix_path" ]; then
        log_warning "Invalid prefix path for dotfiles visibility"
        return 1
    fi

    log_info "Enabling dotfiles visibility in prefix: $prefix_path"

    # Direct registry command approach
    echo "Running direct registry command to enable dotfiles visibility..."
    run_with_proton_wine "$prefix_path" "reg" "add" "HKCU\\Software\\Wine" "/v" "ShowDotFiles" "/d" "Y" "/f"
    local result=$?

    if [ $result -eq 0 ]; then
        echo -e "${color_green}Dotfiles visibility enabled successfully${color_reset}"
        log_info "Dotfiles visibility enabled successfully"
    else
        echo -e "${color_yellow}Warning: Failed to enable dotfiles visibility (exit code: $result)${color_reset}"
        log_warning "Failed to enable dotfiles visibility (exit code: $result)"
        
        # Optional: Add verification to check if it worked despite the error
        echo "Verifying registry setting..."
        run_with_proton_wine "$prefix_path" "reg" "query" "HKCU\\Software\\Wine" "/v" "ShowDotFiles"
    fi

    return $result
}

# Function to remove window decorations for Pandora Behaviour Engine
set_pandora_no_decorations() {
    local prefix_path="$1"

    if [ -z "$prefix_path" ] || [ ! -d "$prefix_path" ]; then
        log_warning "Invalid prefix path for setting Pandora window decoration removal"
        return 1
    fi

    log_info "Setting window decoration removal for Pandora Behaviour Engine+"

    # Create a registry file with proper structure for Wine
    local reg_file=$(mktemp --suffix=.reg)
    TEMP_FILES+=("$reg_file")

    # Create registry entry for Pandora - note the escaped + sign
    cat > "$reg_file" << EOF
REGEDIT4

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\Pandora Behaviour Engine+.exe\\X11 Driver]
"Decorated"="N"
EOF

    # Copy the registry file to the prefix
    local win_reg_file="$prefix_path/drive_c/temp_pandora.reg"
    cp "$reg_file" "$win_reg_file"

    # Apply the registry changes using Proton's regedit
    echo "Applying registry changes for Pandora..."
    run_with_proton_wine "$prefix_path" "regedit" "C:\\temp_pandora.reg"
    local result=$?

    # Clean up
    rm -f "$win_reg_file" 2>/dev/null
    rm -f "$reg_file"

    if [ $result -ne 0 ]; then
        log_warning "Failed to set window decoration removal for Pandora"
        return 1
    fi

    log_info "Window decorations disabled for Pandora Behaviour Engine+"
    return 0
}

# Function to set Windows XP mode for SSE Edit tools
set_sseedit_to_winxp() {
    local prefix_path="$1"

    if [ -z "$prefix_path" ] || [ ! -d "$prefix_path" ]; then
        log_warning "Invalid prefix path for setting Windows XP mode"
        return 1
    fi

    log_info "Setting Windows XP compatibility mode for all XEDIT tools"

    # Create a registry file with proper structure for Wine
    local reg_file=$(mktemp --suffix=.reg)
    TEMP_FILES+=("$reg_file")

    # Create correct registry entry based on actual Wine registry structure
    cat > "$reg_file" << EOF
REGEDIT4

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\SSEEdit.exe]
"Version"="winxp"

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\SSEEdit64.exe]
"Version"="winxp"

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\FO4Edit.exe]
"Version"="winxp"

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\FO4Edit64.exe]
"Version"="winxp"

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\TES4Edit.exe]
"Version"="winxp"

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\TES4Edit64.exe]
"Version"="winxp"

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\xEdit64.exe]
"Version"="winxp"

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\SF1Edit64.exe]
"Version"="winxp"

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\FNVEdit.exe]
"Version"="winxp"

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\FNVEdit64.exe]
"Version"="winxp"

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\xFOEdit.exe]
"Version"="winxp"

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\xFOEdit64.exe]
"Version"="winxp"

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\xSFEEdit.exe]
"Version"="winxp"

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\xSFEEdit64.exe]
"Version"="winxp"

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\xTESEdit.exe]
"Version"="winxp"

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\xTESEdit64.exe]
"Version"="winxp"

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\FO3Edit.exe]
"Version"="winxp"

[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\FO3Edit64.exe]
"Version"="winxp"
EOF

    # Copy the registry file to the prefix
    local win_reg_file="$prefix_path/drive_c/temp_xpedit.reg"
    cp "$reg_file" "$win_reg_file"

    # Apply the registry changes using Proton's regedit
    echo "Applying registry changes..."
    run_with_proton_wine "$prefix_path" "regedit" "C:\\temp_xpedit.reg"
    local result=$?

    # Clean up
    rm -f "$win_reg_file" 2>/dev/null
    rm -f "$reg_file"

    if [ $result -ne 0 ]; then
        log_warning "Failed to set Windows XP mode for SSEEdit tools"
        return 1
    fi

    log_info "Windows XP mode set for all xEdit tools"
    return 0
}

# Function to let user select DPI scaling
select_dpi_scaling() {
    log_info "Starting DPI scaling selection"

    # Get stored scaling from config if available
    local default_scaling=$(get_config "default_scaling" "96")

    print_section "DPI Scaling Selection"
    echo -e "Choose a DPI scaling value for Mod Organizer 2:"
    echo -e "${color_desc}Higher values make the UI larger. Recommended for HiDPI displays.${color_reset}\n"

    local scaling_options=(
        "96" "Standard scaling (100%)"
        "120" "Medium scaling (125%)"
        "144" "Large scaling (150%)"
        "192" "Extra large scaling (200%)"
        "Custom" "Enter a custom scaling value"
    )

    # Show menu with scaling options
    for ((i=0; i<${#scaling_options[@]}; i+=2)); do
        local option="${scaling_options[i]}"
        local description="${scaling_options[i+1]}"

        # Highlight default option
        if [ "$option" = "$default_scaling" ]; then
            echo -e "${color_option}$((i/2+1)). $option${color_reset} - $description ${color_green}(Current)${color_reset}"
        else
            echo -e "${color_option}$((i/2+1)). $option${color_reset} - $description"
        fi
    done

    # Get user choice
    local choice
    while true; do
        read -rp $'\nSelect a scaling option (1-'$((${#scaling_options[@]}/2))'): ' choice

        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if (( choice >= 1 && choice <= ${#scaling_options[@]}/2 )); then
                # Get selected option
                selected_scaling="${scaling_options[((choice-1)*2)]}"

                # If custom, prompt for value
                if [ "$selected_scaling" = "Custom" ]; then
                    while true; do
                        read -rp "Enter custom scaling value (96-240): " selected_scaling
                        if [[ "$selected_scaling" =~ ^[0-9]+$ ]] && (( selected_scaling >= 96 && selected_scaling <= 240 )); then
                            break
                        else
                            echo "Invalid scaling value. Please enter a number between 96 and 240."
                        fi
                    done
                fi

                log_info "Selected DPI scaling: $selected_scaling"
                set_config "default_scaling" "$selected_scaling"
                return 0
            fi
        fi

        echo "Invalid choice. Please try again."
    done
}


# Function to apply DPI scaling to selected game
apply_dpi_scaling() {
    log_info "Applying DPI scaling ($selected_scaling) to game: $selected_name (AppID: $selected_appid)"

    if [ -z "$selected_appid" ] || [ -z "$selected_name" ]; then
        handle_error "No game selected. Please select a game first." false
        return 1
    fi

    if [ -z "$selected_scaling" ]; then
        handle_error "No scaling value selected. Please select a scaling value first." false
        return 1
    fi

    # Start progress tracking
    local tracker=$(start_progress_tracking "Applying DPI scaling" 20)

    print_section "Applying DPI Scaling"
    echo -e "Applying ${color_green}$selected_scaling DPI${color_reset} scaling to ${color_blue}$selected_name${color_reset}"

    # Find the prefix path for the selected game
    local steam_root=$(get_steam_root)
    local compatdata_path=$(find_game_compatdata "$selected_appid" "$steam_root")
    local prefix_path="$compatdata_path/pfx"

    log_info "Using compatdata path: $compatdata_path"

    if [ ! -d "$prefix_path" ]; then
        end_progress_tracking "$tracker" false
        handle_error "Could not find Proton prefix at: $prefix_path" false
        return 1
    fi

    update_progress "$tracker" 5 20

    # Create a Windows batch script to apply registry changes silently
    local batch_file=$(mktemp --suffix=.bat)
    TEMP_FILES+=("$batch_file")

    # Write Windows commands to the batch file
    echo "@echo off" > "$batch_file"
    echo "reg add \"HKCU\\Control Panel\\Desktop\" /v LogPixels /t REG_DWORD /d $selected_scaling /f" >> "$batch_file"
    echo "reg add \"HKCU\\Software\\Wine\\X11 Driver\" /v LogPixels /t REG_DWORD /d $selected_scaling /f" >> "$batch_file"
    echo "exit 0" >> "$batch_file"

    update_progress "$tracker" 10 20

    # Copy the batch file to the prefix
    local win_batch_file="$prefix_path/drive_c/temp_dpi.bat"
    mkdir -p "$prefix_path/drive_c/" 2>/dev/null
    cp "$batch_file" "$win_batch_file"
    chmod +x "$win_batch_file"

    log_info "Created batch file: $win_batch_file"

    # Run the batch file with Proton's Wine
    echo -e "Applying registry changes silently..."
    log_info "Running batch file to set registry keys with Proton's Wine"

    run_with_proton_wine "$prefix_path" "C:\\temp_dpi.bat"
    local result=$?

    # Clean up temporary batch file in the prefix
    rm -f "$win_batch_file" 2>/dev/null

    update_progress "$tracker" 20 20

    if [ $result -ne 0 ]; then
        end_progress_tracking "$tracker" false
        handle_error "Failed to apply registry changes. Check log for details." false
        return 1
    fi

    echo -e "\n${color_green}DPI scaling successfully applied!${color_reset}"
    echo -e "You need to ${color_yellow}restart Mod Organizer 2${color_reset} for changes to take effect."

    if $show_advice; then
        echo -e "\n${color_header}Tip:${color_reset} If text is too small or too large, try different scaling values."
        echo -e "     For most modern monitors, a value between 120-144 works well."
    fi

    end_progress_tracking "$tracker" true
    return 0
}

# Function to install .NET 9 SDK directly
install_dotnet9_sdk() {
    local prefix_path="$1"
    local dotnet_url="https://builds.dotnet.microsoft.com/dotnet/Sdk/9.0.203/dotnet-sdk-9.0.203-win-x64.exe"
    local dotnet_file="dotnet-sdk-9.0.203-win-x64.exe"

    log_info "Installing .NET 9 SDK directly from Microsoft"
    echo -e "\n${color_header}Installing .NET 9 SDK...${color_reset}"

    # Find steam root and Proton path
    local steam_root=$(get_steam_root)
    local proton_path=$(find_proton_path "$steam_root")

    if [ -z "$proton_path" ]; then
        log_error "Could not find Proton installation"
        return 1
    fi

    # Create a temporary directory for the download
    local temp_dir=$(mktemp -d)
    TEMP_FILES+=("$temp_dir")

    # Download the file
    echo -e "Downloading .NET 9 SDK from Microsoft..."
    if ! curl -L -o "$temp_dir/$dotnet_file" "$dotnet_url"; then
        log_error "Failed to download .NET 9 SDK"
        rm -rf "$temp_dir" 2>/dev/null
        return 1
    fi

    # Copy to the Wine prefix
    mkdir -p "$prefix_path/drive_c/temp" 2>/dev/null
    local win_file="$prefix_path/drive_c/temp/$dotnet_file"
    cp "$temp_dir/$dotnet_file" "$win_file"

    # Run the installer with silent options using Proton's Wine
    echo -e "Running .NET 9 SDK installer (silent mode)..."

    # Using environment variables needed for Proton
    env STEAM_COMPAT_CLIENT_INSTALL_PATH="$steam_root" \
        STEAM_COMPAT_DATA_PATH="$(dirname "$prefix_path")" \
        "$proton_path" run "C:\\temp\\$dotnet_file" /q

    local result=$?

    # Clean up
    rm -f "$win_file" 2>/dev/null
    rm -rf "$temp_dir" 2>/dev/null

    if [ $result -ne 0 ]; then
        log_error "Failed to install .NET 9 SDK with status $result"
        return 1
    fi

    log_info ".NET 9 SDK installed successfully"
    echo -e "${color_green}.NET 9 SDK installed successfully!${color_reset}"
    return 0
}

# Function to setup DigiCert certificate for Synthesis
setup_synthesis_certificate() {
    log_info "Checking if user needs Synthesis certificate setup"

    print_section "Synthesis Patcher Support"
    echo -e "Synthesis is a popular patching framework used in Bethesda game modlists."
    echo -e "${color_yellow}Users of Synthesis may encounter NuGet certificate validation errors.${color_reset}"

    if confirm_action "Will you be using Synthesis with this setup?"; then
        echo -e "\nTo fix potential NuGet package validation errors, we need to install a certificate."
        echo -e "This requires ${color_yellow}sudo${color_reset} access to install the DigiCert Universal Root certificate."

        if confirm_action "Install DigiCert Universal Root certificate?"; then
            log_info "User confirmed certificate installation"

            echo -e "\n${color_blue}Downloading certificate...${color_reset}"
            if ! wget -q https://cacerts.digicert.com/universal-root.crt.pem; then
                log_error "Failed to download certificate"
                echo -e "${color_red}Failed to download certificate.${color_reset}"
                return 1
            fi

            echo -e "${color_blue}Installing certificate (you may be prompted for your password)...${color_reset}"
            if ! sudo trust anchor --store universal-root.crt.pem; then
                log_error "Failed to install certificate"
                echo -e "${color_red}Failed to install certificate.${color_reset}"
                return 1
            fi

            # Clean up
            rm -f universal-root.crt.pem

            echo -e "\n${color_green}Certificate installed successfully!${color_reset}"
            echo -e "This should resolve NuGet certificate validation errors when using Synthesis."
            log_info "Certificate installed successfully"
        else
            log_info "User declined certificate installation"
            echo -e "\n${color_yellow}If you encounter NuGet certificate errors later, you can manually install the certificate with:${color_reset}"
            echo -e "${color_blue}wget https://cacerts.digicert.com/universal-root.crt.pem${color_reset}"
            echo -e "${color_blue}sudo trust anchor --store universal-root.crt.pem${color_reset}"
        fi
    else
        log_info "User indicated they won't be using Synthesis"
    fi

    return 0
}

# Function to install Proton dependencies for a selected game
install_proton_dependencies() {
    if [ -z "$selected_appid" ] || [ -z "$selected_name" ]; then
        handle_error "No game selected. Please select a game first." false
        return 1
    fi

    log_info "Installing Proton dependencies for $selected_name (AppID: $selected_appid)"

    # Check if components are defined
    if [ "${#components[@]}" -eq 0 ]; then
        get_game_components "$selected_appid"
    fi

    # Add dotnet9 to components if needed (ensure it's in the list)
    # You can remove this for games where you don't want .NET 9
    components+=("dotnet9")
    log_info "Added dotnet9 to components list"

    print_section "Installing Dependencies"
    echo -e "Installing common dependencies for ${color_blue}$selected_name${color_reset}"
    echo -e "This may take some time. Please be patient.\n"

    # Show components to be installed
    echo -e "${color_header}Components to install:${color_reset}"
    for comp in "${components[@]}"; do
        echo -e "- $comp"
    done
    echo ""

    # Confirm installation
    if ! confirm_action "Continue with installation?"; then
        log_info "User canceled installation"
        return 1
    fi

    # Check for dotnet9 component
    local has_dotnet9=false
    local standard_components=()

    for comp in "${components[@]}"; do
        if [ "$comp" = "dotnet9" ]; then
            has_dotnet9=true
            log_info "Detected dotnet9 in components list"
        else
            standard_components+=("$comp")
        fi
    done

    # Use a temp file for logging protontricks output
    local temp_log=$(mktemp)
    TEMP_FILES+=("$temp_log")

    # Install all standard components at once with --no-bwrap
    if [ ${#standard_components[@]} -gt 0 ]; then
        echo -e "\n${color_header}Installing standard components...${color_reset}"
        echo -e "This will take several minutes. Please wait..."

        log_info "Running: $protontricks_cmd --no-bwrap $selected_appid -q ${standard_components[*]}"

        # Show a simple spinner animation
        echo -n "Installing"

        # Run the installation in the background
        $protontricks_cmd --no-bwrap "$selected_appid" -q "${standard_components[@]}" > "$temp_log" 2>&1 &
        local pid=$!

        # Simple spinner while waiting
        local chars="/-\|"
        while ps -p $pid > /dev/null; do
            for (( i=0; i<${#chars}; i++ )); do
                echo -en "\b${chars:$i:1}"
                sleep 0.2
            done
        done
        echo -en "\b"

        # Check the result
        wait $pid
        local status=$?

        if [ $status -ne 0 ]; then
            # Copy the temp log to our log file for debugging
            cat "$temp_log" >> "$log_file"
            log_error "Dependency installation failed with status $status"
            handle_error "Failed to install components. Check log for details." false
            echo -e "\n${color_yellow}Installation may be partially completed.${color_reset}"

            # Show the error from the temp log
            echo -e "\n${color_header}Error details:${color_reset}"
            tail -n 10 "$temp_log"

            # Wait for user to acknowledge the error
            pause "Review the error above and press any key to continue..."
            return 1
        fi
    fi

    # Find the prefix path for the selected game
    local steam_root=$(get_steam_root)
    local compatdata_path=$(find_game_compatdata "$selected_appid" "$steam_root")
    local prefix_path="$compatdata_path/pfx"

    if [ ! -d "$prefix_path" ]; then
        handle_error "Could not find Proton prefix at: $prefix_path" false
        return 1
    fi

    # If we have dotnet9 to install, do it separately
    if $has_dotnet9; then
        echo -e "\n${color_header}Installing .NET 9 SDK...${color_reset}"
        # Install .NET 9 SDK
        if ! install_dotnet9_sdk "$prefix_path"; then
            handle_error "Failed to install .NET 9 SDK. Check log for details." false
            return 1
        fi
    fi

    # Success message
    echo -e "\n${color_green}All dependencies installed successfully!${color_reset}"
    log_info "Dependencies installed successfully"

    # Enable dotfiles visibility
    if [ -d "$prefix_path" ]; then
        echo -e "\n${color_header}Enabling dotfiles visibility...${color_reset}"
        enable_show_dotfiles "$prefix_path"
        echo -e "${color_green}Hidden (.) files will now be visible in Wine/Proton.${color_reset}"

        # Set Windows XP compatibility for SSEEdit tools
        echo -e "\n${color_header}Setting Windows XP mode for XEDIT tools...${color_reset}"
        set_sseedit_to_winxp "$prefix_path"
        echo -e "${color_green}All XEDIT tools will now use Windows XP compatibility mode. (Drag and drop support!)${color_reset}"

    fi

    if [ -d "$prefix_path" ]; then
        echo -e "\n${color_header}Configuring Pandora Behaviour Engine+...${color_reset}"
        set_pandora_no_decorations "$prefix_path"
        echo -e "${color_green}Window decorations removed for Pandora Behaviour Engine+.${color_reset}"
    fi

    setup_synthesis_certificate

    # Offer some tips
    if $show_advice; then
        echo -e "\n${color_header}What's next?${color_reset}"
        echo -e "1. You can now run Mod Organizer 2 through Steam"
        echo -e "2. Consider setting up the NXM handler for easier mod downloads"
        echo -e "3. If text is too small, configure DPI scaling from the main menu"
        echo -e "4. Press any button to continue"
    fi

    return 0
}
